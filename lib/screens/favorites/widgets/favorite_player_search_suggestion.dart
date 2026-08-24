import 'package:chessever2/repository/supabase/players/players_repository.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef FavoritePlayerSearchFetcher =
    Future<List<Map<String, dynamic>>> Function(String query);

final favoritePlayerSearchFetcherProvider =
    Provider<FavoritePlayerSearchFetcher>((ref) {
      final repository = PlayersRepository();
      return (query) => repository.searchPlayers(query: query, pageSize: 12);
    });

final favoritePlayerSearchProvider = FutureProvider.autoDispose
    .family<List<PlayerStandingModel>, String>((ref, rawQuery) async {
      final query = rawQuery.trim();
      if (query.length < 2) return const [];

      var cancelled = false;
      ref.onDispose(() => cancelled = true);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (cancelled) return const [];

      final rows = await ref.read(favoritePlayerSearchFetcherProvider)(query);
      final seenIds = <int>{};
      final results = <PlayerStandingModel>[];

      for (final row in rows) {
        final fideId = int.tryParse(row['fideId']?.toString() ?? '');
        final name = row['name']?.toString().trim() ?? '';
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

enum FavoritePlayerSearchSurface { favorites, games }

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
  final Set<int> _addingPlayerIds = {};

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

    final search = ref.watch(favoritePlayerSearchProvider(query));
    return search.when(
      loading:
          () => Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Searching players...',
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      error:
          (_, __) => _message(
            icon: Icons.search_off_rounded,
            title: 'Could not search players',
            subtitle: 'Please check your connection and try again.',
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

    final addable = results
        .where((player) => !_isFavorite(player))
        .toList(growable: false);
    if (addable.isEmpty) {
      if (widget.surface == FavoritePlayerSearchSurface.games) {
        return _message(
          icon: Icons.sports_esports_outlined,
          title: 'No games found for this player.',
        );
      }
      return _message(
        icon: Icons.favorite_rounded,
        title: 'Already in your favorites',
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Looking for a player?',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose a player to add to your favorites.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          for (final player in addable) _playerRow(player),
        ],
      ),
    );
  }

  Widget _playerRow(PlayerStandingModel player) {
    final isAdding =
        player.fideId != null && _addingPlayerIds.contains(player.fideId);
    final hasFlag = player.countryCode.trim().isNotEmpty;
    final title = player.title?.trim() ?? '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onOpenPlayer(player),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: context.colors.divider.withValues(alpha: 0.55),
              ),
            ),
          ),
          child: Row(
            children: [
              if (hasFlag) ...[
                FederationFlag(
                  federation: player.countryCode,
                  width: 22,
                  height: 15,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        if (title.isNotEmpty) ...[
                          Text(
                            title,
                            style: AppTypography.textSmMedium.copyWith(
                              color: kPrimaryColor.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            player.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.textSmMedium.copyWith(
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (player.score > 0) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${player.score}',
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  tooltip: 'Add ${player.name} to favorites',
                  onPressed: isAdding ? null : () => _add(player),
                  icon:
                      isAdding
                          ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.colors.textPrimary,
                            ),
                          )
                          : Icon(
                            Icons.favorite_border_rounded,
                            color: context.colors.textPrimary,
                          ),
                ),
              ),
            ],
          ),
        ),
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
      if (mounted) {
        setState(() => _addingPlayerIds.remove(fideId));
      }
    }
  }

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

  Widget _message({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: context.colors.textPrimary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.85),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
