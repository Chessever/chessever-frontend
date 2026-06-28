import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/models/like_tag.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/string_utils.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/backfilled_federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Unified game card for library screens.
/// Uses the same design as GamebaseSearchGameCard for consistency.
class LibraryGameCard extends HookConsumerWidget {
  const LibraryGameCard({
    super.key,
    required this.game,
    required this.onTap,
    this.onLongPress,
    this.eventName,
    this.eco,
    this.date,
    this.showRound = true,
    this.tags = const <String>[],
    this.reserveTagSlot = false,
    this.tagCounts,
  });

  final GamesTourModel game;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? eventName;
  final String? eco;
  final DateTime? date;
  final bool showRound;
  final List<String> tags;

  /// When true, the tag row keeps its height even with no tags, so every card
  /// in a database list stays the same size. Used by saved-analysis lists
  /// (My Database, My Likes); left false for gamebase/import cards.
  final bool reserveTagSlot;

  /// Optional tag-frequency map (tag label → total games carrying that tag in
  /// the enclosing collection). When provided, the chips render sorted by
  /// count desc — most-used tag leftmost — so the user's dominant categories
  /// surface first. Tie-break follows canonical [kLikeTags] order.
  final Map<String, int>? tagCounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawName = eventName ?? game.tourSlug ?? game.tourId;

    // useMemoized: the event-name cleanup (two replaceAll passes + slug→title)
    // is a pure function of rawName, keyed on a value-stable String — so it's
    // computed once and reused across scroll-driven rebuilds / live updates
    // instead of re-running every frame this card rebuilds.
    final displayEventName = useMemoized(() {
      final cleanedName =
          rawName.replaceAll('-', ' ').replaceAll('_', ' ').trim();
      final isGeneric =
          cleanedName.isEmpty ||
          cleanedName.toLowerCase() == 'gamebase' ||
          cleanedName.toLowerCase() == 'search' ||
          cleanedName.toLowerCase() == 'library';
      return isGeneric ? 'Library' : StringUtils.slugToTitle(rawName);
    }, [rawName]);

    final timeControlIcon = _getTimeControlIcon(game, displayEventName);
    final displayEco = eco ?? game.eco ?? ''; // Only ECO code, never round info
    final displayDate = _formatDate(date ?? game.lastMoveTime);

    // useMemoized: tag normalize + count-desc sort (builds a canonical-order
    // map then sorts) recomputed only when the tag list/counts reference
    // changes — no resort when the enclosing list re-renders this card with
    // the same inputs.
    final visibleTags = useMemoized(() {
      final result = normalizeLikeTagLabels(tags).toList();
      final counts = tagCounts;
      if (counts != null && result.length > 1) {
        final canonicalOrder = <String, int>{
          for (var i = 0; i < kLikeTags.length; i++) kLikeTags[i].label: i,
        };
        result.sort((a, b) {
          final cmp = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
          if (cmp != 0) return cmp;
          final ia = canonicalOrder[a] ?? kLikeTags.length;
          final ib = canonicalOrder[b] ?? kLikeTags.length;
          return ia.compareTo(ib);
        });
      }
      return result;
    }, [tags, tagCounts]);

