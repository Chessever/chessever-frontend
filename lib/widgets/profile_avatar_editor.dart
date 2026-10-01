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
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close profile photo',
    barrierColor: Colors.transparent,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240),
    pageBuilder: (_, __, ___) => const _ProfileAvatarEditor(),
    // Content stays visible throughout the transition, including its first frame.
    transitionBuilder: (_, animation, __, child) => ScaleTransition(
      scale: Tween(
        begin: 0.92,
        end: 1.0,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
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
    return PopScope(
      canPop: !_busy,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: GestureDetector(
                  onTap: _busy ? null : () => Navigator.pop(context),
                  child: ColoredBox(
                    color: context.colors.scrim.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Close profile photo',
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
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
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(24.sp, 12.sp, 24.sp, 24.sp),
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
                              style: TextStyle(color: context.colors.danger),
                            ),
                          ),
                        SizedBox(height: 16.sp),
                        AppButton(
                          text: _draft == null ? 'Upload' : 'Save',
                          isLoading: _busy,
                          backgroundColor: context.colors.surface,
                          textColor: context.colors.textPrimary,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
