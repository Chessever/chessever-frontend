import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/library/space_library_bridge.dart';
import 'package:chessever2/screens/my_space/models/space_auto_item.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_auto_tile.dart';
import 'package:chessever2/screens/my_space/widgets/space_metrics.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Store extends SpaceShortcutsNotifier {
  _Store(this.seed);
  final List<SpaceShortcut> seed;
  @override
  Future<List<SpaceShortcut>> build() async => seed;
  @override
  Future<SpaceShortcut?> removeTarget(SpaceShortcutKind kind, String id) async {
    final pin = pinFor(kind, id);
    state = AsyncData([
      for (final s in state.requireValue)
        if (s.key != pin?.key) s,
    ]);
    return pin;
  }

  @override
  Future<void> restore(SpaceShortcut s) async =>
      state = AsyncData([s, ...state.requireValue]);
}

class _Hidden extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => const {};
  @override
  void hide(String key) => state = {...state, key};
  @override
  void unhide(String key) => state = {...state}..remove(key);
}

class _FavoriteEvents extends FavoriteEventsNotifier {
  _FavoriteEvents(this.favorite);
  final FavoriteEvent favorite;
  int removals = 0;
  @override
  Future<List<FavoriteEvent>> build() async => [favorite];
  @override
  Future<void> removeFavorite(String id, {String? eventName}) async {
    removals++;
    state = const AsyncData([]);
  }
}

class _Likes extends LikedGamesNotifier {
  _Likes(this.analysis);
  final SavedAnalysis analysis;
  int removals = 0;
  @override
  Future<List<SavedAnalysis>> build() async => [analysis];
  @override
  Future<bool> removeAnalysis(SavedAnalysis analysis) async {
    removals++;
    state = const AsyncData([]);
    return true;
  }
}

class _EngineSettings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();
}

