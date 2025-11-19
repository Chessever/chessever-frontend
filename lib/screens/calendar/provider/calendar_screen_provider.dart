import 'package:chessever2/repository/supabase/calendar_event/calendar_event_repository.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
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

      final selectedYear = ref.read(selectedYearProvider);

      // Search both group broadcasts AND calendar events
      final broadcasts = await ref.read(supabaseSearchProvider(query).future);
      final calendarEvents = await ref
          .read(calendarEventRepositoryProvider)
          .searchCalendarEvents(query);

      // Convert broadcasts to card models
      final broadcastCards = broadcasts
          .map(
            (b) => GroupEventCardModel.fromGroupBroadcast(
              b,
              ref.read(liveBroadcastIdsProvider),
            ),
          )
          .toList();

      // Convert calendar events to card models
      final calendarCards = calendarEvents
          .map((e) => GroupEventCardModel.fromCalendarEvent(e))
          .toList();

      // Combine both lists
      final allEventCards = [...broadcastCards, ...calendarCards];

      final monthConverter = ref.read(monthProvider);
      final Set<String> eventMonths = {};

      for (var a = 0; a < allEventCards.length; a++) {
        final start = allEventCards[a].startDate;
        final end = allEventCards[a].endDate;

        // Safety check in case dates are null
        if (start == null || end == null) continue;

        // Filter: only process events that overlap with the selected year
        if (start.year > selectedYear || end.year < selectedYear) continue;

        // Get all months from start to end, but only for the selected year
        DateTime current = DateTime(start.year, start.month);
        final endMonth = DateTime(end.year, end.month);

        while (!current.isAfter(endMonth)) {
          // Only add months that are in the selected year
          if (current.year == selectedYear) {
            final monthName = monthConverter.monthNumberToName(current.month);
            eventMonths.add(monthName);
          }
          current = DateTime(current.year, current.month + 1);
        }
      }

      final filteredMonths = eventMonths.toList();

      print('🎯 Months with events in $selectedYear: $filteredMonths');

      state = AsyncValue.data(filteredMonths);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void reset() {
    _init();
  }
}