    return TappableScale(
      onTap: () {
        HapticFeedbackService.cardTap();
        onTap();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress:
            onLongPress != null
                ? () {
                  HapticFeedbackService.buttonPress();
                  onLongPress!();
                }
                : null,
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surfaceRecessed,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Column(
            children: [
              // Top section - light background with player info
              Container(
                padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 10.h),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment(-1.0, 0.26),
                    end: Alignment(1.0, -0.26),
                    colors: [Color(0xFFDDDDE0), Color(0xFFADAEB3)],
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(12.br),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _PlayerInfo(
                        name: game.whitePlayer.name,
                        title: ChessTitleUtils.normalize(
                          game.whitePlayer.title,
                        ),
                        rating:
                            game.whitePlayer.rating > 0
                                ? game.whitePlayer.displayRating
                                : '',
                        federation: game.whitePlayer.countryCode,
                        fideId: game.whitePlayer.fideId,
                        alignment: CrossAxisAlignment.start,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      child: _ResultOrEvalBar(game: game, ref: ref),
                    ),
                    Expanded(
                      child: _PlayerInfo(
                        name: game.blackPlayer.name,
                        title: ChessTitleUtils.normalize(
                          game.blackPlayer.title,
                        ),
                        rating:
                            game.blackPlayer.rating > 0
                                ? game.blackPlayer.displayRating
                                : '',
                        federation: game.blackPlayer.countryCode,
                        fideId: game.blackPlayer.fideId,
                        alignment: CrossAxisAlignment.end,
                      ),
                    ),
                  ],
                ),
              ),
              // Bottom section - dark background with event info
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(12.br),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Left: time control icon + event name
                        Image.asset(
                          timeControlIcon,
                          width: 14.sp,
                          height: 14.sp,
                        ),
                        SizedBox(width: 4.w),
                        Expanded(
                          child: Text(
                            displayEventName,
                            style: AppTypography.textXsRegular.copyWith(
                              color: context.colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // ECO code (only if available)
                        if (showRound && displayEco.isNotEmpty) ...[
                          SizedBox(width: 8.w),
                          Text(
                            displayEco,
                            style: AppTypography.textXsRegular.copyWith(
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ],
                        // Date (always right-most)
                        if (displayDate.isNotEmpty) ...[
                          SizedBox(width: 8.w),
                          Text(
                            displayDate,
                            style: AppTypography.textXsRegular.copyWith(
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (reserveTagSlot || visibleTags.isNotEmpty) ...[
                      SizedBox(height: 6.h),
                      if (visibleTags.isNotEmpty)
                        _LibraryTagChips(tags: visibleTags)
                      else
                        // No tags: keep a single chip-row of height so cards
                        // stay uniformly sized across the list.
                        SizedBox(height: 22.h),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Get time control icon from game data
  /// Primary source: timeControl field from group_broadcasts table (via tours join)
  /// Fallback: event name keywords (e.g., "Tata Steel Blitz")
  /// NOTE: Do NOT use remaining clock time - it's unreliable (a classical game
  /// with 5 minutes left would be wrongly classified as blitz)
  String _getTimeControlIcon(GamesTourModel game, String eventName) {
    // Primary: use the actual time_control from group_broadcasts
    if (game.timeControl != null && game.timeControl!.isNotEmpty) {
      switch (game.timeControl!.toLowerCase()) {
        case 'standard':
        case 'classical':
          return PngAsset.classicalIcon;
        case 'rapid':
          return PngAsset.rapidIcon;
        case 'blitz':
        case 'bullet':
          return PngAsset.blitzIcon;
      }
    }

    // Fallback: check event name for keywords
    final event = eventName.toLowerCase();
    if (event.contains('blitz') || event.contains('bullet')) {
      return PngAsset.blitzIcon;
    }
    if (event.contains('titled')) return PngAsset.blitzIcon;
    if (event.contains('speed chess')) return PngAsset.blitzIcon;
    if (event.contains('rapid')) return PngAsset.rapidIcon;

    // Default to classical for standard/unknown events
    return PngAsset.classicalIcon;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

/// Readable tag presentation for library cards.
///
/// Tags are sorted before this widget, then rendered as normal chips in a
/// wrapping row so every persisted label remains visible instead of collapsing
/// secondary tags into unlabeled slivers.
class _LibraryTagChips extends StatelessWidget {
  const _LibraryTagChips({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5.w,
      runSpacing: 5.h,
      children: [for (final tag in tags) _LibraryTagChip(label: tag)],
    );
  }
}

class _LibraryTagChip extends StatelessWidget {
  const _LibraryTagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tag = likeTagByLabel(label);
    final color = tag?.color ?? context.colors.textSecondary;

    return Container(
      constraints: BoxConstraints(maxWidth: 160.w),
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999.br),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.textXsMedium.copyWith(
          color: context.colors.textPrimary,
          fontSize: 10.sp,
        ),
      ),
    );
  }
}

class _PlayerInfo extends StatelessWidget {
  const _PlayerInfo({
    required this.name,
    required this.title,
    required this.rating,
    required this.alignment,
    required this.federation,
    required this.fideId,
  });

  final String name;
  final String title;
  final String rating;
  final CrossAxisAlignment alignment;
  final String federation;
  final int? fideId;

  @override
  Widget build(BuildContext context) {
    final rank = [
      if (title.isNotEmpty) title,
      if (rating.isNotEmpty) rating,
    ].join(' ');

    // Imported PGNs often omit [WhiteFed]/[BlackFed] but include FideId tags,
    // so BackfilledFederationFlag resolves the country via Supabase's
    // chess_players lookup. If no real country is available, the flag widget
    // renders nothing rather than a generic placeholder.
    final flag = BackfilledFederationFlag(
      federation: federation,
      fideId: fideId,
      width: 14.sp,
      height: 10.sp,
      borderRadius: BorderRadius.circular(2.br),
    );

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Row(
          mainAxisAlignment:
              alignment == CrossAxisAlignment.end
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
          children: [
            if (alignment != CrossAxisAlignment.end) ...[
              flag,
              SizedBox(width: 6.w),
            ],
            Flexible(
              child: Text(
                name,
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.background,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign:
                    alignment == CrossAxisAlignment.end
                        ? TextAlign.right
                        : TextAlign.left,
              ),
            ),
            if (alignment == CrossAxisAlignment.end) ...[
              SizedBox(width: 6.w),
              flag,
            ],
          ],
        ),
        SizedBox(height: 2.h),
        Text(
          rank,
          style: AppTypography.textXsRegular.copyWith(
            color: context.colors.textTertiary,
            fontSize: 12.sp,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign:
              alignment == CrossAxisAlignment.end
                  ? TextAlign.right
                  : TextAlign.left,
        ),
      ],
    );
  }
}

/// Result score display: "½ - ½", "1 - 0", "0 - 1"
/// Uses larger dash (18sp semibold) with smaller scores (12sp medium) per CSS spec.
class _GameResultScore extends StatelessWidget {
  const _GameResultScore({required this.status});

  final GameStatus status;

  @override
  Widget build(BuildContext context) {
    final (left, right) = switch (status) {
      GameStatus.whiteWins => ('1', '0'),
      GameStatus.blackWins => ('0', '1'),
      GameStatus.draw => ('½', '½'),
      _ => ('*', '*'),
    };

    final scoreStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.005 * 12,
      color: const Color(0xFF000000),
    );

    final dashStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 18.sp,
      fontWeight: FontWeight.w600,
      height: 26 / 18,
      letterSpacing: 0.001 * 18,
      color: const Color(0xFF000000),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(left, style: scoreStyle),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w),
          child: Text('-', style: dashStyle),
        ),
        Text(right, style: scoreStyle),
      ],
    );
  }
}

/// Shows either eval bar for ongoing games or result text for finished games.
/// Mirrors the behavior of _CenterContent in game_card.dart.
class _ResultOrEvalBar extends StatelessWidget {
  const _ResultOrEvalBar({required this.game, required this.ref});

  final GamesTourModel game;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    // Use effectiveGameStatus to handle DB update lag
    final effectiveStatus = game.effectiveGameStatus;

    // If game is not ongoing, show result score
    if (effectiveStatus != GameStatus.ongoing) {
      return _GameResultScore(status: effectiveStatus);
    }

    // Check if engine gauge is enabled in settings
    final showEngineGauge = ref.watch(
      engineSettingsProviderNew.select(
        (state) => state.valueOrNull?.showEngineGauge ?? true,
      ),
    );

    // If engine gauge is disabled, show "LIVE" indicator
    if (!showEngineGauge) {
      return Text(
        'LIVE',
        style: AppTypography.textSmMedium.copyWith(
          color: kPrimaryColor,
          fontSize: 12.sp,
        ),
      );
    }

    // Show the eval progress bar for ongoing games
    return ChessProgressBar(gamesTourModel: game);
  }
}
