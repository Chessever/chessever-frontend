import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';

/// Cache for notation trees to avoid rebuilding on every pointer change
class NotationTreeCache {
  final Map<String, _CacheEntry> _cache = {};
  static const int _maxCacheSize = 50;

  /// Get or build a notation tree for the given navigator state
  /// Uses gameId + structure hash for cache key
  List<NotationNode> getOrBuild(ChessGameNavigatorState navigatorState) {
    final cacheKey = _buildCacheKey(navigatorState);

    // Check cache
    final cached = _cache[cacheKey];
    if (cached != null) {
      cached.lastAccessed = DateTime.now();
      return cached.nodes;
    }

    // Build new tree
    final nodes = NotationTreeBuilder.fromNavigatorState(navigatorState);

    // Store in cache
    _cache[cacheKey] = _CacheEntry(
      nodes: nodes,
      lastAccessed: DateTime.now(),
    );

    // Cleanup old entries if cache is too large
    if (_cache.length > _maxCacheSize) {
      _evictOldest();
    }

    return nodes;
  }

  /// Build a cache key based on game structure
  String _buildCacheKey(ChessGameNavigatorState navigatorState) {
    final game = navigatorState.game;
    final gameId = game.gameId;
    final mainlineLength = game.mainline.length;
    final variationCount = _countVariations(game.mainline);

    // Cache key: gameId + mainline length + total variation count
    // This ensures cache invalidation when structure changes
    return '$gameId-$mainlineLength-$variationCount';
  }

  /// Count total variations in the game tree
  int _countVariations(ChessLine moves) {
    int count = 0;
    for (final move in moves) {
      if (move.variations != null && move.variations!.isNotEmpty) {
        count += move.variations!.length;
        for (final variation in move.variations!) {
          count += _countVariations(variation);
        }
      }
    }
    return count;
  }

  /// Evict the oldest cache entry
  void _evictOldest() {
    if (_cache.isEmpty) return;

    String? oldestKey;
    DateTime? oldestTime;

    for (final entry in _cache.entries) {
      if (oldestTime == null || entry.value.lastAccessed.isBefore(oldestTime)) {
        oldestTime = entry.value.lastAccessed;
        oldestKey = entry.key;
      }
    }

    if (oldestKey != null) {
      _cache.remove(oldestKey);
    }
  }

  /// Clear the entire cache
  void clear() {
    _cache.clear();
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    return {
      'size': _cache.length,
      'maxSize': _maxCacheSize,
    };
  }
}

class _CacheEntry {
  final List<NotationNode> nodes;
  DateTime lastAccessed;

  _CacheEntry({
    required this.nodes,
    required this.lastAccessed,
  });
}
