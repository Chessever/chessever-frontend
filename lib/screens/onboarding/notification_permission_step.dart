import 'package:chessever2/screens/onboarding/widgets/onboarding_ui.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// One favourite, reduced to what this step needs to draw it.
@immutable
class NotificationStepPlayer {
  const NotificationStepPlayer({
    required this.name,
    required this.fideId,
    this.title,
  });

  final String name;

  /// Used to resolve the FIDE headshot, the same way the selection list does.
  final String fideId;
  final String? title;

  /// Surname only — full names overrun the line once three are joined, and the
  /// surname is how these players are actually referred to.
  String get shortName {
    final parts = name.trim().split(RegExp(r'[\s,]+'))
      ..removeWhere((part) => part.isEmpty);
    if (parts.isEmpty) return name.trim();
    // Gamebase rows arrive "Carlsen, Magnus"; plain rows arrive "Magnus
    // Carlsen". Comma means the surname already leads.
    return name.contains(',') ? parts.first : parts.last;
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'[\s,]+'))
      ..removeWhere((part) => part.isEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

/// The step between picking favourites and the native permission dialog.
///
/// It exists because the OS prompt is one-shot: asked cold at launch it reads
/// as noise and a decline is permanent. Asked here it has an answer to "for
/// what" that the user just supplied themselves — so the step shows the
/// players they picked rather than a generic bell. [players] being empty is a
/// real state (the step is skippable upstream), and it degrades to the copy
/// alone rather than inventing stand-in faces.
class NotificationPermissionStep extends StatefulWidget {
  const NotificationPermissionStep({
    required this.onContinue,
    required this.topPadding,
    required this.bottomPadding,
    this.players = const <NotificationStepPlayer>[],
    super.key,
  });

  final Future<void> Function() onContinue;
  final double topPadding;
  final double bottomPadding;
  final List<NotificationStepPlayer> players;

  @override
  State<NotificationPermissionStep> createState() =>
      _NotificationPermissionStepState();
}

class _NotificationPermissionStepState
    extends State<NotificationPermissionStep> {
  bool _isContinuing = false;

  Future<void> _continue() async {
    if (_isContinuing) return;
    setState(() => _isContinuing = true);
    try {
      await widget.onContinue();
    } finally {
      if (mounted) setState(() => _isContinuing = false);
    }
  }

  /// "Magnus", "Magnus and Hikaru", "Magnus, Hikaru and Ding" — anything past
  /// three would wrap, so the rest are counted instead of listed.
  String _subtitle() {
    final names = widget.players
        .map((player) => player.shortName)
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) {
      return 'Know the moment your favorite players start a game.';
    }
    final String subject;
    if (names.length == 1) {
      subject = names.first;
    } else if (names.length <= 3) {
      subject =
          '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
    } else {
      final remaining = names.length - 2;
      subject = '${names.take(2).join(', ')} and $remaining others';
    }
    return 'Know the moment $subject start a game.';
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 24.w,
      tablet: 32.w,
    );
    final maxWidth = ResponsiveHelper.isTablet ? 500.0 : double.infinity;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            widget.topPadding + 60.h,
            horizontalPadding,
            widget.bottomPadding + 16.h,
          ),
          child: Column(
            children: [
              const Spacer(flex: 1),

              if (widget.players.isNotEmpty) ...[
                _FavoritesCluster(players: widget.players)
                    .animate()
                    .fadeIn(duration: 600.ms, curve: onboardingGentleSpring)
                    .scale(
                      begin: const Offset(0.85, 0.85),
                      end: const Offset(1, 1),
                      duration: 700.ms,
                      curve: onboardingSmoothSpring,
                    ),
                SizedBox(height: 40.h),
              ],

              Text(
                    'Never miss a game from your favorites',
                    textAlign: TextAlign.center,
                    style: AppTypography.displayXsBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 500.ms, curve: onboardingSmoothSpring)
                  .move(
                    begin: const Offset(0, 16),
                    curve: onboardingSmoothSpring,
                  ),

              SizedBox(height: 8.h),

              Text(
                    _subtitle(),
                    textAlign: TextAlign.center,
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.6),
                    ),
                  )
                  .animate(delay: 300.ms)
                  .fadeIn(duration: 500.ms, curve: onboardingSmoothSpring),

              const Spacer(flex: 2),

              OnboardingPrimaryButton(
                    label: 'Continue',
                    onTap: _isContinuing ? null : _continue,
                    isLoading: _isContinuing,
                  )
                  .animate(delay: 450.ms)
                  .fadeIn(duration: 400.ms, curve: onboardingSmoothSpring)
                  .move(
                    begin: const Offset(0, 30),
                    curve: onboardingSmoothSpring,
                  ),

              SizedBox(height: 8.h),
            ],
          ),
        ),
      ),
    );
  }
}

/// The favourites the user just picked, overlapped into one group.
///
/// Overlapping reads as "these belong together" in a way a spaced row does not,
/// and it keeps three avatars comfortably inside the phone width. Each circle
/// carries a ring in the page's own background colour so the one behind it is
/// separated by the gap rather than by a drawn outline.
class _FavoritesCluster extends StatelessWidget {
  const _FavoritesCluster({required this.players});

  final List<NotificationStepPlayer> players;

  @override
  Widget build(BuildContext context) {
    // Beyond three the cluster gets wider than the copy above it.
    final shown = players.take(3).toList(growable: false);
    final diameter = 92.w;
    final ring = 3.w;
    final overlap = 24.w;
    final step = diameter - overlap;
    final totalWidth = diameter + step * (shown.length - 1);

    return SizedBox(
      width: totalWidth,
      height: diameter,
      child: Stack(
        children: <Widget>[
          for (var i = 0; i < shown.length; i++)
            Positioned(
              // Later avatars sit to the right and, via the Stack order below,
              // in front — so the ring always cuts the one behind it.
              left: i * step,
              top: 0,
              child: Container(
                width: diameter,
                height: diameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.background,
                  border: Border.all(
                    color: context.colors.background,
                    width: ring,
                  ),
                ),
                child: ClipOval(
                  child: _FidePhotoAvatar(
                    player: shown[i],
                    size: diameter - ring * 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// An avatar that resolves the player's FIDE headshot after first paint.
///
/// The selection list resolves photos the same way. The initials render
/// immediately and the photo crossfades in if one exists, so the cluster is
/// never blank while the lookup is in flight and never gaps when it fails.
class _FidePhotoAvatar extends StatefulWidget {
  const _FidePhotoAvatar({required this.player, required this.size});

  final NotificationStepPlayer player;
  final double size;

  @override
  State<_FidePhotoAvatar> createState() => _FidePhotoAvatarState();
}

class _FidePhotoAvatarState extends State<_FidePhotoAvatar> {
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    final fideId = widget.player.fideId;
    if (fideId.isEmpty) return;
    FidePhotoService.getPhotoUrlOrNull(fideId).then((url) {
      if (!mounted || url == null) return;
      setState(() => _photoUrl = url);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PlayerInitialsAvatar(
      photoUrl: _photoUrl,
      initials: widget.player.initials,
      title: widget.player.title,
      size: widget.size,
      isCircular: true,
    );
  }
}
