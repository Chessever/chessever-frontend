import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/screens/collections/collection_catalog_views.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef CollectionAuthorProfileKey = ({
  String id,
  String name,
  String? collectionSlug,
});

/// Resolve legacy name credits through the existing public catalog. Namesakes
/// are distinguished by membership of the collection whose credit was tapped.
final collectionAuthorProfileProvider = FutureProvider.autoDispose
    .family<CollectionAuthor?, CollectionAuthorProfileKey>((ref, key) async {
      final repository = ref.watch(collectionsRepositoryProvider);
      final seed = CollectionAuthor(id: key.id, name: key.name);
      final query = CollectionSearchQuery(
        authorId: seed.hasCatalogIdentity ? seed.id : '',
        author: seed.hasCatalogIdentity ? '' : seed.name,
      );
      final candidates = <CollectionAuthor>[];
      var offset = 0;
      while (true) {
        final page = await repository.searchAuthors(query, offset);
        candidates.addAll(
          page.items.where(
            (author) =>
                author.id == seed.id ||
                (!seed.hasCatalogIdentity &&
                    author.name.trim().toLowerCase() ==
                        seed.name.trim().toLowerCase()),
          ),
        );
        offset += page.items.length;
        if (page.items.isEmpty || offset >= page.total) break;
      }
      if (seed.hasCatalogIdentity) return candidates.firstOrNull;
      if (candidates.length <= 1) return candidates.firstOrNull;
      if (key.collectionSlug != null) {
        for (final author in candidates.where(
          (author) => author.hasCatalogIdentity,
        )) {
          var bookOffset = 0;
          while (true) {
            final books = await repository.searchBooks(
              CollectionSearchQuery(authorId: author.id),
              bookOffset,
            );
            if (books.items.any((book) => book.slug == key.collectionSlug)) {
              return author;
            }
            bookOffset += books.items.length;
            if (books.items.isEmpty || bookOffset >= books.total) break;
          }
        }
      }
      throw StateError('This author could not be identified.');
    });

class CollectionAuthorScreen extends ConsumerStatefulWidget {
  const CollectionAuthorScreen({
    super.key,
    required this.author,
    this.query = const CollectionSearchQuery(),
    this.initialTab = 1,
    this.collectionSlug,
  }) : assert(initialTab == 0 || initialTab == 1);

  final CollectionAuthor author;
  final CollectionSearchQuery query;

  /// About = 0; author cards open Collections = 1 by default.
  final int initialTab;
  final String? collectionSlug;

  static Future<void> open(
    BuildContext context, {
    required CollectionAuthor author,
    CollectionSearchQuery query = const CollectionSearchQuery(),
    bool about = false,
    String? collectionSlug,
  }) {
    HapticFeedbackService.cardTap();
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CollectionAuthorScreen(
          author: author,
          query: query,
          initialTab: about ? 0 : 1,
          collectionSlug: collectionSlug,
        ),
      ),
    );
  }

  @override
  ConsumerState<CollectionAuthorScreen> createState() =>
      _CollectionAuthorScreenState();
}

class _CollectionAuthorScreenState
    extends ConsumerState<CollectionAuthorScreen> {
  final _tabs = EventViewController();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = (
      id: widget.author.id,
      name: widget.author.name,
      collectionSlug: widget.collectionSlug,
    );
    final profile = ref.watch(collectionAuthorProfileProvider(key));
    final author = profile.valueOrNull ?? widget.author;
    Widget retry() => Center(
      child: Padding(
        padding: EdgeInsets.all(24.sp),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              userFacingError(
                profile.error!,
                fallback: "Couldn't load this author.",
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.invalidate(collectionAuthorProfileProvider(key)),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
    return EventViewShell(
      title: author.name,
      onTitleTap: () {
        HapticFeedbackService.buttonPress();
        _tabs.showTab(0, scrollToTop: true);
      },
      tabs: const ['About', 'Collections'],
      initialTab: widget.initialTab,
      controller: _tabs,
      pageBuilder: (_, index) {
        if (profile.hasError &&
            (index == 0 || !widget.author.hasCatalogIdentity)) {
          return retry();
        }
        if (profile.isLoading &&
            (index == 0 || !widget.author.hasCatalogIdentity)) {
          return const Center(child: CircularProgressIndicator());
        }
        if (index == 0) {
          final paragraphs = [
            for (final paragraph in (author.about ?? '').split(
              RegExp(r'\n\s*\n'),
            ))
              if (paragraph.trim().isNotEmpty) paragraph.trim(),
          ];
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(collectionAuthorProfileProvider(key));
              try {
                await ref.read(collectionAuthorProfileProvider(key).future);
              } catch (_) {
                // The provider's error renders the retry state above.
              }
            },
            child: ListView(
              key: const ValueKey('collection_author_about'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                20.sp,
                20.sp,
                20.sp,
                32.sp + MediaQuery.viewPaddingOf(context).bottom,
              ),
              children: [
                if (author.avatarUrl != null) ...[
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: PlayerInitialsAvatar(
                      photoUrl: author.avatarUrl,
                      initials: author.name
                          .split(RegExp(r'\s+'))
                          .where((part) => part.isNotEmpty)
                          .take(2)
                          .map((part) => part.characters.first)
                          .join(),
                      size: 72.w,
                      isCircular: true,
                    ),
                  ),
                  SizedBox(height: 20.sp),
                ],
                if (paragraphs.isEmpty)
                  Text(
                    'No author description available yet.',
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                for (final paragraph in paragraphs)
                  Padding(
                    padding: EdgeInsets.only(bottom: 12.sp),
                    child: Text(
                      paragraph,
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }
        final query = widget.query;
        return CollectionBooksCatalog(
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
            author: author.hasCatalogIdentity ? '' : author.name,
          ),
        );
      },
    );
  }
}