void main() {
  for (final subscribed in [false, true]) {
    testWidgets(
      'My Space never offers source ${subscribed ? 'unsubscribe' : 'deletion'}',
      (tester) async {
        late List<LibraryMenuAction> actions;
        final folder = LibraryFolder(
          id: 'database',
          userId: 'owner',
          name: 'Club preparation',
          color: '#333333',
          icon: 'folder',
          orderIndex: 0,
          isSubscribed: subscribed,
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 1),
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: Consumer(
                builder: (context, ref, _) {
                  ResponsiveHelper.init(context);
                  actions = spaceLibraryFolderActions(context, ref, folder);
                  return const Scaffold();
                },
              ),
            ),
          ),
        );
        expect(
          actions.map((action) => action.label),
          isNot(anyOf(contains('Delete'), contains('Unsubscribe'))),
        );
        expect(actions.where((action) => action.destructive), isEmpty);
      },
    );
  }

  testWidgets(
    'removing a favorited event preserves its favorite through Undo',
    (tester) async {
      final model = GroupEventCardModel(
        id: 'cal_event_club',
        title: 'Club championship',
        dates: 'October 2026',
        maxAvgElo: 0,
        timeUntilStart: '',
        tourEventCategory: TourEventCategory.upcoming,
        timeControl: 'standard',
        eventSource: EventSource.communityEvent,
        startDate: null,
        endDate: null,
      );
      final favorite = FavoriteEvent(
        id: 'favorite',
        userId: 'user',
        eventId: model.id,
        eventName: model.title,
        metadata: const {},
        createdAt: DateTime(2026, 10),
        updatedAt: DateTime(2026, 10),
      );
      final favorites = _FavoriteEvents(favorite);
      final pin = eventSpaceDraft(model);
      final store = _Store([pin]);
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            spaceShortcutsProvider.overrideWith(() => store),
            spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
            favoriteEventsProvider.overrideWith(() => favorites),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Consumer(
              builder: (context, ref, _) {
                ResponsiveHelper.init(context);
                container = ProviderScope.containerOf(context);
                ref.watch(spaceShortcutsProvider);
                ref.watch(favoriteEventsProvider);
                return Scaffold(
                  body: TextButton(
                    onPressed: () => showLibraryContextMenu(
                      context: context,
                      actions: eventMenuActions(
                        context: context,
                        ref: ref,
                        model: model,
                        spaceDraft: pin,
                      ),
                    ),
                    child: const Text('Event actions'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Event actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from My Space'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.contains(pin.kind, pin.targetId), isFalse);
      expect(
        eventIsFavorited(
          container.read(favoriteEventsProvider).requireValue,
          model,
        ),
        isTrue,
      );
      expect(favorites.removals, 0);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(store.contains(pin.kind, pin.targetId), isTrue);
      expect(favorites.removals, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  for (final sourceKind in ['owned', 'subscribed', 'liked']) {
    testWidgets(
      'remove and undo an automatic $sourceKind card without touching its source',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final folder = sourceKind == 'liked'
            ? null
            : LibraryFolder(
                id: 'database',
                userId: 'owner',
                name: 'Club preparation',
                color: '#333333',
                icon: 'folder',
                orderIndex: 0,
                isSubscribed: sourceKind == 'subscribed',
                createdAt: DateTime(2026, 10),
                updatedAt: DateTime(2026, 10),
              );
        final analysis = sourceKind == 'liked'
            ? SavedAnalysis(
                id: 'liked-game',
                userId: 'user',
                title: 'Club game',
                chessGame: ChessGame.fromPgn(
                  'liked-game',
                  '[White "Club Player"]\n[Black "Opponent"]\n[Result "*"]\n\n1. e4 e5 *',
                ),
                analysisState: const {},
                variationComments: const {},
                lastViewedPosition: -1,
                tags: const [],
                isFavorite: true,
                createdAt: DateTime(2026, 10),
                updatedAt: DateTime(2026, 10),
              )
            : null;
        final likes = analysis == null ? null : _Likes(analysis);
        final item = SpaceAutoItem(
          shortcut: folder == null
              ? spaceLikedGameFace(analysis!)
              : spaceLibraryFolderDraft(folder),
          origin: folder == null
              ? SpaceAutoOrigin.liked
              : SpaceAutoOrigin.library,
          folder: folder,
          analysis: analysis,
        );
        final store = _Store([item.shortcut]);
        final hidden = _Hidden();
        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              spaceShortcutsProvider.overrideWith(() => store),
              spaceHiddenAutoKeysProvider.overrideWith(() => hidden),
              engineSettingsProviderNew.overrideWith(_EngineSettings.new),
              if (likes != null) likedGamesProvider.overrideWith(() => likes),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: Consumer(
                builder: (context, ref, _) {
                  ResponsiveHelper.init(context);
                  container = ProviderScope.containerOf(context);
                  ref.watch(spaceShortcutsProvider);
                  if (likes != null) ref.watch(likedGamesProvider);
                  final visible = !ref
                      .watch(spaceHiddenAutoKeysProvider)
                      .contains(item.key);
                  return Scaffold(
                    body: Center(
                      child: visible
                          ? SizedBox(
                              width: item.shortcut.kind.tileWidth,
                              height: SpaceMetrics.railHeight,
                              child: SpaceAutoTile(
                                item: item,
                                section: SpaceSection.library,
                                onOpen: (_) {},
                              ),
                            )
                          : const Text('Removed'),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.longPress(find.byType(SpaceAutoTile));
        await tester.pumpAndSettle();
        expect(find.text('Delete'), findsNothing);
        expect(find.text('Unsubscribe'), findsNothing);
        expect(find.text('Remove from likes'), findsNothing);
        expect(find.text('Move to database'), findsNothing);
        await tester.ensureVisible(find.text('Remove from My Space'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove from My Space'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(SpaceAutoTile), findsNothing);
        expect(hidden.state, contains(item.key));
        expect(
          store.contains(item.shortcut.kind, item.shortcut.targetId),
          isFalse,
        );
        expect(item.folder, folder);
        if (likes != null) {
          expect(likes.removals, 0);
          expect(container.read(likedGamesProvider).requireValue, [analysis]);
          expect(
            container.read(spaceAutoRowProvider(SpaceSection.likes)).leading,
            isEmpty,
          );
        }
        await tester.tap(find.text('Undo'));
        await tester.pump();
        expect(hidden.state, isEmpty);
        expect(find.byType(SpaceAutoTile), findsOneWidget);
        expect(
          store.contains(item.shortcut.kind, item.shortcut.targetId),
          isTrue,
        );
        if (likes != null) {
          expect(likes.removals, 0);
          expect(
            container.read(spaceAutoRowProvider(SpaceSection.likes)).leading,
            hasLength(1),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }
}
