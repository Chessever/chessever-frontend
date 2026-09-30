import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/screens/collections/collection_catalog_list.dart';
import 'package:chessever2/screens/collections/collection_explore.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/screens/collections/opening_event_card.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:chessever2/widgets/game_filter/eco_filter_dropdown.dart'
    show EcoBrowseNode, buildEcoBrowseTree;
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CollectionBooksCatalog extends ConsumerWidget {
  const CollectionBooksCatalog({
    super.key,
    required this.query,
    this.bottomPadding = 0,
  });
  final CollectionSearchQuery query;
  final double bottomPadding;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(collectionsRepositoryProvider);
    final favorites = ref.watch(favoriteEventsProvider).valueOrNull ?? const [];
    return CollectionCatalogList<Collection>(
      key: ObjectKey(repository),
      query: query,
      load: (offset) async {
        final page = await repository.searchBooks(query, offset);
        return CatalogBatch(page.items, page.total);
      },
      identity: (book) => book.id,
      compare: query.sort == 'default'
          ? (a, b) {
              final aStarred = collectionIsFavorited(favorites, a);
              final bStarred = collectionIsFavorited(favorites, b);
              if (aStarred != bStarred) return aStarred ? -1 : 1;
              // Retain the server's order for equally ranked books.
              return 0;
            }
          : null,
      padding: EdgeInsets.fromLTRB(
        16.sp,
        12.sp,
        16.sp,
        24.sp + MediaQuery.viewPaddingOf(context).bottom + bottomPadding,
      ),
      emptyMessage: 'No books yet.',
      itemBuilder: (book) => Padding(
        padding: EdgeInsets.only(bottom: 12.sp),
        child: CollectionCard(collection: book),
      ),
    );
  }
}

