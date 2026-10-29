import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/like_flight.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// One width for every footer button, so Report and Like sit as an even pair
/// on a shared axis whatever their labels say.
const double kNotationFooterButtonWidth = 140;
const double kNotationFooterButtonHeight = 44;
const double _kFooterRadius = 12;

/// The action row under the notation: Report and Like, side by side and
/// centred as one unit. Either may be absent; a lone button stays centred.
class NotationFooterActions extends StatelessWidget {
  const NotationFooterActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// The shared shell of a notation footer button: a recessed tonal surface,
/// icon and a short label. Both footer actions use it, so neither reads as the
/// "primary" of a filled-versus-outlined pair; state shows through the border
/// tone and the icon instead.
class NotationFooterButton extends StatelessWidget {
  const NotationFooterButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.dimmed = false,
    this.borderColor,
    this.fill,
    this.semanticsLabel,
    this.semanticsValue,
    this.semanticsHint,
    this.semanticsEnabled = true,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onTap;

  /// Unavailable look. The button can still take a tap (to say why).
  final bool dimmed;
  final Color? borderColor;

  /// Painted under the label, clipped to the button (the report's progress).
  final Widget? fill;
  final String? semanticsLabel;
  final String? semanticsValue;
  final String? semanticsHint;
  final bool semanticsEnabled;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_kFooterRadius);
    return Semantics(
      button: true,
      enabled: semanticsEnabled,
      label: semanticsLabel,
      value: semanticsValue,
      hint: semanticsHint,
      excludeSemantics: semanticsLabel != null,
      child: SizedBox(
        width: kNotationFooterButtonWidth,
        height: kNotationFooterButtonHeight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Ink(
              decoration: BoxDecoration(
                color: dimmed
                    ? context.colors.surfaceRecessed.withValues(alpha: 0.5)
                    : context.colors.surfaceRecessed,
                borderRadius: radius,
                border: Border.all(
                  color: borderColor ?? context.colors.divider,
                ),
              ),
              child: Stack(
                children: [
                  if (fill != null)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(_kFooterRadius - 1),
                        child: fill,
                      ),
                    ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          icon,
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: dimmed
                                    ? context.colors.textTertiary
                                    : context.colors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Like, next to Report under the notation.
///
/// Liking used to be reachable only by double-tapping the board, which nothing
/// on screen advertised. This button does not have its own like logic: it runs
/// the board's gesture through [LikeFlightAnchor.likeFromPage], so the heart
/// bursts on the board, flies to the AppBar badge and offers the tag chip —
/// the same answer a double-tap gives, which is how the gesture gets learnt.
class LikeGameButton extends ConsumerStatefulWidget {
  const LikeGameButton({
    super.key,
    required this.likeId,
    required this.pageIndex,
  });

  /// [GamesTourModel.likeId] of the game on this page.
  final String likeId;
  final int pageIndex;

  @override
  ConsumerState<LikeGameButton> createState() => _LikeGameButtonState();
}

class _LikeGameButtonState extends ConsumerState<LikeGameButton> {
  final GlobalKey _heartKey = GlobalKey();

  /// Bumped whenever the liked state flips, from here or anywhere else (a
  /// double-tap, My Likes). Each bump replays the heart's spring from [_popFrom].
  int _pops = 0;
  double _popFrom = 1;

  void _handleTap() {
    final box = _heartKey.currentContext?.findRenderObject();
    final centre = box is RenderBox && box.attached
        ? box.localToGlobal(box.size.center(Offset.zero))
        : Offset.zero;
    ref.read(likeFlightAnchorProvider).likeFromPage(widget.pageIndex, centre);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isGameLikedProvider(widget.likeId), (previous, next) {
      if (previous == null || previous == next) return;
      setState(() {
        _pops++;
        // A like pops the heart in from small; an unlike only gives way.
        _popFrom = next ? 0.4 : 0.8;
      });
    });
    final liked = ref.watch(isGameLikedProvider(widget.likeId));
    final likeColor = context.colors.danger;

    return NotationFooterButton(
      key: const ValueKey('notation-like-button'),
      onTap: _handleTap,
      label: liked ? 'Liked' : 'Like',
      semanticsLabel: liked ? 'Liked. Tap to unlike' : 'Like this game',
      semanticsHint: 'You can also double-tap the board',
      borderColor: liked ? likeColor.withValues(alpha: 0.55) : null,
      icon: SingleMotionBuilder(
        key: ValueKey(_pops),
        motion: const CupertinoMotion.bouncy(),
        from: _pops == 0 ? 1 : _popFrom,
        value: 1,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: _heartKey,
          size: 19,
          color: liked ? likeColor : context.colors.accentText,
        ),
      ),
    );
  }
}
