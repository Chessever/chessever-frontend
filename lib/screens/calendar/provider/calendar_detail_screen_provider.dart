import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final calendarDetailScreenProvider = AutoDisposeStateNotifierProvider.family<
  _CalendarDetailScreenController,
  AsyncValue<List<GroupEventCardModel>>,
  CalendarFilterArgs
>((ref, filterArges) {
  return _CalendarDetailScreenController(ref: ref, filterArgs: filterArges);
});

class _CalendarDetailScreenController
    extends StateNotifier<AsyncValue<List<GroupEventCardModel>>> {
  _CalendarDetailScreenController({required this.ref, required this.filterArgs})
    : super(const AsyncValue.loading()) {
    _init();
    _listenToLiveIds();
  }

  final Ref ref;
  final CalendarFilterArgs filterArgs;

  List<GroupBroadcast> groupBroadcast = [];

  Future<void> _init({List<String>? newLiveId}) async {
    try {
      final liveIds = newLiveId ?? <String>[];

      final current = await ref
          .read(groupBroadcastRepositoryProvider)
          .getCurrentMonthGroupBroadcasts(
            selectedMonth: filterArgs.month,
            selectedYear: filterArgs.year,
          );

      groupBroadcast = current;

      final tours = [...current];

      if (tours.isEmpty) {
        state = const AsyncValue.data([]);
        return;
      }

      final filtered =
          tours.where((t) {
            if (t.dateStart == null || t.dateEnd == null) return false;

            final monthStart = DateTime(filterArgs.year, filterArgs.month, 1);
            final monthEnd = DateTime(filterArgs.year, filterArgs.month + 1, 0);

            return t.dateStart!.isBefore(
                  monthEnd.add(const Duration(days: 1)),
                ) &&
                t.dateEnd!.isAfter(
                  monthStart.subtract(const Duration(days: 1)),
                );
          }).toList();

      final cards =
          filtered
              .map((t) => GroupEventCardModel.fromGroupBroadcast(t, liveIds))
              .toList();

      final sortedEvents = ref
          .read(tournamentSortingServiceProvider)
          .sortAllTours(cards);

      state = AsyncValue.data(sortedEvents);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _listenToLiveIds() {
    ref.listen<AsyncValue<List<String>>>(liveGroupBroadcastIdsProvider, (
      previous,
      next,
    ) {
      next.whenData((liveIds) {
        // Only update if live IDs actually changed
        if (ref.read(liveBroadcastIdsProvider).length != liveIds.length ||
            !ref
                .read(liveBroadcastIdsProvider)
                .every((id) => liveIds.contains(id))) {
          ref.read(liveBroadcastIdsProvider.notifier).state = liveIds;
          _init(newLiveId: liveIds);
        }
      });
    });
  }

  Future<void> search(String query) async {
    try {
      final tours = groupBroadcast.map(
        (e) => GroupEventCardModel.fromGroupBroadcast(
          e,
          ref.read(liveBroadcastIdsProvider),
        ),
      );

      final selectedMonth = ref.read(selectedMonthProvider);
      final selectedYear = ref.read(selectedYearProvider);

      final monthStart = DateTime(selectedYear, selectedMonth, 1);
      final monthEnd = DateTime(selectedYear, selectedMonth + 1, 0);

      var filtered =
          tours.where((t) {
            if (t.startDate == null || t.endDate == null) return false;
            return t.startDate!.isBefore(
                  monthEnd.add(const Duration(days: 1)),
                ) &&
                t.endDate!.isAfter(
                  monthStart.subtract(const Duration(days: 1)),
                );
          }).toList();

      final q = query.trim().toLowerCase();
      if (q.isNotEmpty) {
        filtered =
            filtered.where((t) {
              final nameMatch = t.title.toLowerCase().contains(q);
              final tcMatch = t.timeControl.toLowerCase().contains(q);
              return nameMatch || tcMatch;
            }).toList();

        filtered.sort((a, b) {
          int score(GroupEventCardModel t) {
            final name = t.title.toLowerCase();
            final tc = t.timeControl.toLowerCase();

            if (name == q || tc == q) return 100;
            if (name.startsWith(q) || tc.startsWith(q)) return 10;
            if (name.contains(q) || tc.contains(q)) return 1;
            return 0;
          }

          return score(b).compareTo(score(a));
        });
      }

      state = AsyncValue.data(filtered);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    await _init();
  }
}

class CalendarFilterArgs {
  final int month;
  final int year;

  const CalendarFilterArgs({required this.month, required this.year});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarFilterArgs &&
          runtimeType == other.runtimeType &&
          month == other.month &&
          year == other.year;

  @override
  int get hashCode => month.hashCode ^ year.hashCode;
}
