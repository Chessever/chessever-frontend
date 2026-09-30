import 'package:chessever2/screens/collections/collection_catalog_views.dart';
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/screens/collections/collection_catalog_list.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/collections/opening_event_card.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The same index works across Collections and within a book. Its metadata is
/// public; selecting a book opening still goes through that book's access gate.
class CollectionOpeningsView extends ConsumerWidget {
  const CollectionOpeningsView({
    super.key,
    this.slug,
    this.search,
    this.onPick,
    this.bottomPadding = 0,
  });
  final String? slug;
  final CollectionSearchQuery? search;
  final ValueChanged<CollectionOpening>? onPick;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = search;
    if (query != null && slug == null) {
      final repository = ref.watch(collectionsRepositoryProvider);
      return CollectionCatalogList<CollectionOpening>(
        key: ObjectKey(repository),
        query: query,
        load: (offset) async {
          final page = await repository.searchOpenings(query, offset);
          return CatalogBatch(page.items, page.total);
        },
        identity: (opening) => opening.eco,
        padding: _listPadding(context, extraBottom: bottomPadding),
        emptyMessage: 'No openings yet.',
        itemBuilder: (opening) => Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: _card(context, ref, opening),
        ),
      );
    }
    final provider = collectionOpeningsProvider(slug);
    final openings = ref.watch(provider);
    return openings.when(
      loading: () => const _ExploreLoading(),
      error: (error, _) => _ExploreNotice(
        message: userFacingError(error, fallback: "Couldn't load openings."),
        onRetry: () => ref.invalidate(provider),
      ),
      data: (items) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(provider);
          try {
            await ref.read(provider.future);
          } catch (_) {
            // The provider renders the failed refresh with its retry action.
          }
        },
        child: items.isEmpty
            ? const _ExploreNotice(
                message:
                    'Openings will appear here when games in published books have been indexed.',
              )
            : ListView.separated(
                key: PageStorageKey('collection_openings_${slug ?? 'all'}'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: _listPadding(context, extraBottom: bottomPadding),
                itemCount: items.length,
                separatorBuilder: (_, _) => SizedBox(height: 12.sp),
                itemBuilder: (context, index) {
                  return _card(context, ref, items[index]);
                },
              ),
      ),
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, CollectionOpening opening) {
    final name = collectionOpeningName(opening);
    void open() {
      HapticFeedbackService.cardTap();
      if (onPick != null) {
        onPick!(opening);
      } else {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OpeningBooksScreen(opening: opening),
          ),
        );
      }
    }

    return OpeningEventCard(
      key: ValueKey('collection_opening_${opening.eco}'),
      name: name,
      eco: opening.eco,
      fen: opening.fen,
      gameCount: opening.gameCount,
      bookCount: slug == null ? opening.bookCount : null,
      onTap: open,
      menuActions: (menuContext) => [
        LibraryMenuAction(
          icon: Icons.open_in_new_rounded,
          label: 'Open',
          onSelected: open,
        ),
        spaceMenuAction(
          context: menuContext,
          ref: ref,
          draft: spaceOpeningDraft(
            targetId: opening.eco,
            name: name,
            extraParams: {
              if (opening.fen != null) 'fen': opening.fen,
              'gameCount': opening.gameCount,
            },
          ),
        ),
      ],
    );
  }
}

