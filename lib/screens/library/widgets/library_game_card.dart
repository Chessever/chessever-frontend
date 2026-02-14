import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Unified game card for library screens.
/// Uses the same design as GamebaseSearchGameCard for consistency.
class LibraryGameCard extends ConsumerWidget {
  const LibraryGameCard({
    super.key,
    required this.game,
    required this.onTap,
    this.onLongPress,
    this.eventName,
    this.eco,
    this.date,
    this.showRound = true,
  });

  final GamesTourModel game;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? eventName;
  final String? eco;
  final DateTime? date;
  final bool showRound;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayEventName = _formatEventName(
      eventName ?? game.tourSlug ?? game.tourId,
    );
    final timeControlIcon = _getTimeControlIcon(game, displayEventName);
    final displayEco = eco ?? '';  // Only ECO code, never round info
    final displayDate = _formatDate(date ?? game.lastMoveTime);

    return TappableScale(
      onTap: () {
        HapticFeedbackService.cardTap();
        onTap();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onLongPress != null
            ? () {
                HapticFeedbackService.buttonPress();
                onLongPress!();
              }
            : null,
        child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2E2E2E),
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
                      title: ChessTitleUtils.normalize(game.whitePlayer.title),
                      rating: game.whitePlayer.rating > 0
                          ? game.whitePlayer.displayRating
                          : '',
                      federation: game.whitePlayer.countryCode,
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
                      title: ChessTitleUtils.normalize(game.blackPlayer.title),
                      rating: game.blackPlayer.rating > 0
                          ? game.blackPlayer.displayRating
                          : '',
                      federation: game.blackPlayer.countryCode,
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
                color: const Color(0xFF1A1A1C),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(12.br),
                ),
              ),
              child: Row(
                children: [
                  // Left: time control icon + event name
                  Expanded(
                    child: Row(
                      children: [
                        Image.asset(
                          timeControlIcon,
                          width: 14.sp,
                          height: 14.sp,
                        ),
                        SizedBox(width: 4.w),
                        Flexible(
                          child: Text(
                            displayEventName,
                            style: AppTypography.textXsRegular.copyWith(
                              color: kWhiteColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Center: ECO code
                  if (showRound && displayEco.isNotEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          displayEco,
                          style: AppTypography.textXsRegular.copyWith(
                            color: kWhiteColor,
                          ),
                        ),
                      ),
                    ),
                  // Right: Date
                  if (displayDate.isNotEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          displayDate,
                          style: AppTypography.textXsRegular.copyWith(
                            color: kWhiteColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  String _formatEventName(String rawName) {
    final cleaned = rawName.replaceAll('-', ' ').replaceAll('_', ' ').trim();
    if (cleaned.isEmpty ||
        cleaned.toLowerCase() == 'gamebase' ||
        cleaned.toLowerCase() == 'search' ||
        cleaned.toLowerCase() == 'library') {
      return 'Library';
    }
    // Apply proper title case
    return _toTitleCase(cleaned);
  }

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;

    // Words that should stay lowercase in titles (unless first word)
    const lowercaseWords = {
      'a', 'an', 'the', 'and', 'but', 'or', 'for', 'nor', 'on', 'at',
      'to', 'from', 'by', 'of', 'in', 'vs', 'vs.'
    };

    // Words/abbreviations that should stay uppercase
    const uppercaseWords = {
      'gm', 'im', 'fm', 'cm', 'wgm', 'wim', 'wfm', 'wcm',
      'usa', 'uk', 'ussr', 'fide', 'ecf', 'uscf',
      'ii', 'iii', 'iv', 'vi', 'vii', 'viii', 'ix', 'xi', 'xii'
    };

    final words = text.split(RegExp(r'\s+'));
    final result = <String>[];

    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.isEmpty) continue;

      final lowerWord = word.toLowerCase();

      // Check if it's an abbreviation that should be uppercase
      if (uppercaseWords.contains(lowerWord)) {
        result.add(word.toUpperCase());
      }
      // Check if it's a word that should stay lowercase (but not if first word)
      else if (i > 0 && lowercaseWords.contains(lowerWord)) {
        result.add(lowerWord);
      }
      // Otherwise capitalize first letter
      else {
        result.add('${word[0].toUpperCase()}${word.substring(1).toLowerCase()}');
      }
    }

    return result.join(' ');
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
    if (event.contains('rapid')) return PngAsset.rapidIcon;

    // Default to classical for standard/unknown events
    return PngAsset.classicalIcon;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class _PlayerInfo extends StatelessWidget {
  const _PlayerInfo({
    required this.name,
    required this.title,
    required this.rating,
    required this.alignment,
    required this.federation,
  });

  final String name;
  final String title;
  final String rating;
  final CrossAxisAlignment alignment;
  final String federation;

  @override
  Widget build(BuildContext context) {
    final rank = [
      if (title.isNotEmpty) title,
      if (rating.isNotEmpty) rating,
    ].join(' ');

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Row(
          mainAxisAlignment: alignment == CrossAxisAlignment.end
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (alignment != CrossAxisAlignment.end &&
                federation.trim().isNotEmpty) ...[
              FederationFlag(
                federation: federation,
                width: 14.sp,
                height: 10.sp,
                borderRadius: BorderRadius.circular(2.br),
              ),
              SizedBox(width: 6.w),
            ],
            Flexible(
              child: Text(
                name,
                style: AppTypography.textSmMedium.copyWith(
                  color: const Color(0xFF09090B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: alignment == CrossAxisAlignment.end
                    ? TextAlign.right
                    : TextAlign.left,
              ),
            ),
            if (alignment == CrossAxisAlignment.end &&
                federation.trim().isNotEmpty) ...[
              SizedBox(width: 6.w),
              FederationFlag(
                federation: federation,
                width: 14.sp,
                height: 10.sp,
                borderRadius: BorderRadius.circular(2.br),
              ),
            ],
          ],
        ),
        SizedBox(height: 2.h),
        Text(
          rank,
          style: AppTypography.textXsRegular.copyWith(
            color: const Color(0xFF71717A),
            fontSize: 12.sp,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign:
              alignment == CrossAxisAlignment.end ? TextAlign.right : TextAlign.left,
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
