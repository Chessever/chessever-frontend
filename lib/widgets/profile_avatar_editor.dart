import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/glass_dialog_route.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessever2/widgets/user_avatar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _profileAvatarMediaChannel = MethodChannel('com.chessever/media_picker');

/// Mobile uses the system gallery picker with access to one chosen photo only.
/// No camera or library-wide permission is requested. Other platforms retain
/// their existing file picker. Only the prepared square is uploaded.
final profileAvatarPickerProvider = Provider<Future<Uint8List?> Function()>(
  (ref) => () async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android)) {
      final Object? raw;
      try {
        raw = await _profileAvatarMediaChannel.invokeMethod<Object?>(
          'pickProfileImage',
        );
      } on PlatformException {
        throw const FormatException(
          'This photo could not be read. Choose another image.',
        );
      }
      if (raw == null) return null;
      final bytes = raw is Map ? raw['bytes'] : null;
      if (bytes is Uint8List && bytes.isNotEmpty) {
        return prepareProfileAvatar(bytes);
      }
      throw const FormatException(
        'This photo could not be read. Choose another image.',
      );
    }
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (picked == null) return null;
    final file = picked.files.single;
    if (file.size > 5 * 1024 * 1024) {
      throw const FormatException('Choose a photo smaller than 5 MB.');
    }
    if (file.bytes == null) {
      throw const FormatException(
        'This photo could not be read. Choose another image.',
      );
    }
    return prepareProfileAvatar(file.bytes!);
  },
);

/// Center crop once for identical preview and published author portraits.
Future<Uint8List> prepareProfileAvatar(Uint8List bytes) async {
  if (bytes.length > 5 * 1024 * 1024) {
    throw const FormatException('Choose a photo smaller than 5 MB.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  late final ui.Codec codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 20000000) {
      throw const FormatException('Choose a photo with smaller dimensions.');
    }
    final factor = math.min(
      1.0,
      1024 / math.max(descriptor.width, descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * factor).round()),
      targetHeight: math.max(1, (descriptor.height * factor).round()),
    );
  } catch (_) {
    descriptor?.dispose();
    rethrow;
  } finally {
    buffer.dispose();
  }
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      final side = math.min(image.width, image.height).toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          (image.width - side) / 2,
          (image.height - side) / 2,
          side,
          side,
        ),
        const Rect.fromLTWH(0, 0, 512, 512),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final square = await picture.toImage(512, 512);
      picture.dispose();
      try {
        final data = await square.toByteData(format: ui.ImageByteFormat.png);
        if (data == null || data.lengthInBytes > 1024 * 1024) {
          throw const FormatException('Choose a simpler or smaller photo.');
        }
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        square.dispose();
      }
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
    descriptor.dispose();
  }
}

Future<void> showProfileAvatarEditor(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final user = container.read(currentUserProvider);
  if (user == null || user.isAnonymous) {
    final allowed = await showAuthUpgradeSheet(
      context: context,
      title: 'Save your profile photo',
      message: 'Sign in to use your photo on your profile and published books.',
      completeSignInInSheet: true,
    );
    if (!allowed || !context.mounted) return;
  }
  // A lightbox on a plain scrim: nothing re-blurs the whole screen while it
  // opens. The scrim fades and the stage scales up on a spring, visible from
  // its first frame; an outside tap closes it unless a save is running.
  await showGlassDialog<void>(
    context: context,
    useSafeArea: false,
    barrierLabel: 'Close profile photo',
    scrim: ProfileAvatarLightbox.scrimOf(context),
    builder: (_) => const _ProfileAvatarEditor(),
  );
}

/// The avatar lightbox's colours, in one place (and pinned by
/// `test/dialogs_glass_contrast_test.dart`).
///
/// The stage is dark in both themes, as a photo viewer's is: the theme's
/// scrim ink, dense enough that the page under it falls quiet (nothing
/// blurs the page, so it is dimmed further than under a popup and only
/// the photo holds the eye). The controls sit on dark glass a step lighter
/// than that stage, so their white type reads at well over 7:1 in light as
/// in dark, where the light theme used to leave a mid-grey slab at 4.8:1.
abstract final class ProfileAvatarLightbox {
  /// The scrim at rest, over the page.
  static Color scrimOf(BuildContext context) =>
      context.colors.scrim.withValues(alpha: context.isLightTheme ? 0.9 : 0.85);

  /// The page as the stage leaves it: what the controls' glass stands on,
  /// and is solved over.
  static Color stageOf(BuildContext context) =>
      Color.alphaBlend(scrimOf(context), context.colors.background);

  /// The controls' glass: a step of white over the stage.
  static Color controlsToneOf(BuildContext context) =>
      Color.alphaBlend(Colors.white.withValues(alpha: 0.06), stageOf(context));

