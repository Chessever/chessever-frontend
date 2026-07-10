import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/liquid_glass/glass_kit.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

MiniatureGamesFilter copyMiniaturesFilter(
  MiniatureGamesFilter source, {
  MiniatureGamesWindow? window,
  MiniatureGamesSort? sort,
  MiniatureGamesSortOrder? order,
  String? search,
  bool clearSearch = false,
}) {
  return MiniatureGamesFilter(
    window: window ?? source.window,
    sort: sort ?? source.sort,
    order: order ?? source.order,
    search: clearSearch ? null : search ?? source.search,
    results: source.results,
    eco: source.eco,
    ecoCategories: source.ecoCategories,
    opening: source.opening,
    variation: source.variation,
    timeControls: source.timeControls,
    onlineStatus: source.onlineStatus,
    minRating: source.minRating,
    maxRating: source.maxRating,
    minMoves: source.minMoves,
    maxMoves: source.maxMoves,
    dateFrom: source.dateFrom,
    dateTo: source.dateTo,
    player: source.player,
    playerId: source.playerId,
  );
}

MiniatureGamesFilter resetMiniaturesFilter(
  MiniatureGamesFilter source, {
  bool preserveWindow = true,
}) {
  return MiniatureGamesFilter(
    window: preserveWindow ? source.window : MiniatureGamesWindow.all,
    sort: MiniatureGamesSort.recent,
    order: MiniatureGamesSortOrder.desc,
  );
}

int miniaturesAdvancedFilterCount(MiniatureGamesFilter filter) {
  var count = 0;
  if (filter.sort != MiniatureGamesSort.recent ||
      filter.order != MiniatureGamesSortOrder.desc) {
    count += 1;
  }
  if (filter.results.isNotEmpty) count += 1;
  if (_hasText(filter.eco) || filter.ecoCategories.isNotEmpty) count += 1;
  if (_hasText(filter.opening) || _hasText(filter.variation)) count += 1;
  if (filter.timeControls.isNotEmpty) count += 1;
  if (filter.onlineStatus != MiniatureGameOnlineStatus.all) count += 1;
  if (filter.minRating != null || filter.maxRating != null) count += 1;
  if (filter.minMoves != null || filter.maxMoves != null) count += 1;
  if (_hasText(filter.dateFrom) || _hasText(filter.dateTo)) count += 1;
  if (_hasText(filter.player) || _hasText(filter.playerId)) count += 1;
  return count;
}

bool miniaturesHasSearch(MiniatureGamesFilter filter) =>
    _hasText(filter.search);

bool _hasText(String? value) => value?.trim().isNotEmpty == true;

