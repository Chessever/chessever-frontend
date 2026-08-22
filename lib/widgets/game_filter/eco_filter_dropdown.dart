import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:flutter/material.dart';

class _EcoBrowseNode {
  _EcoBrowseNode({
    required this.suggestion,
    required this.depth,
    required this.ancestorIds,
  });

  final OpeningSearchSuggestion suggestion;
  final int depth;
  final List<String> ancestorIds;
  final List<_EcoBrowseNode> children = <_EcoBrowseNode>[];
}

Map<String, List<_EcoBrowseNode>> _buildEcoBrowseTree(
  List<OpeningSearchSuggestion> suggestions,
) {
  final grouped = <String, List<OpeningSearchSuggestion>>{};
  for (final suggestion in suggestions) {
    final category = suggestion.filter.categoryLetter;
    if (category != null) {
      grouped.putIfAbsent(category, () => []).add(suggestion);
    }
  }

  final result = <String, List<_EcoBrowseNode>>{};
  for (final entry in grouped.entries) {
    final nodesById = <String, _EcoBrowseNode>{};
    final parentById = <String, OpeningSearchSuggestion?>{};
    final uniqueSuggestions = <OpeningSearchSuggestion>[];
    final seenIds = <String>{};
    for (final suggestion in entry.value) {
      if (seenIds.add(suggestion.id)) uniqueSuggestions.add(suggestion);
    }

    for (final suggestion in uniqueSuggestions) {
      OpeningSearchSuggestion? nearestParent;
      for (final candidate in uniqueSuggestions) {
        if (!candidate.isFamily || candidate.id == suggestion.id) continue;
        final parentCodes = candidate.filter.exactEcoCodes;
        final childCodes = suggestion.filter.exactEcoCodes;
        if (parentCodes.length <= childCodes.length ||
            !childCodes.every(parentCodes.contains)) {
          continue;
        }
        final moveCompatible =
            candidate.movePath.isEmpty ||
            suggestion.movePath.isEmpty ||
            EcoOpenings.isMovePrefix(candidate.movePath, suggestion.movePath);
        if (suggestion.isFamily && !moveCompatible) continue;
        if (nearestParent == null ||
            _compareParentCandidates(
                  candidate,
                  nearestParent,
                  child: suggestion,
                ) <
                0) {
          nearestParent = candidate;
        }
      }
      parentById[suggestion.id] = nearestParent;
    }

    List<String> ancestorsFor(OpeningSearchSuggestion suggestion) {
      final ancestors = <String>[];
      var parent = parentById[suggestion.id];
      final visited = <String>{suggestion.id};
      while (parent != null && visited.add(parent.id)) {
        ancestors.insert(0, parent.id);
        parent = parentById[parent.id];
      }
      return ancestors;
    }

    for (final suggestion in uniqueSuggestions) {
      final ancestors = ancestorsFor(suggestion);
      nodesById[suggestion.id] = _EcoBrowseNode(
        suggestion: suggestion,
        depth: ancestors.length,
        ancestorIds: ancestors,
      );
    }

    final roots = <_EcoBrowseNode>[];
    for (final suggestion in uniqueSuggestions) {
      final node = nodesById[suggestion.id]!;
      final parent = parentById[suggestion.id];
      if (parent == null) {
        roots.add(node);
      } else {
        nodesById[parent.id]?.children.add(node);
      }
    }
    _sortBrowseNodes(roots);
    result[entry.key] = roots;
  }
  return result;
}

int _compareParentCandidates(
  OpeningSearchSuggestion left,
  OpeningSearchSuggestion right, {
  required OpeningSearchSuggestion child,
}) {
  bool moveCompatible(OpeningSearchSuggestion candidate) =>
      candidate.movePath.isEmpty ||
      child.movePath.isEmpty ||
      EcoOpenings.isMovePrefix(candidate.movePath, child.movePath);

  final leftCompatible = moveCompatible(left);
  final rightCompatible = moveCompatible(right);
  if (leftCompatible != rightCompatible) return leftCompatible ? -1 : 1;
  final scopeSize = left.filter.exactEcoCodes.length.compareTo(
    right.filter.exactEcoCodes.length,
  );
  final moveDepth = right.movePath.length.compareTo(left.movePath.length);
  if (child.isFamily) {
    if (scopeSize != 0) return scopeSize;
    if (moveDepth != 0) return moveDepth;
  } else {
    if (moveDepth != 0) return moveDepth;
    if (scopeSize != 0) return scopeSize;
  }
  return _compareBrowseSuggestions(left, right);
}

void _sortBrowseNodes(List<_EcoBrowseNode> nodes) {
  nodes.sort(
    (left, right) =>
        _compareBrowseSuggestions(left.suggestion, right.suggestion),
  );
  for (final node in nodes) {
    _sortBrowseNodes(node.children);
  }
}

