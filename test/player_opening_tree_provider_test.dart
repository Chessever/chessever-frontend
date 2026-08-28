import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/memorial_tree_scope.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository({
    this.treeFails = false,
    this.treeStaysBuilding = false,
  }) : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  final bool treeFails;
  final bool treeStaysBuilding;
  int aggregateCalls = 0;
  int buildCalls = 0;
  int statusCalls = 0;
  int treeCalls = 0;
  int memorialBuildCalls = 0;
  int memorialStatusCalls = 0;
  int memorialTreeCalls = 0;
  String? memorialSourceIdentity;

  @override
  Future<GamebaseResponse> getMoveAggregates({
    required String fen,
    List<String> moves = const [],
    String? playerId,
    TimeControl? timeControl,
    int? minRating,
    int? maxRating,
    String? color,
    String? result,
    int? yearFrom,
    int? yearTo,
    bool? isOnline,
  }) async {
    aggregateCalls += 1;
    return const GamebaseResponse(
      status: 'success',
      data: GamebaseData(
        moves: [
          MoveAggregate(uci: 'e2e4', white: 1, black: 0, draws: 0, total: 1),
        ],
      ),
    );
  }

  @override
  Future<Map<String, dynamic>> startPlayerOpeningTreeBuild({
    required String playerId,
    int maxPly = 24,
    bool forceRebuild = false,
  }) async {
    buildCalls += 1;
    return {
      'status': 'success',
      'data': {'treeId': 'tree-1', 'status': 'building'},
    };
  }

  @override
  Future<Map<String, dynamic>> getPlayerOpeningTreeStatus({
    required String playerId,
    required String treeId,
  }) async {
    statusCalls += 1;
    return {
      'status': 'success',
      'data': {
        'status':
            treeFails ? 'error' : (treeStaysBuilding ? 'building' : 'complete'),
        if (treeFails) 'error': 'boom',
      },
    };
  }

  @override
  Future<Map<String, dynamic>?> getPlayerOpeningTree({
    required String playerId,
    required String treeId,
  }) async {
    treeCalls += 1;
    if (treeFails) return null;
    return {'status': 'success', 'data': _snapshotJson()};
  }

  @override
  Future<Map<String, dynamic>> startMemorialOpeningTreeBuild({
    required String sourceIdentity,
    int maxPly = 24,
    bool forceRebuild = false,
  }) async {
    memorialBuildCalls += 1;
    memorialSourceIdentity = sourceIdentity;
    return {
      'status': 'success',
      'data': {'treeId': 'memorial-tree-1', 'status': 'building'},
    };
  }

  @override
  Future<Map<String, dynamic>> getMemorialOpeningTreeStatus({
    required String sourceIdentity,
    required String treeId,
  }) async {
    memorialStatusCalls += 1;
    memorialSourceIdentity = sourceIdentity;
    return {
      'status': 'success',
      'data': {'status': 'complete'},
    };
  }

  @override
  Future<Map<String, dynamic>?> getMemorialOpeningTree({
    required String sourceIdentity,
    required String treeId,
  }) async {
    memorialTreeCalls += 1;
    memorialSourceIdentity = sourceIdentity;
    return {'status': 'success', 'data': _snapshotJson()};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('player-scoped explorer serves moves from downloaded tree', () async {
    final repo = _FakeGamebaseRepository();
    final container = ProviderContainer(
      overrides: [gamebaseRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final explorerSub = container.listen(
      gamebaseExplorerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(explorerSub.close);
    final treeSub = container.listen(
      playerOpeningTreeProvider('player-uuid'),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(treeSub.close);

    final notifier = container.read(gamebaseExplorerProvider.notifier);
    notifier.enableLocalPlayerTree('player-uuid');
    notifier.initializeWithPlayer(_player);
    container.read(playerOpeningTreeProvider('player-uuid').notifier).start();

    await _waitForTree(container, 'player-uuid');
    notifier.syncLocalPlayerTree('player-uuid');

    var state = container.read(gamebaseExplorerProvider);
    expect(state.moveAggregates.map((m) => m.uci), ['e2e4']);
    expect(state.moveAggregates.single.total, 10);
    expect(repo.aggregateCalls, 0);

    final afterE4 = Chess.initial.play(NormalMove.fromUci('e2e4'));
    notifier.setPositionWithMoves(afterE4.fen, const ['e2e4']);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    state = container.read(gamebaseExplorerProvider);
    expect(state.moveAggregates.map((m) => m.uci), ['e7e5']);
    expect(repo.aggregateCalls, 0);
  });

  test('tree build error surfaces on scoped explorer state', () async {
    final repo = _FakeGamebaseRepository(treeFails: true);
    final container = ProviderContainer(
      overrides: [gamebaseRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final explorerSub = container.listen(
      gamebaseExplorerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(explorerSub.close);
    final treeSub = container.listen(
      playerOpeningTreeProvider('player-uuid'),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(treeSub.close);

    final notifier = container.read(gamebaseExplorerProvider.notifier);
    notifier.enableLocalPlayerTree('player-uuid');
    notifier.initializeWithPlayer(_player);
    container.read(playerOpeningTreeProvider('player-uuid').notifier).start();

    await _waitForTreeError(container, 'player-uuid');
    notifier.syncLocalPlayerTree('player-uuid');

    final state = container.read(gamebaseExplorerProvider);
    expect(state.error, contains('boom'));
    expect(repo.aggregateCalls, 0);
  });

  test('Memorial Build Tree uses only the source-identity endpoints', () async {
    final repo = _FakeGamebaseRepository();
    final container = ProviderContainer(
      overrides: [gamebaseRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    const sourceIdentity = 'memorial:memorial-e03cdf6af47b368c';
    final scopeKey = memorialTreeScopeKey(sourceIdentity);
    final treeSub = container.listen(
      playerOpeningTreeProvider(scopeKey),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(treeSub.close);

    container.read(playerOpeningTreeProvider(scopeKey).notifier).start();
    await _waitForTree(container, scopeKey);

    expect(repo.memorialSourceIdentity, sourceIdentity);
    expect(repo.memorialBuildCalls, 1);
    expect(repo.memorialStatusCalls, 1);
    expect(repo.memorialTreeCalls, 1);
    expect(repo.buildCalls, 0);
    expect(repo.statusCalls, 0);
    expect(repo.treeCalls, 0);
  });

  test('unscoped explorer still uses aggregate API', () async {
    final repo = _FakeGamebaseRepository();
    final container = ProviderContainer(
      overrides: [gamebaseRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final explorerSub = container.listen(
      gamebaseExplorerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(explorerSub.close);

    await container.read(gamebaseExplorerProvider.notifier).refresh();

    expect(repo.aggregateCalls, greaterThanOrEqualTo(1));
    expect(
      container.read(gamebaseExplorerProvider).moveAggregates.single.uci,
      'e2e4',
    );
  });

  test('building tree polls status without probing the full tree', () async {
    final repo = _FakeGamebaseRepository(treeStaysBuilding: true);
    final container = ProviderContainer(
      overrides: [gamebaseRepositoryProvider.overrideWithValue(repo)],
    );
    final provider = playerOpeningTreeProvider('player-uuid');
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    addTearDown(container.dispose);

    container.read(provider.notifier).start();
    for (var i = 0; i < 20 && repo.statusCalls == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(repo.statusCalls, 1);
    expect(repo.treeCalls, 0);
  });
}

const _player = GamebasePlayer(
  id: 'player-uuid',
  fideId: '1',
  name: 'Player, Test',
  gender: PlayerGender.male,
  fed: 'USA',
  title: 'GM',
);

Future<void> _waitForTree(ProviderContainer container, String playerId) async {
  for (var i = 0; i < 20; i++) {
    final state = container.read(playerOpeningTreeProvider(playerId));
    if (state.progress.status == PlayerOpeningTreeStatus.complete) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('tree did not complete');
}

Future<void> _waitForTreeError(
  ProviderContainer container,
  String playerId,
) async {
  for (var i = 0; i < 20; i++) {
    final state = container.read(playerOpeningTreeProvider(playerId));
    if (state.progress.status == PlayerOpeningTreeStatus.error) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('tree did not fail');
}

Map<String, dynamic> _snapshotJson() {
  final afterE4 = Chess.initial.play(NormalMove.fromUci('e2e4'));
  return {
    'tid': 'tree-1',
    'pid': 'player-uuid',
    'mp': 24,
    'r': 0,
    'g': '2026-06-12T00:00:00.000Z',
    'fk': [
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
      afterE4.fen.split(RegExp(r'\s+')).take(4).join(' '),
    ],
    'n': [
      {
        'id': 0,
        'f': 0,
        'p': 0,
        'm': [
          {'u': 'e2e4', 'c': 1, 'w': 6, 'b': 2, 'd': 2, 't': 10},
        ],
      },
      {
        'id': 1,
        'f': 1,
        'p': 1,
        'm': [
          {'u': 'e7e5', 'c': 2, 'w': 3, 'b': 4, 'd': 1, 't': 8},
        ],
      },
    ],
  };
}
