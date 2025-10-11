import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/utils/month_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final calendarScreenProvider = AutoDisposeStateNotifierProvider(
  (ref) => _CalendarScreenNotifier(ref),
);

class _CalendarScreenNotifier extends StateNotifier<AsyncValue<List<String>>> {
  _CalendarScreenNotifier(this.ref) : super(AsyncValue.loading()) {
    _init();
  }

  final Ref ref;

  Future<void> _init() async {
    try {
      final allMonths = ref.read(monthProvider).getAllMonthNames();

      state = AsyncValue.data(allMonths);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> onSearchTournaments(String query) async {
    try {
      state = const AsyncValue.loading();

      final broadcasts = await ref.read(supabaseSearchProvider(query).future);

      final tourEventCardModel =
          broadcasts
              .map(
                (b) => GroupEventCardModel.fromGroupBroadcast(
                  b,
                  ref.read(liveBroadcastIdsProvider),
                ),
              )
              .toList();

      final monthConverter = ref.read(monthProvider);
      final Set<String> eventMonths = {};

      for (var a = 0; a < tourEventCardModel.length; a++) {
        final start = tourEventCardModel[a].startDate;
        final end = tourEventCardModel[a].endDate;

        // Safety check in case dates are null
        if (start == null || end == null) continue;

        // Get all months from start to end
        DateTime current = DateTime(start.year, start.month);
        final endMonth = DateTime(end.year, end.month);

        while (!current.isAfter(endMonth)) {
          final monthName = monthConverter.monthNumberToName(current.month);
          eventMonths.add(monthName);
          current = DateTime(current.year, current.month + 1);
        }
      }

      final filteredMonths = eventMonths.toList();

      print('🎯 Months with events: $filteredMonths');

      state = AsyncValue.data(filteredMonths);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void reset() {
    _init();
  }
}