class OpeningBooksScreen extends ConsumerWidget {
  const OpeningBooksScreen({super.key, required this.opening, this.search});
  final CollectionSearchQuery? search;
  final CollectionOpening opening;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (search != null) {
      final q = search!;
      return EventViewShell(
        title: collectionOpeningName(opening),
        tabs: const ['Books'],
        tabStripOverride: const SizedBox.shrink(),
        pageBuilder: (_, __) => CollectionBooksCatalog(
          query: CollectionSearchQuery(
            text: q.text,
            eco: opening.eco,
            result: q.result,
            year: q.year,
            minYear: q.minYear,
            maxYear: q.maxYear,
            author: q.author,
            authorId: q.authorId,
            annotated: q.annotated,
            sort: q.sort,
          ),
        ),
      );
    }
    final provider = collectionBooksForOpeningProvider(opening.eco);
    final books = ref.watch(provider);
    return EventViewShell(
      title: '${opening.eco} · ${collectionOpeningName(opening)}',
      tabs: const ['Books'],
      pageBuilder: (context, _) => books.when(
        loading: () => const _ExploreLoading(),
        error: (error, _) => _ExploreNotice(
          message: userFacingError(
            error,
            fallback: "Couldn't load books for this opening.",
          ),
          onRetry: () => ref.invalidate(provider),
        ),
        data: (items) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(provider);
            try {
              await ref.read(provider.future);
            } catch (_) {
              // The provider renders the failed refresh with its retry action.
            }
          },
          child: items.isEmpty
              ? const _ExploreNotice(
                  message: 'No published books study this opening yet.',
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: _listPadding(context),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => SizedBox(height: 12.sp),
                  itemBuilder: (context, index) => CollectionCard(
                    collection: items[index],
                    opening: opening,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Pages the published-games feed, mounting one game at a time and requesting
/// the next bounded batch only when the reader asks. Opening a board steps
/// through exactly the games already shown.
class PublishedCollectionGamesView extends ConsumerStatefulWidget {
  const PublishedCollectionGamesView({
    super.key,
    this.bottomPadding = 0,
    this.search = const CollectionSearchQuery(),
  });
  final CollectionSearchQuery search;
  final double bottomPadding;
  @override
  ConsumerState<PublishedCollectionGamesView> createState() =>
      _PublishedCollectionGamesViewState();
}

class _PublishedCollectionGamesViewState
    extends ConsumerState<PublishedCollectionGamesView>
    with AutomaticKeepAliveClientMixin {
  final List<CollectionGame> _games = [];
  int _nextOffset = 0;
  int _total = 0;
  int _generation = 0;
  bool _loading = true;
  bool _hasMore = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant PublishedCollectionGamesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search) {
      _load(reset: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final scroll = PrimaryScrollController.maybeOf(context);
        if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
      });
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || !_hasMore)) return;
    final generation = reset ? ++_generation : _generation;
    if (reset) {
      _games.clear();
      _nextOffset = 0;
      _total = 0;
      _hasMore = false;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final batch = await ref
          .read(collectionsRepositoryProvider)
          .fetchPublishedGames(offset: _nextOffset, search: widget.search);
      if (!mounted || generation != _generation) return;
      final seen = {for (final game in _games) game.id};
      setState(() {
        _games.addAll(batch.games.where((game) => seen.add(game.id)));
        _nextOffset = batch.nextOffset;
        _total = batch.total;
        _hasMore = batch.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _open(int index) {
    HapticFeedbackService.cardTap();
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChessBoardScreenNew(
          currentIndex: index,
          games: [for (final game in _games) game.game],
          viewSource: ChessboardView.tour,
          showGamebaseButton: false,
          disableGamebaseOverlayByDefault: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen(collectionsRepositoryProvider, (_, _) => _load(reset: true));
    ref.listen(
      subscriptionProvider.select((s) => s.isSubscribed),
      (_, _) => _load(reset: true),
    );
    if (_games.isEmpty && _loading) return const _ExploreLoading();
    if (_games.isEmpty && _error != null) {
      return _ExploreNotice(
        message: userFacingError(
          _error,
          fallback:
              _error is CollectionsRequestException &&
                  (_error as CollectionsRequestException).statusCode == 400
              ? 'Check your search. Use an ECO code such as B20 or a tag like [White "Carlsen"].'
              : "Couldn't load published games.",
        ),
        onRetry: () => _load(reset: true),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notice) {
          if (notice.metrics.extentAfter < 600 && _error == null) _load();
          return false;
        },
        child: _games.isEmpty && !_hasMore
            ? _ExploreNotice(
                message: widget.search.isActive
                    ? 'No matching games. Try another search or clear filters.'
                    : 'No readable games yet. Browse Books to discover published collections.',
              )
            : ListView.builder(
                key: ValueKey(widget.search),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  top: 16.sp,
                  bottom:
                      24.sp +
                      MediaQuery.viewPaddingOf(context).bottom +
                      widget.bottomPadding,
                ),
                itemCount: _games.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: EdgeInsets.fromLTRB(20.sp, 0, 20.sp, 12.sp),
                      child: Text(
                        '$_total ${_total == 1 ? 'game' : 'games'}',
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    );
                  }
                  if (index == _games.length + 1) {
                    if (_loading) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (_error != null) {
                      return TextButton(
                        onPressed: () => _load(),
                        child: const Text('Try loading more again'),
                      );
                    }
                    if (!_hasMore) {
                      return const SizedBox.shrink();
                    }
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _error == null) _load();
                    });
                    return const SizedBox(height: 48);
                  }
                  final game = _games[index - 1];
                  return Padding(
                    padding: EdgeInsets.only(bottom: 16.sp),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (game.card.collectionTitle != null)
                          Padding(
                            padding: EdgeInsets.fromLTRB(20.sp, 0, 20.sp, 4.sp),
                            child: Text(
                              game.card.collectionTitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.textXsMedium.copyWith(
                                color: context.colors.textSecondary,
                              ),
                            ),
                          ),
                        DiscoveryGameList(
                          games: [game.game],
                          viewMode: GamesListViewMode.gamesCard,
                          streamEnabled: false,
                          onOpen: (_, _) => _open(index - 1),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

EdgeInsets _listPadding(BuildContext context, {double extraBottom = 0}) =>
    EdgeInsets.fromLTRB(
      16.sp,
      16.sp,
      16.sp,
      24.sp + MediaQuery.viewPaddingOf(context).bottom + extraBottom,
    );

class _ExploreNotice extends StatelessWidget {
  const _ExploreNotice({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    children: [
      Text(
        message,
        textAlign: TextAlign.center,
        style: AppTypography.textSmRegular.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
      if (onRetry != null)
        TextButton(onPressed: onRetry, child: const Text('Try again')),
    ],
  );
}

class _ExploreLoading extends StatelessWidget {
  const _ExploreLoading();
  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.all(16.sp),
    children: const [
      DiscoveryGameListSkeleton(
        count: 4,
        viewMode: GamesListViewMode.gamesCard,
      ),
    ],
  );
}
