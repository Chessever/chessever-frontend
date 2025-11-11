import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CachedNotationTree {
  final String signature;
  final NotationTree tree;

  const CachedNotationTree({required this.signature, required this.tree});
}

class NotationTreeCacheNotifier
    extends StateNotifier<Map<String, CachedNotationTree>> {
  NotationTreeCacheNotifier() : super(const {});

  CachedNotationTree? lookup(String gameId) => state[gameId];

  void store(String gameId, CachedNotationTree cache) {
    state = {...state, gameId: cache};
  }
}

final notationTreeCacheProvider = StateNotifierProvider<
  NotationTreeCacheNotifier,
  Map<String, CachedNotationTree>
>((ref) => NotationTreeCacheNotifier());

class NotationTreeParams {
  final ChessGame game;
  final String signature;

  const NotationTreeParams({required this.game, required this.signature});

  String get gameId => game.gameId;

  @override
  bool operator ==(Object other) {
    return other is NotationTreeParams &&
        other.gameId == gameId &&
        other.signature == signature;
  }

  @override
  int get hashCode => Object.hash(gameId, signature);
}

final notationTreeProvider = Provider.autoDispose
    .family<NotationTree, NotationTreeParams>((ref, params) {
      final cache = ref.watch(notationTreeCacheProvider);
      final cached = cache[params.gameId];
      if (cached != null && cached.signature == params.signature) {
        return cached.tree;
      }

      final tree = NotationTreeBuilder.build(params.game);
      Future.microtask(() {
        ref
            .read(notationTreeCacheProvider.notifier)
            .store(
              params.gameId,
              CachedNotationTree(signature: params.signature, tree: tree),
            );
      });
      return tree;
    });
