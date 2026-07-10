import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/liquid_glass/search_expand_state.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Collapsed glass search circle that expands horizontally into a field.
///
/// Designed for island top chrome — never permanently reserves a full-width
/// search slab. Expand/collapse is horizontal-only.
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
    this.expandedHeight = 40,
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
          height: widget.expandedHeight,
          child:
              widget.expanded
                  ? _ExpandedField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    hintText: widget.hintText,
                    colors: colors,
                    textFieldKey: widget.textFieldKey,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted,
                    onCollapse: _collapse,
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

class _ExpandedField extends StatelessWidget {
  const _ExpandedField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.colors,
    required this.onCollapse,
    this.onChanged,
    this.onSubmitted,
    this.textFieldKey,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final AppColors colors;
  final VoidCallback onCollapse;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Key? textFieldKey;

  @override
  Widget build(BuildContext context) {
    // Glass surface island wrapping a sharp text field (not nested glass
    // controls inside glass — text field is opaque content).
    return GlassContainer(
      useOwnLayer: true,
      shape: const LiquidRoundedSuperellipse(borderRadius: 22),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(CupertinoIcons.search, size: 18, color: colors.iconSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: textFieldKey,
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: AppTypography.textSmMedium.copyWith(
                color: colors.textPrimary,
              ),
              cursorColor: colors.brand,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hintText,
                hintStyle: AppTypography.textSmMedium.copyWith(
                  color: colors.textTertiary,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          GestureDetector(
            onTap: onCollapse,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 18,
                color: colors.iconSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
