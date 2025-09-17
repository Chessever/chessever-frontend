// filepath: /Users/mac/Documents/chessever-frontend/lib/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

final gamesTourScrollProvider =
    StateNotifierProvider<_GamesTourScrollProvider, ItemScrollController>(
      (ref) => _GamesTourScrollProvider(),
    );

class _GamesTourScrollProvider extends StateNotifier<ItemScrollController> {
  _GamesTourScrollProvider() : super(ItemScrollController());
}
