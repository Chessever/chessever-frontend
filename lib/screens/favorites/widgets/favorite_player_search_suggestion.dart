import 'package:chessever2/repository/supabase/players/players_repository.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Indirection so tests can serve rows without a Supabase client.
typedef FavoritePlayerSearchFetcher =
    Future<List<Map<String, dynamic>>> Function(String query);

final favoritePlayerSearchFetcherProvider =
    Provider<FavoritePlayerSearchFetcher>((ref) {
      final repository = PlayersRepository();
      return (query) => repository.searchPlayers(query: query, pageSize: 12);
    });

/// Global player lookup for a Favorites search that matched nothing local.
///
/// `searchPlayers` does the matching and the ordering in Postgres (name/title
/// ilike, federation code equality, rating descending) — this only maps rows
/// and drops the ones that cannot be acted on.
///
/// `autoDispose` plus the leading delay is the debounce: each keystroke makes a
/// new family entry and disposes the previous one, so an abandoned query is
/// cancelled before it ever reaches the network.
final favoritePlayerSearchProvider = FutureProvider.autoDispose
    .family<List<PlayerStandingModel>, String>((ref, rawQuery) async {
      final query = rawQuery.trim();
      // One letter matches most of the database; it is noise, not a search.
      if (query.length < 2) return const <PlayerStandingModel>[];

      var cancelled = false;
      ref.onDispose(() => cancelled = true);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (cancelled) return const <PlayerStandingModel>[];

      final rows = await ref.read(favoritePlayerSearchFetcherProvider)(query);
      final seenIds = <int>{};
      final results = <PlayerStandingModel>[];

      for (final row in rows) {
        final fideId = int.tryParse(row['fideId']?.toString() ?? '');
        final name = row['name']?.toString().trim() ?? '';
        // A row with no FIDE id cannot be added or de-duplicated against the
        // existing favourites, so offering it would dead-end.
        if (fideId == null || name.isEmpty || !seenIds.add(fideId)) continue;

        results.add(
          PlayerStandingModel(
            countryCode: row['fed']?.toString() ?? '',
            title: row['title']?.toString(),
            name: name,
            score: (row['rating'] as num?)?.toInt() ?? 0,
            scoreChange: 0,
            matchScore: null,
            fideId: fideId,
          ),
        );
      }
      return results;
    });

/// Which tab is asking — only the wording of the "nothing to offer" state
/// differs, because on Games the user was looking for games, not players.
enum FavoritePlayerSearchSurface { favorites, games }

/// What a Favorites search shows instead of a dead end.
///
/// Searching Favorites only ever matched the handful of players already
/// followed, so any other name returned "No results" — the one moment the user
/// has clearly told us who they want. This offers those players from the global
/// database, to open or to add straight from the row.
class FavoritePlayerSearchSuggestion extends ConsumerStatefulWidget {
  const FavoritePlayerSearchSuggestion({
    super.key,
    required this.query,
    required this.favorites,
    required this.surface,
    required this.onAdd,
    required this.onOpenPlayer,
  });

  final String query;
  final List<PlayerStandingModel> favorites;
  final FavoritePlayerSearchSurface surface;
  final Future<void> Function(PlayerStandingModel player) onAdd;
  final ValueChanged<PlayerStandingModel> onOpenPlayer;

  @override
  ConsumerState<FavoritePlayerSearchSuggestion> createState() =>
      _FavoritePlayerSearchSuggestionState();
}

class _FavoritePlayerSearchSuggestionState
    extends ConsumerState<FavoritePlayerSearchSuggestion> {
  /// Rows with an add already in flight. The guards behind [widget.onAdd] can
  /// await an auth sheet or a paywall, which leaves the row tappable for as
  /// long as that takes — without this a second tap would add twice.
  final Set<int> _addingPlayerIds = <int>{};

  @override
  Widget build(BuildContext context) {
    final query = widget.query.trim();
    if (query.length < 2) {
      return _message(
        icon: Icons.search_rounded,
        title: 'Keep typing',
        subtitle: 'Enter at least 2 letters to search players.',
      );
    }

    return ref
        .watch(favoritePlayerSearchProvider(query))
        .when(
          loading: () => _busy(),
          error:
              (_, _) => _message(
                icon: Icons.search_off_rounded,
                title: 'Could not search players',
                subtitle: 'Check your connection and try again.',
              ),
          data: _buildResults,
        );
  }

  Widget _buildResults(List<PlayerStandingModel> results) {
    if (results.isEmpty) {
      return _message(
        icon: Icons.person_search_outlined,
        title: 'No player found',
        subtitle: 'Check the spelling or try another name.',
      );
    }

    // Everything matching is already followed — there is nothing to add, and
    // saying so is more use than an empty list.
    final addable = results
        .where((player) => !_isFavorite(player))
        .toList(growable: false);
    if (addable.isEmpty) {
      return widget.surface == FavoritePlayerSearchSurface.games
          ? _message(
            icon: Icons.sports_esports_outlined,
            title: 'No games yet',
            subtitle: 'These players have no games here right now.',
          )
          : _message(
            icon: Icons.favorite_rounded,
            title: 'Already in your favorites',
            subtitle:
                'Every player matching "${widget.query.trim()}" is '
                'already followed.',
          );
    }

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.sp,
      tablet: 24.sp,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        24.h,
        horizontalPadding,
        8.h,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Aligns the label with the card's own text column rather than the
            // list edge, so the heading does not sit left of every name.
            padding: EdgeInsets.only(left: 4.w, bottom: 12.h),
            child: Text(
              'Not following yet',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
          // The same card the Favorites list itself renders: tapping opens the
          // profile, and its heart is the add. `showRank: false` because a
          // search result holds no rank in this list. A successful add makes
          // the player a favourite, which drops the row from `addable` on the
          // next build — that disappearance is the confirmation.
          for (final player in addable)
            FigmaPlayerCard(
              key: ValueKey<int?>(player.fideId),
              player: player,
              rank: null,
              showRank: false,
              isFavorite: false,
              showFavoriteButton: true,
              onTap: () => widget.onOpenPlayer(player),
              onToggleFavorite: () => _add(player),
            ),
        ],
      ),
    );
  }

  Future<void> _add(PlayerStandingModel player) async {
    final fideId = player.fideId;
    if (fideId == null || _addingPlayerIds.contains(fideId)) return;

    setState(() => _addingPlayerIds.add(fideId));
    try {
      await widget.onAdd(player);
    } finally {
      if (mounted) setState(() => _addingPlayerIds.remove(fideId));
    }
  }

  /// FIDE id is the identity; the normalised name is the fallback for
  /// favourites saved before an id was recorded.
  bool _isFavorite(PlayerStandingModel player) {
    final normalizedName = _normalizeName(player.name);
    return widget.favorites.any((favorite) {
      if (player.fideId != null && favorite.fideId == player.fideId) {
        return true;
      }
      return _normalizeName(favorite.name) == normalizedName;
    });
  }

  String _normalizeName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Widget _busy() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 48.h),
      child: Center(
        child: SizedBox(
          width: 24.w,
          height: 24.h,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.colors.textPrimary.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  /// Mirrors the Favorites tab's own empty state, so a search that finds
  /// nothing looks like the rest of the tab rather than a second design.
  Widget _message({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 56.h),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48.ic,
              color: context.colors.textPrimary.withValues(alpha: 0.5),
            ),
            SizedBox(height: 16.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.7),
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: EdgeInsets.only(top: 8.h),
                child: Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
