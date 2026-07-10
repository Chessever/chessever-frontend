import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/liquid_glass/search_expand_state.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Collapsed glass search circle that expands horizontally into package
/// [GlassSearchBar] (not a permanent full-width slab).
///
/// Expand/collapse is horizontal-only. Expanded mode uses the package
/// search surface so we get native jelly cancel/clear affordances.
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
        final targetW = searchExpandTargetWidth(
          available: available,
          expanded: widget.expanded,
          collapsedSize: widget.collapsedSize,
        );

        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          width: targetW,
          height: widget.expanded ? widget.expandedHeight : widget.collapsedSize,
          child:
              widget.expanded
                  ? KeyedSubtree(
                    key: widget.textFieldKey,
                    // Package GlassSearchBar owns glass + clear + cancel.
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
                    alignment: Alignment.centerRight,
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
        );
      },
    );
  }
}
