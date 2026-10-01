import 'package:chessever2/widgets/game_filter/game_filter_choice_chips.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/game_filter/filter_popup_components.dart';
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
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
  Future<List<String>> Function()? loadAuthors,
}) => showAlertModal<CollectionSearchQuery>(
  context: context,
  horizontalPadding: 0,
  child: _Filters(query: query, loadAuthors: loadAuthors),
);

class _Filters extends StatefulWidget {
  const _Filters({required this.query, required this.loadAuthors});
  final Future<List<String>> Function()? loadAuthors;
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
  late Future<List<String>> _authors =
      widget.loadAuthors?.call() ?? Future.value(const <String>[]);
  late GameResultFilter _result = GameResultFilter.values.firstWhere(
    (value) => value.statusValue == widget.query.result,
    orElse: () => GameResultFilter.all,
  );
  late bool _limitYears =
      widget.query.year != null ||
      widget.query.minYear != null ||
      widget.query.maxYear != null;

  void _apply() => Navigator.pop(
    context,
    CollectionSearchQuery(
      text: widget.query.text,
      eco: _eco.code ?? '',
      minYear: _limitYears ? _years.start.round() : null,
      maxYear: _limitYears ? _years.end.round() : null,
      author: _author,
      authorId: widget.query.authorId,
      result: _result.statusValue ?? '',
    ),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FilterPopupFrame(
        onReset: () => Navigator.pop(
          context,
          CollectionSearchQuery(text: widget.query.text),
        ),
        onApply: _apply,
        sections: [
          const FilterSectionLabel('Opening'),
          SizedBox(height: 8.h),
          EcoFilterDropdown(
            value: _eco,
            exactCodesOnly: true,
            onChanged: (value) => setState(() => _eco = value),
          ),
          SizedBox(height: 20.h),
          const FilterSectionLabel('Game year'),
          SizedBox(height: 8.h),
          FilterChoiceGrid<bool>(
            key: const ValueKey('collection_year_filter'),
            values: const [false, true],
            label: (value) => value ? 'Year range' : 'All years',
            isSelected: (value) => _limitYears == value,
            onTap: (value) => setState(() => _limitYears = value),
          ),
          if (_limitYears) ...[
            SizedBox(height: 8.h),
            WheelRangeFilter(
              minValue: GameFilter.absoluteMinYear.toDouble(),
              maxValue: _currentYear.toDouble(),
              currentStart: _years.start,
              currentEnd: _years.end,
              divisions: _currentYear - GameFilter.absoluteMinYear,
              onChanged: (value) => setState(() => _years = value),
            ),
          ],
          SizedBox(height: 20.h),
          if (widget.loadAuthors != null) ...[
            const FilterSectionLabel('Author'),
            SizedBox(height: 8.h),
            FutureBuilder<List<String>>(
              future: _authors,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return TextButton(
                    onPressed: () =>
                        setState(() => _authors = widget.loadAuthors!()),
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
                  itemLabel: (value) => value.isEmpty ? 'All authors' : value,
                  onChanged: (value) => setState(() => _author = value),
                );
              },
            ),
            SizedBox(height: 20.h),
          ],

          const FilterSectionLabel('Result'),
          SizedBox(height: 8.h),
          GameFilterChoiceChips<GameResultFilter>(
            key: const ValueKey('collection_result_filter'),
            values: GameResultFilter.values,
            selected: _result,
            label: (value) =>
                value == GameResultFilter.all ? 'All' : value.displayText,
            onTap: (value) {
              HapticFeedbackService.selection();
              setState(() => _result = value);
            },
          ),
          SizedBox(height: 16.h),
        ],
      ),
    ),
  );
}
