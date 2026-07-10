import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:chessever2/widgets/liquid_glass/search_expand_state.dart';
import 'package:cue/cue.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:motor/motor.dart';

/// Collapsed glass search circle that expands horizontally into package
/// [GlassSearchBar] with Apple Music–style widen / collapse.
///
/// Motion stack:
/// - **cue** [Cue.onToggle] + [Act.sizedClip] — horizontal widen from the
///   search circle (alignment right), reverse uses snappy motion.
/// - **motor** [SingleMotionBuilder] — soft scale settle on the shell.
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

        // motor: shell scale pulse while cue widens the clip.
        return SingleMotionBuilder(
          motion: GlassMotion.shellPulse,
          value: widget.expanded ? 1.0 : 0.0,
          builder: (context, pulse, _) {
            final scale = GlassMotion.shellScale(pulse);
            return Transform.scale(
              scale: scale,
              alignment: widget.expandAlignment,
              child: Cue.onToggle(
                toggled: widget.expanded,
                // Widen forward — underdamped smooth = soft jelly overshoot.
                motion: const CueMotion.smooth(dampingRatio: 0.78),
                // Collapse back — near-critical snappy settle.
                reverseMotion: const CueMotion.snappy(dampingRatio: 0.95),
                acts: [
                  Act.sizedClip(
                    from: NSize.width(collapsed),
                    to: NSize.width(expandedW),
                    alignment: widget.expandAlignment,
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