class CollectionAuthorsCatalog extends ConsumerWidget {
  const CollectionAuthorsCatalog({
    super.key,
    required this.query,
    this.bottomPadding = 0,
  });
  final CollectionSearchQuery query;
  final double bottomPadding;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(collectionsRepositoryProvider);
    return CollectionCatalogList<CollectionAuthor>(
      key: ValueKey((repository, ref.watch(profileAvatarUrlProvider))),
      query: query,
      load: (offset) async {
        final page = await repository.searchAuthors(query, offset);
        return CatalogBatch(page.items, page.total);
      },
      identity: (author) => author.id,
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.adaptive(phone: 16.sp, tablet: 24.sp),
        8.sp,
        ResponsiveHelper.adaptive(phone: 16.sp, tablet: 24.sp),
        24.sp + MediaQuery.viewPaddingOf(context).bottom + bottomPadding,
      ),
      emptyMessage: 'Authors will appear here when their books are published.',
      indexedItemBuilder: (author, index) => Padding(
        padding: EdgeInsets.only(bottom: 8.sp),
        child: FigmaPlayerCard(
          key: ValueKey('collection_author_${author.id}'),
          player: PlayerStandingModel(
            countryCode: '',
            name: author.name,
            score: 0,
            scoreChange: 0,
            hasRatingDiff: false,
            matchScore:
                '${author.bookCount} ${author.bookCount == 1 ? 'book' : 'books'}',
          ),
          rank: index + 1,
          showRank: true,
          showFavoriteButton: false,
          hideMissingRating: true,
          avatar: PlayerInitialsAvatar(
            photoUrl: author.avatarUrl,
            initials: author.name
                .split(RegExp(r'\s+'))
                .where((s) => s.isNotEmpty)
                .take(2)
                .map((s) => s.characters.first)
                .join(),
            size: 56.w,
            isCircular: true,
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EventViewShell(
                title: author.name,
                tabs: const ['Books'],
                tabStripOverride: const SizedBox.shrink(),
                pageBuilder: (_, __) => CollectionBooksCatalog(
                  query: CollectionSearchQuery(
                    text: query.text,
                    eco: query.eco,
                    result: query.result,
                    year: query.year,
                    minYear: query.minYear,
                    maxYear: query.maxYear,
                    annotated: query.annotated,
                    sort: query.sort,
                    authorId: author.hasCatalogIdentity ? author.id : '',
                    author: query.author.isNotEmpty
                        ? query.author
                        : author.hasCatalogIdentity
                        ? ''
                        : author.name,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// The opening vocabulary is bounded to 500 ECO codes. Read all matching
// metadata so one family is never split between pages or given a false count.
final _openingCatalog = FutureProvider.autoDispose
    .family<List<CollectionOpening>, CollectionSearchQuery>((ref, query) async {
      final repository = ref.watch(collectionsRepositoryProvider);
      final items = <CollectionOpening>[];
      var offset = 0;
      while (offset < 500) {
        final page = await repository.searchOpenings(query, offset);
        items.addAll(page.items);
        offset += page.items.length;
        if (page.items.isEmpty || offset >= page.total) break;
      }
      return items;
    });

final _openingBrowseSuggestions = browseOpeningSuggestions();

class CollectionOpeningCatalog extends ConsumerStatefulWidget {
  const CollectionOpeningCatalog({
    super.key,
    required this.query,
    this.bottomPadding = 0,
    this.slug,
    this.onPick,
  });
  final CollectionSearchQuery query;
  final double bottomPadding;
  final String? slug;
  final ValueChanged<CollectionOpening>? onPick;
  @override
  ConsumerState<CollectionOpeningCatalog> createState() =>
      _CollectionOpeningCatalogState();
}

class _CollectionOpeningCatalogState
    extends ConsumerState<CollectionOpeningCatalog> {
  final _collapsed = <String>{'A', 'B', 'C', 'D', 'E'};
  final _expandedFamilies = <String>{};
  List<CollectionOpening>? _treeItems;
  Map<String, List<EcoBrowseNode>> _tree = {};
  final _nodeItems = <String, List<CollectionOpening>>{};

  void _prepareTree(List<CollectionOpening> items) {
    if (identical(items, _treeItems)) return;
    _treeItems = items;
    final byCode = {for (final opening in items) opening.eco: opening};
    _tree = buildEcoBrowseTree(
      _openingBrowseSuggestions
          .where(
            (suggestion) => suggestion.isFamily
                ? suggestion.filter.exactEcoCodes.any(byCode.containsKey)
                : byCode.containsKey(suggestion.filter.code),
          )
          .toList(),
    );
    _nodeItems.clear();
    List<CollectionOpening> index(EcoBrowseNode node) {
      final descendants = <String, CollectionOpening>{};
      final opening = byCode[node.suggestion.filter.code];
      if (opening != null) descendants[opening.eco] = opening;
      for (final child in node.children) {
        for (final opening in index(child)) {
          descendants[opening.eco] = opening;
        }
      }
      return _nodeItems[node.suggestion.id] = descendants.values.toList();
    }

    for (final roots in _tree.values) {
      for (final node in roots) {
        index(node);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.slug == null
        ? _openingCatalog(widget.query)
        : collectionOpeningsProvider(widget.slug);
    final data = ref.watch(provider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(provider);
        try {
          await ref.read(provider.future);
        } catch (_) {
          // The provider renders the retry state.
        }
      },
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                userFacingError(error, fallback: "Couldn't load openings."),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(provider),
              child: const Text('Try again'),
            ),
          ],
        ),
        data: (items) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16.sp,
            12.sp,
            16.sp,
            24.sp +
                MediaQuery.viewPaddingOf(context).bottom +
                widget.bottomPadding,
          ),
          children: items.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.query.isActive
                          ? 'No openings match this search.'
                          : 'No openings yet.',
                    ),
                  ),
                ]
              : _openingRows(items),
        ),
      ),
    );
  }

  List<Widget> _openingRows(List<CollectionOpening> items) {
    _prepareTree(items);
    return [
      if (widget.slug == null)
        _header(
          key: 'collection_opening_all',
          title: 'All Openings',
          subtitle:
              '${items.length} ${items.length == 1 ? 'opening' : 'openings'}',
          expanded: !_collapsed.contains('all'),
          onToggle: () => _toggleCategory('all'),
        ),
      if (widget.slug != null || !_collapsed.contains('all'))
        for (final category in EcoOpenings.categories.values)
          if (widget.slug == null ||
              _tree[category.letter]?.isNotEmpty == true) ...[
            _header(
              key: 'collection_opening_category_${category.letter}',
              depth: 1,
              title: '${category.letter}: ${category.name}',
              subtitle:
                  '${category.letter}00–${category.letter}99 · '
                  '${_countOpenings(items.where((o) => o.eco.startsWith(category.letter)).length)}',
              expanded: !_collapsed.contains(category.letter),
              onToggle: _tree[category.letter]?.isNotEmpty == true
                  ? () => _toggleCategory(category.letter)
                  : null,
            ),
            if (!_collapsed.contains(category.letter))
              ..._nodes(_tree[category.letter] ?? const []),
          ],
    ];
  }

  void _toggleCategory(String id) => setState(() {
    if (!_collapsed.add(id)) _collapsed.remove(id);
  });

  Widget _header({
    required String key,
    required String title,
    required String subtitle,
    required bool expanded,
    required VoidCallback? onToggle,
    int depth = 0,
  }) => Padding(
    padding: EdgeInsetsDirectional.only(start: depth * 6.w, bottom: 8.sp),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: 90.sp),
      child: TournamentRoundHeader(
        key: ValueKey(key),
        title: title,
        subtitle: subtitle,
        multiline: true,
        titleMaxLines: 1,
        isExpanded: expanded,
        onToggle: onToggle,
      ),
    ),
  );

  List<Widget> _nodes(List<EcoBrowseNode> nodes) => [
    for (final node in nodes)
      if (_nodeItems[node.suggestion.id]?.isNotEmpty == true)
        if (node.suggestion.isFamily) ...[
          _header(
            key: 'collection_opening_family_${node.suggestion.id}',
            title: EcoOpenings.getFamily(node.suggestion.filter.code)!.name,
            subtitle:
                '${node.suggestion.codeLabel} · '
                '${_nodeItems[node.suggestion.id]!.length} '
                '${_nodeItems[node.suggestion.id]!.length == 1 ? 'opening' : 'openings'}',
            depth: node.depth + 2,
            expanded: _expandedFamilies.contains(node.suggestion.id),
            onToggle: () => setState(() {
              if (!_expandedFamilies.add(node.suggestion.id)) {
                _expandedFamilies.remove(node.suggestion.id);
              }
            }),
          ),
          if (_expandedFamilies.contains(node.suggestion.id))
            ..._nodes(node.children),
        ] else
          for (final opening in _nodeItems[node.suggestion.id]!)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: (node.depth + 2) * 6.w,
                bottom: 8.sp,
              ),
              child: OpeningEventCard(
                key: ValueKey('collection_opening_${opening.eco}'),
                name: collectionOpeningName(opening),
                eco: opening.eco,
                fen: opening.fen,
                useEventImageFrame: true,
                bookCount: widget.slug == null ? opening.bookCount : null,
                gameCount: widget.slug != null ? opening.gameCount : null,
                onTap: widget.onPick != null
                    ? () => widget.onPick!(opening)
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OpeningBooksScreen(
                            opening: opening,
                            search: widget.query,
                          ),
                        ),
                      ),
              ),
            ),
  ];

  String _countOpenings(int count) =>
      '$count ${count == 1 ? 'opening' : 'openings'}';
}
