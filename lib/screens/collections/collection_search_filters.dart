import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/game_filter/eco_filter_dropdown.dart';
import 'package:chessever2/widgets/game_filter/expandable_filter_dropdown.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/wheel_range_filter.dart';
import 'package:flutter/material.dart';

Future<CollectionSearchQuery?> showCollectionSearchFilters(
  BuildContext context,
  CollectionSearchQuery query, {
  required Future<List<String>> Function() loadAuthors,
}) => showAlertModal<CollectionSearchQuery>(
  context: context,
  horizontalPadding: 20,
  child: _Filters(query: query, loadAuthors: loadAuthors),
);

class _Filters extends StatefulWidget {
  const _Filters({required this.query, required this.loadAuthors});
  final Future<List<String>> Function() loadAuthors;
  final CollectionSearchQuery query;
  @override
  State<_Filters> createState() => _FiltersState();
}

class _FiltersState extends State<_Filters> {
  late GameEcoFilter _eco = widget.query.eco.isEmpty
      ? GameEcoFilter.all
      : GameEcoFilter.forCode(widget.query.eco);
  final _currentYear = DateTime.now().year;
  late RangeValues _years = RangeValues(
    (widget.query.minYear ?? widget.query.year ?? _currentYear - 1).toDouble(),
    (widget.query.maxYear ?? widget.query.year ?? _currentYear).toDouble(),
  );
  late String _author = widget.query.author;
  late Future<List<String>> _authors = widget.loadAuthors();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      // The shared popup handles presentation; keep the form above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        width: 320.w,
        constraints: BoxConstraints(maxHeight: 600.h),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16.br),
          border: Border.all(
            color: context.colors.textPrimary.withValues(alpha: 0.1),
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
        child: Material(
          type: MaterialType.transparency,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Search filters',
                        style: AppTypography.textMdBold.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(
                          context,
                          CollectionSearchQuery(text: widget.query.text),
                        );
                      },
                      child: const Text('Reset'),
                    ),
                    IconButton(
                      tooltip: 'Close filters',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20.ic,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _label('Opening'),
                SizedBox(height: 8.h),
                EcoFilterDropdown(
                  value: _eco,
                  exactCodesOnly: true,
                  onChanged: (value) => setState(() => _eco = value),
                ),
                SizedBox(height: 16.h),
                _label('Game year'),
                SizedBox(height: 8.h),
                WheelRangeFilter(
                  minValue: GameFilter.absoluteMinYear.toDouble(),
                  maxValue: _currentYear.toDouble(),
                  currentStart: _years.start,
                  currentEnd: _years.end,
                  divisions: _currentYear - GameFilter.absoluteMinYear,
                  onChanged: (value) => setState(() => _years = value),
                ),
                SizedBox(height: 16.h),
                _label('Author'),
                SizedBox(height: 8.h),
                FutureBuilder<List<String>>(
                  future: _authors,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return TextButton(
                        onPressed: () =>
                            setState(() => _authors = widget.loadAuthors()),
                        child: const Text('Retry loading authors'),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Loading authors…'),
                      );
                    }
                    return ExpandableFilterDropdown<String>(
                      key: const ValueKey('collections_author'),
                      value: _author,
                      items: [
                        '',
                        ...{...snapshot.data!, if (_author.isNotEmpty) _author},
                      ],
                      itemLabel: (value) =>
                          value.isEmpty ? 'All authors' : value,
                      onChanged: (value) => setState(() => _author = value),
                    );
                  },
                ),
                SizedBox(height: 16.h),
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      CollectionSearchQuery(
                        text: widget.query.text,
                        eco: _eco.code ?? '',
                        minYear: _years.start.round(),
                        maxYear: _years.end.round(),
                        author: _author,
                      ),
                    );
                  },
                  child: const Text('Apply filters'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget _label(String text) => Text(
    text,
    style: AppTypography.textSmMedium.copyWith(
      color: context.colors.textPrimary,
    ),
  );
}
