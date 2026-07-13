import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Collapsed glass search circle that expands into the canonical package
/// [GlassSearchBar]. The collapse/expand is a clean [AnimatedSize] crossfade —
/// no bespoke motion tower — so the glass never wobbles or over-shoots.
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
    this.collapsedIconSize = 18,
    this.collapsedSettings,
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

  /// Icon size inside the collapsed circle.
  final double collapsedIconSize;

  /// Richer glass for the collapsed button so it can read identically to the
  /// home bottom-nav search button (thicker, deeper tint) instead of the flat
  /// default. Null = package default glass.
  final LiquidGlassSettings? collapsedSettings;
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

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: widget.expandAlignment,
      child: SizedBox(
        // Collapsed circle can be taller than the expanded field (bulky search
        // button), so size to whichever state is active instead of clipping.
        height:
            widget.expanded ? widget.expandedHeight : widget.collapsedSize,
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
                    iconSize: widget.collapsedIconSize,
                    useOwnLayer: true,
                    settings: widget.collapsedSettings,
                  ),
                ),
      ),
    );
  }
}
