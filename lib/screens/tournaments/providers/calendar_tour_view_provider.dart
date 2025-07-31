import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/screens/calendar_screen.dart';
import 'package:chessever2/screens/tournaments/model/tour_event_card_model.dart';
import 'package:chessever2/screens/tournaments/tournament_screen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final calendarTourViewProvider = AutoDisposeStateNotifierProvider.family((
  ref,
  CalendarFilterArgs args,
) {
  return _CalendarTourViewController(
    ref: ref,
    month: args.month,
    year: args.year,
  );
});

class _CalendarTourViewController
    extends StateNotifier<AsyncValue<List<TourEventCardModel>>> {
  _CalendarTourViewController({
    required this.ref,
    required this.month,
    required this.year,
  }) : super(const AsyncValue.loading()) {
    _init();
  }

  final Ref ref;
  final int? month;
  final int? year;

  Future<void> _init() async {
    try {
      final allBroadCast =
          await ref
              .read(groupBroadcastLocalStorage(TournamentCategory.current))
              .getGroupBroadcasts();
      final upcomingBroadCast =
          await ref
              .read(groupBroadcastLocalStorage(TournamentCategory.current))
              .getGroupBroadcasts();

      if (allBroadCast.isEmpty && upcomingBroadCast.isEmpty) {
        state = const AsyncValue.data([]);
        return;
      }

      final selectedMonth = ref.read(selectedMonthProvider);
      final selectedYear = ref.read(selectedYearProvider);

      var tours = [...allBroadCast, ...upcomingBroadCast];

      final filteredTours =
          tours.where((tour) {
            if (tour.dateStart == null || tour.dateEnd == null) return false;

            final startDate = tour.dateStart!;
            final endDate = tour.dateEnd!;

            // Create date range for selected month
            final monthStart = DateTime(selectedYear, selectedMonth, 1);
            final monthEnd = DateTime(selectedYear, selectedMonth + 1, 0);

            // Check if tournament date range overlaps with selected month
            return startDate.isBefore(monthEnd.add(Duration(days: 1))) &&
                endDate.isAfter(monthStart.subtract(Duration(days: 1)));
          }).toList();

      final filteredTourEventCards =
          filteredTours
              .map((t) => TourEventCardModel.fromGroupBroadcast(t))
              .toList();

      state = AsyncValue.data(filteredTourEventCards);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  //todo:
  Future<void> search(String query) async {
    try {
      final allBroadCast =
          await ref
              .read(groupBroadcastLocalStorage(TournamentCategory.current))
              .getGroupBroadcasts();
      final upcomingBroadCast =
          await ref
              .read(groupBroadcastLocalStorage(TournamentCategory.current))
              .getGroupBroadcasts();

      if (query.isEmpty) {
        _init(); // fallback to filtered list if query is empty
        return;
      }

      var tours = [...allBroadCast, ...upcomingBroadCast];
      final filteredTours =
          tours.where((tour) {
            final matchesText =
                tour.name.toLowerCase().contains(query.toLowerCase()) ||
                (tour.timeControl?.toLowerCase().contains(
                      query.toLowerCase(),
                    ) ??
                    false);

            if (tour.dateStart == null || tour.dateStart == null) return true;
            if (month == null || year == null) return true;
            final matchesDate =
                tour.dateStart!.month == month && tour.dateStart!.year == year;

            return matchesText && matchesDate;
          }).toList();

      final filteredTourEventCards =
          filteredTours
              .map((t) => TourEventCardModel.fromGroupBroadcast(t))
              .toList();

      state = AsyncValue.data(filteredTourEventCards);
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
