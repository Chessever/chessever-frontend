import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _kRecentSearchKey = 'global_search_recent_v1';
const _kMaxRecent = 12;

/// Recently searched queries for the dedicated global search page.
final recentSearchesProvider =
    StateNotifierProvider<RecentSearchesNotifier, List<String>>(
      (ref) => RecentSearchesNotifier(),
    );

class RecentSearchesNotifier extends StateNotifier<List<String>> {
  RecentSearchesNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferencesService.instance.initialize();
      final raw = prefs?.getStringList(_kRecentSearchKey) ?? const <String>[];
      state = raw;
    } catch (_) {
      // Graceful no-op if prefs unavailable.
    }
  }

  Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final next = <String>[
      q,
      ...state.where((e) => e.toLowerCase() != q.toLowerCase()),
    ].take(_kMaxRecent).toList(growable: false);
    state = next;
    await _persist(next);
  }

  Future<void> clear() async {
    state = const [];
    await _persist(const []);
  }

  Future<void> remove(String query) async {
    final next =
        state.where((e) => e.toLowerCase() != query.toLowerCase()).toList();
    state = next;
    await _persist(next);
  }

  Future<void> _persist(List<String> values) async {
    try {
      final prefs = await SharedPreferencesService.instance.initialize();
      await prefs?.setStringList(_kRecentSearchKey, values);
    } catch (_) {}
  }
}
