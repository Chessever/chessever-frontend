import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:chessever2/widgets/liquid_glass/search_expand_state.dart';
import 'package:cue/cue.dart';
import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:motor/motor.dart';

/// Collapsed glass search circle that expands horizontally into package
/// [GlassSearchBar] with Apple Music–style widen / collapse.
///
/// Motion stack:
/// - **cue** [Cue.onToggle] + [Act.sizedClip] — true horizontal widen from
///   [expandAlignment] (default: trailing edge, circle on the right).
/// - **cue** [Act.stretch] — soft X-axis “inflate” accent during open.
/// - **cue** [Act.scale] — presence settle around the expansion origin.
/// - **motor** [SingleMotionBuilder] — directional widen/collapse shell
///   scale + mid-morph breathe (asymmetric springs).
/// - **liquid_glass** [GlassSearchBar] — glass field + cancel when expanded.
class GlassIslandSearch extends StatefulWidget {
  const GlassIslandSearch({
    super.key,
    required this.controller,
    required this.expanded,
    required this.onExpandedChanged,
    this.focusNode,
    this.hintText = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.textFieldKey,
    this.collapsedSize = 40,
    this.expandedHeight = 44,
    this.autofocusOnExpand = true,
    /// Expand from trailing edge (Apple Music search circle on the right).
    this.expandAlignment = Alignment.centerRight,
  });

  final TextEditingController controller;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final Key? textFieldKey;
  final double collapsedSize;
  final double expandedHeight;
  final bool autofocusOnExpand;
  final Alignment expandAlignment;

  @override
  State<GlassIslandSearch> createState() => _GlassIslandSearchState();
}

class _GlassIslandSearchState extends State<GlassIslandSearch> {
  late FocusNode _focusNode;
  bool _ownsFocus = false;

  @override
  void initState() {
    super.initState();
    _ownsFocus = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void didUpdateWidget(covariant GlassIslandSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      if (_ownsFocus) _focusNode.dispose();
      _ownsFocus = widget.focusNode == null;
      _focusNode = widget.focusNode ?? FocusNode();
    }
    if (widget.expanded && !oldWidget.expanded && widget.autofocusOnExpand) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
    if (!widget.expanded && oldWidget.expanded) {
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    if (_ownsFocus) _focusNode.dispose();
    super.dispose();
  }

  void _collapse() {
    widget.onClear?.call();
    widget.controller.clear();
    widget.onChanged?.call('');
    widget.onExpandedChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = widget.expandedHeight / 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available =
            constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width * 0.7;
        final collapsed = widget.collapsedSize;
        final expandedW = searchExpandTargetWidth(
          available: available,
          expanded: true,
          collapsedSize: collapsed,
        );

        // motor: directional shell (widen jelly / collapse snappy).
        return SingleMotionBuilder(
          motion: GlassMotion.searchDirection(widget.expanded),
          value: widget.expanded ? 1.0 : 0.0,
          builder: (context, progress, _) {
            final shell = GlassMotion.shellScale(progress, min: 0.94);
            final breathe = GlassMotion.morphBreathe(progress, peak: 0.028);
            return Transform.scale(
              scale: shell * breathe,
              alignment: widget.expandAlignment,
              child: Cue.onToggle(
                toggled: widget.expanded,
                // Same duration/bounce tokens as motor widen / collapse.
                motion: GlassMotion.cueWiden,
                reverseMotion: GlassMotion.cueCollapse,
                acts: [
                  // Core widen: collapsed width ↔ full field. Rest states are
                  // exact (no permanent scale/stretch distortion when closed).
                  Act.sizedClip(
                    from: NSize.width(collapsed),
                    to: NSize.width(expandedW),
                    alignment: widget.expandAlignment,
                    clipGeometry: ClipGeometry.superEllipse(
                      BorderRadius.circular(radius),
                    ),
                  ),
                  // Mid-morph X inflate; 1.0 at both ends so icon stays round.
                  StretchAct.keyframed(
                    alignment: widget.expandAlignment,
                    frames: Keyframes.fractional(
                      const [
                        FKeyframe.key(Stretch.none, at: 0.0),
                        FKeyframe.key(Stretch(x: 1.06, y: 0.98), at: 0.4),
                        FKeyframe.key(Stretch.none, at: 1.0),
                      ],
                      duration: GlassMotion.widenDuration,
                    ),
                  ),
                ],
                child: SizedBox(
                  height: widget.expandedHeight,
                  child:
                      widget.expanded
                          ? KeyedSubtree(
                            key: widget.textFieldKey,
                            child: GlassSearchBar(
                              controller: widget.controller,
                              focusNode: _focusNode,
                              placeholder: widget.hintText,
                              onChanged: widget.onChanged,
                              onSubmitted: widget.onSubmitted,
                              showsCancelButton: true,
                              onCancel: _collapse,
                              autofocus: widget.autofocusOnExpand,
                              useOwnLayer: true,
                              height: widget.expandedHeight,
                              searchIconColor: colors.iconSecondary,
                              clearIconColor: colors.iconSecondary,
                              cancelButtonColor: colors.iconPrimary,
                            ),
                          )
                          : Align(
                            alignment: widget.expandAlignment,
                            child: GlassIconButton(
                              key: widget.textFieldKey,
                              icon: Icon(
                                CupertinoIcons.search,
                                color: colors.iconPrimary,
                              ),
                              onPressed: () => widget.onExpandedChanged(true),
                              size: widget.collapsedSize,
                              iconSize: 18,
                              useOwnLayer: true,
                            ),
                          ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
