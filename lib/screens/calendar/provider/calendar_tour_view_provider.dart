import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';

final calendarTourViewProvider = StateNotifierProvider.family<
  _CalendarTourViewController,
  AsyncValue<List<GroupEventCardModel>>,
  CalendarFilterArgs
>((ref, args) {
  final liveIdsAsync = ref.watch(liveGroupBroadcastIdsProvider);
  return _CalendarTourViewController(
    ref: ref,
    month: args.month,
    year: args.year,
    liveIdsAsync: liveIdsAsync,
  );
});

class _CalendarTourViewController
    extends StateNotifier<AsyncValue<List<GroupEventCardModel>>> {
  _CalendarTourViewController({
    required this.ref,
    required this.month,
    required this.year,
    required this.liveIdsAsync,
  }) : super(const AsyncValue.loading()) {
    _init();
  }

  final Ref ref;
  final int? month;
  final int? year;
  final AsyncValue<List<String>> liveIdsAsync;

  Future<void> _init() async {
    try {
      final liveIds = liveIdsAsync.value ?? <String>[];

      final current =
          await ref
              .read(groupBroadcastLocalStorage(GroupEventCategory.current))
              .getGroupBroadcasts();
      final upcoming =
          await ref
              .read(groupBroadcastLocalStorage(GroupEventCategory.upcoming))
              .getGroupBroadcasts();

      final tours = [...current, ...upcoming];

      if (tours.isEmpty) {
        state = const AsyncValue.data([]);
        return;
      }

      final selectedMonth = ref.read(selectedMonthProvider);
      final selectedYear = ref.read(selectedYearProvider);

      final filtered =
          tours.where((t) {
            if (t.dateStart == null || t.dateEnd == null) return false;

            final monthStart = DateTime(selectedYear, selectedMonth, 1);
            final monthEnd = DateTime(selectedYear, selectedMonth + 1, 0);

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

      state = AsyncValue.data(cards);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> search(String query) async {
    try {
      final liveIds = liveIdsAsync.value ?? <String>[];
      final current =
          await ref
              .read(groupBroadcastLocalStorage(GroupEventCategory.current))
              .getGroupBroadcasts();
      final upcoming =
          await ref
              .read(groupBroadcastLocalStorage(GroupEventCategory.upcoming))
              .getGroupBroadcasts();

      final tours = [...current, ...upcoming];

      final selectedMonth = ref.read(selectedMonthProvider);
      final selectedYear = ref.read(selectedYearProvider);

      final monthStart = DateTime(selectedYear, selectedMonth, 1);
      final monthEnd = DateTime(selectedYear, selectedMonth + 1, 0);

      var filtered =
          tours.where((t) {
            if (t.dateStart == null || t.dateEnd == null) return false;
            return t.dateStart!.isBefore(
                  monthEnd.add(const Duration(days: 1)),
                ) &&
                t.dateEnd!.isAfter(
                  monthStart.subtract(const Duration(days: 1)),
                );
          }).toList();

      final q = query.trim().toLowerCase();
      if (q.isNotEmpty) {
        filtered =
            filtered.where((t) {
              final nameMatch = t.name.toLowerCase().contains(q);
              final tcMatch = t.timeControl?.toLowerCase().contains(q) ?? false;
              return nameMatch || tcMatch;
            }).toList();

        filtered.sort((a, b) {
          int score(GroupBroadcast t) {
            final name = t.name.toLowerCase();
            final tc = t.timeControl?.toLowerCase() ?? '';

            if (name == q || tc == q) return 100;
            if (name.startsWith(q) || tc.startsWith(q)) return 10;
            if (name.contains(q) || tc.contains(q)) return 1;
            return 0;
          }

          return score(b).compareTo(score(a));
        });
      }
      final cards =
          filtered
              .map((t) => GroupEventCardModel.fromGroupBroadcast(t, liveIds))
              .toList();

      state = AsyncValue.data(cards);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

class CalendarFilterArgs {
  final int? month;
  final int? year;

  const CalendarFilterArgs({this.month, this.year});

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
