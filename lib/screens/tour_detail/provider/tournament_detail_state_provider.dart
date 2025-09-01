// tournament_detail_state_provider.dart
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Track if tournament detail screen is active
final tournamentDetailScreenActiveProvider = StateProvider<bool>((ref) => false);

// Track initialization states
final tourDetailInitializedProvider = StateProvider<bool>((ref) => false);
final gamesTourInitializedProvider = StateProvider<bool>((ref) => false);
final gamesAppBarInitializedProvider = StateProvider<bool>((ref) => false);
final playerTourInitializedProvider = StateProvider<bool>((ref) => false);

// Track tab switching state
final isTabSwitchingProvider = StateProvider<bool>((ref) => false);