  /// An error under the name, on that dark glass in both themes: the dark
  /// theme's danger red (#F5453A) lifted halfway to white. The light
  /// theme's red is drawn for paper and all but vanishes there, and the
  /// dark one reads at under 3:1 on the light theme's teal-ink stage.
  static const Color errorInk = Color(0xFFFAA29D);

  /// The main action on that dark glass: the light theme's paper and ink.
  static Color get actionFill => AppColors.light.surface;
  static Color get actionInk => AppColors.light.textPrimary;
}

class _ProfileAvatarEditor extends ConsumerStatefulWidget {
  const _ProfileAvatarEditor();
  @override
  ConsumerState<_ProfileAvatarEditor> createState() =>
      _ProfileAvatarEditorState();
}

class _ProfileAvatarEditorState extends ConsumerState<_ProfileAvatarEditor> {
  Uint8List? _draft;
  bool _busy = false;
  String? _error;
  Future<void> _choose() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await ref.read(profileAvatarPickerProvider)();
      if (mounted && bytes != null) setState(() => _draft = bytes);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userFacingError(
            error,
            fallback: 'This photo could not be read. Choose another image.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _draft == null) return;
    final owner = ref.read(currentUserProvider)?.id;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await collectionsSessionToken();
      if (token == null || owner == null) {
        throw const FormatException('Sign in again to save your photo.');
      }
      final url = await ref
          .read(gamebaseRepositoryProvider)
          .uploadProfileAvatar(_draft!, bearer: token);
      if (!mounted || ref.read(currentUserProvider)?.id != owner) return;
      await ref
          .read(authStateProvider.notifier)
          .updateProfileAvatar(owner, url);
      if (!mounted) return;
      showAppSnack(
        context,
        'Profile photo updated.',
        tone: AppSnackTone.success,
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userFacingError(
            error,
            fallback: 'Could not save your photo. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final size = math.min(
      MediaQuery.sizeOf(context).width * 0.72,
      math.min(320.0, MediaQuery.sizeOf(context).height * 0.42),
    );
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return PopScope(
      canPop: !_busy,
      // A see-through Material: taps that miss the controls reach the
      // route's barrier, which closes the lightbox (asking PopScope first).
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close profile photo',
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final diameter = math.min(size, constraints.maxHeight);
                    return Center(
                      child: SizedBox(
                        width: diameter,
                        height: diameter,
                        child: _draft == null
                            ? UserAvatar(
                                size: diameter / 1.w,
                                showPremiumBorder: false,
                                initialsStyle: TextStyle(
                                  fontSize: diameter * 0.28,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : ClipOval(
                                child: Image.memory(
                                  _draft!,
                                  width: diameter,
                                  height: diameter,
                                  fit: BoxFit.cover,
                                  // Decoded at the size it is shown,
                                  // never past the 512 px square.
                                  cacheWidth: math.min(
                                    512,
                                    (diameter * ratio).ceil(),
                                  ),
                                  gaplessPlayback: true,
                                ),
                              ),
                      ),
                    );
                  },
                ),
              ),
              // The controls on the dark glass, a step lighter than the
              // stage it is solved over, so its white type reads at well
              // over 7:1 in both themes. The stage under it is flat, with
              // nothing to frost, so it takes the material without the
              // live blur. The panel's margin plus its padding put the
              // controls where they always were.
              Padding(
                padding: EdgeInsets.fromLTRB(12.sp, 0, 12.sp, 12.sp),
                child: PopupGlassNoFrost(
                  child: FixedDarkPopupGlass(
                    tone: ProfileAvatarLightbox.controlsToneOf(context),
                    page: ProfileAvatarLightbox.stageOf(context),
                    borderRadius: BorderRadius.circular(20.br),
                    padding: EdgeInsets.all(12.sp),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          user?.displayName ?? 'Profile photo',
                          textAlign: TextAlign.center,
                          style: AppTypography.textMdMedium.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: ProfileAvatarLightbox.errorInk,
                              ),
                            ),
                          ),
                        SizedBox(height: 16.sp),
                        AppButton(
                          text: _draft == null ? 'Upload' : 'Save',
                          isLoading: _busy,
                          // The paper button in both themes: the controls
                          // are dark glass in both, and a dark button on
                          // them all but vanished in the dark theme.
                          backgroundColor: ProfileAvatarLightbox.actionFill,
                          textColor: ProfileAvatarLightbox.actionInk,
                          onPressed: _draft == null ? _choose : _save,
                        ),
                        if (_draft != null)
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _busy ? null : _choose,
                            child: const Text('Choose another photo'),
                          ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
