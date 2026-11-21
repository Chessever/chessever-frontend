// Every bottom sheet the sheets tests open, by name: the real opener, and the
// provider overrides it needs to open offline over the busy page.
import 'dart:typed_data';

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_difficulty_sheet.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_games_cache.dart';
import 'package:chessever2/screens/gamebase/widgets/position_games_sheet.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/library/widgets/add_to_library_sheet.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/sheets/space_add_sheet.dart';
import 'package:chessever2/screens/settings/widgets/start_screen_settings_body.dart';
import 'package:chessever2/screens/tour_detail/bracket/models/knockout_bracket.dart';
import 'package:chessever2/screens/tour_detail/bracket/widgets/knockout_match_sheet.dart';
import 'package:chessever2/services/att_prompt_service.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/paywall/billing_issue_sheet.dart';
import 'package:chessever2/widgets/paywall/manage_subscription_sheet.dart';
import 'package:chessever2/widgets/smooth_bottom_sheet.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'sheets_harness.dart';

/// A sheet the tests open: how, with what in place, and a text it shows.
class SheetScene {
  const SheetScene(this.name, this.opener, {this.overrides = const []});

  final String name;
  final SheetOpener opener;
  final List<Override> overrides;
}

class _Store extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];

  @override
  Future<bool> add(SpaceShortcut draft) async => true;

  @override
  Future<void> markOpened(String id) async {}
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription()
    : super(
        SubscriptionState(
          isSubscribed: true,
          provider: 'stripe',
          inBillingGracePeriod: true,
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EngineSettings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async {
    const settings = EngineSettings(showEngineAnalysis: false);
    state = const AsyncValue.data(settings);
    return settings;
  }
}

/// Saved pages: none, and nothing written to disk.
class _Disk implements ExplorerGamesDiskStore {
  @override
  Future<Map<String, ExplorerGamesSnapshot>> readMany(
    List<String> keys, {
    required String owner,
  }) async => const {};

  @override
  Future<void> write(
    String key,
    GamebaseSearchQueryResponse response,
    DateTime fetchedAt, {
    required String owner,
  }) async {}

  @override
  Future<void> clear() async {}
}

const _names = [
  ('Carlsen, Magnus', 2830, 'Nakamura, Hikaru', 2802),
  ('Caruana, Fabiano', 2795, 'Firouzja, Alireza', 2759),
  ('Gukesh, D', 2777, 'Erigaisi, Arjun', 2778),
  ('So, Wesley', 2741, 'Praggnanandhaa, R', 2758),
  ('Giri, Anish', 2745, 'Abdusattorov, Nodirbek', 2766),
];

/// The explorer's games: a full page, answered at once.
class SheetsGamesRepo extends GamebaseRepository {
  SheetsGamesRepo()
    : super(Dio(), apiKey: 'test', baseUrl: 'https://example.test');

  int requests = 0;

  GamebaseSearchQueryResponse _page(int pageNumber) {
    requests++;
    return GamebaseSearchQueryResponse(
      status: 'success',
      data: [
        for (var i = 0; i < 20; i++)
          <String, dynamic>{
            'id': 'g$pageNumber-$i',
            'white': _names[i % _names.length].$1,
            'black': _names[i % _names.length].$3,
            'result': const ['1-0', '1/2-1/2', '0-1'][i % 3],
            'whiteElo': _names[i % _names.length].$2,
            'blackElo': _names[i % _names.length].$4,
            'date': '2025-0${1 + i % 9}-12',
            'event': 'Tata Steel Masters',
          },
      ],
      metadata: GamebasePaginationMetadata(
        pageNumber: pageNumber,
        pageSize: 20,
        totalCount: 312,
        hasMoreValue: true,
      ),
    );
  }

  @override
  Future<GamebaseSearchQueryResponse> getPositionGames({
    required String fen,
    List<String> moves = const [],
    String? uci,
    TimeControl? timeControl,
    String? playerId,
    String? color,
    String? result,
    int? minRating,
    int? maxRating,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
    bool? isOnline,
    int notationPlies = 0,
    int pageNumber = 0,
    int pageSize = 20,
  }) async => _page(pageNumber);
}

const sheetsExplorerFen =
    'r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R b KQkq - 3 5';
const sheetsExplorerMoves = <String>[
  'e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6', 'd2d3', 'f8c5', 'b1c3', //
];

KnockoutMatch _match() {
  const alpha = BracketParticipant(
    id: 'alpha',
    name: 'Firouzja, Alireza',
    title: 'GM',
    rating: 2759,
  );
  const beta = BracketParticipant(
    id: 'beta',
    name: 'Caruana, Fabiano',
    title: 'GM',
    rating: 2795,
  );
  Player player(String name) => Player(
    name: name,
    title: 'GM',
    rating: 2700,
    fideId: 0,
    fed: '',
    clock: 0,
    team: '',
  );
  return KnockoutMatch(
    key: 'final-match',
    stageKey: 'finals',
    participant1: alpha,
    participant2: beta,
    games: [
      for (var i = 1; i <= 4; i++)
        Games(
          id: 'game-$i',
          roundId: 'final-round',
          roundSlug: 'game-$i',
          tourId: 'final-tour',
          tourSlug: 'final-tour',
          players: i.isOdd
              ? [player(alpha.name), player(beta.name)]
              : [player(beta.name), player(alpha.name)],
          status: const ['1-0', '1/2-1/2', '1/2-1/2', '0-1'][i - 1],
          lastMove: 'e2e4',
        ),
    ],
    participant1Score: 2.5,
    participant2Score: 1.5,
    leader: alpha,
    winner: alpha,
    minimumBoardOrder: 1,
    isComplete: true,
    isLive: false,
  );
}

final List<Override> _explorerOverrides = [
  gamebaseRepositoryProvider.overrideWithValue(SheetsGamesRepo()),
  engineSettingsProviderNew.overrideWith(_EngineSettings.new),
  explorerGamesDiskStoreProvider.overrideWithValue(_Disk()),
  subscriptionProvider.overrideWith((ref) => _Subscription()),
];

/// The scenes, with [shareImage] the PNG the share preview shows.
List<SheetScene> sheetScenes({required Uint8List shareImage}) => [
  SheetScene(
    'my_space_add',
    // As showSpaceAddSheet opens it (Openings is not offered on My Space
    // today, and needs no network to fill).
    (context, ref) => showSmoothBottomSheet<void>(
      context: context,
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      builder: (_) => const SpaceAddSheet(section: SpaceSection.openings),
    ),
    overrides: [spaceShortcutsProvider.overrideWith(_Store.new)],
  ),
  SheetScene(
    'share_preview',
    (context, ref) => showShareImagePreview(
      context,
      imageBytes: shareImage,
      onShareImage: () async {},
      onShareLink: () async {},
    ),
  ),
  SheetScene(
    'start_picker',
    (context, ref) => showStartScreenPicker<BottomNavBarItem>(
      context: context,
      title: 'Start screen',
      options: BottomNavBarItem.values,
      label: (item) => item.name,
      selected: BottomNavBarItem.forYou,
    ),
  ),
  SheetScene(
    'knockout_match',
    (context, ref) => showKnockoutMatchSheet(
      context: context,
      match: _match(),
      onGameTap: (_) {},
    ),
  ),
  SheetScene(
    'add_to_library',
    (context, ref) => showAddToLibrarySheet(context),
  ),
  SheetScene(
    'sort_options',
    (context, ref) => showGamebaseSortOptions(
      context: context,
      sortBy: GamebaseSortField.avgElo,
      sortDirection: GamebaseSortDirection.desc,
      onChanged: (_, __) {},
    ),
  ),
  SheetScene(
    'position_games',
    (context, ref) => showPositionGamesSheet(
      context,
      fen: sheetsExplorerFen,
      moves: sheetsExplorerMoves,
      title: 'Games for 5...Bc5',
    ),
    overrides: _explorerOverrides,
  ),
  SheetScene(
    'explorer_filter',
    (context, ref) => showExplorerFilterSheet(context),
    overrides: _explorerOverrides,
  ),
  SheetScene(
    'puzzle_difficulty',
    (context, ref) => showPuzzleDifficultySheet(context, ref),
  ),
  SheetScene(
    'auth_upgrade',
    (context, ref) => showAuthUpgradeSheet(
      context: context,
      title: 'Sign in to get Premium',
      completeSignInInSheet: true,
    ),
  ),
  SheetScene('att_explainer', (context, ref) => showAttExplainerSheet(context)),
  SheetScene(
    'billing_issue',
    (context, ref) => showBillingIssueSheet(context: context),
    overrides: [subscriptionProvider.overrideWith((ref) => _Subscription())],
  ),
  SheetScene(
    'manage_subscription',
    (context, ref) => showManageSubscriptionSheet(context),
    overrides: [subscriptionProvider.overrideWith((ref) => _Subscription())],
  ),
];