int _compareBrowseSuggestions(
  OpeningSearchSuggestion left,
  OpeningSearchSuggestion right,
) {
  int startOf(OpeningSearchSuggestion suggestion) {
    final family = EcoOpenings.getFamily(suggestion.filter.code);
    final code = family?.rangeStart ?? suggestion.filter.code!;
    return int.parse(code.substring(1));
  }

  int endOf(OpeningSearchSuggestion suggestion) {
    final family = EcoOpenings.getFamily(suggestion.filter.code);
    final code = family?.rangeEnd ?? suggestion.filter.code!;
    return int.parse(code.substring(1));
  }

  final start = startOf(left).compareTo(startOf(right));
  if (start != 0) return start;
  if (left.isFamily != right.isFamily) return left.isFamily ? -1 : 1;
  if (left.isFamily && right.isFamily) {
    final widerFirst = right.filter.exactEcoCodes.length.compareTo(
      left.filter.exactEcoCodes.length,
    );
    if (widerFirst != 0) return widerFirst;
  }
  final end = endOf(left).compareTo(endOf(right));
  if (end != 0) return end;
  final name = left.fullTitle.toLowerCase().compareTo(
    right.fullTitle.toLowerCase(),
  );
  if (name != 0) return name;
  return left.id.compareTo(right.id);
}