class MiniaturesWindowBar extends StatelessWidget {
  const MiniaturesWindowBar({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final MiniatureGamesWindow selected;
  final ValueChanged<MiniatureGamesWindow> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final window in MiniatureGamesWindow.values) ...[
            if (window != MiniatureGamesWindow.values.first)
              const SizedBox(width: 8),
            Semantics(
              button: true,
              selected: selected == window,
              label: '${_windowLabel(window)} miniatures',
              child: ExcludeSemantics(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: GlassChip(
                    key: ValueKey<String>('miniatures-window-${window.name}'),
                    label: _windowLabel(window),
                    selected: selected == window,
                    selectedColor: context.colors.brand.withValues(
                      alpha: context.isLightTheme ? 0.22 : 0.30,
                    ),
                    useOwnLayer: true,
                    labelStyle: AppTypography.textSmMedium.copyWith(
                      color:
                          selected == window
                              ? context.colors.textPrimary
                              : context.colors.tabInactive,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    onTap: () => onSelected(window),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MiniaturesFilterButton extends StatelessWidget {
  const MiniaturesFilterButton({
    required this.activeCount,
    required this.onPressed,
    super.key,
  });

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final semanticsLabel =
        activeCount == 0
            ? 'Filter and sort miniatures'
            : 'Filter and sort miniatures, $activeCount active';
    return Semantics(
      label: semanticsLabel,
      button: true,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: SizedBox.square(
          key: const ValueKey<String>('miniatures-filter-button'),
          dimension: 48,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GlassIconButton(
                icon: Icon(
                  CupertinoIcons.slider_horizontal_3,
                  color: context.colors.iconPrimary,
                ),
                onPressed: onPressed,
                size: 48,
                iconSize: 19,
                useOwnLayer: true,
              ),
              if (activeCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    key: const ValueKey<String>(
                      'miniatures-filter-active-count',
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: context.colors.brand,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      activeCount > 9 ? '9+' : '$activeCount',
                      style: AppTypography.textXxsBold.copyWith(
                        color: context.colors.textInverse,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<MiniatureGamesFilter?> showMiniaturesFilterSheet({
  required BuildContext context,
  required MiniatureGamesFilter currentFilter,
}) {
  return showModalBottomSheet<MiniatureGamesFilter>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.colors.scrim,
    builder: (context) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _MiniaturesFilterSheet(initialFilter: currentFilter),
          ),
        ),
      );
    },
  );
}

class _MiniaturesFilterSheet extends StatefulWidget {
  const _MiniaturesFilterSheet({required this.initialFilter});

  final MiniatureGamesFilter initialFilter;

  @override
  State<_MiniaturesFilterSheet> createState() => _MiniaturesFilterSheetState();
}

class _MiniaturesFilterSheetState extends State<_MiniaturesFilterSheet> {
  late MiniatureGamesSort _sort;
  late MiniatureGamesSortOrder _order;
  late Set<MiniatureGameResult> _results;
  late Set<String> _ecoCategories;
  late Set<MiniatureGameTimeControl> _timeControls;
  late MiniatureGameOnlineStatus _onlineStatus;
  late DateTime? _dateFrom;
  late DateTime? _dateTo;
  bool _playerEdited = false;

  late final TextEditingController _ecoController;
  late final TextEditingController _openingController;
  late final TextEditingController _variationController;
  late final TextEditingController _playerController;
  late final TextEditingController _minRatingController;
  late final TextEditingController _maxRatingController;
  late final TextEditingController _minMovesController;
  late final TextEditingController _maxMovesController;

  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _load(widget.initialFilter);
    _ecoController = TextEditingController(text: widget.initialFilter.eco);
    _openingController = TextEditingController(
      text: widget.initialFilter.opening,
    );
    _variationController = TextEditingController(
      text: widget.initialFilter.variation,
    );
    _playerController = TextEditingController(
      text: widget.initialFilter.player,
    );
    _minRatingController = TextEditingController(
      text: _numberText(widget.initialFilter.minRating),
    );
    _maxRatingController = TextEditingController(
      text: _numberText(widget.initialFilter.maxRating),
    );
    _minMovesController = TextEditingController(
      text: _numberText(widget.initialFilter.minMoves),
    );
    _maxMovesController = TextEditingController(
      text: _numberText(widget.initialFilter.maxMoves),
    );
  }

  @override
  void dispose() {
    _ecoController.dispose();
    _openingController.dispose();
    _variationController.dispose();
    _playerController.dispose();
    _minRatingController.dispose();
    _maxRatingController.dispose();
    _minMovesController.dispose();
    _maxMovesController.dispose();
    super.dispose();
  }

  void _load(MiniatureGamesFilter filter) {
    _sort = filter.sort;
    _order = filter.order;
    _results = Set<MiniatureGameResult>.of(filter.results);
    _ecoCategories = Set<String>.of(filter.ecoCategories);
    _timeControls = Set<MiniatureGameTimeControl>.of(filter.timeControls);
    _onlineStatus = filter.onlineStatus;
    _dateFrom = DateTime.tryParse(filter.dateFrom ?? '');
    _dateTo = DateTime.tryParse(filter.dateTo ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Column(
        children: [
          _buildHeader(),
          Divider(height: 1, color: context.colors.divider),
          Expanded(
            child: ListView(
              key: const ValueKey<String>('miniatures-filter-scroll'),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              physics: const BouncingScrollPhysics(),
              children: [
                _FilterSection(
                  title: 'Sort',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _choiceRow<MiniatureGamesSort>(
                        values: MiniatureGamesSort.values,
                        selected: {_sort},
                        label: _sortLabel,
                        onToggle: (value) => setState(() => _sort = value),
                      ),
                      const SizedBox(height: 8),
                      _choiceRow<MiniatureGamesSortOrder>(
                        values: MiniatureGamesSortOrder.values,
                        selected: {_order},
                        label: _sortOrderLabel,
                        onToggle: (value) => setState(() => _order = value),
                      ),
                    ],
                  ),
                ),
                _FilterSection(
                  title: 'Result',
                  child: _choiceRow<MiniatureGameResult>(
                    values: MiniatureGameResult.values,
                    selected: _results,
                    label: _resultLabel,
                    multiSelect: true,
                    onToggle: (value) {
                      setState(() {
                        if (!_results.remove(value)) _results.add(value);
                      });
                    },
                  ),
                ),
                _FilterSection(
                  title: 'Time control',
                  child: _choiceRow<MiniatureGameTimeControl>(
                    values: MiniatureGameTimeControl.values,
                    selected: _timeControls,
                    label: _timeControlLabel,
                    multiSelect: true,
                    onToggle: (value) {
                      setState(() {
                        if (!_timeControls.remove(value)) {
                          _timeControls.add(value);
                        }
                      });
                    },
                  ),
                ),
                _FilterSection(
                  title: 'Source',
                  child: _choiceRow<MiniatureGameOnlineStatus>(
                    values: MiniatureGameOnlineStatus.values,
                    selected: {_onlineStatus},
                    label: _onlineLabel,
                    onToggle: (value) => setState(() => _onlineStatus = value),
                  ),
                ),
                _FilterSection(
                  title: 'Average rating',
                  subtitle: 'Leave both fields empty for any rating.',
                  child: Row(
                    children: [
                      Expanded(
                        child: _NumberField(
                          key: const ValueKey<String>('miniatures-min-rating'),
                          controller: _minRatingController,
                          label: 'Minimum',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NumberField(
                          key: const ValueKey<String>('miniatures-max-rating'),
                          controller: _maxRatingController,
                          label: 'Maximum',
                        ),
                      ),
                    ],
                  ),
                ),
                _FilterSection(
                  title: 'Finish',
                  subtitle: 'Miniatures end by move 25.',
                  child: Row(
                    children: [
                      Expanded(
                        child: _NumberField(
                          key: const ValueKey<String>('miniatures-min-moves'),
                          controller: _minMovesController,
                          label: 'Minimum moves',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NumberField(
                          key: const ValueKey<String>('miniatures-max-moves'),
                          controller: _maxMovesController,
                          label: 'Maximum moves',
                        ),
                      ),
                    ],
                  ),
                ),
                _FilterSection(
                  title: 'ECO and opening',
                  subtitle: 'An exact ECO code takes priority over a category.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _choiceRow<String>(
                        values: const ['A', 'B', 'C', 'D', 'E'],
                        selected: _ecoCategories,
                        label: (value) => 'ECO $value',
                        multiSelect: true,
                        onToggle: (value) {
                          setState(() {
                            if (!_ecoCategories.remove(value)) {
                              _ecoCategories.add(value);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey<String>('miniatures-eco-field'),
                        controller: _ecoController,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 23,
                        decoration: const InputDecoration(
                          labelText: 'Exact ECO code or list',
                          hintText: 'B03 or B03,C50',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey<String>('miniatures-opening-field'),
                        controller: _openingController,
                        decoration: const InputDecoration(
                          labelText: 'Opening',
                          hintText: 'Sicilian Defense',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey<String>(
                          'miniatures-variation-field',
                        ),
                        controller: _variationController,
                        decoration: const InputDecoration(
                          labelText: 'Variation',
                          hintText: 'Najdorf',
                        ),
                      ),
                    ],
                  ),
                ),
                _FilterSection(
                  title: 'Player',
                  child: TextField(
                    key: const ValueKey<String>('miniatures-player-field'),
                    controller: _playerController,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => _playerEdited = true,
                    decoration: const InputDecoration(
                      labelText: 'Player name',
                      hintText: 'Search either color',
                    ),
                  ),
                ),
                _FilterSection(
                  title: 'Played between',
                  child: Row(
                    children: [
                      Expanded(
                        child: _DateButton(
                          key: const ValueKey<String>('miniatures-date-from'),
                          label: 'From',
                          value: _dateFrom,
                          onPressed: () => _pickDate(isFrom: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DateButton(
                          key: const ValueKey<String>('miniatures-date-to'),
                          label: 'To',
                          value: _dateTo,
                          onPressed: () => _pickDate(isFrom: false),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_validationMessage case final message?) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      key: const ValueKey<String>(
                        'miniatures-filter-validation',
                      ),
                      style: AppTypography.textSmMedium.copyWith(
                        color: context.colors.danger,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.divider),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filter miniatures',
                  style: AppTypography.textLgBold.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Search and filters are available with Premium.',
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Close miniature filters',
            child: IconButton(
              key: const ValueKey<String>('miniatures-filter-close'),
              onPressed: () => Navigator.of(context).pop(),
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: const Icon(CupertinoIcons.xmark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey<String>('miniatures-filter-reset'),
                onPressed: _reset,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Reset filters'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const ValueKey<String>('miniatures-filter-apply'),
                onPressed: _apply,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: context.colors.brand,
                  foregroundColor: context.colors.textInverse,
                ),
                child: const Text('Apply filters'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceRow<T>({
    required List<T> values,
    required Set<T> selected,
    required String Function(T value) label,
    required ValueChanged<T> onToggle,
    bool multiSelect = false,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (multiSelect)
          _OptionChip(
            label: 'Any',
            selected: selected.isEmpty,
            onSelected: (_) {
              setState(() {
                if (T == MiniatureGameResult) {
                  _results.clear();
                } else if (T == MiniatureGameTimeControl) {
                  _timeControls.clear();
                }
              });
            },
          ),
        for (final value in values)
          _OptionChip(
            label: label(value),
            selected: selected.contains(value),
            onSelected: (_) => onToggle(value),
          ),
      ],
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final selected = isFrom ? _dateFrom : _dateTo;
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: selected ?? now,
      firstDate: DateTime(1800),
      lastDate: now.add(const Duration(days: 1)),
      helpText: isFrom ? 'Games from' : 'Games through',
    );
    if (result == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _dateFrom = result;
      } else {
        _dateTo = result;
      }
    });
  }

  void _reset() {
    setState(() {
      _sort = MiniatureGamesSort.recent;
      _order = MiniatureGamesSortOrder.desc;
      _results.clear();
      _ecoCategories.clear();
      _timeControls.clear();
      _onlineStatus = MiniatureGameOnlineStatus.all;
      _dateFrom = null;
      _dateTo = null;
      _ecoController.clear();
      _openingController.clear();
      _variationController.clear();
      _playerController.clear();
      _playerEdited = true;
      _minRatingController.clear();
      _maxRatingController.clear();
      _minMovesController.clear();
      _maxMovesController.clear();
      _validationMessage = null;
    });
  }

  void _apply() {
    final minRating = _optionalInt(_minRatingController.text);
    final maxRating = _optionalInt(_maxRatingController.text);
    final minMoves = _optionalInt(_minMovesController.text);
    final maxMoves = _optionalInt(_maxMovesController.text);

    final validation = _validateRanges(
      minRating: minRating,
      maxRating: maxRating,
      minMoves: minMoves,
      maxMoves: maxMoves,
    );
    if (validation != null) {
      setState(() => _validationMessage = validation);
      return;
    }

    final exactEco = _normalized(_ecoController.text, uppercase: true);
    Navigator.of(context).pop(
      MiniatureGamesFilter(
        window: widget.initialFilter.window,
        sort: _sort,
        order: _order,
        search: widget.initialFilter.search,
        results: Set<MiniatureGameResult>.unmodifiable(_results),
        eco: exactEco,
        ecoCategories:
            exactEco == null
                ? Set<String>.unmodifiable(_ecoCategories)
                : const <String>{},
        opening: _normalized(_openingController.text),
        variation: _normalized(_variationController.text),
        timeControls: Set<MiniatureGameTimeControl>.unmodifiable(_timeControls),
        onlineStatus: _onlineStatus,
        minRating: minRating,
        maxRating: maxRating,
        minMoves: minMoves,
        maxMoves: maxMoves,
        dateFrom: _dateFrom == null ? null : _isoDate(_dateFrom!),
        dateTo: _dateTo == null ? null : _isoDate(_dateTo!),
        player: _normalized(_playerController.text),
        playerId: _playerEdited ? null : widget.initialFilter.playerId,
      ),
    );
  }

  String? _validateRanges({
    required int? minRating,
    required int? maxRating,
    required int? minMoves,
    required int? maxMoves,
  }) {
    if (minRating != null && (minRating < 0 || minRating > 4000) ||
        maxRating != null && (maxRating < 0 || maxRating > 4000)) {
      return 'Ratings must be between 0 and 4000.';
    }
    if (minRating != null && maxRating != null && minRating > maxRating) {
      return 'Minimum rating cannot exceed maximum rating.';
    }
    if (minMoves != null && (minMoves < 3 || minMoves > 25) ||
        maxMoves != null && (maxMoves < 3 || maxMoves > 25)) {
      return 'Move limits must be between 3 and 25.';
    }
    if (minMoves != null && maxMoves != null && minMoves > maxMoves) {
      return 'Minimum moves cannot exceed maximum moves.';
    }
    if (_dateFrom != null && _dateTo != null && _dateFrom!.isAfter(_dateTo!)) {
      return 'The start date must be before the end date.';
    }
    return null;
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.textMdBold.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          if (subtitle case final copy?) ...[
            const SizedBox(height: 3),
            Text(
              copy,
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          child,
          const SizedBox(height: 16),
          Divider(height: 1, color: context.colors.divider),
        ],
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: onSelected,
        showCheckmark: true,
        selectedColor: context.colors.brand.withValues(
          alpha: context.isLightTheme ? 0.18 : 0.26,
        ),
        side: BorderSide(
          color: selected ? context.colors.brand : context.colors.dividerStrong,
        ),
        labelStyle: AppTypography.textSmMedium.copyWith(
          color: context.colors.textPrimary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    super.key,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onPressed,
    super.key,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        alignment: Alignment.centerLeft,
      ),
      icon: const Icon(CupertinoIcons.calendar, size: 18),
      label: Text(value == null ? label : _isoDate(value!)),
    );
  }
}

String _windowLabel(MiniatureGamesWindow window) => switch (window) {
  MiniatureGamesWindow.today => 'Today',
  MiniatureGamesWindow.week => 'Week',
  MiniatureGamesWindow.all => 'All time',
};

String _sortLabel(MiniatureGamesSort sort) => switch (sort) {
  MiniatureGamesSort.rating => 'Rating',
  MiniatureGamesSort.moves => 'Moves',
  MiniatureGamesSort.recent => 'Recent',
};

String _sortOrderLabel(MiniatureGamesSortOrder order) => switch (order) {
  MiniatureGamesSortOrder.asc => 'Ascending',
  MiniatureGamesSortOrder.desc => 'Descending',
};

String _resultLabel(MiniatureGameResult result) => switch (result) {
  MiniatureGameResult.whiteWins => 'White wins',
  MiniatureGameResult.blackWins => 'Black wins',
};

String _timeControlLabel(MiniatureGameTimeControl control) => switch (control) {
  MiniatureGameTimeControl.classical => 'Classical',
  MiniatureGameTimeControl.rapid => 'Rapid',
  MiniatureGameTimeControl.blitz => 'Blitz',
};

String _onlineLabel(MiniatureGameOnlineStatus status) => switch (status) {
  MiniatureGameOnlineStatus.all => 'Any source',
  MiniatureGameOnlineStatus.online => 'Online',
  MiniatureGameOnlineStatus.offline => 'Over the board',
};

String? _normalized(String value, {bool uppercase = false}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return uppercase ? trimmed.toUpperCase() : trimmed;
}

int? _optionalInt(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : int.tryParse(trimmed);
}

String _numberText(int? value) => value == null ? '' : '$value';

String _isoDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
