import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';

/// Searchable ECO filter dropdown with individual codes plus safe parent
/// families. Family choices reuse the same prefix contract as single codes,
/// so existing callers and query paths remain compatible.
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
  // Collapsed Opening search must not steal route focus (which opens the
  // keyboard) when the Library ChessEver Database filter dialog appears.
  final FocusNode _searchFocusNode = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );
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
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
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
        // Keep the search field focusable so an explicit tap can type,
        // but do not request the keyboard just because Opening expanded.
        _searchFocusNode.canRequestFocus = true;
        _searchFocusNode.skipTraversal = false;
      } else {
        _animationController.reverse();
        _searchFocusNode.unfocus();
        _searchFocusNode.canRequestFocus = false;
        _searchFocusNode.skipTraversal = true;
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
    if (letter == null) return context.colors.textPrimary;
    return _categoryColors[letter.toUpperCase()] ?? context.colors.textPrimary;
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

  List<EcoOpeningFamily> _getFilteredFamilies() {
    final query = _searchQuery.toLowerCase().trim();
    if (query.isEmpty) return const <EcoOpeningFamily>[];
    return EcoOpenings.families
        .where((family) {
          return family.codePrefix.toLowerCase().contains(query) ||
              family.name.toLowerCase().contains(query);
        })
        .toList(growable: false);
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
              color:
                  _isExpanded
                      ? context.colors.textPrimary
                      : context.colors.surface,
              borderRadius:
                  _isExpanded
                      ? BorderRadius.vertical(top: Radius.circular(12.br))
                      : BorderRadius.circular(12.br),
              border: Border.all(
                color:
                    _isExpanded
                        ? context.colors.textPrimary.withValues(alpha: 0.2)
                        : context.colors.divider,
              ),
            ),
            child: Row(
              children: [
                // Category badge if specific code selected. The unknown-ECO
                // sentinel belongs to no A–E category, so it gets no badge.
                if (!widget.value.isAll && !widget.value.isUnknownEco) ...[
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
                        widget.value.displayText,
                        style: AppTypography.textSmMedium.copyWith(
                          color:
                              _isExpanded
                                  ? kBlackColor
                                  : context.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!widget.value.isAll &&
                          !widget.value.isUnknownEco) ...[
                        SizedBox(height: 2.h),
                        Text(
                          widget.value.openingName ?? '',
                          style: AppTypography.textXsRegular.copyWith(
                            color:
                                _isExpanded
                                    ? kBlackColor.withValues(alpha: 0.6)
                                    : context.colors.textSecondary,
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
                    color:
                        _isExpanded
                            ? kBlackColor.withValues(alpha: 0.7)
                            : context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expandable options list. ExcludeFocus while collapsed so the
        // offscreen TextField cannot become the dialog's first focus.
        ExcludeFocus(
          excluding: !_isExpanded,
          child: SizeTransition(
            sizeFactor: _expandAnimation,
            alignment: Alignment.topCenter,
            child: Container(
              constraints: BoxConstraints(maxHeight: 320.h),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(12.br),
                ),
                border: Border(
                  left: BorderSide(color: context.colors.divider),
                  right: BorderSide(color: context.colors.divider),
                  bottom: BorderSide(color: context.colors.divider),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSearchField(),
                  Flexible(child: _buildOptionsList()),
                ],
              ),
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
          bottom: BorderSide(
            color: context.colors.divider.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: false,
        onTapOutside: (_) => _searchFocusNode.unfocus(),
        onChanged: (value) => setState(() => _searchQuery = value),
        style: AppTypography.textSmMedium.copyWith(
          color: context.colors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Search',
          hintStyle: AppTypography.textSmRegular.copyWith(
            color: context.colors.textSecondary.withValues(alpha: 0.6),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 18.ic,
            color: context.colors.textSecondary,
          ),
          prefixIconConstraints: BoxConstraints(minWidth: 36.w),
          suffixIcon:
              _searchQuery.isNotEmpty
                  ? GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: Icon(
                      Icons.close_rounded,
                      size: 16.ic,
                      color: context.colors.textSecondary,
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
    final families = _getFilteredFamilies();

    if (filtered.isEmpty && families.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(20.sp),
        child: Text(
          'No openings found',
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.textSecondary,
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

          // Parent families only appear in response to a search. This keeps
          // the familiar 500-code browser compact while making a query such
          // as "Najdorf" offer one safe B90-B99 bulk choice first.
          if (families.isNotEmpty) ...[
            _buildFamilySectionHeader(),
            ...families.map(_buildFamilyItem),
          ],

          // Grouped by category
          for (final category in categories) ...[
            _buildCategoryHeader(category, grouped[category]!.length),
            ...grouped[category]!.map(_buildOpeningItem),
          ],
        ],
      ),
    );
  }

  Widget _buildFamilySectionHeader() {
    return Container(
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 6.h),
      child: Text(
        'Opening families',
        style: AppTypography.textXsMedium.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildFamilyItem(EcoOpeningFamily family) {
    final color = _getCategoryColor(family.codePrefix[0]);
    final isSelected = widget.value.code == family.codePrefix;
    final rangeStart = '${family.codePrefix}0';
    final rangeEnd = '${family.codePrefix}9';

    return Semantics(
      button: true,
      selected: isSelected,
      label:
          'Select ${family.name} family, $rangeStart through $rangeEnd, '
          '${family.codeCount} ECO codes',
      child: GestureDetector(
        key: ValueKey('eco-family-${family.codePrefix}'),
        onTap: () => _selectItem(GameEcoFilter.forFamily(family.codePrefix)),
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: BoxConstraints(minHeight: 48.h),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 9.h),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.08) : null,
            border: Border(
              bottom: BorderSide(
                color: context.colors.divider.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 42.w,
                child: Text(
                  family.codePrefix,
                  textAlign: TextAlign.left,
                  style: AppTypography.textSmBold.copyWith(color: color),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      family.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textSmMedium.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      '$rangeStart-$rangeEnd · ${family.codeCount} codes',
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_rounded, size: 18.ic, color: color),
            ],
          ),
        ),
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
          color:
              isSelected
                  ? context.colors.textPrimary.withValues(alpha: 0.05)
                  : null,
          border: Border(
            bottom: BorderSide(
              color: context.colors.divider.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28.w,
              height: 28.w,
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6.br),
              ),
              child: Icon(
                Icons.grid_view_rounded,
                size: 16.ic,
                color: context.colors.textPrimary.withValues(alpha: 0.8),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                'All Openings',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_rounded,
                size: 18.ic,
                color: context.colors.textPrimary,
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
              color: context.colors.divider.withValues(alpha: 0.3),
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
                color:
                    isSelected
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
                  color: context.colors.textPrimary.withValues(
                    alpha: isSelected ? 1.0 : 0.85,
                  ),
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Check mark if selected
            if (isSelected) ...[
              SizedBox(width: 8.w),
              Icon(Icons.check_rounded, size: 16.ic, color: color),
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
            color: isExpanded ? context.colors.textPrimary : color,
            fontSize: 13.f,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
