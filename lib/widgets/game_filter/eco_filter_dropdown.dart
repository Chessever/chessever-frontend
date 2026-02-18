import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';

/// Searchable ECO filter dropdown with all 500 individual ECO codes
/// Allows filtering by ECO code or opening name
class EcoFilterDropdown extends StatefulWidget {
  const EcoFilterDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final GameEcoFilter value;
  final ValueChanged<GameEcoFilter> onChanged;

  @override
  State<EcoFilterDropdown> createState() => _EcoFilterDropdownState();
}

class _EcoFilterDropdownState extends State<EcoFilterDropdown>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  String _searchQuery = '';
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;
  late Animation<double> _rotationAnimation;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // Category colors
  static const Map<String, Color> _categoryColors = {
    'A': Color(0xFF6366F1), // Indigo
    'B': Color(0xFFF59E0B), // Amber
    'C': Color(0xFF10B981), // Emerald
    'D': Color(0xFF8B5CF6), // Violet
    'E': Color(0xFFEC4899), // Pink
  };

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
        // Focus search field when expanded
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _searchFocusNode.requestFocus();
        });
      } else {
        _animationController.reverse();
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  void _selectItem(GameEcoFilter item) {
    widget.onChanged(item);
    _toggleExpanded();
  }

  Color _getCategoryColor(String? letter) {
    if (letter == null) return kWhiteColor;
    return _categoryColors[letter.toUpperCase()] ?? kWhiteColor;
  }

  List<MapEntry<String, String>> _getFilteredOpenings() {
    final query = _searchQuery.toLowerCase().trim();
    final entries = EcoOpenings.codeToName.entries.toList();

    if (query.isEmpty) {
      return entries;
    }

    return entries.where((entry) {
      final code = entry.key.toLowerCase();
      final name = entry.value.toLowerCase();
      return code.contains(query) || name.contains(query);
    }).toList();
  }

  Map<String, List<MapEntry<String, String>>> _groupByCategory(
    List<MapEntry<String, String>> entries,
  ) {
    final grouped = <String, List<MapEntry<String, String>>>{};
    for (final entry in entries) {
      final category = entry.key[0];
      grouped.putIfAbsent(category, () => []).add(entry);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header (collapsed state)
        GestureDetector(
          onTap: _toggleExpanded,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              color: _isExpanded ? kWhiteColor : kBlack2Color,
              borderRadius: _isExpanded
                  ? BorderRadius.vertical(top: Radius.circular(12.br))
                  : BorderRadius.circular(12.br),
              border: Border.all(
                color: _isExpanded
                    ? kWhiteColor.withValues(alpha: 0.2)
                    : kDividerColor,
              ),
            ),
            child: Row(
              children: [
                // Category badge if specific code selected
                if (!widget.value.isAll) ...[
                  _buildCategoryBadge(
                    widget.value.categoryLetter!,
                    isHeader: true,
                  ),
                  SizedBox(width: 12.w),
                ],
                // Selected value text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.value.isAll
                            ? 'All Openings'
                            : widget.value.code!,
                        style: AppTypography.textSmMedium.copyWith(
                          color: _isExpanded ? kBlackColor : kWhiteColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!widget.value.isAll) ...[
                        SizedBox(height: 2.h),
                        Text(
                          EcoOpenings.getOpeningName(widget.value.code) ?? '',
                          style: AppTypography.textXsRegular.copyWith(
                            color: _isExpanded
                                ? kBlackColor.withValues(alpha: 0.6)
                                : kSecondaryTextColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Chevron
                RotationTransition(
                  turns: _rotationAnimation,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20.ic,
                    color: _isExpanded
                        ? kBlackColor.withValues(alpha: 0.7)
                        : kSecondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expandable options list
        SizeTransition(
          sizeFactor: _expandAnimation,
          axisAlignment: -1,
          child: Container(
            constraints: BoxConstraints(maxHeight: 320.h),
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(12.br),
              ),
              border: Border(
                left: BorderSide(color: kDividerColor),
                right: BorderSide(color: kDividerColor),
                bottom: BorderSide(color: kDividerColor),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search field
                _buildSearchField(),
                // Options list
                Flexible(
                  child: _buildOptionsList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Container(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: kDividerColor.withValues(alpha: 0.5)),
        ),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (value) => setState(() => _searchQuery = value),
        style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
        decoration: InputDecoration(
          hintText: 'Search',
          hintStyle: AppTypography.textSmRegular.copyWith(
            color: kSecondaryTextColor.withValues(alpha: 0.6),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 18.ic,
            color: kSecondaryTextColor,
          ),
          prefixIconConstraints: BoxConstraints(minWidth: 36.w),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: Icon(
                    Icons.close_rounded,
                    size: 16.ic,
                    color: kSecondaryTextColor,
                  ),
                )
              : null,
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8.h),
        ),
      ),
    );
  }

  Widget _buildOptionsList() {
    final filtered = _getFilteredOpenings();

    if (filtered.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(20.sp),
        child: Text(
          'No openings found',
          style: AppTypography.textSmRegular.copyWith(
            color: kSecondaryTextColor,
          ),
        ),
      );
    }

    final grouped = _groupByCategory(filtered);
    final categories = grouped.keys.toList()..sort();

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      radius: Radius.circular(4.br),
      child: ListView(
        controller: _scrollController,
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          // "All Openings" option at top
          if (_searchQuery.isEmpty) _buildAllOpeningsOption(),

          // Grouped by category
          for (final category in categories) ...[
            _buildCategoryHeader(category, grouped[category]!.length),
            ...grouped[category]!.map(_buildOpeningItem),
          ],
        ],
      ),
    );
  }

  Widget _buildAllOpeningsOption() {
    final isSelected = widget.value.isAll;

    return GestureDetector(
      onTap: () => _selectItem(GameEcoFilter.all),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: isSelected ? kWhiteColor.withValues(alpha: 0.05) : null,
          border: Border(
            bottom: BorderSide(color: kDividerColor.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28.w,
              height: 28.w,
              decoration: BoxDecoration(
                color: kWhiteColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6.br),
              ),
              child: Icon(
                Icons.grid_view_rounded,
                size: 16.ic,
                color: kWhiteColor.withValues(alpha: 0.8),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                'All Openings',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_rounded,
                size: 18.ic,
                color: kWhiteColor,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryHeader(String category, int count) {
    final color = _getCategoryColor(category);
    final categoryInfo = EcoOpenings.getCategory(category);

    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 6.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 22.w,
            height: 22.w,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4.br),
            ),
            child: Center(
              child: Text(
                category,
                style: AppTypography.textSmBold.copyWith(
                  color: color,
                  fontSize: 12.f,
                ),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              categoryInfo?.name ?? '',
              style: AppTypography.textXsMedium.copyWith(
                color: color,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Text(
            '$count',
            style: AppTypography.textXsRegular.copyWith(
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpeningItem(MapEntry<String, String> entry) {
    final code = entry.key;
    final name = entry.value;
    final color = _getCategoryColor(code[0]);
    final isSelected = widget.value.code == code;

    return GestureDetector(
      onTap: () => _selectItem(GameEcoFilter.forCode(code)),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : null,
          border: Border(
            bottom: BorderSide(
              color: kDividerColor.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // ECO Code badge
            Container(
              width: 40.w,
              height: 26.h,
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.2)
                    : color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4.br),
                border: Border.all(
                  color: color.withValues(alpha: isSelected ? 0.4 : 0.2),
                  width: 0.5,
                ),
              ),
              child: Center(
                child: Text(
                  code,
                  style: AppTypography.textXsBold.copyWith(
                    color: color,
                    fontSize: 11.f,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
            SizedBox(width: 12.w),
            // Opening name
            Expanded(
              child: Text(
                name,
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: isSelected ? 1.0 : 0.85),
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Check mark if selected
            if (isSelected) ...[
              SizedBox(width: 8.w),
              Icon(
                Icons.check_rounded,
                size: 16.ic,
                color: color,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBadge(String letter, {bool isHeader = false}) {
    final color = _getCategoryColor(letter);
    final isExpanded = isHeader && _isExpanded;

    return Container(
      width: 28.w,
      height: 28.w,
      decoration: BoxDecoration(
        color: isExpanded ? color : color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6.br),
        border: Border.all(
          color: color.withValues(alpha: isExpanded ? 0.3 : 0.4),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: AppTypography.textSmBold.copyWith(
            color: isExpanded ? kWhiteColor : color,
            fontSize: 13.f,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
