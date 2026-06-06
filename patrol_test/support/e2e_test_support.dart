import 'dart:io';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' as app;
import 'package:chessever2/main.dart' show navigatorKey;
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event_repository.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/screens/board_editor/board_editor_screen.dart';
import 'package:chessever2/screens/calendar/calendar_event_detail_screen.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/library/book_preview_screen.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/premium/premium_screen.dart';
import 'package:chessever2/screens/premium_games/premium_games_screen.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:patrol/patrol.dart';

typedef PatrolTester = PatrolIntegrationTester;

const patrolE2eConfig = PatrolTesterConfig(
  existsTimeout: Duration(seconds: 20),
  visibleTimeout: Duration(seconds: 20),
  settleTimeout: Duration(seconds: 20),
  settlePolicy: SettlePolicy.trySettle,
  dragDuration: Duration(milliseconds: 150),
  settleBetweenScrollsTimeout: Duration(seconds: 8),
  printLogs: false,
);

const _defaultTimeout = Duration(seconds: 20);
const _engineTimeout = Duration(seconds: 45);
final _traceFile = File('${Directory.systemTemp.path}/chessever_e2e_trace.log');

void _trace(String message) {
  final line = '[${DateTime.now().toIso8601String()}] $message';
  debugPrint(line);
  try {
    _traceFile.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}

class SeededPlayerData {
  const SeededPlayerData({
    required this.fideId,
    required this.name,
    required this.title,
    required this.rating,
    required this.countryCode,
  });

  final int fideId;
  final String name;
  final String? title;
  final int? rating;
  final String? countryCode;

  String get queryToken {
    final normalized = name.replaceAll(',', ' ');
    final tokens =
        normalized
            .split(RegExp(r'\s+'))
            .map((token) => token.trim())
            .where((token) => token.length >= 3)
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    return tokens.isNotEmpty ? tokens.first : name;
  }
}

class E2eSeedData {
  const E2eSeedData({
    required this.folder,
    required this.shareToken,
    required this.seededPlayers,
    required this.addedFavoriteNames,
    required this.calendarEvent,
  });

  final LibraryFolder folder;
  final String shareToken;
  final List<SeededPlayerData> seededPlayers;
  final List<String> addedFavoriteNames;
  final CalendarEvent? calendarEvent;
}

Future<void> launchAppAndReachSignedInShell(PatrolTester $) async {
  try {
    _traceFile.writeAsStringSync('', mode: FileMode.write, flush: true);
  } catch (_) {}
  _trace('[E2E] launchAppAndReachSignedInShell: app.main()');
  await app.main();
  _trace('[E2E] launchAppAndReachSignedInShell: initial settle');
  await $.pumpAndTrySettle(timeout: const Duration(seconds: 30));

  _trace('[E2E] launchAppAndReachSignedInShell: waiting for home or onboarding');
  await pumpUntil(
    $,
    () =>
        _isVisible($, E2eIds.homeRoot) || _isVisible($, E2eIds.onboardingRoot),
    reason: 'home or onboarding shell',
    timeout: const Duration(seconds: 40),
  );

  _trace('[E2E] launchAppAndReachSignedInShell: completeOnboardingIfVisible');
  await completeOnboardingIfVisible($);
  _trace('[E2E] launchAppAndReachSignedInShell: ensureHomeShell');
  await ensureHomeShell($);
  _trace('[E2E] launchAppAndReachSignedInShell: done');
}

Future<void> completeOnboardingIfVisible(PatrolTester $) async {
  final labels = <String>['Continue to Chessever', 'Get Started', 'Continue'];
  final deadline = DateTime.now().add(const Duration(seconds: 45));

  while (DateTime.now().isBefore(deadline)) {
    if (_isVisible($, E2eIds.homeRoot)) {
      _trace('[E2E] completeOnboardingIfVisible: home already visible');
      return;
    }

    if (_isPlayerSelectionVisible($)) {
      _trace('[E2E] completeOnboardingIfVisible: player selection visible');
      await completePlayerSelectionIfVisible($);
      continue;
    }

    if (_isVisible($, E2eIds.onboardingRoot)) {
      _trace('[E2E] completeOnboardingIfVisible: onboarding root visible');
      if (_isVisible($, E2eIds.onboardingAuthenticatedContinueButton)) {
        _trace(
          '[E2E] completeOnboardingIfVisible: tapping authenticated continue',
        );
        await byId($, E2eIds.onboardingAuthenticatedContinueButton).tap();
        await _pumpAfterOnboardingInteraction($);
        continue;
      }

      bool tapped = false;
      for (final label in labels) {
        if ($(label).isVisibleAt()) {
          _trace('[E2E] completeOnboardingIfVisible: tapping "$label"');
          await $(label).tap();
          await _pumpAfterOnboardingInteraction($);
          tapped = true;
          break;
        }
      }

      if (!tapped) {
        await $.pump(const Duration(milliseconds: 250));
      }
      continue;
    }

    await $.pump(const Duration(milliseconds: 250));
  }

  throw TestFailure('Failed to complete onboarding before timeout');
}

Future<void> completePlayerSelectionIfVisible(PatrolTester $) async {
  if (!_isPlayerSelectionVisible($)) {
    _trace('[E2E] completePlayerSelectionIfVisible: not visible');
    return;
  }

  if (_isButtonEnabled($, E2eIds.playerSelectionContinueButton)) {
    _trace(
      '[E2E] completePlayerSelectionIfVisible: continue already enabled',
    );
    await byId($, E2eIds.playerSelectionContinueButton).tap();
    await _pumpAfterOnboardingInteraction($);
    return;
  }

  _trace('[E2E] completePlayerSelectionIfVisible: selecting players');
  final selectableKeys = _findKeysWithPrefixes($, const [
    '',
  ]).where((key) => RegExp(r'^\d+$').hasMatch(key.value) && key.value != '0');

  for (final key in selectableKeys.take(12)) {
    final finder = $(key);
    if (!finder.isVisibleAt()) {
      continue;
    }
    await finder.tap();
    await $.pump(const Duration(milliseconds: 150));
    if (_isButtonEnabled($, E2eIds.playerSelectionContinueButton)) {
      break;
    }
  }

  if (!_isButtonEnabled($, E2eIds.playerSelectionContinueButton)) {
    throw TestFailure(
      'Failed to enable player selection continue button before timeout',
    );
  }

  _trace('[E2E] completePlayerSelectionIfVisible: tapping continue');
  await byId($, E2eIds.playerSelectionContinueButton).tap();
  await _pumpAfterOnboardingInteraction($);
}

Future<void> ensureHomeShell(PatrolTester $) async {
  _trace('[E2E] ensureHomeShell: waiting for home shell');
  await pumpUntil(
    $,
    () => _isVisible($, E2eIds.homeRoot),
    reason: 'home shell',
    timeout: const Duration(seconds: 30),
  );
  await expectVisible($, E2eIds.homeRoot);
  _trace('[E2E] ensureHomeShell: home visible');
}

Future<E2eSeedData> seedBaselineData(PatrolTester $) async {
  final container = providerContainer();
  final libraryRepository = container.read(libraryRepositoryProvider);
  final chessPlayersRepository = container.read(chessPlayerRepositoryProvider);
  final favoritesNotifier = container.read(favoritePlayersProviderNew.notifier);
  final calendarRepository = container.read(calendarEventRepositoryProvider);

  final existingFavorites = await container.read(
    favoritePlayersProviderNew.future,
  );
  final existingFavoriteNames =
      existingFavorites.map((player) => player.playerName).toSet();

  final topPlayers = await chessPlayersRepository.getTopPlayers(limit: 5);
  if (topPlayers.length < 3) {
    throw TestFailure('Expected at least 3 top players to seed favorites');
  }

  final seededPlayers = topPlayers
      .take(3)
      .map(
        (player) => SeededPlayerData(
          fideId: player.fideid,
          name: player.name,
          title: player.title,
          rating: player.rating,
          countryCode: player.country,
        ),
      )
      .toList(growable: false);

  final addedFavoriteNames = <String>[];
  for (final player in seededPlayers) {
    if (existingFavoriteNames.contains(player.name)) {
      continue;
    }
    await favoritesNotifier.addFavorite(
      fideId: player.fideId.toString(),
      playerName: player.name,
      countryCode: player.countryCode,
      rating: player.rating,
      title: player.title,
    );
    addedFavoriteNames.add(player.name);
  }

  if (addedFavoriteNames.isNotEmpty) {
    await favoritesNotifier.refresh();
    await $.pumpAndTrySettle(timeout: _defaultTimeout);
  }

  final folder = await libraryRepository.createFolder(
    name: 'e2e_patrol_${DateTime.now().millisecondsSinceEpoch}',
  );
  final sharedFolder = await libraryRepository.generateShareToken(folder.id);

  final currentYear = DateTime.now().year;
  final calendarEvents = await calendarRepository.getCalendarEventsForYear(
    year: currentYear,
    limit: 50,
  );

  return E2eSeedData(
    folder: sharedFolder,
    shareToken: sharedFolder.shareToken ?? '',
    seededPlayers: seededPlayers,
    addedFavoriteNames: addedFavoriteNames,
    calendarEvent: calendarEvents.isEmpty ? null : calendarEvents.first,
  );
}

Future<void> cleanupSeedData(E2eSeedData seed) async {
  final container = providerContainer();
  final libraryRepository = container.read(libraryRepositoryProvider);
  final favoritesNotifier = container.read(favoritePlayersProviderNew.notifier);

  try {
    await libraryRepository.deleteFolder(seed.folder.id);
  } catch (_) {}

  for (final playerName in seed.addedFavoriteNames) {
    try {
      await favoritesNotifier.removeFavorite(playerName);
    } catch (_) {}
  }
}

Future<void> resetToHome(PatrolTester $) async {
  final navigator = navigatorKey.currentState;
  if (navigator == null) {
    throw TestFailure('Navigator is not available');
  }
  navigator.pushNamedAndRemoveUntil('/home_screen', (_) => false);
  await $.pumpAndTrySettle(timeout: const Duration(seconds: 20));
  await ensureHomeShell($);
}

Future<void> pushNamedRoute(PatrolTester $, String routeName) async {
  final navigator = navigatorKey.currentState;
  if (navigator == null) {
    throw TestFailure('Navigator is not available');
  }
  navigator.pushNamed(routeName);
  await $.pumpAndTrySettle(timeout: _defaultTimeout);
}

Future<void> pushWidgetRoute(PatrolTester $, Widget widget) async {
  final navigator = navigatorKey.currentState;
  if (navigator == null) {
    throw TestFailure('Navigator is not available');
  }
  navigator.push(MaterialPageRoute<void>(builder: (_) => widget));
  await $.pumpAndTrySettle(timeout: _defaultTimeout);
}

Future<void> popRoute(PatrolTester $) async {
  final navigator = navigatorKey.currentState;
  if (navigator == null || !navigator.canPop()) {
    return;
  }
  navigator.pop();
  await $.pumpAndTrySettle(timeout: _defaultTimeout);
}

Future<void> openHomeDrawer(PatrolTester $) async {
  await ensureHomeShell($);
  final scaffoldFinder = find.ancestor(
    of: find.byKey(e2eKey(E2eIds.homeRoot)),
    matching: find.byType(Scaffold),
  );
  if (scaffoldFinder.evaluate().isEmpty) {
    throw TestFailure('Home scaffold not found');
  }
  final scaffoldState = $.tester.state<ScaffoldState>(scaffoldFinder.first);
  scaffoldState.openDrawer();
  await $.pumpAndTrySettle(timeout: _defaultTimeout);
  await expectVisible($, E2eIds.homeDrawer);
}

Future<void> tapBottomNavRoot(
  PatrolTester $, {
  required String navId,
  required String expectedRoot,
}) async {
  await ensureHomeShell($);
  await byId($, navId).tap();
  await expectVisible($, expectedRoot);
}

Future<void> openDrawerDestination(
  PatrolTester $, {
  required String drawerItemId,
  required String expectedRoot,
}) async {
  await openHomeDrawer($);
  await byId($, drawerItemId).tap();
  await expectVisible($, expectedRoot);
}

Future<void> searchFor(
  PatrolTester $, {
  required String fieldId,
  required String query,
  Duration debounce = const Duration(milliseconds: 700),
}) async {
  await expectVisible($, fieldId);
  await byId($, fieldId).tap();
  await byId($, fieldId).enterText(query);
  await $.pump(debounce);
  await $.pumpAndTrySettle(timeout: _defaultTimeout);
}

Future<void> expectVisible(
  PatrolTester $,
  String id, {
  Duration? timeout,
}) async {
  await byId($, id).waitUntilVisible(timeout: timeout ?? _defaultTimeout);
}

PatrolFinder byId(PatrolTester $, String id) => $(e2eKey(id));

bool isAnyTextVisible(PatrolTester $, Iterable<String> texts) {
  for (final text in texts) {
    if ($(text).isVisibleAt()) {
      return true;
    }
  }
  return false;
}

Future<void> expectAnyTextVisible(
  PatrolTester $,
  Iterable<String> texts, {
  Duration timeout = _defaultTimeout,
}) async {
  await pumpUntil(
    $,
    () => isAnyTextVisible($, texts),
    reason: 'one of ${texts.join(', ')}',
    timeout: timeout,
  );
}

Future<void> expectTextVisible(
  PatrolTester $,
  String text, {
  Duration timeout = _defaultTimeout,
}) async {
  await $(text).waitUntilVisible(timeout: timeout);
}

Future<void> pumpUntil(
  PatrolTester $,
  bool Function() predicate, {
  required String reason,
  Duration timeout = _defaultTimeout,
  Duration step = const Duration(milliseconds: 250),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await $.pump(step);
  }
  throw TestFailure('Timed out waiting for $reason');
}

bool _isVisible(PatrolTester $, String id) => byId($, id).isVisibleAt();

bool _isPlayerSelectionVisible(PatrolTester $) =>
    _isVisible($, E2eIds.playerSelectionRoot) ||
    _isVisible($, E2eIds.playerSelectionSearchField) ||
    _isVisible($, E2eIds.playerSelectionContinueButton);

bool _isButtonEnabled(PatrolTester $, String id) {
  final finder = find.byKey(e2eKey(id));
  if (finder.evaluate().isEmpty) {
    return false;
  }

  final widget = $.tester.widget<ElevatedButton>(finder);
  return widget.onPressed != null;
}

Future<void> _pumpAfterOnboardingInteraction(PatrolTester $) async {
  await $.pump(const Duration(milliseconds: 800));
  await $.pumpAndTrySettle(timeout: const Duration(seconds: 2));
}

List<ValueKey<String>> _findKeysWithPrefixes(
  PatrolTester $,
  List<String> prefixes,
) {
  final results = <String, ValueKey<String>>{};
  for (final element in $.tester.allElements) {
    final key = element.widget.key;
    if (key is! ValueKey<String>) {
      continue;
    }
    if (prefixes.any(key.value.startsWith)) {
      results[key.value] = key;
    }
  }
  final sorted =
      results.values.toList()..sort((a, b) => a.value.compareTo(b.value));
  return sorted;
}

int visibleCountForPrefixes(PatrolTester $, List<String> prefixes) {
  final keys = _findKeysWithPrefixes($, prefixes);
  var count = 0;
  for (final key in keys) {
    if ($(key).isVisibleAt()) {
      count++;
    }
  }
  return count;
}

Future<bool> tapFirstVisibleByPrefixes(
  PatrolTester $,
  List<String> prefixes,
) async {
  final keys = _findKeysWithPrefixes($, prefixes);
  for (final key in keys) {
    final finder = $(key);
    if (!finder.isVisibleAt()) {
      continue;
    }
    await finder.tap();
    await $.pumpAndTrySettle(timeout: _defaultTimeout);
    return true;
  }
  return false;
}

List<String> textsUnderKey(PatrolTester $, String id) {
  final parent = find.byKey(e2eKey(id));
  if (parent.evaluate().isEmpty) {
    return const <String>[];
  }

  final texts = <String>[];
  final textFinder = find.descendant(of: parent, matching: find.byType(Text));
  for (final element in textFinder.evaluate()) {
    final widget = element.widget;
    if (widget is Text) {
      final value = widget.data ?? widget.textSpan?.toPlainText() ?? '';
      final normalized = value.trim();
      if (normalized.isNotEmpty) {
        texts.add(normalized);
      }
    }
  }

  final richTextFinder = find.descendant(
    of: parent,
    matching: find.byType(RichText),
  );
  for (final element in richTextFinder.evaluate()) {
    final widget = element.widget;
    if (widget is RichText) {
      final normalized = widget.text.toPlainText().trim();
      if (normalized.isNotEmpty) {
        texts.add(normalized);
      }
    }
  }

  return texts.toSet().toList();
}

String readEvalText(PatrolTester $) {
  final texts = textsUnderKey($, E2eIds.boardEvalBar);
  return texts.firstWhere((text) => text.isNotEmpty, orElse: () => '');
}

String engineSnapshot(PatrolTester $) {
  final eval = readEvalText($);
  final pv = textsUnderKey($, E2eIds.boardPvList).join(' | ');
  return '$eval || $pv';
}

Future<void> assertBoardEngineReady(PatrolTester $) async {
  await expectVisible($, E2eIds.chessBoardRoot, timeout: _engineTimeout);
  await expectVisible($, E2eIds.boardEvalBar, timeout: _engineTimeout);
  await expectVisible($, E2eIds.boardPvList, timeout: _engineTimeout);

  await pumpUntil(
    $,
    () {
      final eval = readEvalText($);
      return eval.isNotEmpty && eval != '...';
    },
    reason: 'board eval text',
    timeout: _engineTimeout,
  );

  await pumpUntil(
    $,
    () {
      final texts = textsUnderKey($, E2eIds.boardPvList);
      return texts.any(
        (text) =>
            text != '...' &&
            text.length > 2 &&
            RegExp(r'[A-Za-z0-9]').hasMatch(text),
      );
    },
    reason: 'board PV lines',
    timeout: _engineTimeout,
  );
}

Future<void> assertBoardEngineRefreshesAfterMove(
  PatrolTester $, {
  required bool forward,
}) async {
  final before = engineSnapshot($);
  await byId(
    $,
    forward ? E2eIds.boardMoveForward : E2eIds.boardMoveBack,
  ).tap(settlePolicy: SettlePolicy.noSettle);
  await $.pump(const Duration(milliseconds: 250));

  await pumpUntil(
    $,
    () {
      final eval = readEvalText($);
      final snapshot = engineSnapshot($);
      return eval.isNotEmpty && eval != '...' && snapshot != before;
    },
    reason: 'board engine refresh',
    timeout: _engineTimeout,
  );
}

Future<void> stressMoveNavigation(
  PatrolTester $, {
  int forwardTaps = 8,
  int backwardTaps = 8,
}) async {
  for (var i = 0; i < forwardTaps; i++) {
    await byId(
      $,
      E2eIds.boardMoveForward,
    ).tap(settlePolicy: SettlePolicy.noSettle);
    await $.pump(const Duration(milliseconds: 150));
  }
  await assertBoardEngineReady($);

  for (var i = 0; i < backwardTaps; i++) {
    await byId(
      $,
      E2eIds.boardMoveBack,
    ).tap(settlePolicy: SettlePolicy.noSettle);
    await $.pump(const Duration(milliseconds: 150));
  }
  await assertBoardEngineReady($);
}

Future<void> swipeBoardBetweenGames(
  PatrolTester $, {
  required bool forward,
  String? expectedVisibleToken,
}) async {
  final before = engineSnapshot($);
  final boardFinder = find.byKey(e2eKey(E2eIds.chessBoardRoot));
  if (boardFinder.evaluate().isEmpty) {
    throw TestFailure('Board root is not available for swipe navigation');
  }

  await $.tester.drag(
    boardFinder,
    Offset(forward ? -420 : 420, 0),
    touchSlopX: 0,
    touchSlopY: 0,
  );
  await $.pump(const Duration(milliseconds: 300));
  await $.pumpAndTrySettle(timeout: _defaultTimeout);

  await pumpUntil(
    $,
    () => engineSnapshot($) != before,
    reason: 'board game swipe refresh',
    timeout: _engineTimeout,
  );
  await assertBoardEngineReady($);

  if (expectedVisibleToken != null) {
    await expectAnyTextVisible($, [expectedVisibleToken], timeout: _engineTimeout);
  }
}

Future<void> tapBoardNotationToken(
  PatrolTester $,
  String token, {
  bool expectPositionChange = true,
}) async {
  await expectVisible($, E2eIds.boardNotationRoot, timeout: _engineTimeout);
  final before = engineSnapshot($);
  final notationRoot = find.byKey(e2eKey(E2eIds.boardNotationRoot));
  final richTextFinder = find.descendant(
    of: notationRoot,
    matching: find.byWidgetPredicate((widget) {
      if (widget is Text) {
        final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
        return text.contains(token);
      }
      if (widget is RichText) {
        return widget.text.toPlainText().contains(token);
      }
      return false;
    }),
  );

  if (richTextFinder.evaluate().isEmpty) {
    throw TestFailure('Could not find notation token "$token" on the board');
  }

  await $.tester.tap(richTextFinder.first);
  await $.pump(const Duration(milliseconds: 250));
  await $.pumpAndTrySettle(timeout: _defaultTimeout);

  if (expectPositionChange) {
    await pumpUntil(
      $,
      () => engineSnapshot($) != before,
      reason: 'notation tap position change',
      timeout: _engineTimeout,
    );
    await assertBoardEngineReady($);
  }
}

Future<void> selectBoardGame(PatrolTester $, String playerToken) async {
  await expectVisible($, E2eIds.boardGameSelector);
  await byId($, E2eIds.boardGameSelector).tap();
  await $.pumpAndTrySettle(timeout: _defaultTimeout);
  await $(RegExp(playerToken, caseSensitive: false)).tap();
  await $.pumpAndTrySettle(timeout: _defaultTimeout);
}

Future<void> openFirstVisibleBoardFromPrefixes(
  PatrolTester $,
  List<String> prefixes,
) async {
  final keys = _findKeysWithPrefixes($, prefixes);
  for (final key in keys) {
    final finder = $(key);
    if (!finder.isVisibleAt()) {
      continue;
    }
    await finder.tap();
    await $.pump(const Duration(milliseconds: 300));
    if (_isVisible($, E2eIds.chessBoardRoot)) {
      await $.pumpAndTrySettle(timeout: _defaultTimeout);
      await expectVisible($, E2eIds.chessBoardRoot, timeout: _engineTimeout);
      return;
    }
    await $.pumpAndTrySettle(timeout: _defaultTimeout);
  }
  throw TestFailure(
    'Unable to open a chess board from prefixes: ${prefixes.join(', ')}',
  );
}

List<GamesTourModel> buildSyntheticGames() {
  GamesTourModel game({
    required String id,
    required String white,
    required String black,
    required String pgn,
    required String eco,
    required String openingName,
  }) {
    PlayerCard player(String name, int fideId) {
      return PlayerCard(
        name: name,
        federation: 'USA',
        title: 'GM',
        rating: 2700,
        countryCode: 'US',
        team: null,
        fideId: fideId,
      );
    }

    return GamesTourModel(
      gameId: id,
      whitePlayer: player(white, id.hashCode.abs() % 1000000 + 1),
      blackPlayer: player(black, id.hashCode.abs() % 1000000 + 2),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.unknown,
      roundId: 'round_$id',
      roundSlug: 'round-$id',
      tourId: 'tour_synthetic',
      tourSlug: 'synthetic-tour',
      pgn: pgn,
      eco: eco,
      openingName: openingName,
      timeControl: 'classical',
      lastMoveTime: DateTime.now(),
    );
  }

  return <GamesTourModel>[
    game(
      id: 'synthetic_1',
      white: 'Alpha Tester',
      black: 'Beta Probe',
      eco: 'C65',
      openingName: 'Ruy Lopez Berlin Defense',
      pgn:
          '[Event "Patrol Synthetic 1"]\n'
          '[Site "ChessEver"]\n'
          '[Date "2026.03.06"]\n'
          '[Round "1"]\n'
          '[White "Alpha Tester"]\n'
          '[Black "Beta Probe"]\n'
          '[Result "*"]\n'
          '\n'
          '1. e4 e5 2. Nf3 Nc6 3. Bb5 Nf6 4. O-O Nxe4 5. d4 Nd6 6. Bxc6 dxc6 '
          '7. dxe5 Nf5 8. Qxd8+ Kxd8 9. h3 h5 10. Nc3 Be7 11. b3 Be6 *',
    ),
    game(
      id: 'synthetic_2',
      white: 'Gamma Scout',
      black: 'Delta Signal',
      eco: 'D37',
      openingName: 'QGD Classical',
      pgn:
          '[Event "Patrol Synthetic 2"]\n'
          '[Site "ChessEver"]\n'
          '[Date "2026.03.06"]\n'
          '[Round "2"]\n'
          '[White "Gamma Scout"]\n'
          '[Black "Delta Signal"]\n'
          '[Result "*"]\n'
          '\n'
          '1. d4 d5 2. c4 e6 3. Nc3 Nf6 4. Bg5 Be7 5. e3 O-O 6. Nf3 h6 '
          '7. Bh4 b6 8. cxd5 Nxd5 9. Bxe7 Qxe7 10. Nxd5 exd5 11. Rc1 Be6 *',
    ),
    game(
      id: 'synthetic_3',
      white: 'Epsilon Trace',
      black: 'Zeta Node',
      eco: 'B90',
      openingName: 'Sicilian Najdorf',
      pgn:
          '[Event "Patrol Synthetic 3"]\n'
          '[Site "ChessEver"]\n'
          '[Date "2026.03.06"]\n'
          '[Round "3"]\n'
          '[White "Epsilon Trace"]\n'
          '[Black "Zeta Node"]\n'
          '[Result "*"]\n'
          '\n'
          '1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Be3 e5 '
          '7. Nb3 Be6 8. f3 Be7 9. Qd2 O-O 10. O-O-O Nbd7 11. g4 b5 *',
    ),
  ];
}

Future<void> openSyntheticBoard(PatrolTester $) async {
  await pushWidgetRoute(
    $,
    ChessBoardScreenNew(games: buildSyntheticGames(), currentIndex: 0),
  );
}

Future<void> openSettingsDialog(PatrolTester $) async {
  await openHomeDrawer($);
  await byId($, E2eIds.drawerSettings).tap();
  await expectVisible($, E2eIds.settingsRoot);
}

Future<void> openPremiumFavoritesGames(PatrolTester $) async {
  await pushWidgetRoute(
    $,
    const PremiumGamesScreen(type: PremiumGamesType.favorites),
  );
  await expectVisible($, E2eIds.premiumGamesRoot);
}

Future<void> openPremiumCountrymenGames(PatrolTester $) async {
  await pushWidgetRoute(
    $,
    const PremiumGamesScreen(type: PremiumGamesType.countrymen),
  );
  await expectVisible($, E2eIds.premiumGamesRoot);
}

Future<void> openPremiumScreen(PatrolTester $) async {
  await pushWidgetRoute($, const PremiumScreen());
  await expectVisible($, E2eIds.premiumRoot);
}

Future<void> openBoardEditor(PatrolTester $) async {
  await pushWidgetRoute($, const BoardEditorScreen());
  await expectVisible($, E2eIds.boardEditorRoot);
}

Future<void> openOpeningExplorer(PatrolTester $) async {
  await pushWidgetRoute($, GamebaseExplorerScreen.scoped());
  await expectVisible($, E2eIds.openingExplorerRoot);
}

Future<void> openSeededFolder(PatrolTester $, E2eSeedData seed) async {
  await pushWidgetRoute($, FolderContentsScreen(folder: seed.folder));
  await expectVisible($, E2eIds.folderContentsRoot);
}

Future<void> openSharedBookPreview(PatrolTester $, E2eSeedData seed) async {
  await pushWidgetRoute($, BookPreviewScreen(shareToken: seed.shareToken));
  await expectVisible($, E2eIds.bookPreviewRoot);
}

Future<void> openSeededCalendarEvent(PatrolTester $, E2eSeedData seed) async {
  final event = seed.calendarEvent;
  if (event == null) {
    throw TestFailure('No calendar event available for E2E detail route');
  }
  await pushWidgetRoute(
    $,
    CalendarEventDetailScreen(events: [event], initialIndex: 0),
  );
  await expectVisible($, E2eIds.calendarEventDetailRoot);
}

Future<void> openSeededPlayerProfile(
  PatrolTester $,
  SeededPlayerData player, {
  PlayerProfileDataSource dataSource = PlayerProfileDataSource.supabase,
}) async {
  await pushWidgetRoute(
    $,
    PlayerProfileScreen(
      fideId: player.fideId,
      playerName: player.name,
      title: player.title,
      federation: player.countryCode,
      rating: player.rating,
      dataSource: dataSource,
    ),
  );
  await expectVisible($, E2eIds.playerProfileRoot);
}

Future<void> openSeededScorecard(
  PatrolTester $,
  SeededPlayerData player,
) async {
  final container = providerContainer();
  container.read(selectedPlayerProvider.notifier).state = PlayerStandingModel(
    countryCode: player.countryCode ?? '',
    title: player.title,
    name: player.name,
    score: player.rating ?? 0,
    scoreChange: 0,
    matchScore: null,
    fideId: player.fideId,
  );
  await pushWidgetRoute($, const ScoreCardScreen());
  await expectVisible($, E2eIds.scorecardRoot);
}

ProviderContainer providerContainer() {
  final context = navigatorKey.currentContext;
  if (context == null) {
    throw TestFailure('Navigator context is not available');
  }
  return ProviderScope.containerOf(context, listen: false);
}
