import 'dart:io';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/tabs/player_games_tab.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/player_profile/tabs/'
        'player_games_tab.dart',
      ).readAsStringSync();

  test('keeps games on one canvas behind floating Liquid Glass controls', () {
    expect(source, contains('Positioned.fill(child: content)'));
    expect(
      source,
      contains('SliverToBoxAdapter(child: SizedBox(height: topContentInset))'),
    );
    expect(source, contains('GlassIslandStack('));
    expect(source, contains('GlassContainer('));
    expect(source, contains('GlassIconButton('));
    expect(source, contains('bottomContentInset'));

    expect(source, isNot(contains('SliverAppBar(')));
    expect(source, isNot(contains('SliverPersistentHeader(')));
    expect(source, isNot(contains('FlexibleSpaceBar(')));
    expect(source, isNot(contains('_buildStickyHeader')));
  });

  test('preserves keyed state, E2E hooks, refresh, cache, and pagination', () {
    expect(source, contains('playerProfileGamesKeyProvider(_playerKey)'));
    expect(source, contains('playerGamesSelectionModeProvider(_playerKey)'));
    expect(source, contains('E2eIds.playerGamesSearchField'));
    expect(source, contains('E2eIds.playerGamesFilterButton'));
    expect(source, contains('PageStorageKey<String>(_scrollStorageKey)'));
    expect(source, contains('scrollCacheExtent: kListScrollCacheExtent'));
    expect(source, contains('RefreshIndicator('));
    expect(source, contains('.loadMore()'));
    expect(source, contains('_selectedGameIds'));
    expect(source, contains('_groupGamesByEvent'));
    expect(source, contains('ScrollToTopButton('));
  });

  test(
    'supports accessible targets, Dynamic Type, themes, and Reduce Motion',
    () {
      expect(source, contains('MediaQuery.textScalerOf(context).scale(16)'));
      expect(
        source,
        contains('return dynamicExtent < 48 ? 48 : dynamicExtent'),
      );
      expect(source, contains("label: 'Clear game search'"));
      expect(source, contains("label: 'Exit game selection'"));
      expect(source, contains('dimension: controlExtent'));
      expect(source, contains('size: 48'));
      expect(source, contains('GlassMotion.reduceMotion(context)'));
      expect(source, contains('GlassMotion.resolveDuration('));
      expect(source, contains('context.colors.background'));
      expect(source, contains('context.colors.surfaceElevated'));
      expect(source, contains('context.colors.textPrimary'));
    },
  );

  for (final entry in <(String, ThemeData)>[
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    testWidgets(
      'floating chrome has no overflow at 320pt with large text in ${entry.$1} mode',
      (tester) async {
        await _setSurface(tester, const Size(320, 700));
        await _pumpTab(
          tester,
          theme: entry.$2,
          textScaler: const TextScaler.linear(1.8),
        );

        expect(find.byType(SliverAppBar), findsNothing);
        expect(find.byType(TextField), findsOneWidget);
        expect(
          tester
              .getSize(find.byKey(e2eKey(E2eIds.playerGamesFilterButton)))
              .height,
          greaterThanOrEqualTo(48),
        );
        final exception = tester.takeException();
        expect(exception, isNull, reason: _overflowingRowDiagnostics());
      },
    );
  }

  testWidgets('floating chrome has no overflow on a large-text tablet', (
    tester,
  ) async {
    await _setSurface(tester, const Size(1024, 768));
    await _pumpTab(
      tester,
      theme: AppTheme.lightTheme,
      textScaler: const TextScaler.linear(1.6),
    );

    expect(find.byType(TextField), findsOneWidget);
    final exception = tester.takeException();
    expect(exception, isNull, reason: _overflowingRowDiagnostics());
  });

  testWidgets('selection actions remain accessible on a narrow phone', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _setSurface(tester, const Size(320, 700));
    await _pumpTab(
      tester,
      theme: AppTheme.darkTheme,
      textScaler: const TextScaler.linear(1.8),
      selectionMode: true,
    );

    expect(find.bySemanticsLabel('Exit game selection'), findsOneWidget);
    expect(find.bySemanticsLabel('Select first'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

const _playerKey = PlayerProfileKey(fideId: 1, playerName: 'Test Player');

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Future<void> _pumpTab(
  WidgetTester tester, {
  required ThemeData theme,
  required TextScaler textScaler,
  bool selectionMode = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        selectedPlayerProfileTabProvider.overrideWith(
          (ref) => PlayerProfileTab.games,
        ),
        playerGamesSelectionModeProvider(
          _playerKey,
        ).overrideWith((ref) => selectionMode),
        gameRepositoryProvider.overrideWithValue(_EmptyGameRepository()),
        playerEventsKeyProvider(
          _playerKey,
        ).overrideWith((ref) async => const []),
        gamesListViewModeProvider.overrideWithValue(
          GamesListViewMode.gamesCard,
        ),
      ],
      child: LiquidGlassWidgets.wrap(
        child: MaterialApp(
          theme: theme,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final content = MediaQuery(
              data: media.copyWith(
                textScaler: textScaler,
                disableAnimations: true,
              ),
              child: child!,
            );
            return Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return content;
              },
            );
          },
          home: const Scaffold(
            body: PlayerGamesTab(fideId: 1, playerName: 'Test Player'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

class _EmptyGameRepository implements GameRepository {
  @override
  Future<List<Games>> getGamesByFideIdPaginated(
    String fideId, {
    required int limit,
    required int offset,
  }) async => const [];

  @override
  Future<List<Games>> getGamesByPlayerNamePaginated(
    String playerName, {
    required int limit,
    required int offset,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

String _overflowingRowDiagnostics() {
  final diagnostics = <String>[];
  for (final element in find.byType(Row).evaluate()) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderFlex) continue;
    var child = renderObject.firstChild;
    var furthestRight = 0.0;
    while (child != null) {
      final parentData = child.parentData! as FlexParentData;
      final right = parentData.offset.dx + child.size.width;
      if (right > furthestRight) furthestRight = right;
      child = renderObject.childAfter(child);
    }
    if (furthestRight <= renderObject.size.width + 0.1) continue;
    diagnostics.add(
      'Row ${renderObject.size} reaches $furthestRight\n'
      '${element.toStringDeep()}',
    );
  }
  return diagnostics.isEmpty
      ? 'No overflowing Row could be identified.'
      : diagnostics.join('\n');
}