/// Searchable opening filter with parent families, exact ECO choices, and
/// named variations.
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
  late final Map<String, List<_EcoBrowseNode>> _browseRoots;
  final Set<String> _expandedCategories = <String>{};
  final Set<String> _expandedBrowseNodes = <String>{};

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
    _browseRoots = _buildEcoBrowseTree(browseOpeningSuggestions());
    _resetBrowseDisclosure(widget.value);
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
  void didUpdateWidget(covariant EcoFilterDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_isExpanded) {
      _resetBrowseDisclosure(widget.value);
    }
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
        _resetBrowseDisclosure(widget.value);
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
    _resetBrowseDisclosure(item);
    _toggleExpanded();
  }

  void _resetBrowseDisclosure(GameEcoFilter filter) {
    _expandedCategories.clear();
    _expandedBrowseNodes.clear();
    if (filter.isAll || filter.isUnknownEco) return;

    final category = filter.categoryLetter;
    if (category == null) return;
    _expandedCategories.add(category);

    final selected = _findBrowseNode(
      _browseRoots[category] ?? const <_EcoBrowseNode>[],
      filter,
    );
    if (selected != null) {
      _expandedBrowseNodes.addAll(selected.ancestorIds);
    }
  }

  _EcoBrowseNode? _findBrowseNode(
    List<_EcoBrowseNode> nodes,
    GameEcoFilter filter,
  ) {
    for (final node in nodes) {
      if (node.suggestion.filter == filter) return node;
      final match = _findBrowseNode(node.children, filter);
      if (match != null) return match;
    }
    return null;
  }

  void _toggleCategory(String category) {
    setState(() {
      if (!_expandedCategories.add(category)) {
        _expandedCategories.remove(category);
      }
    });
  }

  void _toggleBrowseNode(String id) {
    setState(() {
      if (!_expandedBrowseNodes.add(id)) {
        _expandedBrowseNodes.remove(id);
      }
    });
  }

  Color _getCategoryColor(String? letter) {
    if (letter == null) return context.colors.textPrimary;
    return _categoryColors[letter.toUpperCase()] ?? context.colors.textPrimary;
  }

  List<OpeningSearchSuggestion> _getOpeningSuggestions() {
    final query = _searchQuery.trim();
    if (query.isEmpty) return browseOpeningSuggestions();
    return searchOpeningSuggestions(query);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header (collapsed state)
        GestureDetector(
          key: const ValueKey('eco-dropdown-header'),
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
                  ? IconButton(
                    tooltip: 'Clear opening search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(0);
                      }
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18.ic,
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
    final isBrowsing = _searchQuery.trim().isEmpty;
    final suggestions =
        isBrowsing
            ? const <OpeningSearchSuggestion>[]
            : _getOpeningSuggestions();

    if (!isBrowsing && suggestions.isEmpty) {
      final typedCharacters =
          _searchQuery.replaceAll(RegExp(r'\s+'), '').length;
      final needsMoreCharacters =
          _searchQuery.trim().isNotEmpty &&
          typedCharacters < minimumOpeningSearchCharacters;
      return Padding(
        padding: EdgeInsets.all(20.sp),
        child: Text(
          needsMoreCharacters
              ? 'Type at least $minimumOpeningSearchCharacters letters'
              : 'No openings found',
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      );
    }

    final grouped = <String, List<OpeningSearchSuggestion>>{};
    for (final suggestion in suggestions) {
      final category = suggestion.filter.categoryLetter;
      if (category == null) continue;
      grouped.putIfAbsent(category, () => []).add(suggestion);
    }
    final availableCategories = isBrowsing ? _browseRoots.keys : grouped.keys;
    final categories = <String>[
      for (final category in const ['A', 'B', 'C', 'D', 'E'])
        if (availableCategories.contains(category)) category,
    ];

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      radius: Radius.circular(4.br),
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // "All Openings" option at top
            if (isBrowsing) _buildAllOpeningsOption(),

            if (isBrowsing)
              // Families and exact-code summaries share one parent-first
              // sequence inside each ECO category.
              for (final category in categories) ...[
                _buildCategoryHeader(
                  category,
                  isExpanded: _expandedCategories.contains(category),
                ),
                if (_expandedCategories.contains(category))
                  for (final node in _visibleBrowseNodes(category))
                    _buildSuggestionItem(
                      node.suggestion,
                      treeDepth: node.depth,
                      hasChildren: node.children.isNotEmpty,
                      isExpanded: _expandedBrowseNodes.contains(
                        node.suggestion.id,
                      ),
                      onToggle:
                          node.children.isEmpty
                              ? null
                              : () => _toggleBrowseNode(node.suggestion.id),
                    ),
              ]
            else
              // Search order is global relevance plus ancestry. Regrouping it
              // alphabetically by A-E would bury a strong E-family hit below
              // incidental A-code aliases.
              ...suggestions.map(_buildSuggestionItem),
          ],
        ),
      ),
    );
  }

  List<_EcoBrowseNode> _visibleBrowseNodes(String category) {
    final visible = <_EcoBrowseNode>[];

    void append(List<_EcoBrowseNode> nodes) {
      for (final node in nodes) {
        visible.add(node);
        if (_expandedBrowseNodes.contains(node.suggestion.id)) {
          append(node.children);
        }
      }
    }

    append(_browseRoots[category] ?? const <_EcoBrowseNode>[]);
    return visible;
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

  Widget _buildCategoryHeader(String category, {required bool isExpanded}) {
    final color = _getCategoryColor(category);
    final categoryInfo = EcoOpenings.getCategory(category);

    return Semantics(
      button: true,
      expanded: isExpanded,
      label:
          '${isExpanded ? 'Collapse' : 'Expand'} ECO $category, '
          '${categoryInfo?.name ?? ''}',
      child: InkWell(
        key: ValueKey('eco-category-$category'),
        onTap: () => _toggleCategory(category),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            border: Border(
              bottom: BorderSide(color: color.withValues(alpha: 0.15)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24.w,
                height: 24.w,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4.br),
                ),
                alignment: Alignment.center,
                child: Text(
                  category,
                  style: AppTypography.textSmBold.copyWith(
                    color: color,
                    fontSize: 12.f,
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  categoryInfo?.name ?? '',
                  style: AppTypography.textSmMedium.copyWith(color: color),
                ),
              ),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20.ic,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionItem(
    OpeningSearchSuggestion suggestion, {
    int? treeDepth,
    bool hasChildren = false,
    bool isExpanded = false,
    VoidCallback? onToggle,
  }) {
    final code = suggestion.filter.code!;
    final color = _getCategoryColor(suggestion.filter.categoryLetter);
    final isSelected = widget.value == suggestion.filter;
    final hierarchyDepth = suggestion.hierarchyLabel.split(' › ').length - 1;
    final depth = treeDepth ?? hierarchyDepth;
    final visibleDepth = depth > 3 ? 3 : depth;
    final hierarchyParts = suggestion.hierarchyLabel.split(' › ');
    final displayTitle = hierarchyParts.last;
    final supportingText =
        hierarchyParts.length > 1
            ? hierarchyParts.take(hierarchyParts.length - 1).join(' › ')
            : '';

    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Select ${suggestion.fullTitle}, ECO ${suggestion.codeLabel}',
      child: GestureDetector(
        key: ValueKey(
          suggestion.isFamily
              ? 'eco-family-$code'
              : suggestion.isAggregate
              ? 'eco-code-$code'
              : 'eco-line-${suggestion.id}',
        ),
        onTap: () => _selectItem(suggestion.filter),
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: BoxConstraints(minHeight: 54.h),
          padding: EdgeInsets.fromLTRB(
            16.w + visibleDepth * 6.w,
            8.h,
            16.w,
            8.h,
          ),
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
              Container(
                width: 62.w,
                constraints: const BoxConstraints(minHeight: 26),
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
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
                alignment: Alignment.center,
                child: Text(
                  suggestion.codeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: AppTypography.textXsBold.copyWith(
                    color: color,
                    fontSize: 10.f,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textPrimary.withValues(
                          alpha: isSelected ? 1.0 : 0.9,
                        ),
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (supportingText.isNotEmpty) ...[
                      SizedBox(height: 2.h),
                      Text(
                        supportingText,
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected) ...[
                SizedBox(width: 8.w),
                Icon(Icons.check_rounded, size: 16.ic, color: color),
              ],
              if (hasChildren) ...[
                SizedBox(width: 4.w),
                IconButton(
                  key: ValueKey('eco-expand-${suggestion.id}'),
                  onPressed: onToggle,
                  tooltip:
                      '${isExpanded ? 'Collapse' : 'Expand'} '
                      '${suggestion.fullTitle}',
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  padding: EdgeInsets.zero,
                  icon: AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20.ic,
                      color: color,
                    ),
                  ),
                ),
              ],
            ],
          ),
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
