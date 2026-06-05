import 'dart:async';
import 'dart:developer' as developer;
// import 'dart:io'; // UNUSED: Removed with old dialog approach
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
// DISABLED: Local move impact calculation - we get move impact from Supabase edge function
// This prevents phone from heating up by avoiding local Stockfish calculations for move impact
// import 'package:chessever2/screens/chessboard/analysis/move_impact_analyzer.dart';
// import 'package:chessever2/screens/chessboard/analysis/simple_move_impact.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:chessever2/screens/chessboard/provider/lichess_move_annotations_provider.dart';
import 'package:chessever2/screens/chessboard/notation/notation_cache.dart';
import 'package:chessever2/screens/chessboard/notation/notation_token_builder.dart';
import 'package:chessever2/screens/chessboard/notation/notation_pointer.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/gamebase_overlay_settings_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
// DISABLED: Move annotation overlay (requires move impact analysis)
// import 'package:chessever2/screens/chessboard/widgets/move_annotation_overlay.dart';
import 'package:chessever2/screens/chessboard/widgets/share_game_card_overlay.dart';
import 'package:chessever2/screens/chessboard/widgets/switch_views_tutorial_overlay.dart';
import 'package:chessever2/screens/chessboard/widgets/like_tutorial_overlay.dart';
import 'package:chessever2/screens/settings/settings_page.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/screens/chessboard/widgets/save_analysis_sheet.dart';
import 'package:chessever2/screens/chessboard/widgets/nag_display.dart';
import 'package:chessever2/screens/group_event/providers/countryman_games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/player_profile/utils/twic_event_identity.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:chessever2/services/pip_service.dart';
import 'package:chessever2/providers/pip_mode_provider.dart';
// import 'package:chessever2/utils/keyboard_animation_builder.dart'; // UNUSED: Removed with old dialog
// import 'package:chessever2/providers/keyboard_total_height_provider.dart'; // UNUSED: Removed with old dialog
import 'package:chessever2/utils/figurine_notation.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/string_utils.dart';
import 'package:chessground/chessground.dart';
import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_animate/flutter_animate.dart' hide ShimmerEffect;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/backfilled_federation_flag.dart';
import 'package:chessever2/widgets/logo_pattern_fallback.dart';
// import 'package:chessever2/widgets/smooth_dialog.dart'; // UNUSED: Removed with old dialog
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:country_flags/country_flags.dart' hide Shape, Circle;
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/url_launcher_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:motor/motor.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/heart_burst.dart';
import 'package:chessever2/screens/chessboard/widgets/like_flight.dart';
import 'package:chessever2/screens/gamebase/widgets/board_opening_explorer_panel.dart';
import 'package:chessever2/screens/gamebase/widgets/position_games_sheet.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_game.dart'
    show TimeControl, TimeControlExtension;
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:chessever2/widgets/game_filter/wheel_range_filter.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:chessever2/services/live_updates_service.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/notifications_settings_provider.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';

const Color kGameEndingRedColor = Color(0xCCF53236);

/// Counter bumped by [_ChessBoardScreenNewState] once the outer "Swipe to
/// Browse" walkthrough (step 1/2) is dismissed. The visible analysis panel
/// (`_AnalysisSwipePanels`) listens to this and runs the chained
/// notation↔explorer "Switch Views" tutorial (step 2/2) so the two
/// teachings feel like a single orchestrated flow.
final analysisSwitchViewsTutorialRequestProvider = StateProvider<int>((_) => 0);

/// Counter bumped once the "Switch Views" walkthrough (step 2/3) is dismissed
/// — or skipped — so the outer [_ChessBoardScreenNewState] runs the chained
/// "Double-Tap to Like" teaching (step 3/3) right after, in order and without
/// overlapping the previous card.
final likeTutorialRequestProvider = StateProvider<int>((_) => 0);

final boardSelectionClearRequestProvider = StateProvider.family<int, String>(
  (_, _) => 0,
);

String _boardSelectionClearKey(GamesTourModel game, int index) =>
    '${game.gameId}#$index';

/// Spring-based curve that mimics iOS snappy motion
/// Quick, precise animation with subtle natural settling
class SnappySpringCurve extends Curve {
  const SnappySpringCurve();

  @override
  double transform(double t) {
    // Approximates CupertinoMotion.snappy() using damped spring physics
    // This creates a quick, responsive motion with minimal overshoot
    final damping = 0.85; // High damping for snappy feel
    final frequency = 3.5; // High frequency for quick response

    final omega = frequency * 2 * math.pi;
    final dampingRatio = damping;
    final dampedFreq = omega * math.sqrt(1 - dampingRatio * dampingRatio);

    final envelope = math.exp(-dampingRatio * omega * t);
    final oscillation = math.cos(dampedFreq * t);

    return 1 - envelope * oscillation;
  }
}

/// Spring-based curve that mimics iOS bouncy motion
/// Playful animation with natural bounce and overshoot
class BouncySpringCurve extends Curve {
  const BouncySpringCurve();

  @override
  double transform(double t) {
    // Approximates CupertinoMotion.bouncy() with pronounced spring effect
    // Lower damping creates visible bounce and overshoot
    final damping = 0.55; // Lower damping for bouncy feel
    final frequency = 2.8; // Medium frequency for natural bounce

    final omega = frequency * 2 * math.pi;
    final dampingRatio = damping;
    final dampedFreq = omega * math.sqrt(1 - dampingRatio * dampingRatio);

    final envelope = math.exp(-dampingRatio * omega * t);
    final oscillation = math.cos(dampedFreq * t);

    return 1 - envelope * oscillation;
  }
}

// DISABLED: Local move impact calculation - we get move impact from Supabase edge function
// This prevents phone from heating up by avoiding local Stockfish calculations for move impact
// /// Cached move impact results keyed by game id/signature to avoid recomputation
// class CachedMoveImpact {
//   final String signature;
//   final Map<int, MoveImpactAnalysis> impacts;
//
//   const CachedMoveImpact({required this.signature, required this.impacts});
// }
//
// class MoveImpactCacheNotifier
//     extends StateNotifier<Map<String, CachedMoveImpact>> {
//   MoveImpactCacheNotifier() : super(<String, CachedMoveImpact>{});
//   static const int _maxEntries = 12;
//
//   CachedMoveImpact? lookup(String gameId) => state[gameId];
//
//   void store(String gameId, CachedMoveImpact cached) {
//     final next = Map<String, CachedMoveImpact>.from(state);
//     next.remove(gameId);
//     next[gameId] = cached;
//     while (next.length > _maxEntries) {
//       next.remove(next.keys.first);
//     }
//     state = next;
//   }
//
//   void invalidate(String gameId) {
//     if (!state.containsKey(gameId)) return;
//     final copy = {...state};
//     copy.remove(gameId);
//     state = copy;
//   }
// }
//
// final moveImpactCacheProvider = StateNotifierProvider<
//   MoveImpactCacheNotifier,
//   Map<String, CachedMoveImpact>
// >((ref) => MoveImpactCacheNotifier());

extension LichessMoveAnnotationTypeX on LichessMoveAnnotationType {
  String get symbol {
    switch (this) {
      case LichessMoveAnnotationType.brilliant:
        return '!!';
      case LichessMoveAnnotationType.missedWin:
        return '??';
      case LichessMoveAnnotationType.goodMove:
        return '!';
      case LichessMoveAnnotationType.bestMove:
        return '!';
      case LichessMoveAnnotationType.bookMove:
        return '';
      case LichessMoveAnnotationType.inaccuracy:
        return '?!';
      case LichessMoveAnnotationType.mistake:
        return '?';
      case LichessMoveAnnotationType.blunder:
        return '??';
    }
  }

  String get iconAssetPath {
    switch (this) {
      case LichessMoveAnnotationType.brilliant:
        return 'assets/svgs/brilliant.svg';
      case LichessMoveAnnotationType.missedWin:
        return 'assets/svgs/missed_win.svg';
      case LichessMoveAnnotationType.mistake:
        return 'assets/svgs/mistake.svg';
      case LichessMoveAnnotationType.blunder:
        return 'assets/svgs/blunder.svg';
      case LichessMoveAnnotationType.inaccuracy:
        return 'assets/svgs/inaccuracy.svg';
      case LichessMoveAnnotationType.goodMove:
        return 'assets/svgs/good_move.svg';
      case LichessMoveAnnotationType.bestMove:
        return 'assets/svgs/best_move.svg';
      case LichessMoveAnnotationType.bookMove:
        return 'assets/svgs/book_move.svg';
    }
  }

  Color get color {
    switch (this) {
      case LichessMoveAnnotationType.brilliant:
        return const Color(0xFF177A68);
      case LichessMoveAnnotationType.missedWin:
        return const Color(0xFFF70400);
      case LichessMoveAnnotationType.goodMove:
        return const Color(0xFF177A68);
      case LichessMoveAnnotationType.bestMove:
        return const Color(0xFF28833A);
      case LichessMoveAnnotationType.bookMove:
        return const Color(0xFF4E5B4F);
      case LichessMoveAnnotationType.inaccuracy:
        return const Color(0xFFFABE46);
      case LichessMoveAnnotationType.mistake:
        return const Color(0xFFEB9518);
      case LichessMoveAnnotationType.blunder:
        return const Color(0xFFC9342E);
    }
  }
}

/// Merge NAGs baked into the PGN with NAGs the user has applied locally.
/// PGN NAGs come first (preserving authoring order), user NAGs append after —
/// the SAN/badge resolvers dedupe and re-sort by category at render time.
List<int> _mergeUserNags(
  List<int>? pgnNags,
  String? pointerId,
  Map<String, List<int>> userMoveNags,
) {
  final pgn = pgnNags ?? const <int>[];
  final user =
      pointerId == null
          ? const <int>[]
          : (userMoveNags[pointerId] ?? const <int>[]);
  if (user.isEmpty) return pgn;
  if (pgn.isEmpty) return user;
  return <int>[...pgn, ...user];
}

List<int> _mergeUserNagsForMovePointer(
  ChessMove? move,
  List<Number>? movePointer,
  Map<String, List<int>> userMoveNags,
) {
  final pointerId =
      (movePointer == null || movePointer.isEmpty)
          ? null
          : NotationPointer.encode(movePointer);
  return _mergeUserNags(move?.nags, pointerId, userMoveNags);
}

ChessMove? _moveForPointer(ChessGame? game, ChessMovePointer? pointer) {
  if (game == null || pointer == null || pointer.isEmpty) return null;

  ChessLine? line = game.mainline;
  ChessMove? move;

  for (var depth = 0; depth < pointer.length; depth++) {
    final index = pointer[depth].toInt();
    if (index < 0) return null;

    if (depth.isEven) {
      if (line == null || index >= line.length) return null;
      move = line[index];
    } else {
      final variations = move?.variations;
      if (variations == null || index >= variations.length) return null;
      line = variations[index];
    }
  }

  return move;
}

String _moveSansSignature(List<String> moveSans) {
  // Normalize: strip check indicators (+, #) for consistent signature matching
  // Different PGN parsers may or may not include these symbols
  final normalized =
      moveSans.map((san) => san.replaceAll(RegExp(r'[+#]'), '')).toList();
  return '${normalized.length}:${normalized.join('|')}';
}

// Figurine notation helpers: see `buildFigurineSpans` in figurine_notation.dart

String? _extractLichessSiteUrl(ChessGame game) {
  final candidates = <String?>[
    game.metadata['Site']?.toString(),
    game.metadata['LichessURL']?.toString(),
    game.metadata['SiteUrl']?.toString(),
    game.metadata['Source']?.toString(),
  ];

  for (final candidate in candidates) {
    if (candidate == null || candidate.isEmpty) continue;
    final trimmed = candidate.trim();
    if (trimmed.contains('lichess.org')) {
      return trimmed;
    }
  }
  return null;
}

String? _extractLichessGameId(ChessGame game) {
  final candidates = <String?>[
    game.metadata['Site']?.toString(),
    game.metadata['LichessId']?.toString(),
    game.metadata['LichessGameId']?.toString(),
    game.metadata['LichessURL']?.toString(),
    game.metadata['SiteUrl']?.toString(),
    game.metadata['Source']?.toString(),
  ];

  // Lichess game IDs are exactly 8 characters. (See /game/export/{gameId})
  final idRegex = RegExp(r'^[a-zA-Z0-9]{8}$');
  // Match direct game URLs like https://lichess.org/abcdefgh or /abcdefgh/white
  final urlRegex = RegExp(r'lichess\.org/([a-zA-Z0-9]{8})(?:[/?#]|$)');
  // Match broadcast URLs: lichess.org/broadcast/{slug}/{roundSlug}/{roundId}/{gameId}
  final broadcastRegex = RegExp(
    r'lichess\.org/broadcast/[^/]+/[^/]+/[a-zA-Z0-9]{8}/([a-zA-Z0-9]{8})',
  );

  for (final candidate in candidates) {
    if (candidate == null || candidate.isEmpty) continue;
    final trimmed = candidate.trim();

    // Check broadcast URL first (more specific pattern)
    final broadcastMatch = broadcastRegex.firstMatch(trimmed);
    if (broadcastMatch != null) {
      return broadcastMatch.group(1);
    }

    if (idRegex.hasMatch(trimmed)) {
      return trimmed;
    }
    final match = urlRegex.firstMatch(trimmed);
    if (match != null) {
      return match.group(1);
    }
  }

  final fallbackId = game.gameId.trim();
  if (idRegex.hasMatch(fallbackId)) {
    return fallbackId;
  }

  return null;
}

// DISABLED: Local move impact calculation - we get move impact from Supabase edge function
// This prevents phone from heating up by avoiding local Stockfish calculations for move impact
// /// LAZY move impact provider - calculates impact for a SINGLE move only when needed
// /// This is the NEW approach that doesn't block the eval bar
// /// Returns the impact analysis for a specific move index in a game
// class LazyMoveImpactParams {
//   final ChessBoardProviderParams boardParams;
//   final int moveIndex; // Which move to calculate impact for
//
//   const LazyMoveImpactParams({
//     required this.boardParams,
//     required this.moveIndex,
//   });
//
//   @override
//   bool operator ==(Object other) =>
//       identical(this, other) ||
//       other is LazyMoveImpactParams &&
//           boardParams == other.boardParams &&
//           moveIndex == other.moveIndex;
//
//   @override
//   int get hashCode => boardParams.hashCode ^ moveIndex.hashCode;
// }

// DISABLED: Local move impact calculation - we get move impact from Supabase edge function
// This prevents phone from heating up by avoiding local Stockfish calculations for move impact
// final lazyMoveImpactProvider = FutureProvider.family
//     .autoDispose<MoveImpactAnalysis?, LazyMoveImpactParams>((
//       ref,
//       params,
//     ) async {
//       // Get the board state to access position FENs
//       final boardStateAsync = ref.watch(
//         chessBoardScreenProviderNew(params.boardParams),
//       );
//       final boardState = boardStateAsync.valueOrNull;
//       if (boardState == null) {
//         return null;
//       }
//
//       final allMoves = boardState.allMoves;
//       final moveSans = boardState.moveSans;
//       final startingPosition = boardState.startingPosition;
//
//       if (allMoves.isEmpty ||
//           moveSans.isEmpty ||
//           params.moveIndex >= moveSans.length) {
//         return null;
//       }
//
//       // Generate position FENs for this specific move only
//       final fensParams = PositionFensParams(
//         allMoves: allMoves,
//         startingPosition: startingPosition,
//         gameId: params.boardParams.game.gameId,
//       );
//       final positionFens = ref.watch(positionFensProvider(fensParams));
//
//       if (params.moveIndex >= positionFens.length - 1) {
//         return null; // Invalid move index
//       }
//
//       // Create single move params
//       final singleParams = SingleMoveImpactParams(
//         fenBefore: positionFens[params.moveIndex],
//         fenAfter: positionFens[params.moveIndex + 1],
//         moveSan: moveSans[params.moveIndex],
//         moveIndex: params.moveIndex,
//         gameId: params.boardParams.game.gameId,
//       );
//
//       // Use the new lazy provider that doesn't block eval bar
//       return ref.watch(singleMoveImpactProvider(singleParams).future);
//     });
//
// /// DEPRECATED: Provider that calculates move impacts - BULK ANALYSIS
// /// This approach blocks the eval bar and should not be used
// /// Use lazyMoveImpactProvider instead for individual moves
// final gameMovesImpactProvider = FutureProvider.family.autoDispose<
//   Map<int, MoveImpactAnalysis>?,
//   ChessBoardProviderParams
// >((ref, params) async {
//   debugPrint(
//     '🎨 gameMovesImpactProvider: START for game ${params.game.gameId}',
//   );
//
//   final link = ref.keepAlive();
//   Timer? cleanupTimer;
//
//   ref.onCancel(() {
//     cleanupTimer = Timer(const Duration(seconds: 45), () {
//       debugPrint(
//         '🎨 gameMovesImpactProvider: releasing keepAlive for ${params.game.gameId}',
//       );
//       link.close();
//     });
//   });
//
//   ref.onResume(() {
//     cleanupTimer?.cancel();
//     cleanupTimer = null;
//   });
//
//   ref.onDispose(() {
//     cleanupTimer?.cancel();
//   });
//
//   // Use .select() to watch ONLY the moves data, not the entire state
//   final allMoves = ref.watch(
//     chessBoardScreenProviderNew(
//       params,
//     ).select((state) => state.valueOrNull?.allMoves),
//   );
//   final moveSans = ref.watch(
//     chessBoardScreenProviderNew(
//       params,
//     ).select((state) => state.valueOrNull?.moveSans),
//   );
//   final startingPosition = ref.watch(
//     chessBoardScreenProviderNew(
//       params,
//     ).select((state) => state.valueOrNull?.startingPosition),
//   );
//
//   if (allMoves == null || allMoves.isEmpty || moveSans == null) {
//     debugPrint('🎨 gameMovesImpactProvider: NULL - no moves yet');
//     return null;
//   }
//
//   debugPrint(
//     '🎨 gameMovesImpactProvider: Got ${allMoves.length} moves, ${moveSans.length} SANs',
//   );
//
//   final cacheSignature = '${moveSans.length}:${moveSans.join('|')}';
//   final cachedImpact = ref.read(moveImpactCacheProvider)[params.game.gameId];
//   if (cachedImpact != null && cachedImpact.signature == cacheSignature) {
//     debugPrint(
//       '🎨 gameMovesImpactProvider: Using cached impacts for ${params.game.gameId}',
//     );
//     return cachedImpact.impacts;
//   }
//
//   // Generate position FENs (starting position + after each move)
//   final fensParams = PositionFensParams(
//     allMoves: allMoves,
//     startingPosition: startingPosition,
//     gameId: params.game.gameId,
//   );
//   final positionFens = ref.watch(positionFensProvider(fensParams));
//   debugPrint(
//     '🎨 gameMovesImpactProvider: Generated ${positionFens.length} position FENs',
//   );
//
//   // Determine which moves are white's
//   final isWhiteMoves = List.generate(
//     allMoves.length,
//     (i) => i % 2 == 0, // Even indices = white's moves
//   );
//
//   // Use COMPREHENSIVE impact provider that analyzes alternatives
//   final simpleParams = SimpleMoveImpactParams(
//     positionFens: positionFens,
//     isWhiteMoves: isWhiteMoves,
//     moveSans: moveSans,
//     gameId: params.game.gameId,
//   );
//
//   debugPrint('🎨 gameMovesImpactProvider: Calling simpleMoveImpactProvider...');
//   final impacts = await ref.watch(
//     simpleMoveImpactProvider(simpleParams).future,
//   );
//   debugPrint(
//     '🎨 gameMovesImpactProvider: COMPLETE - got ${impacts.length} impacts',
//   );
//
//   ref
//       .read(moveImpactCacheProvider.notifier)
//       .store(
//         params.game.gameId,
//         CachedMoveImpact(
//           signature: cacheSignature,
//           impacts: Map.unmodifiable(impacts),
//         ),
//       );
//   return impacts;
// });

// Helper function to get move highlight color
Color getLastMoveHighlightColor(ChessBoardStateNew state) {
  return kLastMoveHighlightColor;
}

// Helper function to get move highlight color for analysis mode
Color getAnalysisLastMoveHighlightColor(ChessBoardStateNew state) {
  return kLastMoveHighlightColor;
}

bool _isLightBoardSquare(Square square) {
  // a1 is dark; odd parity is light.
  return (square.file + square.rank) % 2 == 1;
}

IMap<Square, SquareHighlight> _buildLastMoveSquareHighlights(Move? lastMove) {
  if (lastMove == null) return const IMap.empty();

  final highlights = <Square, SquareHighlight>{};
  for (final square in lastMove.squares) {
    final color =
        _isLightBoardSquare(square)
            ? kLastMoveHighlightLightSquare
            : kLastMoveHighlightDarkSquare;
    highlights[square] = SquareHighlight(
      details: HighlightDetails(solidColor: color),
    );
  }

  return highlights.lock;
}

bool _gameHasCustomVariations(ChessGame? game) {
  if (game == null) return false;
  bool found = false;

  void visit(List<ChessMove> moves) {
    for (final move in moves) {
      final variations = move.variations ?? const <ChessLine>[];
      if (variations.isNotEmpty) {
        found = true;
        return;
      }
      for (final variation in variations) {
        if (found) return;
        visit(variation);
      }
    }
  }

  visit(game.mainline);
  return found;
}

Future<bool?> _showAnalysisConfirmationDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  Color? confirmColor,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.br),
        ),
        title: Text(
          title,
          style: AppTypography.textMdBold.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
        content: Text(
          message,
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.7),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: Text(
              confirmLabel,
              style: AppTypography.textSmMedium.copyWith(
                color: confirmColor ?? kPrimaryColor,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class ChessBoardScreenNew extends ConsumerStatefulWidget {
  final int currentIndex;
  final List<GamesTourModel> games;

  /// Optional saved analysis data to restore full state (variations, comments, position)
  final SavedAnalysisData? savedAnalysisData;
  final List<SavedAnalysisData>? savedAnalysesDataByIndex;

  /// When true, hides the event info button in the app bar.
  /// Use this when navigating from library for position analysis where event info is not relevant.
  final bool hideEventInfo;
  final PlayerProfileDataSource playerProfileDataSource;
  final bool showGamebaseButton;

  /// When true, the gamebase overlay will be disabled by default on screen init.
  /// Use this for library routes where games are typically past move 10.
  final bool disableGamebaseOverlayByDefault;
  final bool showClock;

  /// When true, the board starts at the last move instead of the starting position.
  /// Used by the opening explorer's "Analyze" action.
  final bool startAtLastMove;

  /// Optional initial position to show (FEN).
  final String? initialFen;

  const ChessBoardScreenNew({
    required this.currentIndex,
    required this.games,
    this.savedAnalysisData,
    this.savedAnalysesDataByIndex,
    this.hideEventInfo = false,
    this.playerProfileDataSource = PlayerProfileDataSource.supabase,
    this.showGamebaseButton = false,
    this.disableGamebaseOverlayByDefault = false,
    this.showClock = true,
    this.startAtLastMove = false,
    this.initialFen,
    super.key,
  });

  @override
  ConsumerState<ChessBoardScreenNew> createState() => _ChessBoardScreenState();
}

/// Global flag to track when any dropdown/popup is open on the chess board screen.
/// Used to defer rebuilds that would close popups unexpectedly on tablets.
class _ChessBoardPopupState {
  static bool isAnyPopupOpen = false;

  /// Call when opening a popup (dropdown, menu, etc.)
  static void markOpen() {
    isAnyPopupOpen = true;
  }

  /// Call when closing a popup
  static void markClosed() {
    isAnyPopupOpen = false;
  }
}

class _ChessBoardScreenState extends ConsumerState<ChessBoardScreenNew>
    with WidgetsBindingObserver, TickerProviderStateMixin, RouteAware {
  late PageController _pageController;
  // REMOVED: bool analysisMode - was causing useless full rebuilds
  int? _lastViewedIndex;
  int _currentPageIndex = 0;
  final Set<String> _syncedLatestPositions = <String>{};
  bool _isRevertingPage = false;
  ProviderSubscription<AsyncValue<ChessBoardStateNew>>? _boardKeepAliveSub;
  ChessBoardProviderParams? _keepAliveParams;
  Timer? _pageSettleTimer;
  int _pageSettleGeneration = 0;
  ProviderSubscription<AsyncValue<ChessBoardStateNew>>? _audioSub;
  ChessBoardProviderParams? _audioParams;
  ProviderSubscription<AsyncValue<ChessBoardStateNew>>? _pipSub;
  ChessBoardProviderParams? _pipParams;
  bool _didInitialBoardBootstrap = false;

  bool _hasCheckedWalkthrough = false;
  bool _showTutorialOverlay = false;
  late AnimationController _swipeController;
  late Animation<double> _swipeFadeAnimation;
  late Animation<double> _swipeScaleAnimation;
  late Animation<double> _swipeMoveAnimation;
  final GlobalKey<_SwipeTutorialOverlayState> _tutorialOverlayKey = GlobalKey();

  // Step 3/3 ("Double-Tap to Like") — chained after the Switch Views step via
  // [likeTutorialRequestProvider]. Hosted here (not in a nested panel) so the
  // whole teaching flow is orchestrated from one place and shown back-to-back.
  OverlayEntry? _likeTutorialEntry;
  int _lastLikeTutorialRequest = 0;
  bool _showLikeTutorial = false;

  static const String _kWalkthroughShownDateKey =
      'swipable_walkthrough_shown_date';
  static const String _kWalkthroughDontShowKey =
      'swipable_walkthrough_dont_show';

  @override
  void initState() {
    super.initState();
    // Defensive: Ensure currentIndex is within bounds of games list
    final safeIndex = widget.currentIndex.clamp(0, widget.games.length - 1);
    _pageController = PageController(initialPage: safeIndex);
    _currentPageIndex = safeIndex;
    _keepBoardProviderAlive(_currentPageIndex);

    // Note: We'll enable streaming in didChangeDependencies when ref is available
    WidgetsBinding.instance.addObserver(this);
    PipService.instance.addListener(_handlePipModeChanged);
    _setupSwipeAnimation();
    _lastLikeTutorialRequest = ref.read(likeTutorialRequestProvider);

    // Store all games for score card context (used by player name tap → score card)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(chessBoardAllGamesProvider.notifier).state = widget.games;
      }
    });
  }

  void _setupSwipeAnimation() {
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    // Fade In/Out: 0-10% In, 90-100% Out
    _swipeFadeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 80),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 10),
    ]).animate(_swipeController);

    // Scale (Press effect): 10-20% Scale Down, 80-90% Scale Up
    _swipeScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 10),
      TweenSequenceItem(tween: ConstantTween(0.8), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 10),
    ]).animate(_swipeController);

    // Move: Pause at start, Move Out, Pause, Move Back, Pause
    _swipeMoveAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 15),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 10),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 5),
    ]).animate(_swipeController);

    _swipeController.addListener(() {
      if (!_pageController.hasClients) return;

      final width = _pageController.position.viewportDimension;
      final totalItems = widget.games.length;

      // Logic must match _SwipeTutorialOverlay to stay in sync
      bool canGoNext = _currentPageIndex < totalItems - 1;
      double direction = canGoNext ? 1.0 : -1.0;

      // Sync with overlay's maxDrag (width * 0.5)
      double maxDrag = width * 0.5;

      // Positive delta = Scroll Right = Content moves Left (matching hand moving Left)
      double delta = _swipeMoveAnimation.value * maxDrag * direction;
      double baseOffset = _currentPageIndex * width;

      // Use jumpTo to follow animation frame-by-frame without physics interference
      _pageController.position.jumpTo(baseOffset + delta);
    });
  }

  Future<void> _checkAndShowWalkthrough(BuildContext context) async {
    final prefs = ref.read(sharedPreferencesRepository);
    final dontShow = await prefs.getBool(_kWalkthroughDontShowKey) ?? false;
    final lastShownMs = await prefs.getInt(_kWalkthroughShownDateKey);

    // Show each instruction once. Display step 1 only if it has never been seen
    // and isn't opted out. Otherwise hand off to step 2 so any later unseen
    // steps still appear — in order, one at a time (each self-gates on its key).
    if (dontShow || lastShownMs != null) {
      _requestSwitchViewsTutorial();
      return;
    }

    final now = DateTime.now();

    if (context.mounted) {
      // Trigger local overlay instead of ShowcaseView
      setState(() {
        _showTutorialOverlay = true;
      });

      // Play animation 1 time
      int count = 0;
      void statusListener(AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          count++;
          if (count < 1) {
            _swipeController.forward(from: 0.0);
          } else {
            _swipeController.removeStatusListener(statusListener);
            // Stop animation but keep overlay until user dismisses
            // Reset page position so it stops wiggling
            if (_pageController.hasClients) {
              _pageController.jumpToPage(_currentPageIndex);
            }
          }
        }
      }

      _swipeController.addStatusListener(statusListener);
      _swipeController.forward();

      await prefs.setInt(_kWalkthroughShownDateKey, now.millisecondsSinceEpoch);
    }
  }

  void _onWalkthroughFinished() {
    setState(() {
      _showTutorialOverlay = false;
    });
    _swipeController.stop();
    _swipeController.reset();
    if (_pageController.hasClients) {
      _pageController.jumpToPage(_currentPageIndex);
    }
  }

  /// Signals the visible `_AnalysisSwipePanels` to run its notation↔explorer
  /// "Switch Views" walkthrough as step 2/2. Bumping the counter triggers
  /// the listener in the nested state; the panel re-checks its own prefs
  /// guard before showing, so this is safe to call unconditionally after
  /// step 1 dismisses.
  void _requestSwitchViewsTutorial() {
    if (!mounted) return;
    ref
        .read(analysisSwitchViewsTutorialRequestProvider.notifier)
        .update((v) => v + 1);
  }

  Future<void> _suppressWalkthrough() async {
    final prefs = ref.read(sharedPreferencesRepository);
    // "Don't show again" on step 1 must also suppress steps 2 and 3 so the
    // user isn't immediately shown more tutorials they just opted out of.
    await Future.wait([
      prefs.setBool(_kWalkthroughDontShowKey, true),
      prefs.setBool(kSwitchViewsWalkthroughDontShowKey, true),
      prefs.setBool(kLikeWalkthroughDontShowKey, true),
    ]);
  }

  /// Step 3/3: shows the "Double-Tap to Like" teaching once the chained
  /// request fires (after Switch Views dismisses or is skipped). Self-gates on
  /// its own prefs so it isn't shown more than once per 7 days.
  Future<void> _maybeStartLikeTutorial() async {
    if (!mounted || _showLikeTutorial || _showTutorialOverlay) return;

    final prefs = ref.read(sharedPreferencesRepository);
    final dontShow = await prefs.getBool(kLikeWalkthroughDontShowKey) ?? false;
    if (dontShow || !mounted) return;

    // Show once: if it's ever been seen, don't show it again.
    final lastShownMs = await prefs.getInt(kLikeWalkthroughShownDateKey);
    if (lastShownMs != null) return;
    if (!mounted) return;

    _showLikeTutorial = true;
    _insertLikeTutorialOverlay();

    await prefs.setInt(
      kLikeWalkthroughShownDateKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _insertLikeTutorialOverlay() {
    _likeTutorialEntry = OverlayEntry(
      builder: (_) => LikeTutorialOverlay(
        currentStep: 3,
        totalSteps: 3,
        onDismiss: _onLikeTutorialFinished,
        onDontShowAgain: () async {
          final prefs = ref.read(sharedPreferencesRepository);
          await prefs.setBool(kLikeWalkthroughDontShowKey, true);
          _onLikeTutorialFinished();
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_likeTutorialEntry!);
  }

  void _removeLikeTutorialOverlay() {
    _likeTutorialEntry?.remove();
    _likeTutorialEntry = null;
  }

  void _onLikeTutorialFinished() {
    _removeLikeTutorialOverlay();
    _showLikeTutorial = false;
  }

  GamesTourModel _preferFresherGameSnapshot({
    required GamesTourModel navigationGame,
    required GamesTourModel providerGame,
  }) {
    final navigationLastMoveTime = navigationGame.lastMoveTime;
    final providerLastMoveTime = providerGame.lastMoveTime;

    if (navigationLastMoveTime != null && providerLastMoveTime != null) {
      if (navigationLastMoveTime.isAfter(providerLastMoveTime)) {
        return navigationGame;
      }
      if (providerLastMoveTime.isAfter(navigationLastMoveTime)) {
        return providerGame;
      }
    } else if (navigationLastMoveTime != null && providerLastMoveTime == null) {
      return navigationGame;
    } else if (providerLastMoveTime != null && navigationLastMoveTime == null) {
      return providerGame;
    }

    final navigationPgnLength = navigationGame.pgn?.length ?? 0;
    final providerPgnLength = providerGame.pgn?.length ?? 0;
    if (navigationPgnLength > providerPgnLength) {
      return navigationGame;
    }
    if (providerPgnLength > navigationPgnLength) {
      return providerGame;
    }

    final navigationFen = (navigationGame.fen ?? '').trim();
    final providerFen = (providerGame.fen ?? '').trim();
    if (navigationFen.isNotEmpty && providerFen.isEmpty) {
      return navigationGame;
    }
    if (providerFen.isNotEmpty && navigationFen.isEmpty) {
      return providerGame;
    }

    final navigationLastMove = (navigationGame.lastMove ?? '').trim();
    final providerLastMove = (providerGame.lastMove ?? '').trim();
    if (navigationLastMove.isNotEmpty && providerLastMove.isEmpty) {
      return navigationGame;
    }
    if (providerLastMove.isNotEmpty && navigationLastMove.isEmpty) {
      return providerGame;
    }

    // Prefer the navigation payload on ties because it may already contain the
    // card-level realtime snapshot that opened this board.
    return navigationGame;
  }

  GamesTourModel _resolveGameForIndex(int index) {
    if (widget.games.isEmpty) {
      throw StateError('No games available to resolve');
    }

    final safeIndex = index.clamp(0, widget.games.length - 1);
    final fallbackGame = widget.games[safeIndex];
    final view = ref.read(chessboardViewFromProviderNew);

    final AsyncValue<GamesScreenModel>? gamesAsync;
    switch (view) {
      case ChessboardView.tour:
        gamesAsync = ref.read(gamesTourScreenProvider);
        break;
      case ChessboardView.countryman:
        gamesAsync = ref.read(countrymanGamesTourScreenProvider);
        break;
      default:
        // For 'forYou', 'favScorecard', 'playerProfile':
        // We use widget.games (fallbackGame) as the primary source or handle logic elsewhere.
        // Reading countrymanGamesTourScreenProvider here was a bug for non-countryman views.
        gamesAsync = null;
    }

    if (gamesAsync == null) {
      return fallbackGame;
    }

    final liveGames = gamesAsync.valueOrNull?.gamesTourModels;
    if (liveGames == null || liveGames.isEmpty) {
      return fallbackGame;
    }

    for (final game in liveGames) {
      if (game.gameId == fallbackGame.gameId) {
        return _preferFresherGameSnapshot(
          navigationGame: fallbackGame,
          providerGame: game,
        );
      }
    }

    return fallbackGame;
  }

  /// Returns saved analysis data only for the initial page (currentIndex)
  /// This ensures variations/comments and update linkage are restored correctly.
  SavedAnalysisData? _getSavedAnalysisDataForIndex(int index) {
    final allSavedAnalyses = widget.savedAnalysesDataByIndex;
    if (allSavedAnalyses != null &&
        index >= 0 &&
        index < allSavedAnalyses.length) {
      return allSavedAnalyses[index];
    }

    // Only apply saved analysis data to the initial page
    if (index == widget.currentIndex) {
      return widget.savedAnalysisData;
    }
    return null;
  }

  /// Creates ChessBoardProviderParams with optional saved analysis data
  ChessBoardProviderParams _createParams(GamesTourModel game, int index) {
    return ChessBoardProviderParams(
      game: game,
      index: index,
      savedAnalysisData: _getSavedAnalysisDataForIndex(index),
      startAtLastMove: widget.startAtLastMove,
      initialFen: widget.initialFen,
    );
  }

  void _ensureLatestMoveSelected({
    required WidgetRef ref,
    required int pageIndex,
    required ChessBoardStateNew state,
  }) {
    if (pageIndex != _currentPageIndex) return;
    if (state.isLoadingMoves) return;

    // When opened from the opening explorer's games sheet, every page's
    // provider already navigates to the move matching widget.initialFen.
    // Skipping the default-position override preserves that target position
    // when the user swipes between games.
    if (widget.initialFen != null) {
      _syncedLatestPositions.add(state.game.gameId);
      return;
    }

    final gameId = state.game.gameId;
    if (_syncedLatestPositions.contains(gameId)) {
      return;
    }

    final totalMoves = state.analysisState.allMoves.length;
    if (totalMoves == 0) {
      // Game has no moves yet (e.g. board editor with custom FEN).
      // Mark as synced so we don't interfere when the user later adds moves.
      _syncedLatestPositions.add(gameId);
      return;
    }

    // If saved analysis data exists for this page, skip correction entirely —
    // let the provider's _initializeAnalysisBoard handle position restore.
    final hasSavedAnalysis = _getSavedAnalysisDataForIndex(pageIndex) != null;
    if (hasSavedAnalysis) {
      _syncedLatestPositions.add(gameId);
      return;
    }

    // Determine target position:
    // - Live games: latest move
    // - startAtLastMove: latest move (regardless of game status)
    // - Finished games: starting position (-1)
    final isFinished = state.game.gameStatus.isFinished;
    final int targetMoveIndex;
    if (isFinished && !widget.startAtLastMove) {
      targetMoveIndex = -1;
    } else {
      targetMoveIndex = totalMoves - 1;
    }
    final currentIndex = state.analysisState.currentMoveIndex;

    // Check if we're already at the target position
    if (targetMoveIndex == -1) {
      if (currentIndex == -1) {
        _syncedLatestPositions.add(gameId);
        return;
      }
    } else {
      if (currentIndex >= totalMoves - 1) {
        _syncedLatestPositions.add(gameId);
        return;
      }
    }

    final params = ChessBoardProviderParams(game: state.game, index: pageIndex);
    final targetGameId = gameId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_currentPageIndex != pageIndex) {
        _syncedLatestPositions.remove(targetGameId);
        return;
      }
      final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
      notifier.goToMove(targetMoveIndex);
    });

    _syncedLatestPositions.add(gameId);
  }

  /// Keep the active board provider alive even before build starts watching it.
  /// This prevents the autoDispose notifier from being disposed while we kick off
  /// early work (parseMoves / initial eval) from initState/didChangeDependencies.
  void _keepBoardProviderAlive(int pageIndex) {
    if (widget.games.isEmpty) return;

    final params = _createParams(_resolveGameForIndex(pageIndex), pageIndex);

    if (_keepAliveParams == params) return;

    _boardKeepAliveSub?.close();
    _keepAliveParams = params;
    _boardKeepAliveSub = ref.listenManual<AsyncValue<ChessBoardStateNew>>(
      chessBoardScreenProviderNew(params),
      (_, __) {},
      fireImmediately: false,
      onError: (err, st) {
        debugPrint('Error keeping chess board provider alive: $err');
      },
    );
  }

  @override
  void didUpdateWidget(covariant ChessBoardScreenNew oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
    if (_didInitialBoardBootstrap) return;
    _didInitialBoardBootstrap = true;

    // Set the initial visible page index - delayed to avoid modifying provider during build
    Future.microtask(() {
      if (mounted) {
        ref.read(currentlyVisiblePageIndexProvider.notifier).state =
            _currentPageIndex;

        // Disable gamebase overlay by default for library routes (games past move 10)
        if (widget.disableGamebaseOverlayByDefault) {
          ref.read(gamebaseOverlayEnabledProvider.notifier).setEnabled(false);
        }
        // Analysis mode is already enabled by default in the provider initialization
        // No need to toggle it here
        try {
          final initialGame = _resolveGameForIndex(_currentPageIndex);
          final params = _createParams(initialGame, _currentPageIndex);
          final notifier = ref.read(
            chessBoardScreenProviderNew(params).notifier,
          );
          unawaited(
            notifier.parseMoves().whenComplete(
              notifier.evaluateCurrentPosition,
            ),
          );
        } catch (e) {
          debugPrint('Error preparing initial game evaluation: $e');
        }
      }
    });
  }

  void _onPageChanged(int newIndex) {
    unawaited(_handlePageChange(newIndex));
  }

  void _ensureAudioListener(ChessBoardProviderParams params) {
    if (_audioParams == params) return;
    _audioParams = params;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _audioParams != params) return;
      _audioSub?.close();
      _audioSub = ref.listenManual<AsyncValue<ChessBoardStateNew>>(
        chessBoardScreenProviderNew(params),
        _handleAudioProviderChange,
        onError: (e, st) {
          debugPrint("Error in chessBoardScreenProviderNew listener: $e");
        },
      );
    });
  }

  void _handleAudioProviderChange(
    AsyncValue<ChessBoardStateNew>? prev,
    AsyncValue<ChessBoardStateNew> next,
  ) {
    final prevState = prev?.valueOrNull;
    final nextState = next.valueOrNull;
    final prevIndex =
        prevState == null
            ? -1
            : (prevState.isAnalysisMode
                ? prevState.analysisState.currentMoveIndex
                : prevState.currentMoveIndex);
    final currentIndex =
        nextState == null
            ? -1
            : (nextState.isAnalysisMode
                ? nextState.analysisState.currentMoveIndex
                : nextState.currentMoveIndex);

    if (prevIndex == currentIndex || nextState == null) {
      return;
    }

    // Only play audio if this chess board screen is currently active
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) {
      return;
    }

    final state = nextState;

    // Verify this update is for the currently viewed game
    final providerGameIndex = _currentPageIndex;
    final viewGameId = widget.games[providerGameIndex].gameId;
    if (state.game.gameId != viewGameId) {
      return;
    }

    // Make sure we're viewing the correct page in PageView
    final currentPage = _pageController.page ?? _currentPageIndex.toDouble();
    if ((currentPage - _currentPageIndex).abs() > 0.1) {
      return;
    }

    // Check if sound is enabled in user settings
    final boardSettings = ref.read(boardSettingsProviderNew).valueOrNull;
    if (boardSettings?.soundEnabled != true) {
      return;
    }

    final audioService = AudioPlayerService.instance;

    // Determine if we're going forward or backward
    final isMovingForward = currentIndex > prevIndex;

    // For backward navigation, play the sound of the move we just "undid"
    // For forward navigation, play the sound of the move we just made
    final moveIndexForSound = isMovingForward ? currentIndex : prevIndex;

    final movesSan =
        state.isAnalysisMode ? state.analysisState.moveSans : state.moveSans;

    if (moveIndexForSound >= 0 && moveIndexForSound < movesSan.length) {
      audioService.playSfxForSan(movesSan[moveIndexForSound]);
    } else if (currentIndex == -1 && prevIndex >= 0) {
      // Moving back to the starting position
      audioService.playSound(SfxType.move);
    } else if (currentIndex == movesSan.length && movesSan.isNotEmpty) {
      // End of game
      final lastMoveSan = movesSan.last;
      if (lastMoveSan.contains('#')) {
        audioService.playSound(SfxType.checkmate);
      } else if (state.game.gameStatus == GameStatus.draw) {
        audioService.playSound(SfxType.draw);
      } else {
        audioService.playSound(SfxType.move);
      }
    } else {
      audioService.playSound(SfxType.move);
    }
  }

  void _ensurePipListener(ChessBoardProviderParams params) {
    if (_pipParams == params) return;
    _pipParams = params;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pipParams != params) return;
      _pipSub?.close();
      _pipSub = ref.listenManual<AsyncValue<ChessBoardStateNew>>(
        chessBoardScreenProviderNew(params),
        _handlePipProviderChange,
        fireImmediately: true,
        onError: (e, st) {
          debugPrint("Error in PiP chess board listener: $e");
        },
      );
    });
  }

  void _handlePipProviderChange(
    AsyncValue<ChessBoardStateNew>? prev,
    AsyncValue<ChessBoardStateNew> next,
  ) {
    final state = next.valueOrNull;
    if (state == null) return;
    unawaited(_syncPipState(state));
  }

  void _handlePipModeChanged(bool isInPip) {
    if (!isInPip && mounted) {
      unawaited(_syncCurrentPipState());
    }
  }

  Future<void> _syncCurrentPipState() async {
    if (!mounted || widget.games.isEmpty) return;
    final safeIndex = _currentPageIndex.clamp(0, widget.games.length - 1);
    final game = _resolveGameForIndex(safeIndex);
    final params = _createParams(game, safeIndex);
    final state = ref.read(chessBoardScreenProviderNew(params)).valueOrNull;
    if (state == null) {
      await _syncPipGameSnapshot(game);
      return;
    }
    await _syncPipState(state);
  }

  Future<void> _syncPipState(ChessBoardStateNew state) async {
    if (!_isPipEligible(state.game)) {
      await PipService.instance.clearActiveGame();
      return;
    }
    final payload = _buildPipPayload(state.game, state: state);
    if (PipService.instance.isInPip) {
      await PipService.instance.updatePosition(payload);
    } else {
      await PipService.instance.setActiveGame(payload);
    }
  }

  Future<void> _syncPipGameSnapshot(GamesTourModel game) async {
    if (!_isPipEligible(game)) {
      await PipService.instance.clearActiveGame();
      return;
    }
    final payload = _buildPipPayload(game);
    await PipService.instance.setActiveGame(payload);
  }

  bool _isPipEligible(GamesTourModel game) {
    // PiP is free for everyone; eligibility depends only on the chosen mode.
    final mode =
        ref.read(boardSettingsProviderNew).valueOrNull?.pipMode ?? PipMode.off;
    switch (mode) {
      case PipMode.off:
        return false;
      case PipMode.live:
        return GameFilterHelper.isLiveNow(game);
      case PipMode.all:
        return GameFilterHelper.isLiveNow(game) ||
            game.effectiveGameStatus.isFinished;
    }
  }

  Map<String, dynamic> _buildPipPayload(
    GamesTourModel game, {
    ChessBoardStateNew? state,
  }) {
    final analysisState = state?.analysisState;
    final fen =
        analysisState?.position.fen ?? state?.position?.fen ?? game.fen ?? '';
    final lastMoveUci =
        analysisState?.lastMove?.uci ??
        state?.lastMove?.uci ??
        game.lastMove ??
        '';
    final boardSettings = ref.read(boardSettingsProviderNew).valueOrNull;
    final evaluation = state?.evaluation;
    // Whether the viewed position is the live mainline tail. When the user has
    // navigated back to an earlier move (or into an analysis side-variation),
    // freeze PiP on that position instead of following new live moves. No state
    // (game snapshot) means we are showing the latest.
    //
    // NOTE: do NOT use analysisState.isAtEnd here — the navigator only loads the
    // move path up to the current position, so isAtEnd is always true regardless
    // of where the user scrolled. `isAtLiveTail` is the reliable signal (set in
    // _syncAnalysisFromNavigator from the navigator's mainline-tail check).
    final followLive = state?.isAtLiveTail ?? true;
    final eventName =
        game.tourSlug != null && game.tourSlug!.isNotEmpty
            ? StringUtils.slugToTitle(game.tourSlug!)
            : null;
    final roundName =
        game.roundSlug != null && game.roundSlug!.isNotEmpty
            ? StringUtils.formatRoundLabel(game.roundSlug!)
            : null;

    return <String, dynamic>{
      'eligible': true,
      'followLive': followLive,
      'gameId': game.gameId,
      'fen': fen,
      'lastMoveUci': lastMoveUci,
      'lastMove': game.lastMove ?? '',
      'status': game.gameStatus.name,
      if (game.lastMoveTime != null)
        'lastMoveTime': game.lastMoveTime!.toUtc().toIso8601String(),
      if (evaluation != null) 'evalCp': (evaluation * 100).round(),
      if (state?.mate != null) 'mate': state!.mate,
      'whiteName': game.whitePlayer.name,
      'blackName': game.blackPlayer.name,
      'whiteTitle': game.whitePlayer.title,
      'blackTitle': game.blackPlayer.title,
      'whiteRating': game.whitePlayer.rating,
      'blackRating': game.blackPlayer.rating,
      'whiteFed':
          game.whitePlayer.countryCode.isNotEmpty
              ? game.whitePlayer.countryCode
              : game.whitePlayer.federation,
      'blackFed':
          game.blackPlayer.countryCode.isNotEmpty
              ? game.blackPlayer.countryCode
              : game.blackPlayer.federation,
      if (game.whiteClockSeconds != null)
        'whiteClockSeconds': game.whiteClockSeconds,
      if (game.blackClockSeconds != null)
        'blackClockSeconds': game.blackClockSeconds,
      'whiteClock': _formatPipClock(
        game.whiteClockSeconds,
        game.whiteClockCentiseconds,
        game.whiteTimeDisplay,
      ),
      'blackClock': _formatPipClock(
        game.blackClockSeconds,
        game.blackClockCentiseconds,
        game.blackTimeDisplay,
      ),
      if (eventName != null) 'eventName': eventName,
      if (roundName != null) 'roundName': roundName,
      'boardThemeIndex': boardSettings?.boardThemeIndex ?? 9,
      'pieceStyleIndex': boardSettings?.pieceStyleIndex ?? 0,
    };
  }

  String _formatPipClock(int? seconds, int centiseconds, String fallback) {
    final totalSeconds =
        seconds ?? (centiseconds > 0 ? centiseconds ~/ 100 : null);
    if (totalSeconds == null) return fallback;
    final clamped = math.max(0, totalSeconds);
    final hours = clamped ~/ 3600;
    final minutes = (clamped % 3600) ~/ 60;
    final secs = clamped % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _handlePageChange(int newIndex) async {
    if (_isRevertingPage) {
      _isRevertingPage = false;
      return;
    }

    // Ignore page changes during tutorial swipe animation
    // The animation moves the page position but shouldn't change the current index
    if (_showTutorialOverlay) return;

    if (_currentPageIndex == newIndex) return;

    final previousIndex = _currentPageIndex;

    _lastViewedIndex = newIndex;

    // Update current page index immediately
    setState(() {
      _currentPageIndex = newIndex;
    });
    _keepBoardProviderAlive(newIndex);
    unawaited(_syncPipGameSnapshot(_resolveGameForIndex(newIndex)));

    // CRITICAL: Update the global provider to track which page is visible
    // This prevents off-screen games from playing audio
    ref.read(currentlyVisiblePageIndexProvider.notifier).state = newIndex;

    // Cancel active evaluations on the board that just went off-screen
    try {
      final prevGame = _resolveGameForIndex(previousIndex);
      final prevParams = _createParams(prevGame, previousIndex);
      final prevNotifier = ref.read(
        chessBoardScreenProviderNew(prevParams).notifier,
      );
      unawaited(prevNotifier.onBecameInvisible());
    } catch (e) {
      debugPrint('Error cancelling previous game evaluation: $e');
    }

    // OPTIMIZED: Don't read provider state during page changes - just manage the chess board providers
    // This prevents unnecessary provider lookups that could trigger rebuilds

    // Only pause if the previous provider should still be alive (within ±1 range)
    if ((newIndex - previousIndex).abs() <= 1) {
      try {
        final prevGame = _resolveGameForIndex(previousIndex);
        ref
            .read(
              chessBoardScreenProviderNew(
                _createParams(prevGame, previousIndex),
              ).notifier,
            )
            .pauseGame();
      } catch (e) {
        // Provider was disposed, which is fine
      }
    }

    _pageSettleTimer?.cancel();
    final settleGeneration = ++_pageSettleGeneration;
    // PERF: Increased from 220ms to 350ms to reduce jank during rapid swiping
    // This gives more time for the user to settle on a page before triggering
    // expensive evaluation and parsing operations
    _pageSettleTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (_pageSettleGeneration != settleGeneration) return;
      if (_currentPageIndex != newIndex) return;
      try {
        final newGame = _resolveGameForIndex(newIndex);
        final params = _createParams(newGame, newIndex);
        final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
        unawaited(
          notifier.parseMoves().whenComplete(notifier.evaluateCurrentPosition),
        );
      } catch (e) {
        debugPrint('Error parsing moves for new index: $e');
      }
    });
  }

  void _handleLifecycleResume() {
    if (!mounted || widget.games.isEmpty) return;
    ref.invalidate(gameUpdatesStreamProvider);
    ref.invalidate(liveGameUpdateStreamProvider);
    ref.invalidate(gameUpdatesBatchStreamProvider);
    final safeIndex = _currentPageIndex.clamp(0, widget.games.length - 1);
    final currentGame = _resolveGameForIndex(safeIndex);
    final params = _createParams(currentGame, safeIndex);
    try {
      final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
      unawaited(notifier.onBecameVisible(force: true));
    } catch (e) {
      debugPrint('Error refreshing Stockfish on resume: $e');
    }

    // Stop Live Activity when user returns to the app
    _stopLiveActivityIfActive(currentGame);
    unawaited(
      _syncPipState(
        ref.read(chessBoardScreenProviderNew(params)).valueOrNull ??
            ChessBoardStateNew(game: currentGame),
      ),
    );
  }

  void _stopLiveActivityIfActive(GamesTourModel game) {
    final liveService = LiveUpdatesService.instance;
    final activeGameId = liveService.activeGameId;
    if (activeGameId == null) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    // Stop the active live activity since user is back in the app
    unawaited(liveService.stopForGame(activeGameId, user.id));
    debugPrint(
      '[ChessBoardScreen] Stopped Live Activity - user returned to app',
    );
  }

  void _handleLifecyclePaused() {
    if (!mounted || widget.games.isEmpty) return;
    final safeIndex = _currentPageIndex.clamp(0, widget.games.length - 1);
    final currentGame = _resolveGameForIndex(safeIndex);
    final params = _createParams(currentGame, safeIndex);
    try {
      final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
      unawaited(notifier.onBecameInvisible());
    } catch (e) {
      debugPrint('Error pausing Stockfish on lifecycle change: $e');
    }

    // Auto-start Live Activity for live games when app goes to background
    unawaited(_startLiveActivityIfEligible(currentGame));
  }

  Future<void> _enterPipForCurrentGameIfEligible() async {
    if (!mounted || widget.games.isEmpty) return;
    final safeIndex = _currentPageIndex.clamp(0, widget.games.length - 1);
    final currentGame = _resolveGameForIndex(safeIndex);
    final params = _createParams(currentGame, safeIndex);
    final state = ref.read(chessBoardScreenProviderNew(params)).valueOrNull;
    if (state != null) {
      await _syncPipState(state);
    } else {
      await _syncPipGameSnapshot(currentGame);
    }
    if (_isPipEligible(state?.game ?? currentGame)) {
      await PipService.instance.enterIfEligible();
    }
  }

  Future<void> _startLiveActivityIfEligible(GamesTourModel game) async {
    // Only start for ongoing games
    if (!game.gameStatus.isOngoing) return;

    // Check if user is authenticated
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    // Respect master push toggle
    final pushEnabled = ref.read(notificationsSettingsProvider).enabled;
    if (!pushEnabled) return;

    // Backgrounding an active board is an explicit opt-in for live tracking,
    // so don't re-gate it behind the broader live-updates category toggle.

    // Don't start if already active for this game
    final liveService = LiveUpdatesService.instance;
    if (liveService.activeGameId == game.gameId) return;

    // Ensure newest game wins focus
    final activeGameId = liveService.activeGameId;
    if (activeGameId != null && activeGameId != game.gameId) {
      unawaited(liveService.stopForGame(activeGameId, user.id));
    }

    final whitePhoto = null;
    final blackPhoto = null;

    final eventName =
        game.tourSlug != null && game.tourSlug!.isNotEmpty
            ? StringUtils.slugToTitle(game.tourSlug!)
            : null;
    final roundName =
        game.roundSlug != null && game.roundSlug!.isNotEmpty
            ? StringUtils.formatRoundLabel(game.roundSlug!)
            : null;

    final boardSettings = ref.read(boardSettingsProviderNew).valueOrNull;
    final boardThemeIndex = boardSettings?.boardThemeIndex ?? 0;
    final pieceStyleIndex = boardSettings?.pieceStyleIndex ?? 0;

    // Start Live Activity
    unawaited(
      liveService.startForGame(
        gameId: game.gameId,
        userId: user.id,
        playerWhite: game.whitePlayer.name,
        playerBlack: game.blackPlayer.name,
        whiteTitle:
            game.whitePlayer.title.isNotEmpty ? game.whitePlayer.title : null,
        blackTitle:
            game.blackPlayer.title.isNotEmpty ? game.blackPlayer.title : null,
        whiteFed:
            game.whitePlayer.federation.isNotEmpty
                ? game.whitePlayer.federation
                : null,
        blackFed:
            game.blackPlayer.federation.isNotEmpty
                ? game.blackPlayer.federation
                : null,
        whitePhoto: whitePhoto,
        blackPhoto: blackPhoto,
        fen: game.fen,
        lastMove: game.lastMove,
        lastMoveTime: game.lastMoveTime,
        whiteClockSeconds: game.whiteClockSeconds,
        blackClockSeconds: game.blackClockSeconds,
        eventName: eventName,
        roundName: roundName,
        whiteFideId: game.whitePlayer.fideId,
        blackFideId: game.blackPlayer.fideId,
        boardThemeIndex: boardThemeIndex,
        pieceStyleIndex: pieceStyleIndex,
      ),
    );

    debugPrint(
      '[ChessBoardScreen] Auto-started Live Activity for game: ${game.gameId}',
    );
  }

  @override
  void didPushNext() {
    // Another route pushed on top (e.g. Player Profile, Explorer).
    // Pause Stockfish so it doesn't compete with the foreground screen.
    _handleLifecyclePaused();
    super.didPushNext();
  }

  @override
  void didPopNext() {
    // Route on top was popped — board is visible again.
    _scheduleLifecycleResume();
    super.didPopNext();
  }

  void _scheduleLifecycleResume() {
    ForegroundTaskScheduler.schedule(
      key: 'chessboard_resume_$hashCode',
      task: () {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route?.isCurrent != true) return;
        _handleLifecycleResume();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      _scheduleLifecycleResume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      ForegroundTaskScheduler.cancel('chessboard_resume_$hashCode');
      unawaited(_enterPipForCurrentGameIfEligible());
      _handleLifecyclePaused();
    } else {
      ForegroundTaskScheduler.cancel('chessboard_resume_$hashCode');
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    PipService.instance.removeListener(_handlePipModeChanged);
    ForegroundTaskScheduler.cancel('chessboard_resume_$hashCode');
    _boardKeepAliveSub?.close();
    _audioSub?.close();
    _pipSub?.close();
    unawaited(PipService.instance.clearActiveGame());
    _pageSettleTimer?.cancel();
    _removeLikeTutorialOverlay();
    _swipeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _navigateToGame(int gameIndex) {
    debugPrint(
      '🎯 _navigateToGame called with gameIndex: $gameIndex, current: $_currentPageIndex',
    );
    if (gameIndex == _currentPageIndex) {
      debugPrint('🎯 Same page, returning early');
      return;
    }

    // Validate gameIndex is within bounds
    if (gameIndex < 0 || gameIndex >= widget.games.length) {
      debugPrint(
        '🎯 Invalid gameIndex: $gameIndex (games.length: ${widget.games.length})',
      );
      return;
    }

    // OPTIMIZED: Don't read provider during navigation - just pause the current game
    try {
      final currentGame = _resolveGameForIndex(_currentPageIndex);
      ref
          .read(
            chessBoardScreenProviderNew(
              _createParams(currentGame, _currentPageIndex),
            ).notifier,
          )
          .pauseGame();
    } catch (e) {
      debugPrint('Error pausing game during navigation: $e');
    }

    // Use jumpToPage for jumps > 1 page to avoid animation interference
    // animateToPage can trigger multiple onPageChanged events during animation
    final distance = (gameIndex - _currentPageIndex).abs();
    debugPrint(
      '🎯 Navigating from $_currentPageIndex to $gameIndex (distance: $distance)',
    );

    if (!_pageController.hasClients) {
      return;
    }

    if (distance > 1) {
      // For large jumps, use jumpToPage to avoid intermediate page triggers
      _pageController.jumpToPage(gameIndex);
    } else {
      // For adjacent pages, animate smoothly
      _pageController.animateToPage(
        gameIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _toggleGamebase() async {
    final allowed = await requireFullAuthGuard(context);
    if (!allowed) return;
    ref.read(gamebaseOverlayEnabledProvider.notifier).toggle();
  }

  @override
  Widget build(BuildContext context) {
    // Step 3/3 of the new-user teaching chain: when Switch Views (step 2)
    // finishes or is skipped it bumps this counter; show the like teaching on
    // the next frame so it appears right after the previous card, never atop
    // it. The monotonic counter re-arms cleanly on a fresh screen open.
    ref.listen<int>(likeTutorialRequestProvider, (_, next) {
      if (next <= _lastLikeTutorialRequest) return;
      _lastLikeTutorialRequest = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeStartLikeTutorial();
      });
    });

    final view = ref.watch(chessboardViewFromProviderNew);
    AsyncValue<GamesScreenModel> gamesAsync;

    switch (view) {
      case ChessboardView.favScorecard:
      case ChessboardView.playerProfile:
        final selectedPlayer = ref.watch(selectedPlayerProvider);
        if (selectedPlayer == null) {
          // Fallback to widget.games if no player is selected
          gamesAsync = AsyncValue.data(
            GamesScreenModel(gamesTourModels: widget.games, pinnedGamedIs: []),
          );
        } else {
          final gamesValue =
              ref.watch(playerGamesProvider(selectedPlayer)).valueOrNull;
          if (gamesValue == null) {
            // Still loading player games, use widget.games as fallback
            gamesAsync = AsyncValue.data(
              GamesScreenModel(
                gamesTourModels: widget.games,
                pinnedGamedIs: [],
              ),
            );
          } else {
            gamesAsync = AsyncValue.data(
              GamesScreenModel(gamesTourModels: gamesValue, pinnedGamedIs: []),
            );
          }
        }
        break;
      case ChessboardView.tour:
        gamesAsync = ref.watch(gamesTourScreenProvider);
        break;
      case ChessboardView.countryman:
        gamesAsync = ref.watch(countrymanGamesTourScreenProvider);
        break;
      case ChessboardView.forYou:
        // For "For You" tab, use the converted games from forYouGamesProvider
        final games = ref.watch(convertedForYouGamesProvider);
        gamesAsync = AsyncValue.data(
          GamesScreenModel(gamesTourModels: games, pinnedGamedIs: []),
        );
        break;
    }

    // Fallback for contexts (e.g., For You tab) where gamesTourScreenProvider
    // isn't hydrated yet. We still want to open the board with the passed games.
    GamesScreenModel? gamesModel = gamesAsync.valueOrNull;
    if (gamesModel == null || gamesModel.gamesTourModels.isEmpty) {
      if (widget.games.isNotEmpty) {
        gamesModel = GamesScreenModel(
          gamesTourModels: widget.games,
          pinnedGamedIs: const [],
        );
      }
    }

    if (gamesModel == null || gamesModel.gamesTourModels.isEmpty) {
      return _LoadingScreen(
        games: widget.games.isNotEmpty ? widget.games : [widget.games.first],
        currentGameIndex: _currentPageIndex.clamp(0, widget.games.length - 1),
        onGameChanged: (index) {},
        lastViewedIndex: _lastViewedIndex,
      );
    }

    // Merge game data between gamesModel and widget.games
    // CRITICAL: For "For You" view, widget.games has live updates from liveGameCardProvider,
    // while gamesModel (convertedForYouGamesProvider) is a static snapshot without live streaming.
    // So for "For You", we use widget.games directly to preserve live state.
    // For tour/countryman views, gamesModel has live streaming, so prefer it.
    final shouldStream = ref.watch(shouldStreamProvider);
    final preferWidgetGames = view == ChessboardView.forYou || !shouldStream;
    final List<GamesTourModel> liveGames;
    if (preferWidgetGames) {
      // For "For You": widget.games already has live updates from liveGameCardProvider
      liveGames = widget.games;
    } else {
      // For other views: merge with gamesModel which has live streaming
      final liveGamesMap = Map.fromEntries(
        gamesModel.gamesTourModels.map((g) => MapEntry(g.gameId, g)),
      );
      liveGames =
          widget.games
              .map(
                (originalGame) =>
                    liveGamesMap[originalGame.gameId] ?? originalGame,
              )
              .toList();
    }

    final syncedGames = List<GamesTourModel>.from(liveGames);
    if (syncedGames.isEmpty) {
      return _LoadingScreen(
        games: widget.games.isNotEmpty ? widget.games : [widget.games.first],
        currentGameIndex: _currentPageIndex.clamp(0, widget.games.length - 1),
        onGameChanged: (index) {},
        lastViewedIndex: _lastViewedIndex,
      );
    }

    final visibleStart = (_currentPageIndex - 1).clamp(
      0,
      syncedGames.length - 1,
    );
    final visibleEnd = (_currentPageIndex + 1).clamp(0, syncedGames.length - 1);

    // PERFORMANCE FIX: Use select() to only watch the 'game' property, not the entire state.
    // This prevents rebuilds from evaluation updates, PV changes, depth progress, etc.
    // Each PageView item will watch its own full provider state via Consumer.
    for (int i = visibleStart; i <= visibleEnd; i++) {
      final game = syncedGames[i];
      final params = _createParams(game, i);

      // Only watch game changes - this rarely changes compared to eval/PV updates
      final gameFromProvider = ref.watch(
        chessBoardScreenProviderNew(
          params,
        ).select((state) => state.valueOrNull?.game),
      );
      if (gameFromProvider != null) {
        syncedGames[i] = gameFromProvider;
      }
    }

    // Use same params as watch to listen to the same provider
    final currentGame =
        syncedGames[_currentPageIndex.clamp(0, syncedGames.length - 1)];
    final currentParams = _createParams(currentGame, _currentPageIndex);
    _ensureAudioListener(currentParams);
    _ensurePipListener(currentParams);
    // OPTIMIZED: Only watch for updates to games that are currently visible in the PageView
    // This prevents rebuilds when other games in the tournament get updated
    final isTablet = ResponsiveHelper.isTablet;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop(_lastViewedIndex);
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: (context.isLightTheme
                ? SystemUiOverlayStyle.dark
                : SystemUiOverlayStyle.light)
            .copyWith(
              statusBarColor: context.colors.background,
              systemNavigationBarColor: context.colors.background,
            ),
        child:
        // ignore: deprecated_member_use
        ShowCaseWidget(
          onFinish: _onWalkthroughFinished,
          builder: (context) {
            if (!_hasCheckedWalkthrough) {
              _hasCheckedWalkthrough = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _checkAndShowWalkthrough(context);
              });
            }
            return Builder(
              builder: (innerContext) {
                return Scaffold(
                  key: e2eKey(E2eIds.chessBoardRoot),
                  backgroundColor: innerContext.colors.background,
                  resizeToAvoidBottomInset: false,
                  // REMOVED: RawGestureDetector was blocking PageView swipes
                  body: Stack(
                    children: [
                      PageView.builder(
                        padEnds: true,
                        // PERF: Disabled implicit scrolling entirely - it pre-renders adjacent
                        // pages for accessibility which is too expensive for complex chess views.
                        // This significantly reduces memory pressure during rapid swiping.
                        allowImplicitScrolling: false,
                        dragStartBehavior: DragStartBehavior.down,
                        // Allow swiping on tablet as well; landscape block caused gestures to
                        // feel broken on larger devices. Keep physics simple to avoid half-drags.
                        physics:
                            isTablet
                                ? const PageScrollPhysics(
                                  parent: ClampingScrollPhysics(),
                                )
                                : const PageScrollPhysics(),
                        controller: _pageController,
                        onPageChanged: _onPageChanged,
                        itemCount: syncedGames.length,
                        itemBuilder: (context, index) {
                          // Build current page and adjacent pages
                          if (index == _currentPageIndex - 1 ||
                              index == _currentPageIndex ||
                              index == _currentPageIndex + 1) {
                            final game = syncedGames[index];
                            final params = _createParams(game, index);

                            // PERFORMANCE FIX: Wrap each page in Consumer to isolate rebuilds.
                            // This way, evaluation/PV updates only rebuild the affected page,
                            // not the entire PageView and all siblings.
                            return Consumer(
                              builder: (context, ref, _) {
                                try {
                                  final stateAsync = ref.watch(
                                    chessBoardScreenProviderNew(params),
                                  );
                                  return stateAsync.when(
                                    data: (chessBoardState) {
                                      _ensureLatestMoveSelected(
                                        ref: ref,
                                        pageIndex: index,
                                        state: chessBoardState,
                                      );
                                      // PERFORMANCE FIX: Removed useless setState for analysisMode.
                                      // The variable was tracked but never used for rendering,
                                      // causing full parent rebuilds on every analysis mode change.
                                      return _GamePage(
                                        game: chessBoardState.game,
                                        state: chessBoardState,
                                        games: syncedGames,
                                        currentGameIndex: index,
                                        currentPageIndex: _currentPageIndex,
                                        onGameChanged: _navigateToGame,
                                        lastViewedIndex: _lastViewedIndex,
                                        hideEventInfo: widget.hideEventInfo,
                                        playerProfileDataSource:
                                            widget.playerProfileDataSource,
                                        onToggleGamebase: _toggleGamebase,
                                        showGamebaseButton:
                                            widget.showGamebaseButton,
                                        showClock: widget.showClock,
                                        savedAnalysisData:
                                            _getSavedAnalysisDataForIndex(
                                              index,
                                            ),
                                      );
                                    },
                                    loading:
                                        () => _LoadingScreen(
                                          games: liveGames,
                                          currentGameIndex: index,
                                          onGameChanged: _navigateToGame,
                                          lastViewedIndex: _lastViewedIndex,
                                          hideEventInfo: widget.hideEventInfo,
                                        ),
                                    error: (e, _) => ErrorWidget(e),
                                  );
                                } catch (e) {
                                  // Fallback for when provider isn't ready
                                  return _LoadingScreen(
                                    games: liveGames,
                                    currentGameIndex: index,
                                    onGameChanged: _navigateToGame,
                                    lastViewedIndex: _lastViewedIndex,
                                    hideEventInfo: widget.hideEventInfo,
                                  );
                                }
                              },
                            );
                          } else {
                            return SizedBox.shrink();
                          }
                        },
                      ),
                      // Removed redundant IgnorePointer/AnimatedBuilder that was here
                      if (_showTutorialOverlay)
                        Positioned.fill(
                          child: _SwipeTutorialOverlay(
                            key: _tutorialOverlayKey,
                            animationController: _swipeController,
                            moveAnimation: _swipeMoveAnimation,
                            fadeAnimation: _swipeFadeAnimation,
                            scaleAnimation: _swipeScaleAnimation,
                            currentPageIndex: _currentPageIndex,
                            totalItems: syncedGames.length,
                            currentStep: 1,
                            totalSteps: 3,
                            onDismiss: () {
                              _onWalkthroughFinished();
                              _requestSwitchViewsTutorial();
                            },
                            onDontShowAgain: () async {
                              await _suppressWalkthrough();
                              _onWalkthroughFinished();
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SwipeTutorialOverlay extends StatefulWidget {
  final VoidCallback onDismiss;
  final VoidCallback onDontShowAgain;
  final AnimationController animationController;
  final Animation<double> moveAnimation;
  final Animation<double> fadeAnimation;
  final Animation<double> scaleAnimation;
  final int currentPageIndex;
  final int totalItems;
  final int currentStep;
  final int totalSteps;

  const _SwipeTutorialOverlay({
    super.key,
    required this.onDismiss,
    required this.onDontShowAgain,
    required this.animationController,
    required this.moveAnimation,
    required this.fadeAnimation,
    required this.scaleAnimation,
    required this.currentPageIndex,
    required this.totalItems,
    this.currentStep = 0,
    this.totalSteps = 0,
  });

  @override
  State<_SwipeTutorialOverlay> createState() => _SwipeTutorialOverlayState();
}

class _SwipeTutorialOverlayState extends State<_SwipeTutorialOverlay>
    with SingleTickerProviderStateMixin {
  double _opacityTarget = 0.0;
  bool _isExiting = false;
  late AnimationController _timerController;

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );

    // Start entry animation and timer
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _opacityTarget = 1.0;
        });
        _timerController.forward();
      }
    });

    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        animateOut();
      }
    });
  }

  @override
  void dispose() {
    _timerController.dispose();
    super.dispose();
  }

  Future<void> animateOut() async {
    if (_isExiting) return;
    _timerController.stop(); // Stop the visual timer if manual dismiss
    setState(() {
      _isExiting = true;
      _opacityTarget = 0.0;
    });
    // Wait for animation to finish (approximate for spring)
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      widget.onDismiss();
    }
  }

  void _handleDontShowAgain() async {
    if (_isExiting) return;
    _timerController.stop();
    setState(() {
      _isExiting = true;
      _opacityTarget = 0.0;
    });
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      widget.onDontShowAgain();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: const CupertinoMotion.snappy(),
      value: _opacityTarget,
      builder: (context, opacity, child) {
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: GestureDetector(
            onTap: animateOut,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: MediaQuery.sizeOf(context).height,
              width: MediaQuery.sizeOf(context).width,
              color: kBlackColor.withValues(
                alpha: 0.8,
              ), // Restored background for overlay
              child: Stack(
                children: [
                  // Main Content: Bubble + Hand (Centered together)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Modern Message Bubble (Floating Card) with Timer Border
                        SizedBox(
                          width: 280.w,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.topCenter,
                            children: [
                              // Card Background with Progress Border
                              AnimatedBuilder(
                                animation: _timerController,
                                builder: (context, child) {
                                  return CustomPaint(
                                    foregroundPainter: _BorderProgressPainter(
                                      progress: _timerController.value,
                                      color: kPrimaryColor,
                                      strokeWidth: 3.0,
                                      borderRadius: 28.br,
                                    ),
                                    child: Container(
                                      padding: EdgeInsets.fromLTRB(
                                        24.w,
                                        36.h,
                                        24.w,
                                        24.h,
                                      ),
                                      decoration: BoxDecoration(
                                        // Tutorial card sits on top of a dark
                                        // dim scrim in both themes, so it stays
                                        // white with black text for clarity.
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(
                                          28.br,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.3,
                                            ),
                                            blurRadius: 30,
                                            offset: const Offset(0, 12),
                                            spreadRadius: 0,
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (widget.totalSteps > 1 &&
                                              widget.currentStep > 0) ...[
                                            TutorialStepIndicator(
                                              currentStep: widget.currentStep,
                                              totalSteps: widget.totalSteps,
                                            ),
                                            SizedBox(height: 10.h),
                                          ],
                                          Text(
                                            'Swipe to Browse',
                                            style: AppTypography.textLgBold
                                                .copyWith(
                                                  color: kBlackColor,
                                                  height: 1.2,
                                                  letterSpacing: -0.5,
                                                ),
                                            textAlign: TextAlign.center,
                                          ),
                                          SizedBox(height: 8.h),
                                          Text(
                                            'Explore other games in this tournament by swiping horizontally.',
                                            style: AppTypography.textSmMedium
                                                .copyWith(
                                                  color: kBlackColor.withValues(
                                                    alpha: 0.6,
                                                  ),
                                                  height: 1.4,
                                                ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              // Floating Playful Icon
                              Positioned(
                                top: -20.h,
                                child: Container(
                                  padding: EdgeInsets.all(10.sp),
                                  decoration: BoxDecoration(
                                    color: kPrimaryColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: kPrimaryColor.withValues(
                                          alpha: 0.4,
                                        ),
                                        blurRadius: 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 3,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.view_carousel_rounded,
                                    color: Colors.white,
                                    size: 22.sp,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 48.h), // Gap between bubble and hand
                        // Hand Animation
                        SizedBox(
                          height:
                              120.h, // Reserve space for hand movement vertically
                          width: double.infinity,
                          child: AnimatedBuilder(
                            animation: widget.animationController,
                            builder: (context, child) {
                              if (!widget.animationController.isAnimating) {
                                return const SizedBox.shrink();
                              }

                              final width = MediaQuery.sizeOf(context).width;
                              bool canGoNext =
                                  widget.currentPageIndex <
                                  widget.totalItems - 1;
                              double direction = canGoNext ? 1.0 : -1.0;

                              // Reduce drag distance slightly for better visual within column
                              double maxDrag = width * 0.5;
                              double handTranslation =
                                  -1 *
                                  widget.moveAnimation.value *
                                  maxDrag *
                                  direction;

                              return Opacity(
                                opacity: widget.fadeAnimation.value,
                                child: Transform.translate(
                                  offset: Offset(handTranslation, 0),
                                  child: Transform.scale(
                                    scale: widget.scaleAnimation.value,
                                    child: Center(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.15,
                                          ),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.3,
                                              ),
                                              blurRadius: 20,
                                              spreadRadius: 5,
                                            ),
                                          ],
                                        ),
                                        padding: EdgeInsets.all(24.sp),
                                        child: Icon(
                                          Icons.touch_app_rounded,
                                          size: 52.sp,
                                          color: Colors.white,
                                          shadows: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.5,
                                              ),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(height: 48.h), // Gap before control buttons
                        // Control Buttons - Now inside the centered column
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: _handleDontShowAgain,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              child: Text(
                                "Don't show again",
                                style: AppTypography.textSmMedium,
                              ),
                            ),
                            SizedBox(width: 24.w),
                            TextButton(
                              onPressed: animateOut,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.1,
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 24.w,
                                  vertical: 12.h,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30.br),
                                ),
                              ),
                              child: Text(
                                'Got it',
                                style: AppTypography.textSmBold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BorderProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final double borderRadius;

  _BorderProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final r = borderRadius;
    final topCenter = w / 2;
    final bottomCenter = w / 2;

    // Right Path (Clockwise: Top-Center -> Top-Right -> Right -> Bottom-Right -> Bottom-Center)
    final rightPath =
        Path()
          ..moveTo(topCenter, 0)
          ..lineTo(w - r, 0)
          ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
          ..lineTo(w, h - r)
          ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
          ..lineTo(bottomCenter, h);

    // Left Path (Counter-Clockwise: Top-Center -> Top-Left -> Left -> Bottom-Left -> Bottom-Center)
    final leftPath =
        Path()
          ..moveTo(topCenter, 0)
          ..lineTo(r, 0)
          ..arcToPoint(
            Offset(0, r),
            radius: Radius.circular(r),
            clockwise: false,
          )
          ..lineTo(0, h - r)
          ..arcToPoint(
            Offset(r, h),
            radius: Radius.circular(r),
            clockwise: false,
          )
          ..lineTo(bottomCenter, h);

    // Draw Right Segment
    final rightMetric = rightPath.computeMetrics().first;
    final rightExtract = rightMetric.extractPath(
      0,
      rightMetric.length * progress,
    );
    canvas.drawPath(rightExtract, paint);

    // Draw Left Segment
    final leftMetric = leftPath.computeMetrics().first;
    final leftExtract = leftMetric.extractPath(0, leftMetric.length * progress);
    canvas.drawPath(leftExtract, paint);
  }

  @override
  bool shouldRepaint(covariant _BorderProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.borderRadius != borderRadius;
  }
}

class _GamePage extends StatelessWidget {
  final GamesTourModel game;
  final ChessBoardStateNew state;
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final int currentPageIndex;
  final void Function(int) onGameChanged;
  final int? lastViewedIndex;
  final bool hideEventInfo;
  final PlayerProfileDataSource playerProfileDataSource;
  final VoidCallback onToggleGamebase;
  final bool showGamebaseButton;
  final bool showClock;
  final SavedAnalysisData? savedAnalysisData;

  const _GamePage({
    required this.game,
    required this.state,
    required this.games,
    required this.currentGameIndex,
    required this.currentPageIndex,
    required this.onGameChanged,
    required this.onToggleGamebase,
    this.lastViewedIndex,
    this.hideEventInfo = false,
    this.playerProfileDataSource = PlayerProfileDataSource.supabase,
    this.showGamebaseButton = false,
    this.showClock = true,
    this.savedAnalysisData,
  });

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: context.colors.background,
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: _BottomNavBar(
        index: currentGameIndex,
        state: state,
        game: game,
        onGamebaseToggle: onToggleGamebase,
        showGamebaseButton: showGamebaseButton,
      ),
      appBar: _AppBar(
        game: game,
        games: games,
        currentGameIndex: currentGameIndex,
        onGameChanged: onGameChanged,
        lastViewedIndex: lastViewedIndex,
        hideEventInfo: hideEventInfo,
        savedAnalysisData: savedAnalysisData,
      ),
      body: _GameBody(
        index: currentGameIndex,
        currentPageIndex: currentPageIndex,
        game: game,
        state: state,
        playerProfileDataSource: playerProfileDataSource,
        showGamebaseButton: showGamebaseButton,
        showClock: showClock,
      ),
    );
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: scaffold,
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final void Function(int) onGameChanged;
  final int? lastViewedIndex;
  final bool hideEventInfo;

  const _LoadingScreen({
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
    this.lastViewedIndex,
    this.hideEventInfo = false,
  });

  @override
  Widget build(BuildContext context) {
    final sideBarWidth = 20.w;
    final fullScreenWidth = MediaQuery.sizeOf(context).width;

    // Tablet layout detection
    final isTablet = ResponsiveHelper.isTablet;
    final isTabletLandscape = isTablet && ResponsiveHelper.isLandscape;
    final isTabletPortrait = isTablet && !ResponsiveHelper.isLandscape;

    // Calculate content width based on device/orientation
    double contentMaxWidth;
    if (isTabletPortrait) {
      contentMaxWidth = math.min(fullScreenWidth * 0.85, 720.0);
    } else if (isTabletLandscape) {
      // In landscape, board section takes ~58% of width
      contentMaxWidth = fullScreenWidth * 0.58;
    } else {
      contentMaxWidth = fullScreenWidth;
    }

    final boardSize = contentMaxWidth - sideBarWidth - 32.w;

    final scaffold = Scaffold(
      backgroundColor: context.colors.background,
      resizeToAvoidBottomInset: false,
      appBar: _AppBar(
        game: games[currentGameIndex],
        games: games,
        currentGameIndex: currentGameIndex,
        onGameChanged: onGameChanged,
        isLoading: true,
        lastViewedIndex: lastViewedIndex,
        hideEventInfo: hideEventInfo,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth),
          child: Skeletonizer(
            enabled: true,
            child: Column(
              children: [
                // Top player skeleton
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  padding: EdgeInsets.all(8.sp),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(8.br),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40.w,
                        height: 40.h,
                        decoration: BoxDecoration(
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.1,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 120.w,
                              height: 14.h,
                              decoration: BoxDecoration(
                                color: context.colors.textPrimary.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(4.br),
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Container(
                              width: 60.w,
                              height: 12.h,
                              decoration: BoxDecoration(
                                color: context.colors.textPrimary.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(4.br),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 2.h),
                // Board skeleton
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 16.sp),
                  child: Row(
                    children: [
                      // Eval bar skeleton
                      Container(
                        width: sideBarWidth,
                        height: boardSize,
                        decoration: BoxDecoration(
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.05,
                          ),
                          borderRadius: BorderRadius.circular(4.br),
                        ),
                      ),
                      // Board skeleton
                      Container(
                        width: boardSize,
                        height: boardSize,
                        decoration: BoxDecoration(
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.05,
                          ),
                          borderRadius: BorderRadius.circular(4.br),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 2.h),
                // Bottom player skeleton
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  padding: EdgeInsets.all(8.sp),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(8.br),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40.w,
                        height: 40.h,
                        decoration: BoxDecoration(
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.1,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 120.w,
                              height: 14.h,
                              decoration: BoxDecoration(
                                color: context.colors.textPrimary.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(4.br),
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Container(
                              width: 60.w,
                              height: 12.h,
                              decoration: BoxDecoration(
                                color: context.colors.textPrimary.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(4.br),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Moves area skeleton
                Expanded(
                  child: Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(top: 8.h),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceRecessed.withValues(
                        alpha: 0.3,
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12.sp),
                        topRight: Radius.circular(12.sp),
                      ),
                    ),
                    padding: EdgeInsets.all(20.sp),
                    child: Wrap(
                      spacing: 6.sp,
                      runSpacing: 6.sp,
                      children: List.generate(8, (index) {
                        return Container(
                          width: (35 + (index % 5) * 20).w,
                          height: 14.h,
                          decoration: BoxDecoration(
                            color: context.colors.textPrimary.withValues(
                              alpha: 0.05,
                            ),
                            borderRadius: BorderRadius.circular(3.sp),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: scaffold,
    );
  }
}

class _AppBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  final GamesTourModel game;
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final void Function(int) onGameChanged;
  final bool isLoading;
  final int? lastViewedIndex;
  final bool hideEventInfo;
  final SavedAnalysisData? savedAnalysisData;

  const _AppBar({
    required this.game,
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
    this.isLoading = false,
    this.lastViewedIndex,
    this.hideEventInfo = false,
    this.savedAnalysisData,
  });

  @override
  ConsumerState<_AppBar> createState() => _AppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _ResolvedAppBarShareData {
  final String pgn;
  final String? shareUrl;
  final GameShareSnapshot snapshot;
  final double? evaluation;
  final int mate;
  final bool isFlipped;
  final bool isAtGameEnd;

  const _ResolvedAppBarShareData({
    required this.pgn,
    required this.shareUrl,
    required this.snapshot,
    required this.evaluation,
    required this.mate,
    required this.isFlipped,
    required this.isAtGameEnd,
  });
}

bool _shareGameNeedsTerminalPosition(GameSource source) {
  return source == GameSource.gamebase || source == GameSource.openingExplorer;
}

bool _isAnalysisAtFinishedSharePosition({
  required AnalysisBoardState analysisState,
  required GamesTourModel game,
}) {
  final analysisGame = analysisState.game;
  if (analysisGame == null || !game.gameStatus.isFinished) return false;

  // Result-based king effects are only valid on the original mainline.
  if (analysisState.movePointer.length != 1) return false;

  final currentMainlineIndex = analysisState.movePointer[0];
  final totalMainlineMoves = analysisGame.mainline.length;
  if (totalMainlineMoves == 0 ||
      currentMainlineIndex != totalMainlineMoves - 1) {
    return false;
  }

  // Live games must never show finished-result effects.
  if (analysisGame.isLiveGame) return false;

  // Some remote sources can report a finished result while the line/FEN is
  // truncated, so require a true terminal position for those sources.
  if (_shareGameNeedsTerminalPosition(game.source)) {
    return analysisState.position.isGameOver;
  }

  return true;
}

bool _isSnapshotAtFinishedSharePosition({
  required GameShareSnapshot snapshot,
  required GamesTourModel game,
}) {
  if (!game.gameStatus.isFinished) return false;

  if (snapshot.currentMoveIndex < 0 ||
      snapshot.currentMoveIndex != snapshot.moveSans.length - 1) {
    return false;
  }

  if (!_shareGameNeedsTerminalPosition(game.source)) {
    return true;
  }

  try {
    return Chess.fromSetup(Setup.parseFen(snapshot.positionFen)).isGameOver;
  } catch (_) {
    return false;
  }
}

class _AppBarState extends ConsumerState<_AppBar> {
  Future<void> _showSaveAnalysisDialog() async {
    final allowed = await requireFullAuthGuard(context);
    if (!allowed) return;

    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.currentGameIndex,
    );
    final boardState = ref.read(chessBoardScreenProviderNew(params));

    if (!boardState.hasValue || boardState.value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please wait for the game to load'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await showSaveAnalysisSheet(
      context: context,
      state: boardState.value!,
      params: params,
    );
  }

  Future<String?> _fetchGamebaseSharePgn(String gameId) async {
    try {
      final gameWithPgn = await ref
          .read(gamebaseRepositoryProvider)
          .getGameWithPgn(gameId);
      if (gameWithPgn == null) return null;

      final built = buildPgnFromGamebaseData(gameWithPgn.data);
      final raw = gameWithPgn.pgn;
      for (final candidate in [built, raw]) {
        final trimmed = candidate?.trim();
        if (trimmed != null && trimmed.isNotEmpty) {
          return trimmed;
        }
      }
    } catch (_) {
      // Best-effort only. The caller falls back to a header-only PGN.
    }
    return null;
  }

  Future<_ResolvedAppBarShareData> _resolveAppBarShareData() async {
    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.currentGameIndex,
    );
    final boardState = ref.read(chessBoardScreenProviderNew(params));
    final state = boardState.valueOrNull;

    final pgn = await resolveGameSharePgn(
      game: widget.game,
      analysisGame: state?.analysisState.game,
      savedAnalysisData: widget.savedAnalysisData,
      fetchSupabasePgn: (gameId) async {
        try {
          return await ref.read(gameRepositoryProvider).getGamePgn(gameId);
        } catch (_) {
          return null;
        }
      },
      fetchGamebasePgn: _fetchGamebaseSharePgn,
    );

    final snapshot = buildGameShareSnapshot(
      game: widget.game,
      pgn: pgn,
      state: state,
    );

    final boardReady = state != null && !state.isLoadingMoves;
    final isAtGameEnd =
        boardReady
            ? _isAnalysisAtFinishedSharePosition(
              analysisState: state.analysisState,
              game: widget.game,
            )
            : _isSnapshotAtFinishedSharePosition(
              snapshot: snapshot,
              game: widget.game,
            );

    return _ResolvedAppBarShareData(
      pgn: pgn,
      shareUrl: buildGameShareUrl(
        game: widget.game,
        savedAnalysisData: widget.savedAnalysisData,
      ),
      snapshot: snapshot,
      evaluation: boardReady ? state.evaluation : null,
      mate: boardReady ? state.mate ?? 0 : 0,
      isFlipped: boardReady ? state.isBoardFlipped : false,
      isAtGameEnd: isAtGameEnd,
    );
  }

  void copyPgnBtnClicked() async {
    try {
      final resolved = await _resolveAppBarShareData();
      if (resolved.pgn.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No PGN available for this game',
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            backgroundColor: context.colors.surface.withValues(alpha: 0.95),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: resolved.pgn));
      HapticFeedback.lightImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'PGN copied to clipboard',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to copy PGN',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void shareGameBtnClicked() async {
    try {
      final resolved = await _resolveAppBarShareData();
      if (!mounted) return;
      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierDismissible: true,
          barrierColor: Colors.transparent,
          pageBuilder:
              (context, animation, secondaryAnimation) =>
                  _ShareGameScreen(game: widget.game, shareData: resolved),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to prepare game share',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showEventInfoSheet(BuildContext context, WidgetRef ref, String? pgn) {
    // On tablets, use custom barrier with timing guard to prevent phantom tap dismissals
    // while still allowing intentional taps to dismiss after a delay.
    if (ResponsiveHelper.isTablet) {
      _ChessBoardPopupState.markOpen();
      final openedAt = DateTime.now();
      const minOpenDuration = Duration(milliseconds: 600);

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        constraints: ResponsiveHelper.bottomSheetConstraints,
        isDismissible: false, // We handle dismissal ourselves with timing guard
        enableDrag: true,
        builder:
            (sheetContext) => _TabletSafeBottomSheet(
              openedAt: openedAt,
              minOpenDuration: minOpenDuration,
              child: _EventInfoSheet(game: widget.game, pgn: pgn),
            ),
      ).then((_) {
        _ChessBoardPopupState.markClosed();
      });
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        constraints: ResponsiveHelper.bottomSheetConstraints,
        builder: (context) => _EventInfoSheet(game: widget.game, pgn: pgn),
      );
    }
  }

  Widget _buildSaveButton() {
    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.currentGameIndex,
    );

    // Watch autoSaveStatus — this also triggers rebuilds after
    // attachSavedAnalysisId emits AutoSaveStatus.saved.
    final autoSaveStatus = ref.watch(
      chessBoardScreenProviderNew(params).select(
        (state) => state.valueOrNull?.autoSaveStatus ?? AutoSaveStatus.idle,
      ),
    );

    final anchor = ref.read(likeFlightAnchorProvider);
    final isLiked = ref.watch(isGameLikedProvider(widget.game.likeId));

    return ValueListenableBuilder<LikeFlightPhase>(
      valueListenable: anchor.phase,
      builder: (context, phase, __) {
        // Inner save-state icon: idle disk / saving spinner / saved check.
        // Each variant carries a stable ValueKey so AnimatedSwitcher knows
        // they're distinct children and crossfades+scales between them
        // instead of hard-swapping. Removes the flicker that used to make
        // save → saved → idle feel like three separate icons.
        final Widget innerIcon;
        switch (autoSaveStatus) {
          case AutoSaveStatus.saving:
            innerIcon = SizedBox(
              key: const ValueKey('save-spinner'),
              width: 20.sp,
              height: 20.sp,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(
                  context.colors.textPrimary.withValues(alpha: 0.7),
                ),
              ),
            );
            break;
          case AutoSaveStatus.saved:
            innerIcon = Icon(
              Icons.check_circle_outline_rounded,
              key: const ValueKey('save-check'),
              color: kPrimaryColor,
              size: 20.sp,
            );
            break;
          case AutoSaveStatus.idle:
            innerIcon = Icon(
              Icons.save_outlined,
              key: const ValueKey('save-disk'),
              color: context.colors.textPrimary,
              size: 20.sp,
            );
            break;
        }

        final animatedInner = AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.7, end: 1.0).animate(animation),
                child: child,
              ),
            );
          },
          child: innerIcon,
        );

        // Heart badge fades + scales in/out smoothly when isLiked toggles.
        // The outer scale uses Curves.easeOutBack so the badge sticks the
        // landing with a tiny overshoot — same physics feel the flying
        // heart had, no hard pop at the end of the flight.
        //
        // While a like flight is in progress (bursting/flying) the badge is
        // kept hidden so the big flying heart is the ONLY heart on screen —
        // no "two hearts" overlap. The flying heart docks onto this badge's
        // exact rect, then on `landed` the badge appears INSTANTLY
        // (Duration.zero) so the docked-heart → badge handoff is seamless
        // (same glyph, same size, same spot). The optimistic `isLiked` flips
        // true early, so gating on phase is what keeps the badge hidden until
        // the flying heart actually arrives.
        final inFlight = phase == LikeFlightPhase.bursting ||
            phase == LikeFlightPhase.flying;
        final justLanded = phase == LikeFlightPhase.landed;
        final showBadge = isLiked && !inFlight;
        final heartBadge = AnimatedScale(
          scale: showBadge ? 1.0 : 0.0,
          duration:
              justLanded ? Duration.zero : const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: showBadge ? 1.0 : 0.0,
            duration:
                justLanded ? Duration.zero : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Icon(
              Icons.favorite_rounded,
              size: 11.sp,
              color: context.colors.danger,
            ),
          ),
        );

        final stack = Stack(
          clipBehavior: Clip.none,
          children: [
            animatedInner,
            Positioned(
              right: -4.sp,
              bottom: -4.sp,
              // Key sits ABOVE the AnimatedScale on purpose: the badge is
              // scaled to 0 while hidden during flight, and a key INSIDE the
              // scale would have `localToGlobal` collapse to the transform
              // origin (scale-0 maps every child point to center), giving the
              // flight a wrong dock target. Measuring the un-transformed box
              // here yields the badge's true rect even while it's invisible.
              child: KeyedSubtree(
                key: anchor.heartBadgeKey,
                child: heartBadge,
              ),
            ),
          ],
        );

        // When the heart just landed, give the whole slot a one-shot pulse
        // so the badge's arrival reads as a continuation of the flight
        // instead of a sudden appearance. The const ValueKey keeps the
        // Animate state alive across rebuilds inside the same `landed`
        // window so the pulse runs once, not on every rebuild.
        final landed = phase == LikeFlightPhase.landed;
        final pulsing = landed
            ? stack
                .animate(key: const ValueKey('save-button-landed-pulse'))
                .scaleXY(
                  begin: 1.28,
                  end: 1.0,
                  duration: 360.ms,
                  curve: Curves.easeOutBack,
                )
            : stack;

        // Header action stays the save icon at all times — a double-tap
        // like is represented only by the small red badge above. The
        // flight phase still uses the keyed slot as its target.
        return IconButton(
          icon: KeyedSubtree(key: anchor.saveButtonKey, child: pulsing),
          tooltip: 'Save analysis',
          onPressed: widget.isLoading ? null : _showSaveAnalysisDialog,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch the board state for PGN data
    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.currentGameIndex,
    );
    final infoSheetPgn =
        ref.watch(
          chessBoardScreenProviderNew(
            params,
          ).select((state) => state.valueOrNull?.pgnData),
        ) ??
        widget.game.pgn;

    // Debug: Log when AppBar rebuilds on tablets while popup is open
    if (ResponsiveHelper.isTablet && _ChessBoardPopupState.isAnyPopupOpen) {
      debugPrint(
        '⚠️ TABLET APPBAR REBUILD while popup open: gameIndex=${widget.currentGameIndex}',
      );
    }

    return AppBar(
      elevation: 0,
      backgroundColor: context.colors.background,
      surfaceTintColor: context.colors.background,
      leadingWidth: 44.sp,
      titleSpacing: 4.sp,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new,
          color: context.colors.textPrimary,
          size: 20.sp,
        ),
        onPressed: () => Navigator.pop(context, widget.lastViewedIndex),
      ),
      title:
          widget.hideEventInfo
              ? Text(
                'Analysis Board',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
              )
              : _GameSelectionDropdown(
                key: e2eKey(E2eIds.boardGameSelector),
                games: widget.games,
                currentGameIndex: widget.currentGameIndex,
                onGameChanged: widget.onGameChanged,
                isLoading: widget.isLoading,
              ),
      actions: [
        SizedBox(width: 4.sp),
        // Event info button (hidden when navigating from library for position analysis)
        // Uses delayed show on tablets to prevent phantom tap dismissals
        if (!widget.hideEventInfo)
          IconButton(
            icon: Icon(
              Icons.info_outline_rounded,
              color: context.colors.textPrimary,
              size: 20.sp,
            ),
            tooltip: 'Event info',
            onPressed:
                widget.isLoading
                    ? null
                    : () => _showEventInfoSheet(context, ref, infoSheetPgn),
          ),
        // Save Analysis button — with auto-save status animation for library games
        _buildSaveButton(),
        // 3-dot menu - use tablet-safe overlay popup on tablets to prevent
        // phantom tap dismissals, use standard PopupMenuButton on mobile
        if (ResponsiveHelper.isTablet)
          _TabletSafePopupMenu<String>(
            icon: Icon(
              Icons.more_vert,
              color: context.colors.textPrimary,
              size: 22.sp,
            ),
            enabled: !widget.isLoading,
            onSelected: (value) async {
              if (value == 'share') {
                shareGameBtnClicked();
              } else if (value == 'board_settings') {
                final allowed = await requireFullAuthGuard(context);
                if (!allowed) return;
                if (!context.mounted) return;
                Navigator.of(context).push(
                  SettingsPage.route(initiallyExpanded: SettingsSection.board),
                );
              } else if (value == 'clear_analysis') {
                final params = ChessBoardProviderParams(
                  game: widget.game,
                  index: widget.currentGameIndex,
                );
                final boardState = ref.read(
                  chessBoardScreenProviderNew(params),
                );
                final analysisGame = boardState.valueOrNull?.analysisState.game;
                final hasCustomAnalysis = _gameHasCustomVariations(
                  analysisGame,
                );

                if (!hasCustomAnalysis) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('No custom analysis to clear'),
                      backgroundColor: Colors.orange,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                HapticFeedback.selectionClick();
                final confirmed =
                    await _showAnalysisConfirmationDialog(
                      context: context,
                      title: 'Clear analysis?',
                      message:
                          'This will remove every custom branch, including nested subvariants. This action cannot be undone.',
                      confirmLabel: 'Clear',
                      confirmColor: kRedColor,
                    ) ??
                    false;
                if (!confirmed) return;
                HapticFeedback.heavyImpact();
                final notifier = ref.read(
                  chessBoardScreenProviderNew(params).notifier,
                );
                await notifier.clearUserAnalysis();
              }
            },
            itemBuilder:
                (context) => [
                  PopupMenuItem(
                    value: 'board_settings',
                    child: Row(
                      children: [
                        Icon(Icons.settings, color: context.colors.textPrimary),
                        SizedBox(width: 8.w),
                        const Text('Board Settings'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share, color: context.colors.textPrimary),
                        SizedBox(width: 8.w),
                        const Text('Share Game'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    onTap: () {
                      copyPgnBtnClicked();
                    },
                    value: 'copy_pgn',
                    child: Row(
                      children: [
                        Icon(Icons.copy, color: context.colors.textPrimary),
                        SizedBox(width: 8.w),
                        const Text('Copy PGN'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'clear_analysis',
                    child: Row(
                      children: [
                        Icon(Icons.auto_delete_outlined, color: kRedColor),
                        SizedBox(width: 8.w),
                        const Text(
                          'Clear Analysis',
                          style: TextStyle(color: kRedColor),
                        ),
                      ],
                    ),
                  ),
                ],
          )
        else
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: context.colors.textPrimary,
              size: 22.sp,
            ),
            enabled: !widget.isLoading,
            onSelected: (value) async {
              if (value == 'share') {
                shareGameBtnClicked();
              } else if (value == 'board_settings') {
                final allowed = await requireFullAuthGuard(context);
                if (!allowed) return;
                if (!context.mounted) return;
                Navigator.of(context).push(
                  SettingsPage.route(initiallyExpanded: SettingsSection.board),
                );
              } else if (value == 'clear_analysis') {
                final params = ChessBoardProviderParams(
                  game: widget.game,
                  index: widget.currentGameIndex,
                );
                final boardState = ref.read(
                  chessBoardScreenProviderNew(params),
                );
                final analysisGame = boardState.valueOrNull?.analysisState.game;
                final hasCustomAnalysis = _gameHasCustomVariations(
                  analysisGame,
                );

                if (!hasCustomAnalysis) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('No custom analysis to clear'),
                      backgroundColor: Colors.orange,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                HapticFeedback.selectionClick();
                final confirmed =
                    await _showAnalysisConfirmationDialog(
                      context: context,
                      title: 'Clear analysis?',
                      message:
                          'This will remove every custom branch, including nested subvariants. This action cannot be undone.',
                      confirmLabel: 'Clear',
                      confirmColor: kRedColor,
                    ) ??
                    false;
                if (!confirmed) return;
                HapticFeedback.heavyImpact();
                final notifier = ref.read(
                  chessBoardScreenProviderNew(params).notifier,
                );
                await notifier.clearUserAnalysis();
              }
            },
            itemBuilder:
                (context) => [
                  PopupMenuItem(
                    value: 'board_settings',
                    child: Row(
                      children: [
                        Icon(Icons.settings, color: context.colors.textPrimary),
                        SizedBox(width: 8.w),
                        const Text('Board Settings'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share, color: context.colors.textPrimary),
                        SizedBox(width: 8.w),
                        const Text('Share Game'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    onTap: () {
                      copyPgnBtnClicked();
                    },
                    value: 'copy_pgn',
                    child: Row(
                      children: [
                        Icon(Icons.copy, color: context.colors.textPrimary),
                        SizedBox(width: 8.w),
                        const Text('Copy PGN'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'clear_analysis',
                    child: Row(
                      children: [
                        Icon(Icons.auto_delete_outlined, color: kRedColor),
                        SizedBox(width: 8.w),
                        const Text(
                          'Clear Analysis',
                          style: TextStyle(color: kRedColor),
                        ),
                      ],
                    ),
                  ),
                ],
          ),
        SizedBox(width: 4.sp),
      ],
    );
  }
}

/// Tablet-safe popup menu that uses an overlay instead of Flutter's route-based
/// popup to prevent phantom tap dismissals on tablets.
/// This provides the same timing guard protection as _GameSelectionDropdown.
class _TabletSafePopupMenu<T> extends StatefulWidget {
  final Widget icon;
  final List<PopupMenuEntry<T>> Function(BuildContext) itemBuilder;
  final void Function(T)? onSelected;
  final bool enabled;

  const _TabletSafePopupMenu({
    required this.icon,
    required this.itemBuilder,
    this.onSelected,
    this.enabled = true,
  });

  @override
  State<_TabletSafePopupMenu<T>> createState() =>
      _TabletSafePopupMenuState<T>();
}

class _TabletSafePopupMenuState<T> extends State<_TabletSafePopupMenu<T>>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _isOpen = false;
  OverlayEntry? _overlayEntry;
  DateTime? _openedAt;
  static const _minOpenDuration = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _animationController.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    try {
      _overlayEntry?.remove();
    } catch (_) {}
    _overlayEntry = null;
  }

  bool _canDismiss() {
    if (_openedAt == null) return true;
    final elapsed = DateTime.now().difference(_openedAt!);
    if (elapsed < _minOpenDuration) {
      debugPrint(
        '🛡️ TABLET POPUP: _canDismiss() returning false, elapsed=${elapsed.inMilliseconds}ms',
      );
      return false;
    }
    return true;
  }

  void _openMenu() {
    if (!widget.enabled || _isOpen) return;

    HapticFeedback.selectionClick();
    _openedAt = DateTime.now();
    _ChessBoardPopupState.markOpen();

    debugPrint('📂 TABLET POPUP OPENED: time=${_openedAt}');

    setState(() => _isOpen = true);
    _showOverlay();
    _animationController.forward();
  }

  void _closeMenu({bool force = false}) {
    if (!_isOpen) return;

    final elapsed =
        _openedAt != null
            ? DateTime.now().difference(_openedAt!)
            : Duration.zero;
    debugPrint(
      '📕 TABLET POPUP _closeMenu called: force=$force, elapsed=${elapsed.inMilliseconds}ms',
    );

    if (!force && !_canDismiss()) {
      debugPrint('🛡️ TABLET POPUP dismiss blocked - opened too recently');
      return;
    }

    debugPrint('📕 TABLET POPUP CLOSING: proceeding with close');

    _openedAt = null;
    _ChessBoardPopupState.markClosed();
    _animationController.reverse().then((_) {
      if (mounted) {
        setState(() => _isOpen = false);
        _removeOverlay();
      }
    });
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenWidth = MediaQuery.of(context).size.width;

    // Build menu items
    final items = widget.itemBuilder(context);

    _overlayEntry = OverlayEntry(
      builder:
          (context) => Stack(
            children: [
              // Barrier with timing guard
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    debugPrint(
                      '🔲 TABLET POPUP BARRIER TAP: calling _closeMenu',
                    );
                    _closeMenu();
                  },
                  onHorizontalDragStart: (_) {},
                  onHorizontalDragUpdate: (_) {},
                  onHorizontalDragEnd: (_) {},
                  child: Container(color: Colors.black.withValues(alpha: 0.01)),
                ),
              ),
              // Menu positioned near the trigger
              Positioned(
                // Position to the left of the button, aligned to top
                right: screenWidth - offset.dx - size.width,
                top: offset.dy + size.height + 4,
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    final progress = _animation.value.clamp(0.0, 1.0);
                    return Transform.scale(
                      scale: 0.92 + (progress * 0.08),
                      alignment: Alignment.topRight,
                      child: Opacity(opacity: progress, child: child),
                    );
                  },
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    color: context.colors.surfaceRecessed,
                    child: IntrinsicWidth(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children:
                            items.map((item) {
                              if (item is PopupMenuItem<T>) {
                                return InkWell(
                                  onTap: () {
                                    _closeMenu(force: true);
                                    if (item.onTap != null) {
                                      item.onTap!();
                                    }
                                    if (item.value != null &&
                                        widget.onSelected != null) {
                                      widget.onSelected!(item.value as T);
                                    }
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 16.w,
                                      vertical: 12.h,
                                    ),
                                    child: item.child,
                                  ),
                                );
                              } else if (item is PopupMenuDivider) {
                                return Divider(
                                  height: 1,
                                  color: context.colors.textPrimary.withValues(
                                    alpha: 0.1,
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
    );

    overlay.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: IconButton(
        icon: widget.icon,
        onPressed: widget.enabled ? _openMenu : null,
      ),
    );
  }
}

/// Wrapper for bottom sheets on tablets that adds a timing-guarded barrier.
/// This prevents phantom tap dismissals while still allowing intentional taps
/// to dismiss the sheet after a delay.
class _TabletSafeBottomSheet extends StatelessWidget {
  final Widget child;
  final DateTime openedAt;
  final Duration minOpenDuration;

  const _TabletSafeBottomSheet({
    required this.child,
    required this.openedAt,
    required this.minOpenDuration,
  });

  bool _canDismiss() {
    final elapsed = DateTime.now().difference(openedAt);
    return elapsed >= minOpenDuration;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Custom barrier with timing guard - positioned behind the sheet
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_canDismiss()) {
                Navigator.of(context).pop();
              } else {
                debugPrint(
                  '🛡️ TABLET SHEET: barrier tap blocked - opened too recently',
                );
              }
            },
            child: Container(color: Colors.transparent),
          ),
        ),
        // The actual bottom sheet content
        Align(alignment: Alignment.bottomCenter, child: child),
      ],
    );
  }
}

/// Wrapper widget that absorbs horizontal drag gestures on tablets to prevent
/// PageView interference from closing popup menus prematurely.
/// On mobile, this is a pass-through (returns child directly).
/// Also tracks popup open/close state globally to defer rebuilds.
class _TabletPopupMenuWrapper extends StatefulWidget {
  final Widget child;

  const _TabletPopupMenuWrapper({required this.child});

  @override
  State<_TabletPopupMenuWrapper> createState() =>
      _TabletPopupMenuWrapperState();
}

class _TabletPopupMenuWrapperState extends State<_TabletPopupMenuWrapper>
    with WidgetsBindingObserver {
  bool _wasPopupOpen = false;

  @override
  void initState() {
    super.initState();
    if (ResponsiveHelper.isTablet) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void dispose() {
    if (ResponsiveHelper.isTablet) {
      WidgetsBinding.instance.removeObserver(this);
      // Clean up if we had marked a popup as open
      if (_wasPopupOpen) {
        _ChessBoardPopupState.markClosed();
      }
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Popup routes can change metrics; this helps track popup state
  }

  @override
  Widget build(BuildContext context) {
    if (!ResponsiveHelper.isTablet) {
      return widget.child;
    }

    // On tablets, wrap in:
    // 1. Listener to track taps without consuming them
    // 2. GestureDetector to absorb horizontal drags
    return Listener(
      onPointerDown: (_) {
        // When pointer goes down, mark that a popup might be opening
        // This helps protect against immediate rebuilds
        _ChessBoardPopupState.markOpen();
        _wasPopupOpen = true;

        // Schedule cleanup after a delay - gives time for popup to actually open
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted && _wasPopupOpen) {
            // Check if there's still an open popup route
            final navigator = Navigator.of(context, rootNavigator: true);
            final hasPopupRoute = navigator.canPop();
            debugPrint(
              '🕐 TABLET WRAPPER CLEANUP: hasPopupRoute=$hasPopupRoute, isAnyPopupOpen=${_ChessBoardPopupState.isAnyPopupOpen}',
            );
            if (!hasPopupRoute && !_ChessBoardPopupState.isAnyPopupOpen) {
              debugPrint('🕐 TABLET WRAPPER: Resetting popup state');
              _wasPopupOpen = false;
              // Don't reset global state here - let the dropdown/popup handle it
              // _ChessBoardPopupState.markClosed();
            }
          }
        });
      },
      behavior: HitTestBehavior.translucent,
      child: GestureDetector(
        onHorizontalDragStart: (_) {},
        onHorizontalDragUpdate: (_) {},
        onHorizontalDragEnd: (_) {},
        behavior: HitTestBehavior.translucent,
        child: widget.child,
      ),
    );
  }
}

/// Beautiful stadium-chip style game selection dropdown with glass morphism
/// and smooth spring animations - matching CategoryDropdown design language
class _GameSelectionDropdown extends StatefulWidget {
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final void Function(int) onGameChanged;
  final bool isLoading;

  const _GameSelectionDropdown({
    super.key,
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
    this.isLoading = false,
  });

  @override
  State<_GameSelectionDropdown> createState() => _GameSelectionDropdownState();
}

class _GameSelectionDropdownState extends State<_GameSelectionDropdown>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _isOpen = false;
  OverlayEntry? _overlayEntry;

  // Timestamp when dropdown was opened - used to prevent immediate dismissal
  // on tablets where gesture/rebuild timing can cause unwanted closes
  DateTime? _openedAt;

  // Minimum time dropdown must stay open before allowing dismissal (tablet only)
  static const _minOpenDuration = Duration(milliseconds: 500);

  // Track unique open ID to detect stale close attempts
  int _openId = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void deactivate() {
    // Called when widget is removed from tree (before dispose)
    if (_isOpen && ResponsiveHelper.isTablet) {
      debugPrint(
        '🚨 TABLET DROPDOWN: deactivate() called while open! Stack trace:',
      );
      debugPrint(StackTrace.current.toString().split('\n').take(10).join('\n'));
    }
    super.deactivate();
  }

  @override
  void dispose() {
    // Log when dispose is called while dropdown is open - this is the likely culprit
    if (_isOpen && ResponsiveHelper.isTablet) {
      debugPrint(
        '🚨 TABLET DROPDOWN: dispose() called while open! This is likely the bug.',
      );
      debugPrint('🚨 Stack trace:');
      debugPrint(StackTrace.current.toString().split('\n').take(15).join('\n'));
    }
    _removeOverlay();
    _animationController.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    if (_isOpen && ResponsiveHelper.isTablet) {
      debugPrint('🔴 TABLET: _removeOverlay() called while _isOpen=true');
    }
    try {
      _overlayEntry?.remove();
    } catch (_) {}
    _overlayEntry = null;
  }

  /// Check if enough time has passed since opening to allow dismissal.
  /// On tablets, we need this guard to prevent rebuilds from causing
  /// immediate unwanted dismissals.
  bool _canDismiss() {
    if (!ResponsiveHelper.isTablet) return true;
    if (_openedAt == null) return true;
    final elapsed = DateTime.now().difference(_openedAt!);
    final canDismiss = elapsed >= _minOpenDuration;
    if (!canDismiss) {
      debugPrint(
        '🛡️ TABLET: _canDismiss() returning false, elapsed=${elapsed.inMilliseconds}ms',
      );
    }
    return canDismiss;
  }

  String _formatName(String fullName, {double? maxWidth}) {
    List<String> nameParts =
        fullName.trim().split(' ').where((part) => part.isNotEmpty).toList();
    if (nameParts.length <= 1) return fullName;

    String familyName = nameParts.last;
    List<String> otherNames = nameParts.sublist(0, nameParts.length - 1);
    String fullVersion = '${otherNames.join(' ')} $familyName';

    if (maxWidth == null) return fullVersion;

    double estimatedWidth = fullVersion.length * 6.0;
    if (estimatedWidth <= maxWidth) return fullVersion;

    List<String> displayNames = List.from(otherNames);
    for (int i = 0; i < displayNames.length; i++) {
      if (displayNames[i].length > 1) {
        displayNames[i] = '${displayNames[i][0]}.';
        String newVersion = '${displayNames.join(' ')} $familyName';
        double newEstimatedWidth = newVersion.length * 6.0;
        if (newEstimatedWidth <= maxWidth) {
          return newVersion;
        }
      }
    }
    return '${displayNames.join(' ')} $familyName';
  }

  String _extractLastName(String fullName) {
    final name = fullName.trim();
    if (name.isEmpty) return fullName;

    // Handle "LastName, FirstName" format (common in chess)
    if (name.contains(',')) {
      final lastName = name.split(',').first.trim();
      if (lastName.isNotEmpty) return lastName;
    }

    // Suffixes to ignore when finding last name
    const suffixes = {
      'jr',
      'jr.',
      'sr',
      'sr.',
      'ii',
      'iii',
      'iv',
      'v',
      '2nd',
      '3rd',
      '4th',
      '5th',
    };

    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return fullName;
    if (parts.length == 1) return parts.first;

    // Find the last part that isn't a suffix
    for (int i = parts.length - 1; i >= 0; i--) {
      if (!suffixes.contains(parts[i].toLowerCase())) {
        return parts[i];
      }
    }

    return parts.last;
  }

  void _openDropdown() {
    if (widget.games.length <= 1 || widget.isLoading || _isOpen) return;

    HapticFeedback.selectionClick();
    _openId++; // Increment to invalidate any pending close attempts
    final currentOpenId = _openId;
    _openedAt = DateTime.now(); // Track when opened for dismiss protection
    _ChessBoardPopupState.markOpen(); // Mark globally that a popup is open

    if (ResponsiveHelper.isTablet) {
      debugPrint(
        '📂 TABLET DROPDOWN OPENED: openId=$currentOpenId, time=${_openedAt}',
      );
    }

    setState(() => _isOpen = true);
    _showOverlay();
    _animationController.forward();
  }

  void _closeDropdown({bool force = false}) {
    if (!_isOpen) return;

    final elapsed =
        _openedAt != null
            ? DateTime.now().difference(_openedAt!)
            : Duration.zero;

    if (ResponsiveHelper.isTablet) {
      debugPrint(
        '📕 TABLET DROPDOWN _closeDropdown called: force=$force, elapsed=${elapsed.inMilliseconds}ms, openId=$_openId',
      );
      debugPrint('📕 Stack trace (first 8 lines):');
      debugPrint(StackTrace.current.toString().split('\n').take(8).join('\n'));
    }

    // On tablets, prevent immediate dismissal to guard against
    // gesture/rebuild timing issues causing unwanted closes
    if (!force && !_canDismiss()) {
      debugPrint(
        '🛡️ Dropdown dismiss blocked - opened too recently (${elapsed.inMilliseconds}ms < ${_minOpenDuration.inMilliseconds}ms)',
      );
      return;
    }

    if (ResponsiveHelper.isTablet) {
      debugPrint('📕 TABLET DROPDOWN CLOSING: proceeding with close');
    }

    _openedAt = null;
    _ChessBoardPopupState.markClosed(); // Mark globally that popup is closed
    _animationController.reverse().then((_) {
      if (mounted) {
        setState(() => _isOpen = false);
        _removeOverlay();
      }
    });
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final availableHeight = screenHeight - offset.dy - size.height - 32.sp;

    _overlayEntry = OverlayEntry(
      builder:
          (context) => _GameDropdownOverlay(
            layerLink: _layerLink,
            triggerSize: size,
            triggerOffset: offset,
            screenWidth: screenWidth,
            availableHeight: availableHeight,
            animation: _animation,
            games: widget.games,
            currentGameIndex: widget.currentGameIndex,
            isLoading: widget.isLoading,
            onSelect: (selectedIndex) {
              debugPrint(
                '🎯 Dropdown onSelect: selectedIndex=$selectedIndex, currentGameIndex=${widget.currentGameIndex}',
              );
              HapticFeedback.selectionClick();
              if (selectedIndex >= 0 &&
                  selectedIndex < widget.games.length &&
                  selectedIndex != widget.currentGameIndex) {
                debugPrint(
                  '🎯 Calling onGameChanged with index: $selectedIndex',
                );
                widget.onGameChanged(selectedIndex);
              } else {
                debugPrint(
                  '🎯 Skipping navigation - same game or invalid index',
                );
              }
              _closeDropdown(force: true); // User intentionally selected
            },
            onDismiss: _closeDropdown, // Guarded by _canDismiss()
          ),
    );

    overlay.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.games.isEmpty) return const SizedBox.shrink();

    // Debug: Log when dropdown widget rebuilds while open
    if (ResponsiveHelper.isTablet && _isOpen) {
      debugPrint(
        '🔄 TABLET DROPDOWN REBUILD while open: _isOpen=$_isOpen, openId=$_openId',
      );
    }

    final currentGame = widget.games[widget.currentGameIndex];
    final displayText =
        '${_extractLastName(currentGame.whitePlayer.displayName)} vs ${_extractLastName(currentGame.blackPlayer.displayName)}';

    return CompositedTransformTarget(
      link: _layerLink,
      child: _GameChipButton(
        label: displayText,
        gameStatus: currentGame.gameStatus,
        isOpen: _isOpen,
        isLoading: widget.isLoading,
        showChevron: widget.games.length > 1,
        onTap: () {
          if (_isOpen) {
            _closeDropdown(force: true); // User intentionally tapped to close
          } else {
            _openDropdown();
          }
        },
      ),
    );
  }
}

/// Stadium-shaped chip button for game selection trigger
class _GameChipButton extends StatelessWidget {
  final String label;
  final GameStatus gameStatus;
  final bool isOpen;
  final bool isLoading;
  final bool showChevron;
  final VoidCallback? onTap;

  const _GameChipButton({
    required this.label,
    required this.gameStatus,
    required this.isOpen,
    this.onTap,
    this.isLoading = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 6.sp),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100.br),
          color:
              isOpen
                  ? kPrimaryColor.withValues(alpha: 0.15)
                  : context.colors.textPrimary.withValues(alpha: 0.06),
          border: Border.all(
            color:
                isOpen
                    ? kPrimaryColor.withValues(alpha: 0.4)
                    : context.colors.textPrimary.withValues(alpha: 0.12),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status indicator
            _GameStatusIndicator(status: gameStatus, isLoading: isLoading),
            SizedBox(width: 6.sp),
            // Game label - centered, flexible to allow truncation
            Flexible(
              child: Text(
                label,
                style: AppTypography.textXsMedium.copyWith(
                  color: isOpen ? kPrimaryColor : context.colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            // Chevron
            if (showChevron) ...[
              SizedBox(width: 4.sp),
              AnimatedRotation(
                turns: isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color:
                      isOpen
                          ? kPrimaryColor
                          : context.colors.textPrimary.withValues(alpha: 0.7),
                  size: 16.ic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Game status indicator with live pulsing animation
class _GameStatusIndicator extends StatelessWidget {
  final GameStatus status;
  final bool isLoading;

  const _GameStatusIndicator({required this.status, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        width: 10.sp,
        height: 10.sp,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: kPrimaryColor,
        ),
      );
    }

    final color = _getStatusColor(context);
    final isLive = status == GameStatus.ongoing;

    return Container(
      width: 8.sp,
      height: 8.sp,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        // Flat design - no glow/shadow
      ),
      child: isLive ? _LivePulsingDot(color: color) : null,
    );
  }

  Color _getStatusColor(BuildContext context) {
    switch (status) {
      case GameStatus.ongoing:
        return kPrimaryColor;
      case GameStatus.whiteWins:
      case GameStatus.blackWins:
      case GameStatus.draw:
        return context.colors.textPrimaryMuted;
      case GameStatus.unknown:
        return context.colors.textPrimaryMuted;
    }
  }
}

/// Pulsing animation for live/ongoing games
class _LivePulsingDot extends StatefulWidget {
  final Color color;

  const _LivePulsingDot({required this.color});

  @override
  State<_LivePulsingDot> createState() => _LivePulsingDotState();
}

class _LivePulsingDotState extends State<_LivePulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 1 - _controller.value * 0.5),
          ),
        );
      },
    );
  }
}

/// The floating dropdown overlay with glass morphism
class _GameDropdownOverlay extends StatelessWidget {
  final LayerLink layerLink;
  final Size triggerSize;
  final Offset triggerOffset;
  final double screenWidth;
  final double availableHeight;
  final Animation<double> animation;
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final bool isLoading;
  final ValueChanged<int> onSelect;
  final VoidCallback onDismiss;

  const _GameDropdownOverlay({
    required this.layerLink,
    required this.triggerSize,
    required this.triggerOffset,
    required this.screenWidth,
    required this.availableHeight,
    required this.animation,
    required this.games,
    required this.currentGameIndex,
    required this.isLoading,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final dropdownWidth = (screenWidth - 32.w).clamp(280.w, 340.w);
    final leftOffset = (screenWidth - dropdownWidth) / 2;
    final isTablet = ResponsiveHelper.isTablet;

    // On tablets, we need to be more careful about gesture handling.
    // The PageView underneath can compete for gestures, causing the dropdown
    // to dismiss unexpectedly. We use a more robust barrier approach.
    Widget buildBarrier() {
      if (isTablet) {
        // On tablets, use opaque behavior to ensure we catch ALL taps on the barrier.
        // The deferToChild behavior was allowing taps to pass through the transparent
        // container, potentially causing unexpected dismissals.
        // Also absorb horizontal drags to prevent PageView from competing for gestures.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            debugPrint('🔲 TABLET BARRIER TAP: calling onDismiss');
            onDismiss();
          },
          // Absorb horizontal drags on tablets to prevent PageView from
          // competing for gestures, which can cause premature dismissal.
          onHorizontalDragStart: (_) {
            debugPrint('🔲 TABLET BARRIER: horizontal drag absorbed');
          },
          onHorizontalDragUpdate: (_) {},
          onHorizontalDragEnd: (_) {},
          child: Container(
            color: Colors.black.withOpacity(0.01),
          ), // Slightly visible for hit testing
        );
      }
      // On mobile, simple transparent barrier works fine
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Container(color: Colors.transparent),
      );
    }

    return Stack(
      children: [
        Positioned.fill(child: buildBarrier()),
        Positioned(
          left: leftOffset,
          top: triggerOffset.dy + triggerSize.height + 8.sp,
          child: Material(
            type: MaterialType.transparency,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final progress = animation.value.clamp(0.0, 1.0);
                return Transform.scale(
                  scale: 0.92 + (progress * 0.08),
                  alignment: Alignment.topCenter,
                  child: Opacity(opacity: progress, child: child),
                );
              },
              child: GestureDetector(
                // Block taps from reaching the dismiss handler
                onTap: () {},
                // Also absorb horizontal drags on tablets to prevent any
                // gesture leakage to the PageView
                onHorizontalDragStart: isTablet ? (_) {} : null,
                onHorizontalDragUpdate: isTablet ? (_) {} : null,
                onHorizontalDragEnd: isTablet ? (_) {} : null,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: dropdownWidth,
                  constraints: BoxConstraints(
                    maxHeight: availableHeight.clamp(180.0, 380.0),
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(16.br),
                    border: Border.all(
                      color: context.colors.textPrimary.withValues(alpha: 0.08),
                      width: 1.0,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.br),
                    child: _GameDropdownContent(
                      dropdownWidth: dropdownWidth,
                      availableHeight: availableHeight,
                      animation: animation,
                      games: games,
                      currentGameIndex: currentGameIndex,
                      isLoading: isLoading,
                      onSelect: onSelect,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Minimal dropdown content with round section separators
class _GameDropdownContent extends StatefulWidget {
  final double dropdownWidth;
  final double availableHeight;
  final Animation<double> animation;
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final bool isLoading;
  final ValueChanged<int> onSelect;

  const _GameDropdownContent({
    required this.dropdownWidth,
    required this.availableHeight,
    required this.animation,
    required this.games,
    required this.currentGameIndex,
    required this.isLoading,
    required this.onSelect,
  });

  @override
  State<_GameDropdownContent> createState() => _GameDropdownContentState();
}

class _GameDropdownContentState extends State<_GameDropdownContent> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  final List<GlobalKey> _itemKeys = [];

  bool _isDragging = false;
  int _currentIndex = 0;
  double _targetY = 0.0;

  // Item metrics (measured after layout)
  double _itemHeight = 36.0;
  double _itemStride = 38.0; // height + spacing between rows
  double _itemBaseTop = 6.0; // accounts for list padding/margins
  double get _totalItemHeight => _itemStride;
  static const double _indicatorInset = 2.0;

  // Track if pointer started on the selector
  bool _pointerStartedOnSelector = false;
  Offset? _lastPointerPosition;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentGameIndex;
    _targetY = _itemBaseTop + _currentIndex * _totalItemHeight;

    // Scroll to center the current game after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureMetrics();
      _scrollToCenter();
    });
  }

  @override
  void didUpdateWidget(covariant _GameDropdownContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.games.isEmpty) return;
    if (oldWidget.currentGameIndex != widget.currentGameIndex ||
        oldWidget.games.length != widget.games.length) {
      _currentIndex = widget.currentGameIndex.clamp(0, widget.games.length - 1);
      _targetY = _getTargetY(_currentIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _measureMetrics();
        _scrollToCenter();
      });
    }
  }

  /// Scrolls the list to center the current game in the visible area
  void _scrollToCenter() {
    if (!_scrollController.hasClients) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // Calculate the scroll offset to center the current item
    // Item's center position minus half the viewport height
    final itemCenter = _targetY + (_itemHeight / 2);
    final targetScroll = itemCenter - (viewportHeight / 2);

    // Clamp to valid scroll range
    final clampedScroll = targetScroll.clamp(0.0, maxScroll);

    _scrollController.jumpTo(clampedScroll);
  }

  void _measureMetrics() {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return;

    final scrollAtMeasure =
        _scrollController.hasClients ? _scrollController.offset : 0.0;

    double? itemHeight;
    double? firstTop;
    double? secondTop;

    if (_itemKeys.isNotEmpty) {
      final firstCtx = _itemKeys[0].currentContext;
      final firstBox = firstCtx?.findRenderObject() as RenderBox?;
      if (firstBox != null && firstBox.hasSize) {
        itemHeight = firstBox.size.height;
        firstTop =
            listBox.globalToLocal(firstBox.localToGlobal(Offset.zero)).dy;
      }
    }

    if (_itemKeys.length > 1) {
      final secondCtx = _itemKeys[1].currentContext;
      final secondBox = secondCtx?.findRenderObject() as RenderBox?;
      if (secondBox != null && secondBox.hasSize && firstTop != null) {
        secondTop =
            listBox.globalToLocal(secondBox.localToGlobal(Offset.zero)).dy;
      }
    }

    final resolvedHeight = itemHeight ?? _itemHeight;
    // Convert to content-space (viewport Y + scroll offset)
    final resolvedBaseTop =
        firstTop != null ? firstTop + scrollAtMeasure : _itemBaseTop;
    final fallbackStride = resolvedHeight + 2.h; // margin/padding allowance

    double resolvedStride = _itemStride;
    if (secondTop != null && firstTop != null) {
      final stride = secondTop - firstTop;
      resolvedStride = stride > 0 ? stride : fallbackStride;
    } else {
      resolvedStride = fallbackStride;
    }

    if (!mounted) return;

    setState(() {
      _itemHeight = resolvedHeight;
      _itemBaseTop = resolvedBaseTop;
      _itemStride = resolvedStride;
      _targetY = _getTargetY(_currentIndex);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCenter());
  }

  /// Get the content-space Y of the game row for item at [index].
  /// Uses actual rendered position when available, falls back to stride formula.
  /// Items with round separators are taller; this offsets to the game row.
  double _getTargetY(int index) {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox != null && index >= 0 && index < _itemKeys.length) {
      final ctx = _itemKeys[index].currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final scrollOffset =
            _scrollController.hasClients ? _scrollController.offset : 0.0;
        final vpY = listBox.globalToLocal(box.localToGlobal(Offset.zero)).dy;
        final contentY = vpY + scrollOffset;
        // If the item includes a round separator header, its total height
        // exceeds _itemHeight. Offset to the game row at the bottom.
        final separatorOffset = (box.size.height - _itemHeight).clamp(
          0.0,
          double.infinity,
        );
        return contentY + separatorOffset;
      }
    }
    return _itemBaseTop + index * _itemStride;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Check if a global position is within the current selector bounds
  bool _isOnSelector(Offset globalPosition) {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return false;

    final localPos = listBox.globalToLocal(globalPosition);
    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;

    // Calculate selector's current visual position (accounting for scroll and padding)
    final indicatorInset = _indicatorInset.h;
    final selectorHeight = (_itemHeight - indicatorInset * 2).clamp(
      0.0,
      _itemHeight,
    );
    final selectorVisualTop = _targetY - scrollOffset + indicatorInset;
    final selectorVisualBottom = selectorVisualTop + selectorHeight;

    // Add some tolerance for easier grabbing
    const tolerance = 8.0;
    return localPos.dy >= (selectorVisualTop - tolerance) &&
        localPos.dy <= (selectorVisualBottom + tolerance);
  }

  void _handlePointerDown(PointerDownEvent event) {
    _lastPointerPosition = event.position;
    _pointerStartedOnSelector = _isOnSelector(event.position);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_lastPointerPosition == null) return;

    _lastPointerPosition = event.position;

    // Only start dragging if pointer started on the selector
    if (!_isDragging && _pointerStartedOnSelector) {
      HapticFeedback.heavyImpact();
      setState(() => _isDragging = true);
    }

    if (_isDragging) {
      // Update selector position based on current pointer position
      _updateIndexFromPosition(event.position);

      // Auto-scroll when near edges
      _handleEdgeScroll(event.position);
    }
  }

  void _handleEdgeScroll(Offset globalPosition) {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null || !_scrollController.hasClients) return;

    final localPos = listBox.globalToLocal(globalPosition);
    final listHeight = listBox.size.height;
    final maxScroll = _scrollController.position.maxScrollExtent;

    const edgeThreshold = 60.0;
    const scrollSpeed = 8.0;

    if (localPos.dy < edgeThreshold && _scrollController.offset > 0) {
      // Near top edge - scroll up
      final intensity = 1.0 - (localPos.dy / edgeThreshold);
      final scrollAmount = scrollSpeed * intensity;
      final newScroll = (_scrollController.offset - scrollAmount).clamp(
        0.0,
        maxScroll,
      );
      _scrollController.jumpTo(newScroll);
      // Update index after scroll
      _updateIndexFromPosition(globalPosition);
    } else if (localPos.dy > listHeight - edgeThreshold &&
        _scrollController.offset < maxScroll) {
      // Near bottom edge - scroll down
      final intensity = 1.0 - ((listHeight - localPos.dy) / edgeThreshold);
      final scrollAmount = scrollSpeed * intensity;
      final newScroll = (_scrollController.offset + scrollAmount).clamp(
        0.0,
        maxScroll,
      );
      _scrollController.jumpTo(newScroll);
      // Update index after scroll
      _updateIndexFromPosition(globalPosition);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_isDragging &&
        _currentIndex >= 0 &&
        _currentIndex < widget.games.length) {
      HapticFeedback.mediumImpact();
      widget.onSelect(_currentIndex);
    }
    setState(() => _isDragging = false);
    _lastPointerPosition = null;
    _pointerStartedOnSelector = false;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    setState(() => _isDragging = false);
    _lastPointerPosition = null;
    _pointerStartedOnSelector = false;
  }

  void _updateIndexFromPosition(Offset globalPosition) {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return;

    final localPos = listBox.globalToLocal(globalPosition);
    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final contentY = localPos.dy + scrollOffset;

    // Find the nearest game row by checking actual rendered positions.
    // Only visible items have a valid context; off-screen keys are skipped.
    int bestIndex = _currentIndex;
    double bestDist = double.infinity;
    bool foundAny = false;

    for (int i = 0; i < widget.games.length && i < _itemKeys.length; i++) {
      final ctx = _itemKeys[i].currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;

      final vpY = listBox.globalToLocal(box.localToGlobal(Offset.zero)).dy;
      final itemContentY = vpY + scrollOffset;
      final separatorOffset = (box.size.height - _itemHeight).clamp(
        0.0,
        double.infinity,
      );
      final gameRowCenter = itemContentY + separatorOffset + _itemHeight / 2;

      final dist = (contentY - gameRowCenter).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestIndex = i;
        foundAny = true;
      }
    }

    // Fallback to stride-based calculation if no items were rendered
    if (!foundAny) {
      final stride =
          _totalItemHeight <= 0 ? (_itemHeight + 2.h) : _totalItemHeight;
      final adjustedY = contentY - _itemBaseTop;
      bestIndex = (adjustedY / stride).floor().clamp(
        0,
        widget.games.length - 1,
      );
    }

    if (bestIndex != _currentIndex) {
      HapticFeedback.selectionClick();
      _animateToIndex(bestIndex);
    }
  }

  void _animateToIndex(int index) {
    setState(() {
      _currentIndex = index;
      _targetY = _getTargetY(index);
    });
  }

  /// Format round slug/id into a readable label
  String _formatRoundLabel(String slug) {
    return slug
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) =>
              word.isEmpty
                  ? ''
                  : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.dropdownWidth,
      constraints: BoxConstraints(
        maxHeight: widget.availableHeight.clamp(180.h, 380.h),
      ),
      child: Listener(
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: Stack(
          children: [
            // List of games - physics disabled only when dragging selector
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: ListView.builder(
                key: _listKey,
                controller: _scrollController,
                physics:
                    _isDragging ? const NeverScrollableScrollPhysics() : null,
                padding: EdgeInsets.symmetric(vertical: 6.h),
                itemCount: widget.games.length,
                itemBuilder: (context, index) {
                  final game = widget.games[index];
                  final isSelected = index == _currentIndex;

                  while (_itemKeys.length <= index) {
                    _itemKeys.add(GlobalKey());
                  }

                  // Determine if we should show round separator
                  final currentRound = game.roundSlug ?? game.roundId;
                  final previousRound =
                      index > 0
                          ? (widget.games[index - 1].roundSlug ??
                              widget.games[index - 1].roundId)
                          : null;
                  final showRoundSeparator =
                      previousRound != null && currentRound != previousRound;
                  final roundLabel =
                      showRoundSeparator
                          ? _formatRoundLabel(currentRound)
                          : null;

                  return KeyedSubtree(
                    key: _itemKeys[index],
                    child: _GameItemSimple(
                      index: index,
                      animation: widget.animation,
                      game: game,
                      isSelected: isSelected,
                      isDragging: _isDragging,
                      showRoundSeparator: showRoundSeparator,
                      roundLabel: roundLabel,
                      onTap: () {
                        _animateToIndex(index);
                        widget.onSelect(index);
                      },
                    ),
                  );
                },
              ),
            ),
            // Floating water droplet selector - clipped to stay within bounds
            Positioned.fill(
              child: ClipRect(
                child: IgnorePointer(
                  child: ListenableBuilder(
                    listenable: _scrollController,
                    builder: (context, _) {
                      final scrollOffset =
                          _scrollController.hasClients
                              ? _scrollController.offset
                              : 0.0;
                      final indicatorInset = _indicatorInset.h;
                      final indicatorHeight = (_itemHeight - indicatorInset * 2)
                          .clamp(0.0, _itemHeight);

                      return SingleMotionBuilder(
                        motion:
                            _isDragging
                                ? CupertinoMotion.snappy()
                                : CupertinoMotion.bouncy(),
                        value: _targetY - scrollOffset + indicatorInset,
                        builder: (context, animatedY, _) {
                          return CustomPaint(
                            painter: _GameSelectorPainter(
                              y: animatedY,
                              height: indicatorHeight,
                              isDragging: _isDragging,
                              baseColor: kPrimaryColor,
                              horizontalMargin: 6.w,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple game item - tap handled here, drag handled at list level
class _GameItemSimple extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  final GamesTourModel game;
  final bool isSelected;
  final bool isDragging;
  final VoidCallback onTap;
  final bool showRoundSeparator;
  final String? roundLabel;

  const _GameItemSimple({
    required this.index,
    required this.animation,
    required this.game,
    required this.isSelected,
    required this.isDragging,
    required this.onTap,
    this.showRoundSeparator = false,
    this.roundLabel,
  });

  String _extractLastName(String fullName) {
    final name = fullName.trim();
    if (name.isEmpty) return fullName;
    if (name.contains(',')) {
      final lastName = name.split(',').first.trim();
      if (lastName.isNotEmpty) return lastName;
    }
    const suffixes = {
      'jr',
      'jr.',
      'sr',
      'sr.',
      'ii',
      'iii',
      'iv',
      'v',
      '2nd',
      '3rd',
      '4th',
      '5th',
    };
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return fullName;
    if (parts.length == 1) return parts.first;
    for (int i = parts.length - 1; i >= 0; i--) {
      if (!suffixes.contains(parts[i].toLowerCase())) return parts[i];
    }
    return parts.last;
  }

  String _getResultText() {
    switch (game.gameStatus) {
      case GameStatus.whiteWins:
        return '1–0';
      case GameStatus.blackWins:
        return '0–1';
      case GameStatus.draw:
        return '½–½';
      case GameStatus.ongoing:
        return '';
      case GameStatus.unknown:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemDelay = index * 0.05;
    final itemAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(
        itemDelay.clamp(0.0, 0.4),
        (itemDelay + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    final isLive = game.gameStatus == GameStatus.ongoing;
    final resultText = _getResultText();
    final whiteName = _extractLastName(game.whitePlayer.displayName);
    final blackName = _extractLastName(game.blackPlayer.displayName);

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        final clampedValue = itemAnimation.value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 10 * (1 - clampedValue)),
          child: Opacity(opacity: clampedValue, child: child),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Round separator - subtle divider between different rounds
            if (showRoundSeparator && roundLabel != null)
              Container(
                padding: EdgeInsets.only(
                  left: 14.w,
                  right: 14.w,
                  top: index == 0 ? 2.h : 6.h,
                  bottom: 4.h,
                ),
                child: Row(
                  children: [
                    Text(
                      roundLabel!,
                      style: AppTypography.textXxsMedium.copyWith(
                        color: context.colors.textPrimary.withValues(
                          alpha: 0.35,
                        ),
                        letterSpacing: 0.5,
                        fontSize: 9.sp,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Container(
                        height: 0.5,
                        color: context.colors.textPrimary.withValues(
                          alpha: 0.06,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Game row
            Container(
              height: 36.0,
              margin: EdgeInsets.symmetric(horizontal: 6.w, vertical: 1.h),
              padding: EdgeInsets.symmetric(horizontal: 10.w),
              child: Row(
                children: [
                  // Live indicator
                  SizedBox(
                    width: 14.w,
                    child:
                        isLive
                            ? Container(
                              width: 6.w,
                              height: 6.h,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: kPrimaryColor,
                              ),
                            )
                            : null,
                  ),
                  // White player
                  Expanded(
                    child: Text(
                      whiteName,
                      style: AppTypography.textXsMedium.copyWith(
                        color:
                            isSelected
                                ? kPrimaryColor
                                : context.colors.textPrimary.withValues(
                                  alpha: 0.9,
                                ),
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Result
                  Container(
                    width: 36.w,
                    alignment: Alignment.center,
                    child:
                        resultText.isNotEmpty
                            ? Text(
                              resultText,
                              style: AppTypography.textXxsMedium.copyWith(
                                color: context.colors.textPrimary.withValues(
                                  alpha: 0.5,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                            )
                            : Text(
                              'vs',
                              style: AppTypography.textXxsRegular.copyWith(
                                color: context.colors.textPrimary.withValues(
                                  alpha: 0.35,
                                ),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                  ),
                  // Black player
                  Expanded(
                    child: Text(
                      blackName,
                      style: AppTypography.textXsMedium.copyWith(
                        color:
                            isSelected
                                ? kPrimaryColor
                                : context.colors.textPrimary.withValues(
                                  alpha: 0.9,
                                ),
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter for the floating game selector
class _GameSelectorPainter extends CustomPainter {
  final double y;
  final double height;
  final bool isDragging;
  final Color baseColor;
  final double horizontalMargin;

  _GameSelectorPainter({
    required this.y,
    required this.height,
    required this.isDragging,
    required this.baseColor,
    required this.horizontalMargin,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        horizontalMargin,
        y,
        size.width - horizontalMargin * 2,
        height,
      ),
      const Radius.circular(8),
    );

    // Fill
    final fillPaint =
        Paint()
          ..color = baseColor.withValues(alpha: isDragging ? 0.15 : 0.1)
          ..style = PaintingStyle.fill;
    canvas.drawRRect(rect, fillPaint);

    // Border
    final borderPaint =
        Paint()
          ..color = baseColor.withValues(alpha: isDragging ? 0.4 : 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
    canvas.drawRRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(_GameSelectorPainter oldDelegate) {
    return y != oldDelegate.y ||
        height != oldDelegate.height ||
        isDragging != oldDelegate.isDragging;
  }
}

/// Subtle round separator - appears between game groups
class _RoundSeparator extends StatelessWidget {
  final String roundSlug;
  final bool isFirst;
  final int animationIndex;
  final Animation<double> animation;

  const _RoundSeparator({
    required this.roundSlug,
    required this.isFirst,
    required this.animationIndex,
    required this.animation,
  });

  String _formatRoundName(String slug) {
    // Convert slug like "round-1" to "Round 1" or "finals" to "Finals"
    return slug
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) =>
              word.isEmpty
                  ? ''
                  : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final itemDelay = animationIndex * 0.05;
    final itemAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(
        itemDelay.clamp(0.0, 0.4),
        (itemDelay + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        final clampedValue = itemAnimation.value.clamp(0.0, 1.0);
        return Opacity(opacity: clampedValue, child: child);
      },
      child: Container(
        padding: EdgeInsets.only(
          left: 14.w,
          right: 14.w,
          top: isFirst ? 4.h : 12.h,
          bottom: 6.h,
        ),
        child: Row(
          children: [
            Text(
              _formatRoundName(roundSlug),
              style: AppTypography.textXxsMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.4),
                letterSpacing: 0.8,
                fontSize: 9.sp,
              ),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Container(
                height: 0.5,
                color: context.colors.textPrimary.withValues(alpha: 0.06),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Staggered animated game item wrapper
class _AnimatedGameItem extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  final GamesTourModel game;
  final int gameIndex;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback onTap;

  const _AnimatedGameItem({
    required this.index,
    required this.animation,
    required this.game,
    required this.gameIndex,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final itemDelay = index * 0.06;
    final itemAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(
        itemDelay.clamp(0.0, 0.4),
        (itemDelay + 0.6).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        final clampedValue = itemAnimation.value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 12 * (1 - clampedValue)),
          child: Opacity(opacity: clampedValue, child: child),
        );
      },
      child: _GameItem(
        game: game,
        gameIndex: gameIndex,
        isSelected: isSelected,
        isLoading: isLoading,
        onTap: onTap,
      ),
    );
  }
}

/// Compact minimal game item
class _GameItem extends StatefulWidget {
  final GamesTourModel game;
  final int gameIndex;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback onTap;

  const _GameItem({
    required this.game,
    required this.gameIndex,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_GameItem> createState() => _GameItemState();
}

class _GameItemState extends State<_GameItem> {
  bool _isPressed = false;

  String _extractLastName(String fullName) {
    final name = fullName.trim();
    if (name.isEmpty) return fullName;

    // Handle "LastName, FirstName" format (common in chess)
    if (name.contains(',')) {
      final lastName = name.split(',').first.trim();
      if (lastName.isNotEmpty) return lastName;
    }

    // Suffixes to ignore when finding last name
    const suffixes = {
      'jr',
      'jr.',
      'sr',
      'sr.',
      'ii',
      'iii',
      'iv',
      'v',
      '2nd',
      '3rd',
      '4th',
      '5th',
    };

    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return fullName;
    if (parts.length == 1) return parts.first;

    // Find the last part that isn't a suffix
    for (int i = parts.length - 1; i >= 0; i--) {
      if (!suffixes.contains(parts[i].toLowerCase())) {
        return parts[i];
      }
    }

    return parts.last;
  }

  String _getResultText() {
    switch (widget.game.gameStatus) {
      case GameStatus.whiteWins:
        return '1–0';
      case GameStatus.blackWins:
        return '0–1';
      case GameStatus.draw:
        return '½–½';
      case GameStatus.ongoing:
        return '';
      case GameStatus.unknown:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLive = widget.game.gameStatus == GameStatus.ongoing;
    final resultText = _getResultText();
    final whiteName = _extractLastName(widget.game.whitePlayer.displayName);
    final blackName = _extractLastName(widget.game.blackPlayer.displayName);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.symmetric(horizontal: 6.w, vertical: 1.h),
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.br),
          color:
              widget.isSelected
                  ? kPrimaryColor.withValues(alpha: 0.1)
                  : _isPressed
                  ? context.colors.textPrimary.withValues(alpha: 0.03)
                  : Colors.transparent,
        ),
        child: Row(
          children: [
            // Live indicator - fixed width
            SizedBox(
              width: 14.w,
              child:
                  isLive
                      ? Container(
                        width: 6.w,
                        height: 6.h,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kPrimaryColor,
                          boxShadow: [
                            BoxShadow(
                              color: kPrimaryColor.withValues(alpha: 0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      )
                      : null,
            ),
            // White player
            Expanded(
              child: Text(
                whiteName,
                style: AppTypography.textXsMedium.copyWith(
                  color:
                      widget.isSelected
                          ? kPrimaryColor
                          : context.colors.textPrimary.withValues(alpha: 0.9),
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Center: vs or result
            Container(
              width: 36.w,
              alignment: Alignment.center,
              child:
                  resultText.isNotEmpty
                      ? Text(
                        resultText,
                        style: AppTypography.textXxsMedium.copyWith(
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.5,
                          ),
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      )
                      : Text(
                        'vs',
                        style: AppTypography.textXxsRegular.copyWith(
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.35,
                          ),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
            ),
            // Black player
            Expanded(
              child: Text(
                blackName,
                style: AppTypography.textXsMedium.copyWith(
                  color:
                      widget.isSelected
                          ? kPrimaryColor
                          : context.colors.textPrimary.withValues(alpha: 0.9),
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Selection indicator
            SizedBox(
              width: 20.w,
              child:
                  widget.isLoading
                      ? SizedBox(
                        width: 12.sp,
                        height: 12.sp,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: kPrimaryColor,
                        ),
                      )
                      : widget.isSelected
                      ? Icon(
                        Icons.check_rounded,
                        color: kPrimaryColor,
                        size: 14.ic,
                      )
                      : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavBar extends ConsumerWidget {
  final int index;
  final ChessBoardStateNew state;
  final GamesTourModel game;
  final VoidCallback onGamebaseToggle;
  final bool showGamebaseButton;

  const _BottomNavBar({
    required this.index,
    required this.state,
    required this.game,
    required this.onGamebaseToggle,
    this.showGamebaseButton = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // PERF: Use .select() to only rebuild when the enabled state changes
    final gamebaseEnabled = ref.watch(
      gamebaseOverlayEnabledProvider.select((s) => s.valueOrNull ?? true),
    );
    final isGamebaseActive = showGamebaseButton ? gamebaseEnabled : false;

    final params = ChessBoardProviderParams(game: game, index: index);
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    ChessGameNavigatorState? navigatorState;
    final analysisGame = state.analysisState.game;
    if (analysisGame != null) {
      navigatorState = ref.watch(chessGameNavigatorProvider(analysisGame));
    }
    final baseCanMoveForward = state.analysisState.canMoveForward;
    final baseCanMoveBackward = state.analysisState.canMoveBackward;
    final canMoveForward =
        navigatorState != null
            ? (navigatorState.canGoForward || baseCanMoveForward)
            : baseCanMoveForward;
    final canMoveBackward =
        navigatorState != null
            ? (navigatorState.canGoBackward || baseCanMoveBackward)
            : baseCanMoveBackward;
    final previewMoveCount = state.lockedPvLine?.moves.length ?? 0;
    final previewIndex = state.lockedPvNavigationIndex ?? -1;
    final isPreviewActive = state.isPvPreviewActive && previewMoveCount > 0;
    final previewCanMoveForward =
        isPreviewActive ? previewIndex < previewMoveCount - 1 : false;
    final previewCanMoveBackward = isPreviewActive ? previewIndex > 0 : false;
    final effectiveCanMoveForward =
        isPreviewActive ? previewCanMoveForward : canMoveForward;
    final effectiveCanMoveBackward =
        isPreviewActive ? previewCanMoveBackward : canMoveBackward;

    final selectionClearKey = _boardSelectionClearKey(game, index);

    void clearBoardSelection() {
      final clearNotifier = ref.read(
        boardSelectionClearRequestProvider(selectionClearKey).notifier,
      );
      clearNotifier.state++;
    }

    return ChessBoardBottomNavBar(
      key: ValueKey('bottom_nav_gamebase_$isGamebaseActive'),
      gameIndex: index,
      showGamebaseButton: showGamebaseButton,
      onFlip: () => notifier.flipBoard(),
      toggleEngineVisibility: () => notifier.toggleEngineVisibility(),
      onEngineSettingsLongPress: () {
        requireFullAuthGuard(context).then((allowed) {
          if (!allowed) return;
          if (!context.mounted) return;
          Navigator.of(
            context,
          ).push(SettingsPage.route(initiallyExpanded: SettingsSection.engine));
        });
      },
      onRightMove:
          // Normal board arrows only navigate saved notation/PV-preview moves.
          // Do not fall through to engine/PV insertion at the end of notation;
          // engine moves must come from explicit PV/engine UI actions.
          effectiveCanMoveForward
              ? () {
                clearBoardSelection();
                notifier.moveForward().then((_) {
                  final updatedState =
                      ref.read(chessBoardScreenProviderNew(params)).valueOrNull;
                  if (updatedState == null ||
                      updatedState.isPvPreviewActive ||
                      !updatedState.hasUnseenMoves) {
                    return;
                  }
                  final atLastMove =
                      updatedState.analysisState.currentMoveIndex >=
                      updatedState.allMoves.length - 1;
                  if (atLastMove) {
                    notifier.markMovesAsSeen();
                  }
                });
              }
              : null,
      onLeftMove:
          effectiveCanMoveBackward
              ? () {
                clearBoardSelection();
                notifier.moveBackward();
              }
              : null,
      onLongPressBackwardStart: () {
        clearBoardSelection();
        notifier.startLongPressBackward();
      },
      onLongPressBackwardEnd: () => notifier.stopLongPress(),
      onLongPressForwardStart:
          effectiveCanMoveForward
              ? () {
                clearBoardSelection();
                notifier.startLongPressForward();
              }
              : null,
      onLongPressForwardEnd: () => notifier.stopLongPress(),
      canMoveForward: effectiveCanMoveForward,
      canMoveBackward: effectiveCanMoveBackward,
      showEngineAnalysis: state.showEngineAnalysis,
      showUnseenMoveBadge: state.hasUnseenMoves,
      onGamebaseToggle: onGamebaseToggle,
      isGamebaseActive: isGamebaseActive,
    );
  }
}

class _GameBody extends StatelessWidget {
  final int index;
  final int currentPageIndex;
  final GamesTourModel game;
  final ChessBoardStateNew state;
  final PlayerProfileDataSource playerProfileDataSource;
  final bool showGamebaseButton;
  final bool showClock;

  const _GameBody({
    required this.index,
    required this.currentPageIndex,
    required this.game,
    required this.state,
    this.playerProfileDataSource = PlayerProfileDataSource.supabase,
    this.showGamebaseButton = false,
    this.showClock = true,
  });

  @override
  Widget build(BuildContext context) {
    // Analysis mode is always active, use analysis game body
    return _AnalysisGameBody(
      index: index,
      currentPageIndex: currentPageIndex,
      game: game,
      state: state,
      playerProfileDataSource: playerProfileDataSource,
      showGamebaseButton: showGamebaseButton,
      showClock: showClock,
    );
  }
}

class _AnalysisGameBody extends ConsumerWidget {
  final int index;
  final int currentPageIndex;
  final GamesTourModel game;
  final ChessBoardStateNew state;
  final PlayerProfileDataSource playerProfileDataSource;
  final bool showGamebaseButton;
  final bool showClock;

  const _AnalysisGameBody({
    required this.index,
    required this.currentPageIndex,
    required this.game,
    required this.state,
    this.playerProfileDataSource = PlayerProfileDataSource.supabase,
    this.showGamebaseButton = false,
    this.showClock = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The notation/explorer swap moved into `_AnalysisSwipePanels` which
    // owns its own page state and (where applicable) syncs with the
    // gamebase toggle provider — no need to rebuild this body on toggle.

    // Check for tablet landscape mode for side-by-side layout
    final isTabletLandscape =
        ResponsiveHelper.isTablet && ResponsiveHelper.isLandscape;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isVisiblePage = index == currentPageIndex;
        final availableHeight =
            constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height;
        final compactThreshold = 620.h;
        final useCompactLayout =
            availableHeight < compactThreshold && !isTabletLandscape;

        final pvSection = <Widget>[];
        // PV section sits above the swipeable panels and renders on both
        // pages. The explorer panel suppresses its own internal PV via
        // `showHorizontalPvLines: false` so we don't duplicate.
        if (state.isAnalysisMode &&
            state.showEngineAnalysis &&
            state.showPrincipalVariations) {
          pvSection.add(SizedBox(height: 2.h));
          final pvList = _PrincipalVariationList(
            key: e2eKey(E2eIds.boardPvList),
            index: index,
            state: state,
            game: game,
          );
          if (useCompactLayout) {
            pvSection.add(pvList);
          } else {
            pvSection.add(Flexible(flex: 0, child: pvList));
          }
        }

        ValueChanged<String> editNameCallback(bool isWhite) {
          return (newName) {
            final params = ChessBoardProviderParams(game: game, index: index);
            ref
                .read(chessBoardScreenProviderNew(params).notifier)
                .updatePlayerName(isWhite: isWhite, newName: newName);
          };
        }

        final headerChildren = <Widget>[
          _PlayerWidget(
            game: game,
            isFlipped: state.isBoardFlipped,
            blackPlayer: false,
            state: state,
            playerProfileDataSource: playerProfileDataSource,
            showClock: showClock,
            onEditName:
                showGamebaseButton
                    ? editNameCallback(state.isBoardFlipped)
                    : null,
          ),
          SizedBox(height: 1.h),
          _BoardWithSidebar(
            index: index,
            currentPageIndex: currentPageIndex,
            state: state,
            game: game,
          ),
          SizedBox(height: 1.h),
          _PlayerWidget(
            game: game,
            isFlipped: state.isBoardFlipped,
            blackPlayer: true,
            state: state,
            playerProfileDataSource: playerProfileDataSource,
            showClock: showClock,
            onEditName:
                showGamebaseButton
                    ? editNameCallback(!state.isBoardFlipped)
                    : null,
          ),
          ...pvSection,
        ];

        Widget buildAnalysisView() {
          final movesDisplay = _MovesDisplay(
            index: index,
            currentPageIndex: currentPageIndex,
            state: state,
            game: game,
          );

          // Avoid mounting the (global) Gamebase provider for offscreen pages.
          // This prevents multiple PageView children from racing to set the
          // Gamebase FEN, which breaks lookups for real game positions.
          if (!isVisiblePage) {
            return movesDisplay;
          }

          // Paste-FEN flow: the starting position is non-default (notation
          // doesn't begin at "1."), so the user is searching for a specific
          // position rather than studying an opening tree. Replace the
          // opening-explorer swipe page with a position-search games table.
          final startingFen = state.analysisState.startingPosition?.fen;
          final isPositionSearchFlow =
              startingFen != null && startingFen != Chess.initial.fen;

          final gamebaseDisplay =
              isPositionSearchFlow
                  ? _FenPositionGamesTable(
                    fen: state.analysisState.position.fen,
                    enabled: isVisiblePage,
                  )
                  : BoardOpeningExplorerPanel(
                    state: state,
                    onMoveSelected: (uci) {
                      final params = ChessBoardProviderParams(
                        game: game,
                        index: index,
                      );
                      final notifier = ref.read(
                        chessBoardScreenProviderNew(params).notifier,
                      );
                      try {
                        if (uci.length < 4) return;
                        final from = Square.fromName(uci.substring(0, 2));
                        final to = Square.fromName(uci.substring(2, 4));
                        Role? promotion;
                        if (uci.length > 4) {
                          promotion = Role.fromChar(uci[4]);
                        }
                        final move = NormalMove(
                          from: from,
                          to: to,
                          promotion: promotion,
                        );
                        notifier.onAnalysisMove(move);
                      } catch (e) {
                        debugPrint('Error making move from UCI: $e');
                      }
                    },
                  );

          // Notation (page 0) and Opening Explorer / Position Search (page 1)
          // live in a PageView; a horizontal swipe from notation reveals the
          // second panel. Replaces the previous toggle-driven crossfade so the
          // second panel is available everywhere the chess board screen is
          // mounted, not just where `showGamebaseButton: true` was passed.
          // Tablet landscape keeps game switching on the board/chrome, while
          // drags that start inside the notation panel should still reveal
          // the explorer page.
          return _AnalysisSwipePanels(
            movesDisplay: movesDisplay,
            gamebaseDisplay: gamebaseDisplay,
            syncWithGamebaseToggle: showGamebaseButton,
          );
        }

        if (useCompactLayout) {
          final movesPanelHeight = math.max(220.h, availableHeight * 0.55);
          return SingleChildScrollView(
            padding: EdgeInsets.only(bottom: 12.h),
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...headerChildren,
                SizedBox(height: 12.h),
                SizedBox(height: movesPanelHeight, child: buildAnalysisView()),
              ],
            ),
          );
        }

        // ═══════════════════════════════════════════════════════════════════
        // TABLET LANDSCAPE LAYOUT - Modern Chess Studio Design
        // Side-by-side layout: Board section (left) + Analysis section (right)
        // ═══════════════════════════════════════════════════════════════════
        if (isTabletLandscape) {
          final screenHeight = availableHeight;

          // Calculate optimal board size to fit within available height
          // Account for: top padding (8) + player card (~56) + spacing (8) +
          // board + spacing (8) + player card (~56) + bottom padding (8) = ~144 extra
          final playerCardHeight = 56.sp;
          final verticalSpacing = 8.sp;
          final verticalPadding = 8.sp * 2; // top + bottom
          final totalVerticalExtra =
              (playerCardHeight * 2) + (verticalSpacing * 2) + verticalPadding;

          // Board size based on height constraint
          final maxBoardFromHeight = screenHeight - totalVerticalExtra;

          // Eval bar width
          final evalBarWidth = 20.sp;

          // Board size is the height-constrained value (square board)
          final optimalBoardSize = math.max(200.0, maxBoardFromHeight);

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─────────────────────────────────────────────────────────────
                // LEFT SECTION: Board with players and evaluation
                // ─────────────────────────────────────────────────────────────
                SizedBox(
                  width:
                      optimalBoardSize +
                      evalBarWidth +
                      24.sp, // board + eval + margins
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top player card
                      _TabletPlayerCard(
                        game: game,
                        isFlipped: state.isBoardFlipped,
                        blackPlayer: false,
                        state: state,
                        showClock: showClock,
                        onEditName:
                            showGamebaseButton
                                ? editNameCallback(state.isBoardFlipped)
                                : null,
                      ),
                      SizedBox(height: verticalSpacing),
                      // Board with evaluation bar
                      _TabletBoardWithSidebar(
                        index: index,
                        currentPageIndex: currentPageIndex,
                        state: state,
                        game: game,
                        boardSize: optimalBoardSize,
                        evalBarWidth: evalBarWidth,
                      ),
                      SizedBox(height: verticalSpacing),
                      // Bottom player card
                      _TabletPlayerCard(
                        game: game,
                        isFlipped: state.isBoardFlipped,
                        blackPlayer: true,
                        state: state,
                        showClock: showClock,
                        onEditName:
                            showGamebaseButton
                                ? editNameCallback(!state.isBoardFlipped)
                                : null,
                      ),
                    ],
                  ),
                ),

                SizedBox(width: 12.sp),

                // ─────────────────────────────────────────────────────────────
                // RIGHT SECTION: PV cards + Moves display and analysis
                // ─────────────────────────────────────────────────────────────
                Expanded(
                  child: SizedBox(
                    height: screenHeight - 16.sp,
                    child: Column(
                      children: [
                        // PV Cards section for tablet landscape
                        if (pvSection.isNotEmpty) ...[
                          ...pvSection,
                          SizedBox(height: 8.sp),
                        ],
                        // Moves panel with elegant container
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: context.colors.surface,
                              borderRadius: BorderRadius.circular(12.sp),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.06),
                                width: 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: buildAnalysisView(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // ═══════════════════════════════════════════════════════════════════
        // TABLET PORTRAIT LAYOUT - Elegant Centered Design
        // Centered content with generous max-width and refined proportions
        // ═══════════════════════════════════════════════════════════════════
        if (ResponsiveHelper.isTablet) {
          final screenWidth = MediaQuery.sizeOf(context).width;
          // Use 85% of screen width, capped at 720px for optimal readability
          final contentMaxWidth = math.min(screenWidth * 0.85, 720.0);

          return SizedBox.expand(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: Column(
                  children: [
                    SizedBox(height: 4.sp),
                    // Top player with padding
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.sp),
                      child: _TabletPlayerCard(
                        game: game,
                        isFlipped: state.isBoardFlipped,
                        blackPlayer: false,
                        state: state,
                        showClock: showClock,
                        onEditName:
                            showGamebaseButton
                                ? editNameCallback(state.isBoardFlipped)
                                : null,
                      ),
                    ),
                    SizedBox(height: 4.sp),
                    // Board with evaluation
                    _BoardWithSidebar(
                      index: index,
                      currentPageIndex: currentPageIndex,
                      state: state,
                      game: game,
                    ),
                    SizedBox(height: 4.sp),
                    // Bottom player with padding
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.sp),
                      child: _TabletPlayerCard(
                        game: game,
                        isFlipped: state.isBoardFlipped,
                        blackPlayer: true,
                        state: state,
                        showClock: showClock,
                        onEditName:
                            showGamebaseButton
                                ? editNameCallback(!state.isBoardFlipped)
                                : null,
                      ),
                    ),
                    // PV section
                    ...pvSection,
                    SizedBox(height: 4.sp),
                    // Moves panel with elegant container
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.symmetric(horizontal: 16.sp),
                        decoration: BoxDecoration(
                          color: context.colors.surface,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(12.sp),
                            topRight: Radius.circular(12.sp),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: Colors.white.withValues(alpha: 0.06),
                              width: 1,
                            ),
                            left: BorderSide(
                              color: Colors.white.withValues(alpha: 0.06),
                              width: 1,
                            ),
                            right: BorderSide(
                              color: Colors.white.withValues(alpha: 0.06),
                              width: 1,
                            ),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: buildAnalysisView(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Column(
          children: [...headerChildren, Expanded(child: buildAnalysisView())],
        );
      },
    );
  }
}

// DISABLED: Analysis navigation arrows widget completely hidden
// class _AnalysisControlsRow extends ConsumerWidget {
//   final int index;
//   final GamesTourModel game;
//
//   const _AnalysisControlsRow({required this.index, required this.game});
//
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final params = ChessBoardProviderParams(game: game, index: index);
//     final state = ref.watch(chessBoardScreenProviderNew(params)).valueOrNull;
//     final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
//
//     // Use variants when available; default to first PV if none explicitly selected
//     // final hasVariant = state?.principalVariations.isNotEmpty ?? false;
//
//     // Respect PV count from settings in UI
//     // ... (omitted)
//   }
// }

class _PlayerWidget extends StatelessWidget {
  final GamesTourModel game;
  final bool isFlipped;
  final bool blackPlayer;
  final ChessBoardStateNew state;
  final PlayerProfileDataSource playerProfileDataSource;
  final bool showClock;
  final ValueChanged<String>? onEditName;

  const _PlayerWidget({
    required this.game,
    required this.isFlipped,
    required this.blackPlayer,
    required this.state,
    this.playerProfileDataSource = PlayerProfileDataSource.supabase,
    this.showClock = true,
    this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    // Determine if this is the white player
    final isWhitePlayer =
        (blackPlayer && !isFlipped) || (!blackPlayer && isFlipped);

    final currentPosition =
        state.isAnalysisMode ? state.analysisState.position : state.position;

    // Check whose turn it is currently
    final currentTurn = currentPosition?.turn ?? Side.white;
    final isCurrentPlayer =
        (isWhitePlayer && currentTurn == Side.white) ||
        (!isWhitePlayer && currentTurn == Side.black);

    return PlayerFirstRowDetailWidget(
      isCurrentPlayer: isCurrentPlayer,
      isWhitePlayer: isWhitePlayer,
      playerView: PlayerView.boardView,
      gamesTourModel: game,
      chessBoardState: state, // Pass the state for move time calculation
      playerProfileDataSource: playerProfileDataSource,
      showClock: showClock,
      onEditName: onEditName,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TABLET-SPECIFIC WIDGETS
// Refined components optimized for tablet displays with elegant styling
// ═══════════════════════════════════════════════════════════════════════════

/// Tablet-optimized player card with refined visual design
/// Features subtle background, better spacing, and enhanced typography
class _TabletPlayerCard extends StatelessWidget {
  final GamesTourModel game;
  final bool isFlipped;
  final bool blackPlayer;
  final ChessBoardStateNew state;
  final PlayerProfileDataSource playerProfileDataSource;
  final bool showClock;
  final ValueChanged<String>? onEditName;

  const _TabletPlayerCard({
    required this.game,
    required this.isFlipped,
    required this.blackPlayer,
    required this.state,
    this.playerProfileDataSource = PlayerProfileDataSource.supabase,
    this.showClock = true,
    this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    // Determine if this is the white player
    final isWhitePlayer =
        (blackPlayer && !isFlipped) || (!blackPlayer && isFlipped);

    final currentPosition =
        state.isAnalysisMode ? state.analysisState.position : state.position;

    // Check whose turn it is currently
    final currentTurn = currentPosition?.turn ?? Side.white;
    final isCurrentPlayer =
        (isWhitePlayer && currentTurn == Side.white) ||
        (!isWhitePlayer && currentTurn == Side.black);

    // For tablet, wrap in a refined container (no horizontal margin - parent controls spacing)
    return Container(
      decoration: BoxDecoration(
        color:
            isCurrentPlayer
                ? context.colors.surface
                : context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(10.sp),
        border: Border.all(
          color:
              isCurrentPlayer
                  ? context.colors.divider
                  : context.colors.divider.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: PlayerFirstRowDetailWidget(
        isCurrentPlayer: isCurrentPlayer,
        isWhitePlayer: isWhitePlayer,
        playerView: PlayerView.boardView,
        gamesTourModel: game,
        chessBoardState: state,
        playerProfileDataSource: playerProfileDataSource,
        showClock: showClock,
        onEditName: onEditName,
      ),
    );
  }
}

/// Tablet landscape board with sidebar - uses pre-calculated sizes
/// Optimized for side-by-side layout with moves panel
class _TabletBoardWithSidebar extends ConsumerWidget {
  final int index;
  final ChessBoardStateNew state;
  final int currentPageIndex;
  final GamesTourModel game;
  final double boardSize;
  final double evalBarWidth;

  const _TabletBoardWithSidebar({
    required this.index,
    required this.state,
    required this.currentPageIndex,
    required this.game,
    required this.boardSize,
    required this.evalBarWidth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // PERF: Use .select() to only rebuild when showEngineGauge changes
    final engineGaugeEnabled = ref.watch(
      engineSettingsProviderNew.select(
        (s) => s.valueOrNull?.showEngineGauge ?? true,
      ),
    );
    final spoilerState = ref.watch(eventNoSpoilersProvider(game.tourId));
    final showEngineGauge =
        engineGaugeEnabled &&
        !((spoilerState.isLoading || spoilerState.enabled) &&
            game.gameStatus.isFinished);

    final effectiveEvalWidth = showEngineGauge ? evalBarWidth : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Evaluation bar
        if (showEngineGauge)
          SizedBox(
            width: effectiveEvalWidth,
            height: boardSize,
            child: Builder(
              builder: (context) {
                final activePosition =
                    state.isAnalysisMode
                        ? state.analysisState.position
                        : state.position;
                final bool isWhiteToMove = activePosition?.turn != Side.black;

                return EvaluationBarWidget(
                  key: e2eKey(E2eIds.boardEvalBar),
                  width: effectiveEvalWidth,
                  height: boardSize,
                  evaluation: state.evaluation,
                  mate: state.mate,
                  isEvaluating: state.isEvaluating,
                  isFlipped: state.isBoardFlipped,
                  isWhiteToMove: isWhiteToMove,
                  positionKey: activePosition?.fen,
                );
              },
            ),
          ),
        // Chess board
        _AnalysisBoard(
          size: boardSize,
          chessBoardState: state,
          isFlipped: state.isBoardFlipped,
          index: index,
          game: state.game,
        ),
      ],
    );
  }
}

class _BoardWithSidebar extends ConsumerWidget {
  final int index;
  final ChessBoardStateNew state;
  final int currentPageIndex;
  final GamesTourModel game;

  const _BoardWithSidebar({
    required this.index,
    required this.state,
    required this.currentPageIndex,
    required this.game,
  });

  // DISABLED: Only used for move annotation overlay
  // String? _getLastMoveSquare() {
  //   // Analysis mode is always active, always use analysis state
  //   final lastMove = state.analysisState.lastMove;
  //   if (lastMove == null) return null;
  //   if (lastMove is NormalMove) {
  //     return lastMove.to.name;
  //   }
  //   return null;
  // }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // PERF: Use .select() to only rebuild when showEngineGauge changes
    final engineGaugeEnabled = ref.watch(
      engineSettingsProviderNew.select(
        (s) => s.valueOrNull?.showEngineGauge ?? true,
      ),
    );
    final spoilerState = ref.watch(eventNoSpoilersProvider(game.tourId));
    final showEngineGauge =
        engineGaugeEnabled &&
        !((spoilerState.isLoading || spoilerState.enabled) &&
            game.gameStatus.isFinished);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use consistent .sp units for all sizing
        final sideBarWidth = showEngineGauge ? 20.sp : 0.0;
        final horizontalMargin = 16.sp * 2; // Matches Container margin below
        // Use constraints.maxWidth to respect parent constraints (e.g. tablet max width)
        final screenWidth = constraints.maxWidth;
        final boardSize = screenWidth - sideBarWidth - horizontalMargin;

        // Analysis mode is always active, always use analysis state
        // DISABLED: currentIndex only used for move impact analysis
        // final currentIndex = state.analysisState.currentMoveIndex;

        // DISABLED: Move impact analysis causes Lichess 429 rate limits
        // TODO: Re-enable when we have better rate limiting or use only Stockfish
        // // LAZY IMPACT: Only calculate impact for the CURRENT move, not all moves
        // // This prevents blocking the eval bar by not flooding Stockfish queue
        // MoveImpactAnalysis? currentMoveImpact;
        // if (index == currentPageIndex &&
        //     state.allMoves.isNotEmpty &&
        //     currentIndex >= 0) {
        //   final boardParams = ChessBoardProviderParams(
        //     game: game,
        //     index: index,
        //   );
        //   final lazyParams = LazyMoveImpactParams(
        //     boardParams: boardParams,
        //     moveIndex: currentIndex,
        //   );
        //   final impactAsync = ref.watch(lazyMoveImpactProvider(lazyParams));
        //   currentMoveImpact = impactAsync.whenOrNull(data: (data) => data);
        // }

        return Container(
          margin: EdgeInsets.symmetric(horizontal: 16.sp),
          child: Row(
            children: [
              // Conditionally show evaluation bar based on settings
              if (showEngineGauge)
                SizedBox(
                  width: sideBarWidth,
                  height: boardSize,
                  child: Builder(
                    builder: (context) {
                      final activePosition =
                          state.isAnalysisMode
                              ? state.analysisState.position
                              : state.position;
                      final bool isWhiteToMove =
                          activePosition?.turn != Side.black;

                      return EvaluationBarWidget(
                        key: e2eKey(E2eIds.boardEvalBar),
                        width: sideBarWidth,
                        height: boardSize,
                        evaluation: state.evaluation,
                        mate: state.mate,
                        isEvaluating: state.isEvaluating,
                        isFlipped: state.isBoardFlipped,
                        isWhiteToMove: isWhiteToMove,
                        positionKey: activePosition?.fen,
                      );
                    },
                  ),
                ),
              Stack(
                children: [
                  // Analysis mode is always active, always use analysis board
                  _AnalysisBoard(
                    size: boardSize,
                    chessBoardState: state,
                    isFlipped: state.isBoardFlipped,
                    index: index,
                    game: state.game,
                  ),
                  // DISABLED: Move annotation overlay (requires move impact analysis)
                  // // Add move annotation overlay - only show if impact is not normal and not exploring a variant
                  // if (currentMoveImpact != null &&
                  //     currentMoveImpact.impact != MoveImpactType.normal &&
                  //     state.selectedVariantIndex == null)
                  //   BoardMoveAnnotation(
                  //     moveImpact: currentMoveImpact,
                  //     boardSize: boardSize,
                  //     isFlipped: state.isBoardFlipped,
                  //     lastMoveSquare: _getLastMoveSquare(),
                  //   ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// REMOVED: _ChessBoardNew widget - analysis mode is always active, only _AnalysisBoard is used

class _AnalysisBoard extends ConsumerStatefulWidget {
  final double size;
  final ChessBoardStateNew chessBoardState;
  final bool isFlipped;
  final int index;
  final GamesTourModel game;

  const _AnalysisBoard({
    required this.size,
    required this.chessBoardState,
    this.isFlipped = false,
    required this.index,
    required this.game,
  });

  @override
  ConsumerState<_AnalysisBoard> createState() => _AnalysisBoardState();
}

/// Typography rung in the move-list ladder. Higher rungs (mainline) get
/// larger size, heavier weight, tighter tracking; deeper variations step
/// down each axis so the hierarchy is legible at a glance.
class _MoveLadder {
  final double sanSize;
  final FontWeight sanWeight;
  final double sanLetterSpacing;
  final double numberSize;
  final double numberAlpha;

  const _MoveLadder({
    required this.sanSize,
    required this.sanWeight,
    required this.sanLetterSpacing,
    required this.numberSize,
    required this.numberAlpha,
  });
}

class _AnalysisBoardState extends ConsumerState<_AnalysisBoard>
    with TickerProviderStateMixin {
  bool _showDelayedGameEndingEffect = false;
  bool _wasAtEnd = false;
  bool _clearBoardSelectionForFrame = false;
  bool _selectionRestoreScheduled = false;
  int? _lastSelectionClearRequestId;

  // Swipe-to-flip: drag-driven progress + a fixed-duration commit animation.
  // Progress is the unit-π rotation factor (×π → radians for Transform.rotateX).
  // ±0.5 = ±π/2 = edge-on. The orientation swap happens at the edge-on
  // midpoint so the visible rotation stays continuous: animate to ±0.5, call
  // flipBoard(), jump to the opposite ±0.5, animate to 0.
  //
  // Pacing is symmetric by construction: each phase uses an AnimationController
  // whose duration scales linearly with the rotation distance, so angular
  // velocity is identical in both swipe directions regardless of how far the
  // user dragged before releasing.
  static const double _flipMaxProgress = 0.5;
  static const double _flipCommitProgressThreshold = 0.18;
  static const double _flipCommitVelocityThreshold = 600.0;
  static const Duration _flipPhaseFullDuration = Duration(milliseconds: 220);
  static const Duration _flipPhaseMinDuration = Duration(milliseconds: 90);

  late final AnimationController _flipCommitCtrl;
  // Live rotation progress (in units of π). Bound to a ValueNotifier so the
  // wrapper rebuilds only when rotation changes, leaving the chessboard
  // subtree untouched on every other frame.
  late final ValueNotifier<double> _flipProgress;
  // Current commit phase tween — re-targeted before each forward().
  double _flipPhaseFrom = 0.0;
  double _flipPhaseTo = 0.0;
  bool _flipDragActive = false;
  bool _flipCommitting = false;
  // Bumped on every drag start and on every commit. An in-flight commit bails
  // if its captured token is stale, so a new gesture can preempt the previous
  // animation cleanly without leaving _flipCommitting stuck true.
  int _flipCommitToken = 0;

  // Double-tap-to-like: transient heart bursts spawned at the tap point.
  final HeartBurstController _burstController = HeartBurstController();
  late final LikeFlightAnchor _likeFlightAnchor;
  Offset _lastTapPosition = Offset.zero;
  Offset _lastTapGlobalPosition = Offset.zero;
  OverlayEntry? _flyingHeartEntry;
  bool _likeInteractionInProgress = false;
  int _likeInteractionToken = 0;
  // Same-square double-tap-to-like tracking. We detect the "like" double-tap
  // with a passive Listener (raw pointer events) instead of a
  // DoubleTapGestureRecognizer. A DoubleTapGestureRecognizer lives in the
  // gesture arena and holds the pointer stream across two taps to disambiguate;
  // that robs chessground's own pointer-based board (also a raw Listener) of the
  // first tap's clean pointer-up, so the second tap of a tap-two-squares move
  // gets rejected and the move silently fails. A passive Listener never enters
  // the arena, so tap-to-move stays pristine. We only treat two quick taps on
  // the SAME board square as a like — a move's two taps always land on DIFFERENT
  // squares, so a move can never be mistaken for a like.
  int? _lastLikeTapSquareIndex;
  Duration? _lastLikeTapTimestamp;
  static const Duration _likeInteractionLikeDuration = Duration(
    milliseconds: 1650,
  );
  static const Duration _likeInteractionUnlikeDuration = Duration(
    milliseconds: 900,
  );

  /// Tracks the latest mounted board state for the debug VM service
  /// extension `likeBoard` so agents (marionette MCP) can trigger the like
  /// chain without fighting the chessground gesture arena.
  static _AnalysisBoardState? _debugLatest;
  static bool _debugExtRegistered = false;

  void _scheduleSelectionRestore() {
    if (_selectionRestoreScheduled) return;
    _selectionRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _selectionRestoreScheduled = false;
      if (_clearBoardSelectionForFrame) {
        setState(() => _clearBoardSelectionForFrame = false);
      }
    });
  }

  /// True only at the end of the original game mainline (not analysis variations).
  /// movePointer: [] = initial pos, [n] = mainline move n, [n,v,m,...] = variation
  bool _isAtGameEnd(AnalysisBoardState s) {
    return _isAnalysisAtFinishedSharePosition(
      analysisState: s,
      game: widget.game,
    );
  }

  // Map an author-supplied PGN NAG to a Lichess SVG annotation type — but
  // only for NAGs whose glyph is faithfully reproduced by the Lichess SVG.
  // NAG 5 (!?, "Interesting") and NAG 6 (?!, "Dubious") are intentionally
  // omitted: $5 used to map to goodMove, whose SVG renders just "!", which
  // squashed "!?" → "!" on the board. Returning null for those (and $7 □,
  // $10+ evaluation, $32+ observation) lets the fallback in the caller
  // render the literal Unicode glyph from getNagDisplay() in the author
  // color from nag_display.dart, matching the SAN-text rendering exactly.
  LichessMoveAnnotationType? _mapNagToAnnotationType(int nag) {
    switch (nag) {
      case 1:
        return LichessMoveAnnotationType.goodMove; // !
      case 2:
        return LichessMoveAnnotationType.mistake; // ?
      case 3:
        return LichessMoveAnnotationType.brilliant; // !!
      case 4:
        return LichessMoveAnnotationType.blunder; // ??
      default:
        return null;
    }
  }

  Square? _lastMoveDestinationSquare(Move? lastMove) {
    if (lastMove == null) return null;
    if (lastMove is NormalMove) {
      // Castling is encoded as king-captures-rook in dartchess.
      // Map to the king's actual destination square for annotation placement.
      final from = lastMove.from;
      final to = lastMove.to;
      if (from == Square.e1 && to == Square.h1) return Square.g1;
      if (from == Square.e1 && to == Square.a1) return Square.c1;
      if (from == Square.e8 && to == Square.h8) return Square.g8;
      if (from == Square.e8 && to == Square.a8) return Square.c8;
      return to;
    }
    final squares = lastMove.squares.toList();
    if (squares.isEmpty) return null;
    return squares.last;
  }

  Iterable<Shape> _extractAnnotationShapes(ChessMove? move) {
    if (move == null || move.comments == null) return const [];

    final shapes = <Shape>[];

    Color getColor(String code) {
      switch (code.toUpperCase()) {
        case 'G':
          return const Color(0xFF15781B).withValues(alpha: 0.8); // Green
        case 'Y':
          return const Color(0xFFE58F00).withValues(alpha: 0.8); // Yellow
        case 'B':
          return const Color(0xFF003088).withValues(alpha: 0.8); // Blue
        case 'R':
          return const Color(0xFF882020).withValues(alpha: 0.8); // Red
        case 'O':
          return const Color(0xFFE68F00).withValues(alpha: 0.8); // Orange
        default:
          return const Color(
            0xFF15781B,
          ).withValues(alpha: 0.8); // Default green
      }
    }

    for (final comment in move.comments!) {
      // Parse all [%cal ...] blocks in the comment
      final calMatches = RegExp(r'\[%cal\s+([^\]]+)\]').allMatches(comment);
      for (final match in calMatches) {
        final content = match.group(1);
        if (content != null) {
          final items = content.split(',');
          for (final item in items) {
            final trimmed = item.trim();
            if (trimmed.length == 5) {
              // e.g. Gg8g7
              final colorCode = trimmed[0];
              final origStr = trimmed.substring(1, 3);
              final destStr = trimmed.substring(3, 5);

              try {
                final orig = Square.fromName(origStr);
                final dest = Square.fromName(destStr);
                shapes.add(
                  Arrow(color: getColor(colorCode), orig: orig, dest: dest),
                );
              } catch (_) {}
            }
          }
        }
      }

      // Parse all [%csl ...] blocks in the comment
      final cslMatches = RegExp(r'\[%csl\s+([^\]]+)\]').allMatches(comment);
      for (final match in cslMatches) {
        final content = match.group(1);
        if (content != null) {
          final items = content.split(',');
          for (final item in items) {
            final trimmed = item.trim();
            if (trimmed.length == 3) {
              // e.g. Re2
              final colorCode = trimmed[0];
              final sqStr = trimmed.substring(1, 3);

              try {
                final sq = Square.fromName(sqStr);
                shapes.add(Circle(color: getColor(colorCode), orig: sq));
              } catch (_) {}
            }
          }
        }
      }
    }

    return shapes;
  }

  Positioned _buildBoardBadge({
    required Square square,
    required Color color,
    required Widget child,
    double sizeFactor = 0.42,
  }) {
    final squareSize = widget.size / 8;
    final effectiveFile = widget.isFlipped ? 7 - square.file : square.file;
    final effectiveRank = widget.isFlipped ? square.rank : 7 - square.rank;
    final left = effectiveFile * squareSize;
    final top = effectiveRank * squareSize;
    final badgeSize = squareSize * sizeFactor;
    final badgeLeftRaw = left + squareSize - (badgeSize / 2);
    final badgeTopRaw = top - (badgeSize / 2) + (squareSize * 0.04);
    final badgeLeft = badgeLeftRaw.clamp(0.0, widget.size - badgeSize);
    final badgeTop = badgeTopRaw.clamp(0.0, widget.size - badgeSize);

    return Positioned(
      left: badgeLeft,
      top: badgeTop,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1.0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          builder:
              (context, scale, c) => Transform.scale(scale: scale, child: c),
          child: Container(
            width: badgeSize,
            height: badgeSize,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 0.5,
              ),
            ),
            padding: EdgeInsets.all(badgeSize * 0.16),
            child: RepaintBoundary(child: child),
          ),
        ),
      ),
    );
  }

  Positioned _buildBoardAnnotationBadge({
    required Square square,
    required LichessMoveAnnotation annotation,
  }) {
    return _buildBoardBadge(
      square: square,
      color: annotation.type.color,
      sizeFactor: 0.40,
      child: SvgPicture.asset(
        annotation.type.iconAssetPath,
        fit: BoxFit.contain,
      ),
    );
  }

  /// Render any NAG that doesn't have a dedicated SVG as a Container+Text
  /// badge — same anchor + shadow language as the SVG badges, but the symbol
  /// is the literal Unicode glyph from [NagDisplay].
  Positioned _buildBoardNagTextBadge({
    required Square square,
    required NagDisplay display,
  }) {
    final squareSize = widget.size / 8;
    final badgeSize = squareSize * 0.42;
    return _buildBoardBadge(
      square: square,
      color: display.color,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            display.symbol,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.0,
              fontSize: badgeSize * 0.62,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _AnalysisBoard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.game.gameId != oldWidget.game.gameId) {
      _cancelLikeInteraction(resetAnchor: true);
    }

    // We used to bump a _selectionEpoch and re-key the Chessboard on every
    // external FEN change to clear chessground's tap-selection — but the
    // resulting widget remount made chessground's didUpdateWidget never run,
    // which skipped its built-in 200ms piece-translation animation. The
    // key is now stable so chessground sees the FEN change and animates
    // pieces from the old to the new squares.

    final analysisState = widget.chessBoardState.analysisState;
    final isAtGameEnd = _isAtGameEnd(analysisState);
    final gameStatus = widget.game.gameStatus;
    final isGameOver =
        gameStatus != GameStatus.ongoing && gameStatus != GameStatus.unknown;
    final shouldShowEffect = isGameOver && isAtGameEnd;

    if (shouldShowEffect && !_wasAtEnd) {
      // didUpdateWidget can run inside a LayoutBuilder's performLayout, so
      // mutating the provider here throws "Tried to modify a provider while
      // the widget tree was building." Defer the write past the current frame.
      final gameId = widget.game.gameId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(eventNoSpoilersRevealedGamesProvider.notifier)
            .reveal(gameId);
      });
    }

    // When navigating TO the final position, delay showing the effect for animation
    if (shouldShowEffect && !_wasAtEnd) {
      _showDelayedGameEndingEffect = false;
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted && _isAtGameEnd(widget.chessBoardState.analysisState)) {
          setState(() => _showDelayedGameEndingEffect = true);
        }
      });
    }
    // When navigating AWAY from the final position, delay hiding the effect for animation
    else if (!shouldShowEffect && _wasAtEnd && _showDelayedGameEndingEffect) {
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted && !_isAtGameEnd(widget.chessBoardState.analysisState)) {
          setState(() => _showDelayedGameEndingEffect = false);
        }
      });
    }
    // For other cases (e.g., game not over, entered analysis variation), hide immediately
    else if (!shouldShowEffect && !_wasAtEnd) {
      _showDelayedGameEndingEffect = false;
    }

    _wasAtEnd = isAtGameEnd;

    // External flip (e.g., bottom-nav button): if orientation changed
    // without us driving the commit, play a quick swing-in so it doesn't
    // snap. We start at edge-on with the new orientation already rendered
    // and animate back to flat.
    if (widget.isFlipped != oldWidget.isFlipped &&
        !_flipDragActive &&
        !_flipCommitting &&
        _flipProgress.value == 0) {
      _flipPhaseFrom = _flipMaxProgress;
      _flipPhaseTo = 0.0;
      _flipProgress.value = _flipPhaseFrom;
      _flipCommitCtrl.duration = _flipPhaseFullDuration;
      _flipCommitCtrl.forward(from: 0.0);
    }
  }

  @override
  void initState() {
    super.initState();
    _likeFlightAnchor = ref.read(likeFlightAnchorProvider);
    final analysisState = widget.chessBoardState.analysisState;
    _wasAtEnd = _isAtGameEnd(analysisState);

    // If starting at the end position, show effect immediately
    final gameStatus = widget.game.gameStatus;
    final isGameOver =
        gameStatus != GameStatus.ongoing && gameStatus != GameStatus.unknown;
    if (isGameOver && _wasAtEnd) {
      _showDelayedGameEndingEffect = true;
    }

    _flipProgress = ValueNotifier<double>(0.0);
    _flipCommitCtrl = AnimationController(
      vsync: this,
      duration: _flipPhaseFullDuration,
    )..addListener(_drivePhaseFromController);

    if (kDebugMode) {
      _debugLatest = this;
      if (!_debugExtRegistered) {
        _debugExtRegistered = true;
        developer.registerExtension('ext.flutter.likeBoard', (
          method,
          params,
        ) async {
          _debugLatest?._handleDoubleTapLike();
          return developer.ServiceExtensionResponse.result('{"ok":true}');
        });
      }
    }
  }

  @override
  void dispose() {
    _cancelLikeInteraction(resetAnchor: true);
    _flipCommitCtrl.dispose();
    _flipProgress.dispose();
    _burstController.dispose();
    super.dispose();
  }

  // Drive the live rotation from the phase tween. easeInOutCubic keeps
  // angular velocity continuous across the edge-on midpoint (the curve's
  // derivative is 0 at both endpoints), so the two phases visually weld
  // into one continuous flip with no bump or wobble.
  void _drivePhaseFromController() {
    final t = Curves.easeInOutCubic.transform(_flipCommitCtrl.value);
    _flipProgress.value = _flipPhaseFrom + (_flipPhaseTo - _flipPhaseFrom) * t;
  }

  // Duration scales linearly with how much of the half-rotation this phase
  // covers, so angular speed stays constant — a short phase (user already
  // dragged most of the way) finishes quickly, a full phase takes the base
  // duration. Floored at _flipPhaseMinDuration so a near-edge release still
  // reads as motion instead of a snap.
  Duration _scaledPhaseDuration(double phaseDistance) {
    final normalized = (phaseDistance / _flipMaxProgress).clamp(0.0, 1.0);
    final scaledMs =
        (_flipPhaseFullDuration.inMilliseconds * normalized).round();
    final minMs = _flipPhaseMinDuration.inMilliseconds;
    return Duration(milliseconds: scaledMs < minMs ? minMs : scaledMs);
  }

  void _onFlipDragStart(DragStartDetails details) {
    // Always allow a fresh gesture to take over — even mid-commit. Bump the
    // token so any in-flight _commitFlip bails on its next await, then stop
    // the commit controller so the user picks up rotation from where it is.
    _flipCommitToken++;
    _flipCommitting = false;
    _flipDragActive = true;
    _flipCommitCtrl.stop();
    _flipProgress.value = _flipProgress.value.clamp(
      -_flipMaxProgress,
      _flipMaxProgress,
    );
  }

  void _onFlipDragUpdate(DragUpdateDetails details) {
    if (!_flipDragActive) return;
    final delta = details.primaryDelta ?? 0.0;
    if (delta == 0.0 || widget.size <= 0) return;
    // Map raw pixels to progress: a full board height of swipe corresponds
    // to the full ±_flipMaxProgress range (i.e., edge-on).
    final progressDelta = (delta / widget.size) * _flipMaxProgress;
    _flipProgress.value = (_flipProgress.value + progressDelta).clamp(
      -_flipMaxProgress,
      _flipMaxProgress,
    );
  }

  void _onFlipDragEnd(DragEndDetails details) {
    if (!_flipDragActive) return;
    _flipDragActive = false;
    final v = _flipProgress.value;
    final velocity = details.primaryVelocity ?? 0.0;
    final pastThreshold = v.abs() >= _flipCommitProgressThreshold;
    final hasFlingVelocity = velocity.abs() >= _flipCommitVelocityThreshold;
    // If the fling agrees with the current direction (or is dominant),
    // commit. Otherwise either cancel (small drag, low velocity) or commit
    // if the user already dragged past the visual threshold.
    if (hasFlingVelocity || pastThreshold) {
      final commitSign =
          hasFlingVelocity
              ? (velocity > 0 ? 1.0 : -1.0)
              : (v >= 0 ? 1.0 : -1.0);
      _commitFlip(commitSign);
    } else {
      _animateToFlat();
    }
  }

  void _onFlipDragCancel() {
    if (!_flipDragActive) return;
    _flipDragActive = false;
    if (_flipCommitting) return;
    _animateToFlat();
  }

  void _animateToFlat() {
    _flipPhaseFrom = _flipProgress.value;
    _flipPhaseTo = 0.0;
    _flipCommitCtrl.duration = _scaledPhaseDuration(
      (_flipPhaseTo - _flipPhaseFrom).abs(),
    );
    _flipCommitCtrl.forward(from: 0.0);
  }

  /// Two-phase flip: animate to edge-on, swap orientation under cover of
  /// the invisible 90° midpoint, jump to the opposite edge-on, then animate
  /// back to flat. Both phases share the same per-π-radian duration and the
  /// same easeInOutCubic curve, so the angular speed is identical regardless
  /// of swipe direction or how far the user dragged before releasing.
  /// Driven by awaited TickerFutures so the state machine can't desync —
  /// and any new drag bumps the token to bail us out.
  Future<void> _commitFlip(double sign) async {
    final token = ++_flipCommitToken;
    _flipCommitting = true;
    try {
      // Phase 1: drive rotation from current position to edge-on.
      _flipPhaseFrom = _flipProgress.value;
      _flipPhaseTo = sign * _flipMaxProgress;
      _flipCommitCtrl.duration = _scaledPhaseDuration(
        (_flipPhaseTo - _flipPhaseFrom).abs(),
      );
      await _flipCommitCtrl.forward(from: 0.0);
      if (!mounted || token != _flipCommitToken) return;

      // At the invisible midpoint, swap the real orientation. The board
      // rebuild is queued by Riverpod and lands on the next frame, by which
      // time we're already on the back half of the rotation.
      ref
          .read(
            chessBoardScreenProviderNew(
              ChessBoardProviderParams(game: widget.game, index: widget.index),
            ).notifier,
          )
          .flipBoard();
      HapticFeedback.lightImpact();

      // Phase 2: jump to the opposite edge-on (visually identical — both
      // render as a horizontal line) and animate back to flat over the full
      // half-rotation. Always the base duration, so the second half feels
      // identical between swipe directions.
      _flipPhaseFrom = -sign * _flipMaxProgress;
      _flipPhaseTo = 0.0;
      _flipProgress.value = _flipPhaseFrom;
      _flipCommitCtrl.duration = _flipPhaseFullDuration;
      await _flipCommitCtrl.forward(from: 0.0);
      if (!mounted || token != _flipCommitToken) return;
      // Belt-and-braces: snap to a clean zero so a future drag starts from
      // exactly flat, even if the curve left a sub-pixel ε.
      _flipProgress.value = 0.0;
    } finally {
      if (mounted && token == _flipCommitToken) {
        _flipCommitting = false;
      }
    }
  }

  // 3D card-flip wrapper. Listens to the rotation progress and applies an
  // X-axis rotation with perspective plus a subtle scale dip toward edge-on
  // so the flip reads as a tactile, physical card turn.
  //
  // Gesture layering (outer → inner):
  //   * Listener (passive, raw pointer events) — detects the same-square
  //     double-tap-to-like WITHOUT entering the gesture arena, so it can never
  //     swallow a tap-to-move. See _handleBoardPointerDownForLike.
  //   * GestureDetector — picks up vertical drags only (the card flip). A pure
  //     tap has no drag, so the drag recognizer loses the arena on taps and the
  //     Chessboard's own pointer-based tap-to-move stays intact.
  Widget _wrapWithFlipGesture(Widget child) {
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _handleBoardPointerDownForLike,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onVerticalDragStart: _onFlipDragStart,
        onVerticalDragUpdate: _onFlipDragUpdate,
        onVerticalDragEnd: _onFlipDragEnd,
        onVerticalDragCancel: _onFlipDragCancel,
        // Debug-only long-press alias for the same like flow. Lets Marionette
        // and other agent-driven test harnesses trigger the chain without
        // having to fight the chessground tap-to-move gesture arena.
        onLongPressStart:
            kDebugMode
                ? (details) {
                  _lastTapPosition = details.localPosition;
                  _lastTapGlobalPosition = details.globalPosition;
                  _handleDoubleTapLike();
                }
                : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _flipProgress,
              child: child,
              builder: (context, progress, c) {
                if (progress == 0.0) return c!;
                final rotation = progress * math.pi;
                // Peaks at ~6% shrink when edge-on (|rotation| = π/2), eases back
                // to 1.0 at flat. Sells the depth without making pieces lose
                // tap-target presence mid-flip.
                final scale = 1.0 - 0.06 * math.sin(rotation.abs());
                return Transform(
                  alignment: Alignment.center,
                  transform:
                      Matrix4.identity()
                        ..setEntry(3, 2, 0.0014)
                        ..rotateX(rotation)
                        ..scaleByDouble(scale, scale, scale, 1.0),
                  child: c,
                );
              },
            ),
            // Heart-burst overlay — sits flat over the board (never rotates with
            // the flip), ignores pointers, and removes itself when each burst ends.
            Positioned.fill(
              child: Builder(
                builder:
                    (context) => HeartBurstLayer(
                      controller: _burstController,
                      color: context.colors.danger,
                      reduceMotion: MediaQuery.disableAnimationsOf(context),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Detects the same-square double-tap-to-like via raw pointer events.
  ///
  /// Runs on a passive [Listener] that wraps the board, so it never joins the
  /// gesture arena and never steals a tap from chessground's pointer-based
  /// tap-to-move. A tap-two-squares move always lands its two taps on two
  /// DIFFERENT squares, so by only firing when two quick taps hit the SAME
  /// board square we guarantee a move can never be mistaken for a like.
  void _handleBoardPointerDownForLike(PointerDownEvent event) {
    // Mouse right/middle clicks and multi-touch shouldn't arm a like.
    if (event.buttons != kPrimaryButton && event.buttons != 0) {
      _resetLikeTapTracking();
      return;
    }

    final boardSize = widget.size;
    final squareSize = boardSize / 8;
    if (squareSize <= 0) {
      _resetLikeTapTracking();
      return;
    }

    final local = event.localPosition;
    // Taps outside the board square (e.g. coordinate gutters) never count.
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx >= boardSize ||
        local.dy >= boardSize) {
      _resetLikeTapTracking();
      return;
    }

    final file = (local.dx / squareSize).floor().clamp(0, 7);
    final rank = (local.dy / squareSize).floor().clamp(0, 7);
    final squareIndex = rank * 8 + file;

    final lastIndex = _lastLikeTapSquareIndex;
    final lastTime = _lastLikeTapTimestamp;
    final isSameSquare = lastIndex != null && lastIndex == squareIndex;
    final withinWindow =
        lastTime != null && (event.timeStamp - lastTime) <= kDoubleTapTimeout;

    if (isSameSquare && withinWindow) {
      // Second quick tap on the same square → like. Reset so a held third tap
      // can't immediately re-fire.
      _resetLikeTapTracking();
      _lastTapPosition = local;
      _lastTapGlobalPosition = event.position;
      _handleDoubleTapLike();
    } else {
      // First tap, a different square, or too slow → (re)arm for a possible
      // same-square second tap.
      _lastLikeTapSquareIndex = squareIndex;
      _lastLikeTapTimestamp = event.timeStamp;
    }
  }

  void _resetLikeTapTracking() {
    _lastLikeTapSquareIndex = null;
    _lastLikeTapTimestamp = null;
  }

  /// Likes/unlikes the currently-displayed game and spawns the matching burst.
  /// Source-agnostic: broadcast, gamebase and twic games are all likeable; the
  /// double-tap saves a real SavedAnalysis into the per-user "Liked Games"
  /// folder via the canonical "Add to library" flow.
  ///
  /// On LIKE, the chained sequence is:
  ///   1. Burst spawns on the board.
  ///   2. Save button slot stays as the normal save/edit icon.
  ///   3. When the burst finishes, a small "flying heart" overlay tweens
  ///      from the burst's screen position to the save-button slot.
  ///   4. On landing, the save/edit icon remains visible with a small red heart
  ///      badge under it (game is now liked).
  void _handleDoubleTapLike() {
    final game = widget.game;
    debugPrint('[HeartFlight] like-trigger fired source=${game.source.name}');
    if (!_isLikeableSource(game.source)) return;
    if (_likeInteractionInProgress) {
      debugPrint(
        '[HeartFlight] like-trigger ignored in-flight gameId=${game.gameId}',
      );
      return;
    }

    _likeInteractionInProgress = true;
    final interactionToken = ++_likeInteractionToken;
    _removeFlyingHeartEntry();

    final wasLiked =
        ref
            .read(likedGamesProvider)
            .valueOrNull
            ?.any((a) => a.sourceGameId == game.likeId) ??
        false;
    final tapLocal =
        _lastTapPosition == Offset.zero
            ? Offset(widget.size / 2, widget.size / 2)
            : _lastTapPosition;
    final tapGlobal =
        _lastTapGlobalPosition == Offset.zero
            ? tapLocal
            : _lastTapGlobalPosition;

    final anchor = _likeFlightAnchor;

    if (!wasLiked) {
      // Stronger initial "thump" — feels tactile under a real double-tap.
      // No haptic for unlike (intentional asymmetry per user feedback).
      HapticFeedback.mediumImpact();
      anchor.start(); // save button slot receives the incoming heart flight
    }

    _burstController.spawn(
      position: tapLocal,
      isUnlike: wasLiked,
      onFinished: () {
        if (!mounted) return;
        if (interactionToken != _likeInteractionToken) return;
        if (wasLiked) return; // unlike: no flight, no slot fill
        _runFlight(
          from: tapGlobal,
          anchor: anchor,
          interactionToken: interactionToken,
        );
      },
    );

    // Fire-and-forget — the notifier handles optimistic state + rollback.
    final toggleFuture = ref
        .read(likedGamesProvider.notifier)
        .toggle(game)
        .then<void>((_) {});
    final visualFloor = Future<void>.delayed(
      wasLiked ? _likeInteractionUnlikeDuration : _likeInteractionLikeDuration,
    );
    unawaited(
      Future.wait<void>([toggleFuture, visualFloor])
          .catchError((Object error, StackTrace stackTrace) {
            debugPrint('[HeartFlight] like-toggle future failed: $error');
            return <void>[];
          })
          .whenComplete(() {
            if (!mounted) return;
            if (interactionToken != _likeInteractionToken) return;
            _likeInteractionInProgress = false;
          }),
    );
  }

  void _removeFlyingHeartEntry() {
    _flyingHeartEntry?.remove();
    _flyingHeartEntry = null;
  }

  void _cancelLikeInteraction({required bool resetAnchor}) {
    _likeInteractionToken++;
    _likeInteractionInProgress = false;
    _removeFlyingHeartEntry();
    if (resetAnchor) {
      _likeFlightAnchor.reset();
    }
  }

  void _runFlight({
    required Offset from,
    required LikeFlightAnchor anchor,
    required int interactionToken,
  }) {
    // Dock onto the small heart BADGE, not the whole save slot — so the big
    // heart lands exactly where, and at the same size as, the little heart it
    // turns into. Fall back to the slot rect only if the badge isn't laid out.
    final badgeRect = anchor.heartBadgeGlobalRect();
    final target = badgeRect ?? anchor.saveButtonGlobalRect();
    debugPrint('[HeartFlight] _runFlight from=$from target=${target?.center}');
    if (target == null) {
      // No slot to fly to — just complete the chain.
      anchor.land();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        if (interactionToken != _likeInteractionToken) return;
        anchor.reset();
      });
      return;
    }
    anchor.beginFlight();
    final overlay = Overlay.of(context, rootOverlay: true);
    final flightColor = context.colors.danger;
    // Visual continuity: start at the same size the in-board burst just ended
    // at (≈55% of board.shortestSide — matches HeartBurstLayer's default),
    // shrink down to the badge glyph size so the flying heart becomes the
    // badge — a continuous "big heart turns into the little one" morph.
    final startSize = widget.size * 0.55;
    final endSize = target.shortestSide;
    _removeFlyingHeartEntry();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder:
          (_) => FlyingHeart(
            from: from,
            to: target.center,
            color: flightColor,
            startSize: startSize,
            endSize: endSize,
            duration: const Duration(milliseconds: 470),
            onArrived: () {
              if (_flyingHeartEntry != entry) return;
              _removeFlyingHeartEntry();
              if (!mounted) return;
              if (interactionToken != _likeInteractionToken) return;
              anchor.land();
              // Tiny "click into place" haptic at the moment the heart docks.
              HapticFeedback.selectionClick();
              Future.delayed(const Duration(milliseconds: 540), () {
                if (!mounted) return;
                if (interactionToken != _likeInteractionToken) return;
                anchor.reset();
              });
            },
          ),
    );
    _flyingHeartEntry = entry;
    overlay.insert(entry);
  }

  bool _isLikeableSource(GameSource source) =>
      source == GameSource.supabase ||
      source == GameSource.gamebase ||
      source == GameSource.twic ||
      // Games opened from a library database or the Liked Games folder are
      // saved analyses; their like identity is the original sourceGameId
      // (see GamesTourModel.likeId), so they like/unlike like everywhere else.
      source == GameSource.savedAnalysis;

  @override
  Widget build(BuildContext context) {
    // PERF: Use .select() to only rebuild when specific properties change
    final colorScheme = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.colorScheme ?? const BoardSettingsNew().colorScheme,
      ),
    );
    final pieceAssets = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.pieceAssets ?? const BoardSettingsNew().pieceAssets,
      ),
    );
    final showCoordinates = ref.watch(
      boardSettingsProviderNew.select(
        (s) => s.valueOrNull?.showCoordinates ?? true,
      ),
    );
    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.index,
    );
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    final selectionClearRequestId = ref.watch(
      boardSelectionClearRequestProvider(
        _boardSelectionClearKey(widget.game, widget.index),
      ),
    );
    if (_lastSelectionClearRequestId == null) {
      _lastSelectionClearRequestId = selectionClearRequestId;
    } else if (_lastSelectionClearRequestId != selectionClearRequestId) {
      _lastSelectionClearRequestId = selectionClearRequestId;
      _clearBoardSelectionForFrame = true;
    }
    if (_clearBoardSelectionForFrame) {
      _scheduleSelectionRestore();
    }
    final analysisGame = widget.chessBoardState.analysisState.game;
    final activeMovePointer = widget.chessBoardState.analysisState.movePointer;
    final activeMove = _moveForPointer(analysisGame, activeMovePointer);

    // PERF: Use .select() to only rebuild when showPvArrows changes
    final showPvArrows = ref.watch(
      engineSettingsProviderNew.select(
        (s) => s.valueOrNull?.showPvArrows ?? true,
      ),
    );

    // Game-ending effects only belong to the original mainline, not branches.
    final gameStatus = widget.game.gameStatus;
    final isAtGameEnd =
        _isAtGameEnd(widget.chessBoardState.analysisState) &&
        activeMovePointer.length == 1;
    final isGameOver =
        gameStatus != GameStatus.ongoing && gameStatus != GameStatus.unknown;
    final spoilerState = ref.watch(eventNoSpoilersProvider(widget.game.tourId));
    final spoilersRevealedForGame = ref.watch(
      eventNoSpoilersRevealedGamesProvider.select(
        (gameIds) => gameIds.contains(widget.game.gameId),
      ),
    );
    final canShowFinishedSpoilers =
        (!spoilerState.isLoading && !spoilerState.enabled) ||
        !isGameOver ||
        spoilersRevealedForGame;

    // Use delayed flag to allow move animation to complete first
    final showGameEndingEffect =
        isGameOver &&
        isAtGameEnd &&
        _showDelayedGameEndingEffect &&
        canShowFinishedSpoilers;

    final boardAnnotation =
        (() {
          if (analysisGame == null ||
              widget.chessBoardState.isPvPreviewActive) {
            return null;
          }
          final mainlineSans =
              analysisGame.mainline.map((move) => move.san).toList();
          final lichessGameId = _extractLichessGameId(analysisGame);
          final lichessSiteUrl = _extractLichessSiteUrl(analysisGame);
          final lichessAnnotationsAsync = ref.watch(
            lichessMoveAnnotationsProvider(
              LichessMoveAnnotationsParams(
                lichessGameId: lichessGameId,
                siteUrl: lichessSiteUrl,
                signature: _moveSansSignature(mainlineSans),
                moveSans: mainlineSans,
                isLiveGame: analysisGame.isLiveGame,
              ),
            ),
          );
          final lichessAnnotations =
              lichessAnnotationsAsync.valueOrNull ??
              const <int, LichessMoveAnnotation>{};

          final isOnMainline =
              activeMovePointer.isEmpty || activeMovePointer.length == 1;

          // 1. Author/user NAGs win — they reflect explicit intent and must
          // override Lichess analysis classifications. Quality NAGs ($1–$4)
          // get the high-fidelity SVG badge here; non-mappable NAGs ($5–$7,
          // $10+) return null so Path B renders the Unicode glyph badge.
          final mergedNags = _mergeUserNagsForMovePointer(
            activeMove,
            activeMovePointer,
            widget.chessBoardState.moveNags,
          );
          if (mergedNags.isNotEmpty) {
            final nag = primaryBoardNag(mergedNags) ?? mergedNags.first;
            final type = _mapNagToAnnotationType(nag);
            if (type != null) {
              return LichessMoveAnnotation(type: type, comment: '');
            }
            // Non-mappable NAG — let Path B render the text-glyph badge.
            return null;
          }

          // 2. No explicit NAGs → fall back to Lichess fetched analysis on
          // mainline only.
          if (isOnMainline) {
            final currentMoveIndex =
                activeMovePointer.isEmpty ? -1 : activeMovePointer[0].toInt();
            if (currentMoveIndex >= 0 && lichessAnnotations.isNotEmpty) {
              final annotation = lichessAnnotations[currentMoveIndex];
              if (annotation != null) return annotation;
            }
          }

          return null;
        })();
    final boardAnnotationSquare = _lastMoveDestinationSquare(
      widget.chessBoardState.analysisState.lastMove,
    );
    final Positioned? boardAnnotationBadge =
        (() {
          if (boardAnnotationSquare == null) return null;
          // Path A: Lichess analysis annotation OR mappable NAG → SVG badge.
          if (boardAnnotation != null) {
            return _buildBoardAnnotationBadge(
              square: boardAnnotationSquare,
              annotation: boardAnnotation,
            );
          }
          // Path B: any other NAG ($7, $10, $13–$22, $32, $36, $40, $44, $132,
          // $138, $140, $146) → render the literal Unicode glyph in a circular
          // badge. This is what fixes "exclamation symbols don't show on the
          // board" for NAGs that don't have a Lichess SVG mapping. Includes
          // user-applied NAGs from widget.state.moveNags.
          final mergedNags = _mergeUserNagsForMovePointer(
            activeMove,
            activeMovePointer,
            widget.chessBoardState.moveNags,
          );
          final nag = primaryBoardNag(mergedNags);
          if (nag == null) return null;
          // Skip if it would have been an SVG type (already handled above).
          if (_mapNagToAnnotationType(nag) != null) return null;
          final display = getNagDisplay(nag);
          if (display == null) return null;
          return _buildBoardNagTextBadge(
            square: boardAnnotationSquare,
            display: display,
          );
        })();

    // Calculate square highlights and annotations for game ending
    final gameEndingData =
        showGameEndingEffect
            ? _calculateGameEndingData(
              widget.chessBoardState.analysisState.position,
              gameStatus,
            )
            : null;

    // PERF: RepaintBoundary isolates chessboard repaints from propagating
    // to parent widgets during piece animations and drag operations

    final String displayFen = widget.chessBoardState.analysisState.position.fen;

    final lastMoveHighlights = _buildLastMoveSquareHighlights(
      widget.chessBoardState.analysisState.lastMove,
    );
    final squareHighlightsMap = <Square, SquareHighlight>{};
    for (final entry
        in (gameEndingData?.squareHighlights ?? const IMap.empty()).entries) {
      squareHighlightsMap[entry.key] = entry.value;
    }
    for (final entry in lastMoveHighlights.entries) {
      squareHighlightsMap.putIfAbsent(entry.key, () => entry.value);
    }

    final pvShapes =
        (widget.chessBoardState.showEngineAnalysis &&
                widget.chessBoardState.showPrincipalVariations &&
                showPvArrows)
            ? (widget.chessBoardState.shapes ?? const ISet<Shape>.empty())
            : const ISet<Shape>.empty();

    final annotationShapes = _extractAnnotationShapes(activeMove);
    final allShapes = pvShapes.addAll(annotationShapes);
    final sideToMove = widget.chessBoardState.analysisState.position.turn;
    final playerSide =
        _clearBoardSelectionForFrame
            ? PlayerSide.none
            : (sideToMove == Side.white ? PlayerSide.white : PlayerSide.black);

    final chessboard = Chessboard(
      size: widget.size,
      settings: ChessboardSettings(
        enableCoordinates: showCoordinates,
        animationDuration: const Duration(milliseconds: 200),
        dragFeedbackScale: 1,
        dragTargetKind: DragTargetKind.none,
        pieceShiftMethod: PieceShiftMethod.tapTwoSquares,
        autoQueenPromotionOnPremove: false,
        pieceOrientationBehavior: PieceOrientationBehavior.facingUser,
        // Use theme colors from settings with our custom app colors
        colorScheme: colorScheme,
        // Use piece set from settings
        pieceAssets: pieceAssets,
      ),
      orientation: widget.isFlipped ? Side.black : Side.white,
      fen: displayFen,
      lastMove: widget.chessBoardState.analysisState.lastMove,
      shapes: allShapes,
      squareHighlights: IMap(squareHighlightsMap),
      annotations: gameEndingData?.annotations ?? const IMap.empty(),
      game: GameData(
        playerSide: playerSide,
        validMoves: widget.chessBoardState.analysisState.validMoves,
        sideToMove: sideToMove,
        isCheck: widget.chessBoardState.analysisState.position.isCheck,
        promotionMove: widget.chessBoardState.analysisState.promotionMove,
        onMove: (Move move, {bool? viaDragAndDrop}) {
          notifier.onAnalysisMove(move, viaDragAndDrop: viaDragAndDrop);
        },
        onPromotionSelection: (Role? role) {
          notifier.onAnalysisPromotionSelection(role);
        },
      ),
    );

    // If game ended with a winner, add rotated king overlay with motor animation
    if (showGameEndingEffect && gameEndingData?.loserKingSquare != null) {
      final squareSize = widget.size / 8;
      final loserSquare = gameEndingData!.loserKingSquare!;
      final loserSide =
          gameStatus == GameStatus.whiteWins ? Side.black : Side.white;

      // Calculate square position on board
      final file = loserSquare.file;
      final rank = loserSquare.rank;

      // Adjust for board orientation
      final effectiveFile = widget.isFlipped ? 7 - file : file;
      final effectiveRank = widget.isFlipped ? rank : 7 - rank;

      final pieceKind =
          loserSide == Side.white ? PieceKind.whiteKing : PieceKind.blackKing;
      final pieceImage = pieceAssets[pieceKind];

      // Composite square color: board square color + red highlight
      final isLightSquare = (effectiveFile + effectiveRank) % 2 == 0;
      final baseSquareColor =
          isLightSquare ? colorScheme.lightSquare : colorScheme.darkSquare;
      final compositeColor = Color.alphaBlend(
        kGameEndingRedColor,
        baseSquareColor,
      );

      return _wrapWithFlipGesture(
        RepaintBoundary(
          child: Stack(
            children: [
              chessboard,
              if (boardAnnotationBadge != null) boardAnnotationBadge,
              // Animated falling king overlay using motor springs
              _FallenKingOverlay(
                left: effectiveFile * squareSize,
                top: effectiveRank * squareSize,
                squareSize: squareSize,
                pieceImage: pieceImage!,
                squareColor: compositeColor,
              ),
            ],
          ),
        ),
      );
    }

    // If game ended in a draw, add peace icons on both kings with motor animation
    if (showGameEndingEffect &&
        gameStatus == GameStatus.draw &&
        gameEndingData != null) {
      final squareSize = widget.size / 8;
      final position = widget.chessBoardState.analysisState.position;
      final board = position.board;
      final whiteKingSquare = board.kingOf(Side.white);
      final blackKingSquare = board.kingOf(Side.black);

      if (whiteKingSquare != null && blackKingSquare != null) {
        return _wrapWithFlipGesture(
          RepaintBoundary(
            child: Stack(
              children: [
                chessboard,
                if (boardAnnotationBadge != null) boardAnnotationBadge,
                // Animated peace icon on white king
                _AnimatedPeaceIcon(
                  square: whiteKingSquare,
                  squareSize: squareSize,
                  isFlipped: widget.isFlipped,
                  delayMs: 0,
                ),
                // Animated peace icon on black king (slight delay for stagger effect)
                _AnimatedPeaceIcon(
                  square: blackKingSquare,
                  squareSize: squareSize,
                  isFlipped: widget.isFlipped,
                  delayMs: 100,
                ),
              ],
            ),
          ),
        );
      }
    }

    return _wrapWithFlipGesture(
      RepaintBoundary(
        child: Stack(
          children: [
            chessboard,
            if (boardAnnotationBadge != null) boardAnnotationBadge,
          ],
        ),
      ),
    );
  }

  /// Calculate game ending visual data (square highlights and annotations)
  _GameEndingData? _calculateGameEndingData(
    Position position,
    GameStatus gameStatus,
  ) {
    final board = position.board;
    final whiteKingSquare = board.kingOf(Side.white);
    final blackKingSquare = board.kingOf(Side.black);

    if (whiteKingSquare == null || blackKingSquare == null) {
      return null;
    }

    // Convert dartchess Square to chessground Square
    final whiteKingCgSquare = Square.fromName(whiteKingSquare.name);
    final blackKingCgSquare = Square.fromName(blackKingSquare.name);

    if (gameStatus == GameStatus.draw) {
      // Draw: mint green background for both kings (peace icon added as overlay)
      return _GameEndingData(
        squareHighlights: IMap({
          whiteKingCgSquare: const SquareHighlight(
            details: HighlightDetails(
              solidColor: Color(0xCCADE1CD), // Mint green with alpha
            ),
          ),
          blackKingCgSquare: const SquareHighlight(
            details: HighlightDetails(
              solidColor: Color(0xCCADE1CD), // Mint green with alpha
            ),
          ),
        }),
        annotations: const IMap.empty(),
        loserKingSquare: null,
      );
    } else if (gameStatus == GameStatus.whiteWins) {
      // White wins: black king is the loser
      return _GameEndingData(
        squareHighlights: IMap({
          blackKingCgSquare: const SquareHighlight(
            details: HighlightDetails(
              solidColor: Color(0xCCF53236), // Red with alpha
            ),
          ),
        }),
        annotations: const IMap.empty(),
        loserKingSquare: blackKingSquare,
      );
    } else if (gameStatus == GameStatus.blackWins) {
      // Black wins: white king is the loser
      return _GameEndingData(
        squareHighlights: IMap({
          whiteKingCgSquare: const SquareHighlight(
            details: HighlightDetails(
              solidColor: Color(0xCCF53236), // Red with alpha
            ),
          ),
        }),
        annotations: const IMap.empty(),
        loserKingSquare: whiteKingSquare,
      );
    }

    return null;
  }
}

/// Data class for game ending visual effects
class _GameEndingData {
  final IMap<Square, SquareHighlight> squareHighlights;
  final IMap<Square, Annotation> annotations;
  final Square? loserKingSquare;

  const _GameEndingData({
    required this.squareHighlights,
    required this.annotations,
    required this.loserKingSquare,
  });
}

/// Animated fallen king overlay using motor springs
/// Shows the losing king tilting and falling with smooth physics-based animation
class _FallenKingOverlay extends StatefulWidget {
  final double left;
  final double top;
  final double squareSize;
  final ImageProvider pieceImage;
  final Color squareColor;

  const _FallenKingOverlay({
    required this.left,
    required this.top,
    required this.squareSize,
    required this.pieceImage,
    required this.squareColor,
  });

  @override
  State<_FallenKingOverlay> createState() => _FallenKingOverlayState();
}

class _FallenKingOverlayState extends State<_FallenKingOverlay> {
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    // Trigger animation after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _animate = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.left,
      top: widget.top,
      child: IgnorePointer(
        child: SizedBox(
          width: widget.squareSize,
          height: widget.squareSize,
          child: Stack(
            children: [
              // Opaque background to hide the king piece underneath
              ColoredBox(
                color: widget.squareColor,
                child: const SizedBox.expand(),
              ),
              Center(
                // Animate rotation with motor's bouncy spring
                child: SingleMotionBuilder(
                  motion: const CupertinoMotion.bouncy(),
                  value:
                      _animate
                          ? -math.pi / 4
                          : 0.0, // -45 degrees when animated
                  builder: (context, rotation, child) {
                    return Transform.rotate(
                      angle: rotation,
                      // Rotate around exact center - no offset needed
                      alignment: Alignment.center,
                      child: child,
                    );
                  },
                  child: Image(image: widget.pieceImage, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated peace icon overlay for draw games using motor springs
/// Shows a dove (🕊️) icon in the top-right corner of each king's cell
class _AnimatedPeaceIcon extends StatefulWidget {
  final Square square;
  final double squareSize;
  final bool isFlipped;
  final int delayMs;

  const _AnimatedPeaceIcon({
    required this.square,
    required this.squareSize,
    required this.isFlipped,
    required this.delayMs,
  });

  @override
  State<_AnimatedPeaceIcon> createState() => _AnimatedPeaceIconState();
}

class _AnimatedPeaceIconState extends State<_AnimatedPeaceIcon> {
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    // Trigger animation after delay for stagger effect
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) {
        setState(() => _animate = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.square.file;
    final rank = widget.square.rank;

    // Adjust for board orientation
    final effectiveFile = widget.isFlipped ? 7 - file : file;
    final effectiveRank = widget.isFlipped ? rank : 7 - rank;

    // Smaller icon size for subtle appearance
    final containerSize = widget.squareSize * 0.28;

    return Positioned(
      // Position at top-right corner of the king's square
      left:
          effectiveFile * widget.squareSize +
          widget.squareSize -
          containerSize -
          1,
      top: effectiveRank * widget.squareSize + 1,
      child: IgnorePointer(
        child: SingleMotionBuilder(
          motion: const CupertinoMotion.bouncy(),
          value: _animate ? 1.0 : 0.0,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              alignment: Alignment.topRight,
              child: child,
            );
          },
          child: Container(
            width: containerSize,
            height: containerSize,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Colors.black,
                  BlendMode.srcIn,
                ),
                child: Text(
                  '🕊️',
                  style: TextStyle(fontSize: containerSize * 0.6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonContainer extends StatelessWidget {
  final double height;
  final double width;
  final double borderRadius;

  const _SkeletonContainer({
    required this.height,
    required this.width,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: context.colors.textPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Two-page swipeable bottom panel: notation (page 0) and opening explorer
/// (page 1). Mirrors the gamebase explorer screen's `_ExplorerBottomPanels`
/// pattern but kept screen-local: each chess board screen instance has its
/// own page controller so swiping in one game doesn't bleed into another.
///
/// When [syncWithGamebaseToggle] is true (passed by tour-game contexts that
/// also surface the explicit "open Gamebase" toggle button), the page index
/// stays in sync with [gamebaseOverlayEnabledProvider] in both directions.
class _AnalysisSwipePanels extends ConsumerStatefulWidget {
  const _AnalysisSwipePanels({
    required this.movesDisplay,
    required this.gamebaseDisplay,
    required this.syncWithGamebaseToggle,
  });

  final Widget movesDisplay;
  final Widget gamebaseDisplay;
  final bool syncWithGamebaseToggle;

  @override
  ConsumerState<_AnalysisSwipePanels> createState() =>
      _AnalysisSwipePanelsState();
}

class _AnalysisSwipePanelsState extends ConsumerState<_AnalysisSwipePanels>
    with SingleTickerProviderStateMixin {
  static const int _totalPages = 2;

  late final PageController _pageController;
  int _currentPage = 0;

  late AnimationController _swipeController;
  late Animation<double> _swipeFadeAnimation;
  late Animation<double> _swipeScaleAnimation;
  late Animation<double> _swipeMoveAnimation;
  bool _showTutorialOverlay = false;
  OverlayEntry? _tutorialEntry;
  int _lastTutorialRequest = 0;

  @override
  void initState() {
    super.initState();
    if (widget.syncWithGamebaseToggle) {
      final enabled =
          ref.read(gamebaseOverlayEnabledProvider).valueOrNull ?? false;
      _currentPage = enabled ? 1 : 0;
    }
    _pageController = PageController(initialPage: _currentPage);
    _lastTutorialRequest = ref.read(analysisSwitchViewsTutorialRequestProvider);
    _setupSwipeAnimation();
  }

  @override
  void dispose() {
    _removeTutorialOverlay();
    _swipeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _setupSwipeAnimation() {
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _swipeFadeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 80),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 10),
    ]).animate(_swipeController);

    _swipeScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 10),
      TweenSequenceItem(tween: ConstantTween(0.8), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 10),
    ]).animate(_swipeController);

    _swipeMoveAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 15),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 10),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 5),
    ]).animate(_swipeController);

    // Slide the notation panel underneath the finger hint so the user sees
    // the view they'll land on as the hand sweeps.
    _swipeController.addListener(() {
      if (!_pageController.hasClients) return;
      final width = _pageController.position.viewportDimension;
      final canGoNext = _currentPage < _totalPages - 1;
      final direction = canGoNext ? 1.0 : -1.0;
      final maxDrag = width * 0.5;
      final moveValue = _swipeMoveAnimation.value;
      final handTranslation = -1 * moveValue * maxDrag * direction;
      final baseOffset = _currentPage * width;
      _pageController.position.jumpTo(baseOffset - handTranslation);
    });
  }

  Future<void> _maybeStartSwitchViewsTutorial() async {
    if (!mounted || _showTutorialOverlay) return;

    final prefs = ref.read(sharedPreferencesRepository);
    final dontShow =
        await prefs.getBool(kSwitchViewsWalkthroughDontShowKey) ?? false;
    if (!mounted) return;
    // Skipping this step must still hand off to step 3 so the like teaching
    // isn't lost for users who already dismissed/saw Switch Views.
    if (dontShow) {
      _requestLikeTutorial();
      return;
    }

    // Show once: if this teaching has ever been seen (here or in the standalone
    // gamebase explorer), skip it but still hand off to step 3.
    final lastShownMs = await prefs.getInt(kSwitchViewsWalkthroughShownDateKey);
    if (lastShownMs != null) {
      _requestLikeTutorial();
      return;
    }
    if (!mounted) return;

    _showTutorialOverlay = true;
    _insertTutorialOverlay();

    int count = 0;
    void statusListener(AnimationStatus status) {
      if (status != AnimationStatus.completed) return;
      count++;
      if (count < 1) {
        _swipeController.forward(from: 0.0);
      } else {
        _swipeController.removeStatusListener(statusListener);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentPage);
        }
      }
    }

    _swipeController.addStatusListener(statusListener);
    _swipeController.forward();

    await prefs.setInt(
      kSwitchViewsWalkthroughShownDateKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _insertTutorialOverlay() {
    _tutorialEntry = OverlayEntry(
      builder:
          (_) => SwitchViewsTutorialOverlay(
            animationController: _swipeController,
            moveAnimation: _swipeMoveAnimation,
            fadeAnimation: _swipeFadeAnimation,
            scaleAnimation: _swipeScaleAnimation,
            currentPageIndex: _currentPage,
            totalItems: _totalPages,
            currentStep: 2,
            totalSteps: 3,
            // Normal dismiss → chain step 3 (Double-Tap to Like).
            onDismiss: () {
              _onWalkthroughFinished();
              _requestLikeTutorial();
            },
            // "Don't show again" suppresses step 3 too (handled in
            // _suppressWalkthrough), so do NOT chain it here.
            onDontShowAgain: () async {
              await _suppressWalkthrough();
              _onWalkthroughFinished();
            },
          ),
    );
    Overlay.of(context, rootOverlay: true).insert(_tutorialEntry!);
  }

  /// Bumps the shared counter so the outer screen runs the step 3/3 like
  /// teaching right after this one — back-to-back, never overlapping.
  void _requestLikeTutorial() {
    if (!mounted) return;
    ref.read(likeTutorialRequestProvider.notifier).update((v) => v + 1);
  }

  void _removeTutorialOverlay() {
    _tutorialEntry?.remove();
    _tutorialEntry = null;
  }

  void _onWalkthroughFinished() {
    _removeTutorialOverlay();
    _swipeController.stop();
    _swipeController.reset();
    if (_pageController.hasClients) {
      _pageController.jumpToPage(_currentPage);
    }
    if (mounted) {
      setState(() {
        _showTutorialOverlay = false;
      });
    } else {
      _showTutorialOverlay = false;
    }
  }

  Future<void> _suppressWalkthrough() async {
    final prefs = ref.read(sharedPreferencesRepository);
    // Opting out here also suppresses the chained step 3 like teaching.
    await Future.wait([
      prefs.setBool(kSwitchViewsWalkthroughDontShowKey, true),
      prefs.setBool(kLikeWalkthroughDontShowKey, true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // React to the parent's request to chain step 2 after step 1 dismisses.
    // Using a monotonically increasing counter means the signal re-fires
    // cleanly if the user reopens the chess board and the outer walkthrough
    // runs again.
    ref.listen<int>(analysisSwitchViewsTutorialRequestProvider, (_, next) {
      if (next <= _lastTutorialRequest) return;
      _lastTutorialRequest = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeStartSwitchViewsTutorial();
      });
    });

    if (widget.syncWithGamebaseToggle) {
      ref.listen<AsyncValue<bool>>(gamebaseOverlayEnabledProvider, (
        previous,
        next,
      ) {
        if (_showTutorialOverlay) return;
        final enabled = next.valueOrNull ?? false;
        final targetPage = enabled ? 1 : 0;
        if (targetPage == _currentPage || !_pageController.hasClients) return;
        _pageController.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      });
    }

    return PageView(
      controller: _pageController,
      dragStartBehavior: DragStartBehavior.down,
      physics: const ClampingScrollPhysics(),
      onPageChanged: (page) {
        if (_showTutorialOverlay) return;
        _currentPage = page;
        if (!widget.syncWithGamebaseToggle) return;
        // Keep the toggle button reflection in sync with the swipe so the
        // button label/icon doesn't lie about the visible panel.
        final notifier = ref.read(gamebaseOverlayEnabledProvider.notifier);
        final currentEnabled =
            ref.read(gamebaseOverlayEnabledProvider).valueOrNull ?? false;
        final shouldEnable = page == 1;
        if (currentEnabled != shouldEnable) {
          notifier.setEnabled(shouldEnable);
        }
      },
      children: [widget.movesDisplay, widget.gamebaseDisplay],
    );
  }
}

class _FenPositionGamesTable extends ConsumerStatefulWidget {
  const _FenPositionGamesTable({required this.fen, required this.enabled});

  final String fen;
  final bool enabled;

  @override
  ConsumerState<_FenPositionGamesTable> createState() =>
      _FenPositionGamesTableState();
}

class _FenPositionGamesTableState
    extends ConsumerState<_FenPositionGamesTable> {
  static const int _pageSize = 20;
  static const double _scrollPrefetchExtent = 520;

  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  final List<GamesTourModel> _games = <GamesTourModel>[];

  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _nextPageNumber = 0;
  int _requestToken = 0;
  String? _error;
  int? _totalCount;

  // Filters drive both the table fetch and the per-row / header bottom sheets,
  // so the user sees a consistent set of games. `/api/game-position/fen/games`
  // accepts the same filter+sort surface as the explorer endpoint.
  GamebaseFilters _filters = const GamebaseFilters();

  bool get _hasActiveFilters {
    final f = _filters;
    return f.timeControls.isNotEmpty ||
        f.gameResult != null ||
        f.isOnline != null ||
        f.minRating != null ||
        f.maxRating != null ||
        f.yearFrom != null ||
        f.yearTo != null ||
        f.playerColor != null ||
        f.playerIds.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.enabled) {
      _fetchPage(reset: true);
    }
  }

  @override
  void didUpdateWidget(covariant _FenPositionGamesTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameEnabled = !oldWidget.enabled && widget.enabled;
    final positionChanged =
        _positionKey(oldWidget.fen) != _positionKey(widget.fen);
    if (widget.enabled && (becameEnabled || positionChanged)) {
      _fetchPage(reset: true);
    }
  }

  @override
  void dispose() {
    _requestToken++;
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  static String _positionKey(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return fen.trim();
    return parts.take(4).join(' ');
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        !widget.enabled ||
        _isInitialLoading ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }
    if (_scrollController.position.extentAfter > _scrollPrefetchExtent) {
      return;
    }
    _fetchPage();
  }

  Future<void> _fetchPage({bool reset = false}) async {
    if (!widget.enabled) return;

    if (reset) {
      setState(() {
        _rows.clear();
        _games.clear();
        _isInitialLoading = true;
        _isLoadingMore = false;
        _hasMore = true;
        _nextPageNumber = 0;
        _totalCount = null;
        _error = null;
      });
    } else {
      if (_isInitialLoading || _isLoadingMore || !_hasMore) return;
      setState(() {
        _isLoadingMore = true;
        _error = null;
      });
    }

    final requestToken = ++_requestToken;
    final pageNumber = _nextPageNumber;

    try {
      final timeControlFilter =
          _filters.timeControls.isNotEmpty ? _filters.timeControls.first : null;
      final playerIdFilter =
          _filters.playerIds.isNotEmpty ? _filters.playerIds.first : null;
      final response = await ref
          .read(gamebaseRepositoryProvider)
          .getFenPositionGames(
            fen: widget.fen,
            pageNumber: pageNumber,
            pageSize: _pageSize,
            timeControl: timeControlFilter,
            playerId: playerIdFilter,
            color: _filters.playerColor?.name,
            result: _filters.gameResult?.apiValue,
            isOnline: _filters.isOnline,
            minRating: _filters.minRating,
            maxRating: _filters.maxRating,
            yearFrom: _filters.yearFrom,
            yearTo: _filters.yearTo,
            sortBy: _filters.sortBy,
            sortDirection: _filters.sortDirection,
          );
      if (!mounted || requestToken != _requestToken) return;

      final mergedRows = List<Map<String, dynamic>>.from(_rows);
      final mergedGames = List<GamesTourModel>.from(_games);
      final existingIds = <String>{
        for (final row in _rows)
          if ((row['id']?.toString().trim() ?? '').isNotEmpty)
            row['id'].toString().trim(),
      };

      for (final row in response.data) {
        final id = row['id']?.toString().trim();
        if (id != null && id.isNotEmpty && !existingIds.add(id)) {
          continue;
        }
        mergedRows.add(row);
        mergedGames.add(_mapPreviewToTourModel(row));
      }

      final addedCount = mergedRows.length - _rows.length;
      setState(() {
        _rows
          ..clear()
          ..addAll(mergedRows);
        _games
          ..clear()
          ..addAll(mergedGames);
        _hasMore = response.metadata.hasMore && addedCount > 0;
        _nextPageNumber = pageNumber + 1;
        _totalCount = response.metadata.totalCount ?? _totalCount;
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted || requestToken != _requestToken) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isInitialLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  static GamesTourModel _mapPreviewToTourModel(Map<String, dynamic> row) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    int? parsePositiveInt(dynamic value) {
      final parsed = parseInt(value);
      return parsed > 0 ? parsed : null;
    }

    String readString(String key) => (row[key]?.toString() ?? '').trim();

    final id = readString('id');
    final safeId = id.isNotEmpty ? id : 'unknown';
    final rawDate = row['date'];
    final date = rawDate == null ? null : DateTime.tryParse(rawDate.toString());
    final resultStr =
        readString('result').isNotEmpty ? readString('result') : '*';
    final timeControl = readString('timeControl');
    final eco = readString('eco');
    final opening = readString('opening');
    final variation = readString('variation');
    final event = readString('event');
    final site = readString('site');

    final whiteName = readString('white');
    final blackName = readString('black');
    final whitePlayerId = readString('whitePlayerId');
    final blackPlayerId = readString('blackPlayerId');
    final whiteFed = readString('whiteFed');
    final blackFed = readString('blackFed');
    final whiteTitle = readString('whiteTitle');
    final blackTitle = readString('blackTitle');
    final whiteElo = parseInt(row['whiteElo']);
    final blackElo = parseInt(row['blackElo']);
    final avgElo = parseInt(row['avgElo']);

    final formatCode = eco.isNotEmpty ? eco : timeControl;
    final openingName =
        variation.isNotEmpty
            ? '$opening: $variation'
            : (opening.isNotEmpty ? opening : null);
    final eventName =
        event.isNotEmpty ? event : (site.isNotEmpty ? site : 'Gamebase');

    return GamesTourModel(
      gameId: safeId,
      source: GameSource.gamebase,
      whitePlayer: PlayerCard(
        name: whiteName.isNotEmpty ? whiteName : 'White',
        federation: whiteFed,
        title: whiteTitle,
        rating: whiteElo,
        countryCode: whiteFed,
        team: null,
        fideId: parsePositiveInt(row['whiteFideId']),
        gamebasePlayerId: whitePlayerId.isNotEmpty ? whitePlayerId : null,
      ),
      blackPlayer: PlayerCard(
        name: blackName.isNotEmpty ? blackName : 'Black',
        federation: blackFed,
        title: blackTitle,
        rating: blackElo,
        countryCode: blackFed,
        team: null,
        fideId: parsePositiveInt(row['blackFideId']),
        gamebasePlayerId: blackPlayerId.isNotEmpty ? blackPlayerId : null,
      ),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.fromString(resultStr),
      roundId: 'fen_position',
      roundSlug: formatCode.isNotEmpty ? formatCode : null,
      tourId: eventName,
      tourSlug: site.isNotEmpty ? site : null,
      lastMoveTime: date,
      eco: eco.isNotEmpty ? eco : null,
      openingName: openingName,
      timeControl: timeControl.isNotEmpty ? timeControl : null,
      avgElo: avgElo > 0 ? avgElo : null,
      isOnline: row['isOnline'] == true,
    );
  }

  Future<void> _openGame(int index) async {
    final game = _games[index];
    final hasPremium = await requirePremiumGuard(context, ref);
    if (!hasPremium || !mounted) return;

    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => Center(
            child: CircularProgressIndicator(color: context.colors.textPrimary),
          ),
    );

    try {
      final repo = ref.read(gamebaseRepositoryProvider);
      final gameWithPgn = await repo.getGameWithPgn(game.gameId);

      String? pgn;
      if (gameWithPgn != null) {
        final built = buildPgnFromGamebaseData(gameWithPgn.data);
        for (final candidate in [built, gameWithPgn.pgn]) {
          final trimmed = candidate?.trim();
          if (trimmed == null || trimmed.isEmpty) continue;
          if (pgnHasMoves(trimmed)) {
            pgn = trimmed;
            break;
          }
          pgn ??= trimmed;
        }
      }

      pgn ??= buildHeaderOnlyPgn(
        whiteName: game.whitePlayer.name,
        blackName: game.blackPlayer.name,
        result: game.gameStatus.displayText,
        event: game.tourId,
        site: game.tourSlug,
        eco: game.eco ?? game.roundSlug,
        opening: game.openingName,
        date: game.lastMoveTime,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      final boardGames = _games
          .map((g) => g.gameId == game.gameId ? g.copyWith(pgn: pgn) : g)
          .toList(growable: false);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => ChessBoardScreenNew(
                games: boardGames,
                currentIndex: index.clamp(0, boardGames.length - 1),
                disableGamebaseOverlayByDefault: true,
                initialFen: widget.fen,
              ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to open game')));
    }
  }

  void _showAllGamesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      builder:
          (_) => PositionGamesSheet(
            fen: widget.fen,
            title: 'Games',
            filters: _filters,
            useFenEndpoint: true,
          ),
    );
  }

  Future<void> _showFiltersSheet() async {
    final updated = await showModalBottomSheet<GamebaseFilters>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      builder: (_) => _FenPositionFiltersSheet(initial: _filters),
    );
    if (updated == null || !mounted) return;
    setState(() => _filters = updated);
    _fetchPage(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed.withValues(alpha: 0.3),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12.sp),
          topRight: Radius.circular(12.sp),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FenPositionGamesHeader(
            loadedCount: _games.length,
            totalCount: _totalCount,
            hasMore: _hasMore,
            isLoading: _isInitialLoading,
            hasActiveFilters: _hasActiveFilters,
            onShowGames: _showAllGamesSheet,
            onShowFilters: _showFiltersSheet,
          ),
          Divider(
            height: 1,
            color: context.colors.textPrimary.withValues(alpha: 0.08),
          ),
          _FenPositionGamesColumnHeader(),
          Expanded(
            child:
                _isInitialLoading && _games.isEmpty
                    ? Center(
                      child: CircularProgressIndicator(
                        color: context.colors.textPrimary,
                        strokeWidth: 2,
                      ),
                    )
                    : (_error != null && _games.isEmpty)
                    ? _FenPositionGamesEmpty(
                      message: 'Failed to load games',
                      detail: _error,
                      onRetry: () => _fetchPage(reset: true),
                    )
                    : (_games.isEmpty)
                    ? _FenPositionGamesEmpty(
                      message: 'No Games Found',
                      onRetry: () => _fetchPage(reset: true),
                    )
                    : ListView.separated(
                      controller: _scrollController,
                      padding: EdgeInsets.only(bottom: bottomPadding + 8.h),
                      itemCount: _games.length + 1,
                      separatorBuilder:
                          (_, __) => Divider(
                            height: 1,
                            color: context.colors.textPrimary.withValues(
                              alpha: 0.06,
                            ),
                          ),
                      itemBuilder: (context, index) {
                        if (index == _games.length) {
                          return _FenPositionGamesFooter(
                            isLoadingMore: _isLoadingMore,
                            hasMore: _hasMore,
                            loadedCount: _games.length,
                            totalCount: _totalCount,
                            onLoadMore: _fetchPage,
                          );
                        }

                        return _FenPositionGameRow(
                          game: _games[index],
                          onTap: () => _openGame(index),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

class _FenPositionGamesHeader extends StatelessWidget {
  const _FenPositionGamesHeader({
    required this.loadedCount,
    required this.totalCount,
    required this.hasMore,
    required this.isLoading,
    required this.hasActiveFilters,
    required this.onShowGames,
    required this.onShowFilters,
  });

  final int loadedCount;
  final int? totalCount;
  final bool hasMore;
  final bool isLoading;
  final bool hasActiveFilters;
  final VoidCallback onShowGames;
  final VoidCallback onShowFilters;

  @override
  Widget build(BuildContext context) {
    final countText =
        isLoading
            ? 'Searching'
            : loadedCount == 0
            ? '0 games'
            : totalCount != null
            ? '$totalCount games'
            : hasMore
            ? '$loadedCount+ games'
            : '$loadedCount games';

    return SizedBox(
      height: 36.h,
      child: Row(
        children: [
          SizedBox(width: 14.w),
          Expanded(
            child: Text(
              'Games',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            countText,
            maxLines: 1,
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.textPrimaryMuted,
              fontWeight: FontWeight.normal,
            ),
          ),
          SizedBox(width: 4.w),
          IconButton(
            tooltip: 'All games for this position',
            constraints: BoxConstraints.tight(Size(36.sp, 36.sp)),
            padding: EdgeInsets.zero,
            onPressed: onShowGames,
            icon: Icon(
              Icons.list_alt_rounded,
              color: context.colors.textPrimaryMuted,
              size: 18.sp,
            ),
          ),
          IconButton(
            tooltip: 'Filters',
            constraints: BoxConstraints.tight(Size(36.sp, 36.sp)),
            padding: EdgeInsets.zero,
            onPressed: onShowFilters,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.tune_rounded,
                  color:
                      hasActiveFilters
                          ? kPrimaryColor
                          : context.colors.textPrimaryMuted,
                  size: 18.sp,
                ),
                if (hasActiveFilters)
                  Positioned(
                    right: -3.w,
                    top: -3.h,
                    child: Container(
                      width: 8.sp,
                      height: 8.sp,
                      decoration: const BoxDecoration(
                        color: kPrimaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FenPositionGamesColumnHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = AppTypography.textXsMedium.copyWith(
      color: context.colors.textPrimary.withValues(alpha: 0.45),
      fontWeight: FontWeight.w600,
    );

    return Container(
      height: 28.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      color: context.colors.surface.withValues(alpha: 0.24),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('White', style: style)),
          SizedBox(width: 8.w),
          SizedBox(
            width: 48.w,
            child: Text('Result', style: style, textAlign: TextAlign.center),
          ),
          SizedBox(width: 8.w),
          Expanded(flex: 5, child: Text('Black', style: style)),
          SizedBox(width: 8.w),
          SizedBox(
            width: 42.w,
            child: Text('Year', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 18.sp),
        ],
      ),
    );
  }
}

class _FenPositionGameRow extends StatelessWidget {
  const _FenPositionGameRow({required this.game, required this.onTap});

  final GamesTourModel game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final result =
        game.gameStatus.displayText.isNotEmpty
            ? game.gameStatus.displayText
            : '*';
    final year = game.lastMoveTime?.year.toString() ?? '';

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: 58.h),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: _FenPositionPlayerCell(player: game.whitePlayer),
            ),
            SizedBox(width: 8.w),
            SizedBox(
              width: 48.w,
              child: Center(
                child: Container(
                  constraints: BoxConstraints(minWidth: 38.w),
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: context.colors.textPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6.br),
                  ),
                  child: Text(
                    result,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textXsMedium.copyWith(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            Expanded(
              flex: 5,
              child: _FenPositionPlayerCell(
                player: game.blackPlayer,
                alignRight: true,
              ),
            ),
            SizedBox(width: 8.w),
            SizedBox(
              width: 42.w,
              child: Text(
                year,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textXsMedium.copyWith(
                  color: context.colors.textPrimaryMuted,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FenPositionPlayerCell extends StatelessWidget {
  const _FenPositionPlayerCell({required this.player, this.alignRight = false});

  final PlayerCard player;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (player.title.trim().isNotEmpty) player.title.trim(),
      if (player.rating > 0) player.rating.toString(),
    ].join(' ');

    final federation =
        player.countryCode.trim().isNotEmpty
            ? player.countryCode
            : player.federation;
    final flag =
        federation.trim().isEmpty &&
                (player.fideId == null || player.fideId! <= 0)
            ? null
            : SizedBox(
              width: 12.w,
              height: 8.h,
              child: Center(
                child: BackfilledFederationFlag(
                  federation: federation,
                  fideId: player.fideId,
                  width: 12.w,
                  height: 8.h,
                  borderRadius: BorderRadius.circular(1.5.br),
                ),
              ),
            );

    final nameWidget = Flexible(
      child: Text(
        player.name,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.textXsMedium.copyWith(
          color: context.colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final nameRow = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment:
          alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
      children:
          alignRight
              ? [
                nameWidget,
                if (flag != null) ...[SizedBox(width: 5.w), flag],
              ]
              : [
                if (flag != null) ...[flag, SizedBox(width: 5.w)],
                nameWidget,
              ],
    );

    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        nameRow,
        if (meta.isNotEmpty) ...[
          SizedBox(height: 2.h),
          Text(
            meta,
            textAlign: alignRight ? TextAlign.right : TextAlign.left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.48),
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ],
    );
  }
}

class _FenPositionGamesFooter extends StatelessWidget {
  const _FenPositionGamesFooter({
    required this.isLoadingMore,
    required this.hasMore,
    required this.loadedCount,
    required this.totalCount,
    required this.onLoadMore,
  });

  final bool isLoadingMore;
  final bool hasMore;
  final int loadedCount;
  final int? totalCount;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 14.h),
        child: Center(
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              color: context.colors.textPrimary,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    if (hasMore) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        child: OutlinedButton(
          onPressed: onLoadMore,
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: context.colors.textPrimary.withValues(alpha: 0.18),
            ),
            foregroundColor: context.colors.textPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.br),
            ),
          ),
          child: const Text('Load more'),
        ),
      );
    }

    if (loadedCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Text(
        totalCount != null
            ? 'Showing $loadedCount of $totalCount games'
            : 'Showing $loadedCount games',
        textAlign: TextAlign.center,
        style: AppTypography.textXsMedium.copyWith(
          color: context.colors.textPrimary.withValues(alpha: 0.45),
          fontWeight: FontWeight.normal,
        ),
      ),
    );
  }
}

class _FenPositionGamesEmpty extends StatelessWidget {
  const _FenPositionGamesEmpty({
    required this.message,
    this.detail,
    required this.onRetry,
  });

  final String message;
  final String? detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // Wrapped in SingleChildScrollView so it stays usable in tight swipe-panel
    // heights instead of overflowing the parent Column.
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.manage_search_rounded,
              color: context.colors.textPrimary.withValues(alpha: 0.45),
              size: 22.sp,
            ),
            SizedBox(height: 6.h),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXsMedium.copyWith(
                color: context.colors.textPrimaryMuted,
                fontWeight: FontWeight.normal,
              ),
            ),
            if (detail != null && detail!.isNotEmpty) ...[
              SizedBox(height: 4.h),
              Text(
                detail!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textXsMedium.copyWith(
                  color: context.colors.textPrimary.withValues(alpha: 0.42),
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
            SizedBox(height: 6.h),
            TextButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded, size: 14.sp),
              label: const Text('Retry'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filter sheet for the FEN-position-search table. Visually mirrors the
/// opening-explorer's `_FilterSheet` (FilterChip + tier filter + section
/// labels in `context.colors.textSecondary`, full-width primary Apply button, "Clear
/// all" action when any draft filter is active) so the two surfaces stay
/// consistent. Returns the resulting [GamebaseFilters] via Navigator.pop.
class _FenPositionFiltersSheet extends StatefulWidget {
  const _FenPositionFiltersSheet({required this.initial});

  final GamebaseFilters initial;

  @override
  State<_FenPositionFiltersSheet> createState() =>
      _FenPositionFiltersSheetState();
}

class _FenPositionFiltersSheetState extends State<_FenPositionFiltersSheet> {
  static const double _yearMin = 1800;
  static double get _yearMax => DateTime.now().year.toDouble();

  late GamebaseFilters _draftFilters;
  late int? _selectedMinRating;
  late RangeValues _yearRange;

  @override
  void initState() {
    super.initState();
    _draftFilters = widget.initial;
    _selectedMinRating = RatingTierFilter.normalizeMinRating(
      _draftFilters.minRating,
    );
    _yearRange = RangeValues(
      (_draftFilters.yearFrom?.toDouble() ?? _yearMin).clamp(
        _yearMin,
        _yearMax,
      ),
      (_draftFilters.yearTo?.toDouble() ?? _yearMax).clamp(_yearMin, _yearMax),
    );
  }

  int? get _effectiveMinRating => _selectedMinRating;

  int? get _effectiveMaxRating => null;

  int? get _effectiveYearFrom {
    final v = _yearRange.start.round();
    return v <= _yearMin ? null : v;
  }

  int? get _effectiveYearTo {
    final v = _yearRange.end.round();
    return v >= _yearMax ? null : v;
  }

  void _toggleTimeControl(TimeControl tc) {
    setState(() {
      _draftFilters = _draftFilters.copyWith(
        timeControls: _draftFilters.timeControls.contains(tc) ? const [] : [tc],
      );
    });
  }

  void _toggleResult(GamebaseGameResult result) {
    setState(() {
      _draftFilters = _draftFilters.copyWith(
        gameResult: _draftFilters.gameResult == result ? null : result,
      );
    });
  }

  void _toggleOnline(bool value) {
    setState(() {
      _draftFilters = _draftFilters.copyWith(
        isOnline: _draftFilters.isOnline == value ? null : value,
      );
    });
  }

  bool get _hasActiveDraft =>
      _draftFilters.timeControls.isNotEmpty ||
      _draftFilters.gameResult != null ||
      _draftFilters.isOnline != null ||
      _effectiveMinRating != null ||
      _effectiveMaxRating != null ||
      _effectiveYearFrom != null ||
      _effectiveYearTo != null;

  void _clearAll() {
    setState(() {
      _draftFilters = const GamebaseFilters();
      _selectedMinRating = null;
      _yearRange = RangeValues(_yearMin, _yearMax);
    });
  }

  void _apply() {
    final result = _draftFilters.copyWith(
      minRating: _effectiveMinRating,
      maxRating: _effectiveMaxRating,
      yearFrom: _effectiveYearFrom,
      yearTo: _effectiveYearTo,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final filters = _draftFilters;
    final hasActiveDraft = _hasActiveDraft;

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surfaceRecessed,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Padding(
              padding: EdgeInsets.all(16.sp),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header (matches opening explorer "Filters" + "Clear all")
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filters',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 18.f,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasActiveDraft)
                        TextButton(
                          onPressed: _clearAll,
                          child: Text(
                            'Clear all',
                            style: TextStyle(
                              color: kPrimaryColor,
                              fontSize: 14.f,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 16.sp),

                  // Time control
                  _FilterSectionLabel(label: 'Time Control'),
                  SizedBox(height: 8.sp),
                  Wrap(
                    spacing: 8.sp,
                    children:
                        TimeControl.values.map((tc) {
                          final selected = filters.timeControls.contains(tc);
                          return _ExplorerStyleFilterChip(
                            label: tc.displayName,
                            selected: selected,
                            onSelected: () => _toggleTimeControl(tc),
                          );
                        }).toList(),
                  ),
                  SizedBox(height: 16.sp),

                  // Result
                  _FilterSectionLabel(label: 'Result'),
                  SizedBox(height: 8.sp),
                  Wrap(
                    spacing: 8.sp,
                    children:
                        GamebaseGameResult.values.map((r) {
                          final selected = filters.gameResult == r;
                          return _ExplorerStyleFilterChip(
                            label: r.displayText,
                            selected: selected,
                            onSelected: () => _toggleResult(r),
                          );
                        }).toList(),
                  ),
                  SizedBox(height: 16.sp),

                  // Format (OTB / Online)
                  _FilterSectionLabel(label: 'Format'),
                  SizedBox(height: 8.sp),
                  Wrap(
                    spacing: 8.sp,
                    children: [
                      _ExplorerStyleFilterChip(
                        label: 'OTB Only',
                        selected: filters.isOnline == false,
                        onSelected: () => _toggleOnline(false),
                      ),
                      _ExplorerStyleFilterChip(
                        label: 'Online Only',
                        selected: filters.isOnline == true,
                        onSelected: () => _toggleOnline(true),
                      ),
                    ],
                  ),
                  SizedBox(height: 16.sp),

                  // Rating level
                  _FilterSectionLabel(label: 'Level'),
                  SizedBox(height: 8.sp),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.w),
                    child: RatingTierFilter(
                      selectedMinRating: _selectedMinRating,
                      onChanged:
                          (value) => setState(() => _selectedMinRating = value),
                    ),
                  ),
                  SizedBox(height: 24.sp),

                  // Year range
                  _FilterSectionLabel(label: 'Year Range'),
                  SizedBox(height: 8.sp),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: WheelRangeFilter(
                      minValue: _yearMin,
                      maxValue: _yearMax,
                      currentStart: _yearRange.start,
                      currentEnd: _yearRange.end,
                      divisions: (_yearMax - _yearMin).toInt(),
                      onChanged: (v) => setState(() => _yearRange = v),
                    ),
                  ),
                  SizedBox(height: 24.sp),

                  // Apply button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _apply,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        padding: EdgeInsets.symmetric(vertical: 12.sp),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.br),
                        ),
                      ),
                      child: Text(
                        'Apply',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 14.f,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterSectionLabel extends StatelessWidget {
  const _FilterSectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: context.colors.textSecondary,
        fontSize: 12.f,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _ExplorerStyleFilterChip extends StatelessWidget {
  const _ExplorerStyleFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: kPrimaryColor.withValues(alpha: 0.2),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? kPrimaryColor : context.colors.textPrimary,
        fontSize: 12.f,
      ),
      backgroundColor: context.colors.surface,
      side: BorderSide(
        color: selected ? kPrimaryColor : context.colors.divider,
      ),
    );
  }
}

class _MovesDisplay extends ConsumerStatefulWidget {
  final int index;
  final ChessBoardStateNew state;
  final GamesTourModel game;
  final int currentPageIndex;

  const _MovesDisplay({
    required this.state,
    required this.index,
    required this.game,
    required this.currentPageIndex,
  });

  @override
  ConsumerState<_MovesDisplay> createState() => _MovesDisplayState();
}

class _MovesDisplayState extends ConsumerState<_MovesDisplay> {
  static const int _autoCollapseDepth = 3;
  static const int _autoCollapseMoveThreshold = 12;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _moveKeys = {};
  final ListEquality<int> _pointerEquality = const ListEquality<int>();
  final Set<String> _collapsedVariationIds = <String>{};
  final Set<String> _expandedVariationIds = <String>{};
  final Set<String> _expandedCommentIds = <String>{};
  bool _hasInitiallyScrolled = false;
  String? _lastSignature;
  ChessMovePointer? _lastPointer;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state.isLoadingMoves) {
      return _buildMovesLoadingSkeleton();
    }

    final analysisGame = widget.state.analysisState.game;
    if (analysisGame == null) {
      // Game is still being initialized by the analysis navigator.
      // Show loading skeleton instead of "No moves" to avoid flicker.
      return _buildMovesLoadingSkeleton();
    }

    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.index,
    );
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    final navigatorState = ref.watch(chessGameNavigatorProvider(analysisGame));
    final signature = notationGameSignature(navigatorState.game);
    final mainlineSans =
        navigatorState.game.mainline.map((move) => move.san).toList();
    final lichessGameId = _extractLichessGameId(navigatorState.game);
    final lichessSiteUrl = _extractLichessSiteUrl(navigatorState.game);
    // Debug: Log extracted Lichess identifiers (silenced — per-frame spam)
    // debugPrint(
    //   '🎯 [Notation] Extracted: gameId=$lichessGameId, siteUrl=$lichessSiteUrl, isLive=${navigatorState.game.isLiveGame}, moves=${mainlineSans.length}',
    // );
    final lichessAnnotationsAsync = ref.watch(
      lichessMoveAnnotationsProvider(
        LichessMoveAnnotationsParams(
          lichessGameId: lichessGameId,
          siteUrl: lichessSiteUrl,
          signature: _moveSansSignature(mainlineSans),
          moveSans: mainlineSans,
          isLiveGame: navigatorState.game.isLiveGame,
        ),
      ),
    );
    final lichessAnnotations =
        lichessAnnotationsAsync.valueOrNull ??
        const <int, LichessMoveAnnotation>{};

    // Debug: Log annotation state
    if (lichessAnnotations.isNotEmpty) {
      debugPrint(
        '🎯 [Annotations] Got ${lichessAnnotations.length} annotations for game $lichessGameId',
      );
      debugPrint('🎯 [Annotations] Keys: ${lichessAnnotations.keys.toList()}');
    } else if (lichessAnnotationsAsync.isLoading) {
      debugPrint('🎯 [Annotations] Loading for game $lichessGameId...');
    } else if (lichessAnnotationsAsync.hasError) {
      debugPrint('🎯 [Annotations] Error: ${lichessAnnotationsAsync.error}');
    }

    // Get figurine notation setting and piece assets for rendering
    final useFigurine = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.useFigurine ?? const BoardSettingsNew().useFigurine,
      ),
    );
    final pieceAssets = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.pieceAssets ?? const BoardSettingsNew().pieceAssets,
      ),
    );
    final rawPgnMode = ref.watch(
      boardSettingsProviderNew.select(
        (s) => s.valueOrNull?.rawPgnMode ?? false,
      ),
    );

    if (_lastSignature != signature) {
      _moveKeys.clear();
      _hasInitiallyScrolled = false;
      _lastSignature = signature;
      // Reset cached variation collapse state when the notation tree changes
      _collapsedVariationIds.clear();
      _expandedVariationIds.clear();
    }

    final notationParams = NotationTreeParams(
      game: navigatorState.game,
      signature: signature,
    );
    final tree = ref.watch(notationTreeProvider(notationParams));

    final hasMoves = tree.mainline.isNotEmpty;
    final tailNode = hasMoves ? tree.mainline.last : null;
    final tailPointerId =
        tailNode != null ? NotationPointer.encode(tailNode.pointer) : null;

    ChessMovePointer pointerCandidate = navigatorState.movePointer;
    if (pointerCandidate.isEmpty &&
        widget.state.analysisState.movePointer.isNotEmpty) {
      pointerCandidate = widget.state.analysisState.movePointer;
    }
    final hasPointer = pointerCandidate.isNotEmpty;
    final isAtTailByIndex =
        hasMoves &&
        widget.state.analysisState.currentMoveIndex == tree.mainline.length - 1;
    final shouldFallbackToTail =
        !hasPointer && isAtTailByIndex && tailNode != null;

    final pointerForHighlightId =
        hasPointer
            ? NotationPointer.encode(pointerCandidate)
            : shouldFallbackToTail
            ? tailPointerId
            : null;
    final pointerForScroll =
        hasPointer
            ? pointerCandidate
            : shouldFallbackToTail
            ? List<Number>.of(tailNode.pointer)
            : const <Number>[];

    if (pointerForScroll.isNotEmpty) {
      _schedulePointerScroll(pointerForScroll, pointerForHighlightId);
    }

    final forcedOpenIds = <String>{};
    _collectVariationAncestors(
      pointerForHighlightId,
      tree.mainline,
      forcedOpenIds,
    );

    final effectiveLichessAnnotations =
        rawPgnMode ? const <int, LichessMoveAnnotation>{} : lichessAnnotations;

    final pointerMap = <String, NotationMoveNode>{};
    final tokens = buildNotationTokens(
      tree.mainline,
      depth: 0,
      startingPly: tree.startingPly,
      pointerMap: pointerMap,
      forcedOpenIds: forcedOpenIds,
      variationComments: widget.state.variationComments,
      lichessAnnotations: effectiveLichessAnnotations,
      collapsedVariationIds: _collapsedVariationIds,
      expandedVariationIds: _expandedVariationIds,
      autoCollapseDepth: _autoCollapseDepth,
      autoCollapseMoveThreshold: _autoCollapseMoveThreshold,
      rawPgnMode: rawPgnMode,
    );

    final currentNode =
        pointerForHighlightId != null
            ? pointerMap[pointerForHighlightId]
            : null;
    final currentPly = currentNode?.ply ?? -1;

    final rows = _buildNotationRows(
      tokens,
      params: params,
      currentPly: currentPly,
      currentPointerId: pointerForHighlightId,
      tailPointerId: tailPointerId,
      lichessAnnotations: effectiveLichessAnnotations,
      useFigurine: useFigurine,
      pieceAssets: pieceAssets,
      pointerMap: pointerMap,
      rawPgnMode: rawPgnMode,
    );

    // Paste-FEN flow can land here with no moves yet (tokens empty). Don't
    // try to fake notation — show a clear empty-state. The forward arrow in
    // the bottom nav auto-plays the engine's top PV move from this position
    // (see `onRightMove` override at the call site), at which point the
    // notation renders normally starting from the FEN's fullmove counter.
    if (rows.isEmpty) {
      final notationContent = Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.south_east_rounded,
                color: context.colors.textPrimary.withValues(alpha: 0.45),
                size: 22.sp,
              ),
              SizedBox(height: 8.h),
              Text(
                'No moves played yet',
                textAlign: TextAlign.center,
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'Tap → to play the engine’s top move, or swipe ← to see games at this position.',
                textAlign: TextAlign.center,
                style: AppTypography.textXsMedium.copyWith(
                  color: context.colors.textPrimary.withValues(alpha: 0.45),
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      );
      Widget content = Container(
        key: e2eKey(E2eIds.boardNotationRoot),
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed.withValues(alpha: 0.3),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(12.sp),
            topRight: Radius.circular(12.sp),
          ),
        ),
        child: notationContent,
      );
      return content;
    }

    final notationContent = SingleChildScrollView(
      controller: _scrollController,
      child: Container(
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.fromLTRB(16.sp, 16.sp, 16.sp, 20.sp),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: rows,
          ),
        ),
      ),
    );

    // Tablet landscape hides the reset icon since tablets navigate
    // position-search flows differently.
    final isTabletLandscape =
        ResponsiveHelper.isTablet && ResponsiveHelper.isLandscape;

    // Reset to the pasted-FEN starting state — only meaningful in the
    // position-search flow (the user came from Board Editor → Paste FEN →
    // Analyze). For mainline games this would wipe legitimate moves, so it's
    // gated on the starting position being non-default.
    final notationStartingFen =
        widget.state.analysisState.startingPosition?.fen;
    final isPositionSearchFlow =
        notationStartingFen != null && notationStartingFen != Chess.initial.fen;

    Widget content = Container(
      key: e2eKey(E2eIds.boardNotationRoot),
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed.withValues(alpha: 0.3),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12.sp),
          topRight: Radius.circular(12.sp),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: notationContent),
          if (isPositionSearchFlow && !isTabletLandscape)
            Positioned(
              top: 4.h,
              right: 4.w,
              child: IconButton(
                tooltip: 'Reset to pasted position',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tight(Size(28.sp, 28.sp)),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  notifier.deleteContinuationFromPointer(const []);
                },
                icon: Icon(
                  Icons.restart_alt_rounded,
                  color: context.colors.textPrimaryMuted,
                  size: 16.ic,
                ),
              ),
            ),
          // Subtle overlay when preview is active - only covers main variant area
          if (widget.state.isPvPreviewActive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0, // Will be covered by PV cards naturally
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  // Tap anywhere on overlay to exit preview
                  ref
                      .read(chessBoardScreenProviderNew(params).notifier)
                      .clearPvPreview();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12.sp),
                      topRight: Radius.circular(12.sp),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12.sp),
                      topRight: Radius.circular(12.sp),
                    ),
                    child: Stack(
                      children: [
                        BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                        Align(
                          alignment: Alignment.center,
                          child: TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.elasticOut,
                            tween: Tween(begin: 0.0, end: 1.0),
                            builder: (context, value, child) {
                              final clampedValue = value.clamp(0.0, 1.0);
                              return Transform.scale(
                                scale: 0.8 + (clampedValue * 0.2),
                                child: Opacity(
                                  opacity: clampedValue,
                                  child: child,
                                ),
                              );
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 18.sp,
                                vertical: 16.sp,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.visibility_outlined,
                                    color: Colors.white.withValues(alpha: 0.95),
                                    size: 20.sp,
                                  ),
                                  SizedBox(height: 8.sp),
                                  Text(
                                    'Preview mode',
                                    textAlign: TextAlign.center,
                                    style: AppTypography.textSmMedium.copyWith(
                                      color: Colors.white,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  SizedBox(height: 4.sp),
                                  Text(
                                    'Tap anywhere to exit or swipe the hero card up to apply.',
                                    textAlign: TextAlign.center,
                                    style: AppTypography.textXsRegular.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 12.sp),
                                  // Promote main variant button
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () async {
                                        // Prevent tap from propagating to parent GestureDetector
                                        HapticFeedback.mediumImpact();

                                        final lockedLine =
                                            widget.state.lockedPvLine;
                                        if (lockedLine == null) return;

                                        // Confirm before promoting
                                        final confirmed =
                                            await showDialog<bool>(
                                              context: context,
                                              builder:
                                                  (
                                                    dialogContext,
                                                  ) => AlertDialog(
                                                    backgroundColor:
                                                        context.colors.surface,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12.br,
                                                          ),
                                                    ),
                                                    title: Text(
                                                      'Promote to main variant?',
                                                      style: AppTypography
                                                          .textMdBold
                                                          .copyWith(
                                                            color:
                                                                context
                                                                    .colors
                                                                    .textPrimary,
                                                          ),
                                                    ),
                                                    content: Text(
                                                      'This will replace the main variant with this preview line.',
                                                      style: AppTypography
                                                          .textSmRegular
                                                          .copyWith(
                                                            color: context
                                                                .colors
                                                                .textPrimary
                                                                .withValues(
                                                                  alpha: 0.7,
                                                                ),
                                                          ),
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed:
                                                            () => Navigator.of(
                                                              dialogContext,
                                                            ).pop(false),
                                                        child: Text(
                                                          'Cancel',
                                                          style: AppTypography
                                                              .textSmMedium
                                                              .copyWith(
                                                                color: context
                                                                    .colors
                                                                    .textPrimary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.7,
                                                                    ),
                                                              ),
                                                        ),
                                                      ),
                                                      TextButton(
                                                        onPressed:
                                                            () => Navigator.of(
                                                              dialogContext,
                                                            ).pop(true),
                                                        child: Text(
                                                          'Promote',
                                                          style: AppTypography
                                                              .textSmMedium
                                                              .copyWith(
                                                                color:
                                                                    kPrimaryColor,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                            ) ??
                                            false;

                                        if (!confirmed) return;
                                        if (!context.mounted) return;

                                        notifier.promotePreviewToMainVariant();
                                      },
                                      borderRadius: BorderRadius.circular(8.sp),
                                      splashColor: kPrimaryColor.withValues(
                                        alpha: 0.3,
                                      ),
                                      highlightColor: kPrimaryColor.withValues(
                                        alpha: 0.2,
                                      ),
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 20.sp,
                                          vertical: 10.sp,
                                        ),
                                        decoration: BoxDecoration(
                                          color: kPrimaryColor.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8.sp,
                                          ),
                                          border: Border.all(
                                            color: kPrimaryColor.withValues(
                                              alpha: 0.4,
                                            ),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.upgrade_rounded,
                                              color: context.colors.textPrimary,
                                              size: 16.sp,
                                            ),
                                            SizedBox(width: 8.sp),
                                            Text(
                                              'Promote main variant',
                                              style: AppTypography.textSmMedium
                                                  .copyWith(
                                                    color:
                                                        context
                                                            .colors
                                                            .textPrimary,
                                                    letterSpacing: 0.2,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return content;
  }

  Widget _buildMoveChip(
    NotationDisplayToken token,
    ChessBoardProviderParams params,
    int currentPly,
    String? currentPointerId,
    String? tailPointerId,
    Map<int, LichessMoveAnnotation> lichessAnnotations, {
    bool useFigurine = true,
    PieceAssets? pieceAssets,
    bool rawPgnMode = false,
  }) {
    final pointerId = token.pointerId;
    final key =
        pointerId == null
            ? null
            : _moveKeys.putIfAbsent(pointerId, () => GlobalKey());
    final isCurrent = pointerId != null && pointerId == currentPointerId;
    final isTail =
        pointerId != null &&
        tailPointerId != null &&
        pointerId == tailPointerId;

    // Author/user NAGs win — Lichess fetched analysis is only used as a
    // fallback when no NAGs are present on the move.
    // Raw PGN mode hides all auto symbols (NAGs + Lichess annotations).
    final rawAnnotation =
        rawPgnMode
            ? null
            : _resolveLichessAnnotation(token, lichessAnnotations);
    final nags =
        rawPgnMode
            ? const <int>[]
            : _mergeUserNags(
              token.node?.move.nags,
              token.pointerId,
              widget.state.moveNags,
            );

    // Resolve NAGs into displays. Quality NAGs are highlighted on the move
    // text itself; evaluation/observation NAGs render in their muted slate
    // and never tint the SAN.
    final displayNags = <NagDisplay>[];
    NagDisplay? firstQualityNag;
    final seen = <int>{};
    for (final nag in nags) {
      if (!seen.add(nag)) continue;
      final d = getNagDisplay(nag);
      if (d != null) {
        displayNags.add(d);
        if (d.isQuality) firstQualityNag ??= d;
      }
    }

    final annotation = displayNags.isEmpty ? rawAnnotation : null;

    final depth = token.depth;
    final isMainline = token.node?.isMainline ?? (depth <= 0);
    final ladder = _moveLadderForDepth(depth, isMainline: isMainline);
    final baseColor = _resolveMoveColor(token, currentPly);
    final qualityColor = firstQualityNag?.color;
    final annotationColor = annotation?.type.color;
    final color = qualityColor ?? annotationColor ?? baseColor;

    final textStyle = AppTypography.textXsMedium.copyWith(
      color: color,
      fontSize: ladder.sanSize,
      fontWeight: isCurrent ? FontWeight.w800 : ladder.sanWeight,
      letterSpacing: ladder.sanLetterSpacing,
      height: 1.2,
    );
    final numberStyle = AppTypography.textXsMedium.copyWith(
      color: context.colors.textPrimary.withValues(alpha: ladder.numberAlpha),
      fontSize: ladder.numberSize,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: 0.0,
      height: 1.2,
    );

    // Build move text spans - either with figurine pieces or plain text
    final List<InlineSpan> moveSpans;
    if (useFigurine && pieceAssets != null) {
      moveSpans = buildFigurineSpans(
        text: token.text,
        pieceAssets: pieceAssets,
        style: textStyle,
        pieceSize: 14.sp, // Slightly larger than text for clarity
        numberStyle: numberStyle,
      );
    } else {
      // Derive move-number prefix directly from the formatted move text
      final String fullText = token.text;
      String prefix = '';
      String body = fullText;

      final prefixRegex = RegExp(r'^(\d+\.{1,3}\s+)(.*)$');
      final match = prefixRegex.firstMatch(fullText);
      if (match != null) {
        prefix = match.group(1)!;
        body = match.group(2)!;
      }

      moveSpans = [
        if (prefix.isNotEmpty) TextSpan(text: prefix, style: numberStyle),
        TextSpan(text: body, style: textStyle),
      ];
    }

    // Determine annotation presentation: inline symbol or badge
    final annotationPres =
        annotation != null
            ? resolveAnnotationPresentation(annotation.type)
            : null;

    // Evaluative annotations: append colored symbol inline after the SAN text
    if (annotationPres == AnnotationPresentation.inlineSymbol) {
      moveSpans.add(
        TextSpan(
          text: annotation!.type.symbol,
          style: textStyle.copyWith(
            color: annotation.type.color,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else if (annotation == null && displayNags.isNotEmpty) {
      // Quality glyphs (!, ??, !?, ?!, ...) — bold, color-coded, hugged to SAN.
      // Eval glyphs (±, ∞, ⩲, ⩱, +-, ...) — separated by a hair-space and
      // rendered in muted slate so they don't compete with quality glyphs.
      // Order: quality first, then evaluation, then observation.
      final ordered = [...displayNags]..sort((a, b) {
        int rank(NagDisplay d) => switch (d.category) {
          NagCategory.quality => 0,
          NagCategory.evaluation => 1,
          NagCategory.observation => 2,
        };
        return rank(a).compareTo(rank(b));
      });
      for (final d in ordered) {
        if (d.isQuality) {
          moveSpans.add(
            TextSpan(
              text: d.symbol,
              style: textStyle.copyWith(
                color: d.color,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          );
        } else {
          moveSpans.add(
            TextSpan(
              text: ' ${d.symbol}',
              style: textStyle.copyWith(
                color: d.color,
                fontWeight: FontWeight.w500,
                fontSize: ladder.sanSize - 0.5,
                letterSpacing: 0.0,
              ),
            ),
          );
        }
      }
    }

    // bookMove: keep the floating badge (no inline symbol available)
    final Widget? annotationBadge =
        annotationPres == AnnotationPresentation.badgeOnly
            ? Container(
              width: 14.sp,
              height: 14.sp,
              decoration: BoxDecoration(
                color: annotation!.type.color,
                borderRadius: BorderRadius.circular(999),
              ),
              padding: EdgeInsets.all(2.sp),
              child: RepaintBoundary(
                child: SvgPicture.asset(
                  annotation.type.iconAssetPath,
                  fit: BoxFit.contain,
                ),
              ),
            )
            : null;

    return GestureDetector(
      key: key,
      onTap: () {
        final pointer = token.pointer;
        if (pointer == null) return;
        ref
            .read(chessBoardScreenProviderNew(params).notifier)
            .goToMovePointer(pointer);
        if (isTail && widget.state.hasUnseenMoves) {
          ref
              .read(chessBoardScreenProviderNew(params).notifier)
              .markMovesAsSeen();
        }
      },
      onLongPress: () {
        final pointer = token.pointer;
        if (pointer == null) return;
        _showMoveActions(
          params,
          pointer,
          token.text,
          token.node?.move.san == '--',
          token.node?.isMainline ?? false,
          _variantHeadPointerForToken(token),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
            decoration: BoxDecoration(
              color:
                  isCurrent
                      ? context.colors.textPrimaryMuted.withValues(alpha: 0.25)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(4.sp),
              border: Border.all(
                color:
                    isCurrent ? context.colors.textPrimary : Colors.transparent,
                width: 0.7,
              ),
            ),
            child: Text.rich(TextSpan(children: moveSpans)),
          ),
          if (isTail && widget.state.hasUnseenMoves)
            Positioned(
              top: -2.sp,
              right: -2.sp,
              child: _BlinkingRedDot(size: 6.sp),
            ),
          if (annotationBadge != null)
            Positioned(top: -4.sp, right: 10.sp, child: annotationBadge),
        ],
      ),
    );
  }

  // ===========================================================================
  // Tree-aware notation layout — partitions a flat token stream into a Column
  // of rows: consecutive moves stay in a Wrap, comments and variations break
  // to full-width blocks. Variations get a depth-colored left rail (the
  // "ladder") so the eye can follow nesting at a glance — no parens needed.
  // ===========================================================================

  List<Widget> _buildNotationRows(
    List<NotationDisplayToken> tokens, {
    required ChessBoardProviderParams params,
    required int currentPly,
    required String? currentPointerId,
    required String? tailPointerId,
    required Map<int, LichessMoveAnnotation> lichessAnnotations,
    required bool useFigurine,
    required PieceAssets? pieceAssets,
    required Map<String, NotationMoveNode> pointerMap,
    bool rawPgnMode = false,
  }) {
    final widgets = <Widget>[];
    var currentRun = <NotationDisplayToken>[];

    void flushRun() {
      if (currentRun.isEmpty) return;
      widgets.add(
        Padding(
          padding: EdgeInsets.symmetric(vertical: 1.sp),
          child: Wrap(
            spacing: 4.sp,
            runSpacing: 3.sp,
            crossAxisAlignment: WrapCrossAlignment.center,
            children:
                currentRun
                    .map(
                      (t) => _buildMoveChip(
                        t,
                        params,
                        currentPly,
                        currentPointerId,
                        tailPointerId,
                        lichessAnnotations,
                        useFigurine: useFigurine,
                        pieceAssets: pieceAssets,
                        rawPgnMode: rawPgnMode,
                      ),
                    )
                    .toList(),
          ),
        ),
      );
      currentRun = <NotationDisplayToken>[];
    }

    var i = 0;
    while (i < tokens.length) {
      final t = tokens[i];

      if (t.type == NotationTokenType.move ||
          t.type == NotationTokenType.ellipsis) {
        currentRun.add(t);
        i++;
        continue;
      }

      if (t.type == NotationTokenType.openParen) {
        flushRun();
        // Slice out the contents of this variation up to its matching close.
        final innerTokens = <NotationDisplayToken>[];
        var depth = 1;
        i++;
        while (i < tokens.length && depth > 0) {
          if (tokens[i].type == NotationTokenType.openParen) {
            depth++;
          } else if (tokens[i].type == NotationTokenType.closeParen) {
            depth--;
            if (depth == 0) {
              i++; // consume matching closeParen
              break;
            }
          }
          innerTokens.add(tokens[i]);
          i++;
        }
        widgets.add(
          _buildVariationBlock(
            openParenToken: t,
            innerTokens: innerTokens,
            params: params,
            currentPly: currentPly,
            currentPointerId: currentPointerId,
            tailPointerId: tailPointerId,
            lichessAnnotations: lichessAnnotations,
            useFigurine: useFigurine,
            pieceAssets: pieceAssets,
            pointerMap: pointerMap,
            rawPgnMode: rawPgnMode,
          ),
        );
        continue;
      }

      if (t.type == NotationTokenType.closeParen) {
        // Stray close paren — skip defensively.
        i++;
        continue;
      }

      if (t.type == NotationTokenType.variationPlaceholder) {
        flushRun();
        widgets.add(_buildCollapsedVariationBlock(t));
        i++;
        continue;
      }

      if (t.type == NotationTokenType.comment) {
        flushRun();
        widgets.add(_buildCommentBlock(t, params));
        i++;
        continue;
      }

      if (t.type == NotationTokenType.lichessComment) {
        flushRun();
        widgets.add(_buildLichessCommentBlock(t));
        i++;
        continue;
      }

      i++;
    }
    flushRun();
    return widgets;
  }

  /// Container that wraps an entire variation in a depth-colored left rail
  /// with a header chip showing the divergence point ("alt to 5...Bc5").
  /// Beyond depth 4 the indent is capped — rails carry the hierarchy.
  Widget _buildVariationBlock({
    required NotationDisplayToken openParenToken,
    required List<NotationDisplayToken> innerTokens,
    required ChessBoardProviderParams params,
    required int currentPly,
    required String? currentPointerId,
    required String? tailPointerId,
    required Map<int, LichessMoveAnnotation> lichessAnnotations,
    required bool useFigurine,
    required PieceAssets? pieceAssets,
    required Map<String, NotationMoveNode> pointerMap,
    bool rawPgnMode = false,
  }) {
    final variation = openParenToken.variation;
    final depth = openParenToken.depth;
    final accent = _accentColorForToken(openParenToken);
    final railColor = accent.withValues(alpha: 0.45);
    final railWidth = depth == 1 ? 2.0 : 1.5;
    final indentPx = math.min(depth - 1, 3) * 6.sp;

    String? headerLabel;
    if (variation != null && variation.parentPointer.isNotEmpty) {
      final parentId = NotationPointer.encode(variation.parentPointer);
      final parent = pointerMap[parentId];
      if (parent != null) {
        final dots = parent.isWhiteMove ? '.' : '...';
        final cleanSan = parent.move.san.replaceAll(RegExp(r'[!?]+$'), '');
        headerLabel = '${parent.moveNumber}$dots$cleanSan';
      }
    }

    final innerRows = _buildNotationRows(
      innerTokens,
      params: params,
      currentPly: currentPly,
      currentPointerId: currentPointerId,
      tailPointerId: tailPointerId,
      lichessAnnotations: lichessAnnotations,
      useFigurine: useFigurine,
      pieceAssets: pieceAssets,
      pointerMap: pointerMap,
      rawPgnMode: rawPgnMode,
    );

    return Padding(
      padding: EdgeInsets.only(left: indentPx, top: 4.sp, bottom: 4.sp),
      child: Container(
        padding: EdgeInsets.only(left: 9.sp, top: 2.sp, bottom: 2.sp),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: railColor, width: railWidth)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (headerLabel != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  if (variation != null) _focusVariationHead(variation);
                },
                onLongPress: () => _showVariationActions(openParenToken),
                child: Padding(
                  padding: EdgeInsets.only(bottom: 3.sp),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.subdirectory_arrow_right_rounded,
                        size: 11.sp,
                        color: accent.withValues(alpha: 0.85),
                      ),
                      SizedBox(width: 3.sp),
                      Flexible(
                        child: Text(
                          'alt to $headerLabel',
                          style: AppTypography.textXsRegular.copyWith(
                            color: accent.withValues(alpha: 0.85),
                            fontSize: 10.sp,
                            fontStyle: FontStyle.italic,
                            letterSpacing: 0.2,
                            height: 1.0,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 6.sp),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _toggleVariationCollapse(openParenToken);
                        },
                        child: Icon(
                          Icons.unfold_less_rounded,
                          size: 12.sp,
                          color: accent.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ...innerRows,
          ],
        ),
      ),
    );
  }

  /// Tappable pill shown in place of an auto-collapsed variation. One row
  /// in the Column — never inline with adjacent moves.
  Widget _buildCollapsedVariationBlock(NotationDisplayToken token) {
    final accent = _accentColorForToken(token);
    return Padding(
      padding: EdgeInsets.only(top: 4.sp, bottom: 4.sp),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            _toggleVariationCollapse(token);
          },
          onLongPress: () => _showVariationActions(token),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 9.sp, vertical: 4.sp),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: accent.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.unfold_more_rounded,
                  size: 11.sp,
                  color: accent.withValues(alpha: 0.85),
                ),
                SizedBox(width: 4.sp),
                Text(
                  token.text,
                  style: AppTypography.textXsMedium.copyWith(
                    color: accent.withValues(alpha: 0.95),
                    fontSize: 10.5.sp,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Editorial block-quote for a comment — full-width, depth-colored left
  /// rail, soft white wash. Long comments fold to a "Read more" toggle.
  Widget _buildCommentBlock(
    NotationDisplayToken token,
    ChessBoardProviderParams params,
  ) {
    final fullText = token.commentText?.trim() ?? token.text.trim();
    if (fullText.isEmpty) return const SizedBox.shrink();
    final id = token.pointerId ?? token.variation?.id;
    if (id == null) return const SizedBox.shrink();

    final isExpanded = _expandedCommentIds.contains(id);
    final isLong = fullText.length > _variationCommentPreviewChars;
    final displayText =
        (isLong && !isExpanded)
            ? '${fullText.substring(0, _variationCommentPreviewChars).trimRight()}…'
            : fullText;

    final depth = math.max(1, token.depth);
    final accent = _colorForVariationAccent(
      depth,
      seed: token.variationColorKey ?? token.variation?.id,
    );

    return Padding(
      padding: EdgeInsets.only(top: 5.sp, bottom: 5.sp),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          if (isLong) {
            _toggleCommentExpansion(id, isExpanded);
          } else {
            _editNotationComment(token, params, fullText);
          }
        },
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _editNotationComment(token, params, fullText);
        },
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(11.sp, 8.sp, 11.sp, 8.sp),
          decoration: BoxDecoration(
            color: context.colors.textPrimary.withValues(alpha: 0.045),
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(6.sp),
              bottomRight: Radius.circular(6.sp),
            ),
            border: Border(
              left: BorderSide(color: accent.withValues(alpha: 0.65), width: 3),
            ),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: displayText,
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.86),
                    fontSize: 13.sp,
                    height: 1.45,
                    letterSpacing: 0.05,
                  ),
                ),
                if (isLong)
                  TextSpan(
                    text: isExpanded ? '   Show less' : '   Read more',
                    style: AppTypography.textXsMedium.copyWith(
                      color: accent.withValues(alpha: 0.95),
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLichessCommentBlock(NotationDisplayToken token) {
    final text = token.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 4.sp, bottom: 4.sp),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(11.sp, 7.sp, 11.sp, 7.sp),
        decoration: BoxDecoration(
          color: context.colors.textPrimary.withValues(alpha: 0.025),
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(6.sp),
            bottomRight: Radius.circular(6.sp),
          ),
          border: Border(
            left: BorderSide(
              color: context.colors.textPrimary.withValues(alpha: 0.18),
              width: 2,
            ),
          ),
        ),
        child: Text(
          text,
          style: AppTypography.textXsRegular.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.6),
            fontSize: 12.sp,
            height: 1.4,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  void _toggleCommentExpansion(String id, bool isExpanded) {
    setState(() {
      if (isExpanded) {
        _expandedCommentIds.remove(id);
      } else {
        _expandedCommentIds.add(id);
      }
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _editNotationComment(
    NotationDisplayToken token,
    ChessBoardProviderParams params,
    String fallbackText,
  ) async {
    final pointerId = token.pointerId ?? token.variation?.id;
    if (pointerId == null) {
      return;
    }

    HapticFeedback.selectionClick();

    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    final currentComment =
        widget.state.variationComments[pointerId] ?? fallbackText;
    final hostContext = context;

    final commentConfig = _VariationCommentSheetConfig(
      initialValue: currentComment,
      onSubmit: (ctx, value) async {
        final trimmed = value.trim();
        final normalizedInitial = currentComment.trim();
        if (trimmed == normalizedInitial) {
          return;
        }
        final limited =
            trimmed.length > _variationCommentMaxChars
                ? trimmed.substring(0, _variationCommentMaxChars)
                : trimmed;
        notifier.updateVariationComment(
          variationId: pointerId,
          comment: limited,
        );
      },
    );

    final route = ChessSheetRoutes.commentEditor(
      context: context,
      builder:
          (_) => _DirectCommentSheet(
            config: commentConfig,
            hostContext: hostContext,
          ),
    );

    await Navigator.of(context).push(route);
  }

  void _focusVariationHead(NotationVariationNode variation) {
    if (variation.moves.isEmpty) {
      return;
    }
    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.index,
    );
    final headPointer = List<Number>.of(variation.moves.first.pointer);
    ref
        .read(chessBoardScreenProviderNew(params).notifier)
        .goToMovePointer(headPointer);
  }

  void _toggleVariationCollapse(NotationDisplayToken token) {
    final variation = token.variation;
    if (variation == null) {
      HapticFeedback.lightImpact();
      return;
    }

    final variationId = variation.id;
    final defaultCollapsed = token.defaultsToCollapsed;
    final isCurrentlyCollapsed = token.isCollapsed;

    // If we're trying to collapse a forced-open variation (user is inside it),
    // first navigate to the parent move, then collapse
    if (token.isForcedOpen && !isCurrentlyCollapsed) {
      // Navigate to the parent move (the move that has this variation)
      final parentPointer = variation.parentPointer;
      if (parentPointer.isNotEmpty) {
        final params = ChessBoardProviderParams(
          game: widget.game,
          index: widget.index,
        );
        ref
            .read(chessBoardScreenProviderNew(params).notifier)
            .goToMovePointer(parentPointer);
      }
    }

    setState(() {
      if (defaultCollapsed) {
        if (_expandedVariationIds.remove(variationId)) {
          // revert to default collapsed
        } else {
          _expandedVariationIds.add(variationId);
          _collapsedVariationIds.remove(variationId);
        }
      } else {
        if (_collapsedVariationIds.remove(variationId)) {
          // revert to expanded state
        } else {
          _collapsedVariationIds.add(variationId);
          _expandedVariationIds.remove(variationId);
        }
      }
    });
    HapticFeedback.selectionClick();
  }

  static const List<Color> _variationDepthPalette = [
    Color(0xFFE9EDCC),
    Color(0xFFD6E3BC),
    Color(0xFFBFD3CB),
    Color(0xFFA6C2DA),
    Color(0xFF8EB2CB),
  ];

  Color _accentColorForToken(NotationDisplayToken token) {
    final depth = math.max(1, token.depth);
    final seed = token.variationColorKey ?? token.variation?.id;
    return _colorForVariationAccent(depth, seed: seed);
  }

  Color _colorForVariationAccent(int depth, {String? seed}) {
    if (seed == null || seed.isEmpty) {
      return _colorForVariationDepth(depth);
    }
    return _colorFromSeed(seed);
  }

  Color _colorFromSeed(String seed) {
    final normalizedSeed = seed.hashCode & 0x7fffffff;
    final random = math.Random(normalizedSeed);
    final hue = random.nextDouble() * 360.0;
    final saturation = 0.45 + random.nextDouble() * 0.35;
    final lightness = 0.45 + random.nextDouble() * 0.25;
    final hslColor = HSLColor.fromAHSL(1.0, hue, saturation, lightness);
    return hslColor.toColor();
  }

  Color _colorForVariationDepth(int depth) {
    if (depth <= 0) {
      return context.colors.textPrimary;
    }
    final paletteIndex = (depth - 1) % _variationDepthPalette.length;
    return _variationDepthPalette[paletteIndex];
  }

  Color _resolveMoveColor(NotationDisplayToken token, int currentPly) {
    final node = token.node;
    if (node == null) {
      return context.colors.textPrimary;
    }

    if (token.pointerId == null) {
      return context.colors.textPrimary;
    }

    final isPast = currentPly >= 0 && node.ply <= currentPly;
    if (node.isMainline || token.depth <= 0) {
      return context.colors.textPrimary.withValues(alpha: isPast ? 0.95 : 0.95);
    }

    // Variation moves: white with alpha that decays by depth — readable
    // hierarchy without per-line tinting (the rail carries the depth color).
    final alpha = switch (token.depth) {
      1 => isPast ? 0.85 : 0.78,
      2 => isPast ? 0.70 : 0.62,
      _ => isPast ? 0.58 : 0.50,
    };
    return context.colors.textPrimary.withValues(alpha: alpha);
  }

  /// Typography ladder per variation depth — the visual hierarchy that lets
  /// the eye separate mainline from subline at a glance, in concert with the
  /// guide-rail colors.
  _MoveLadder _moveLadderForDepth(int depth, {required bool isMainline}) {
    if (isMainline || depth <= 0) {
      return _MoveLadder(
        sanSize: 13.sp,
        sanWeight: FontWeight.w700,
        sanLetterSpacing: -0.1,
        numberSize: 12.sp,
        numberAlpha: 0.55,
      );
    }
    if (depth == 1) {
      return _MoveLadder(
        sanSize: 12.5.sp,
        sanWeight: FontWeight.w600,
        sanLetterSpacing: -0.05,
        numberSize: 11.5.sp,
        numberAlpha: 0.45,
      );
    }
    if (depth == 2) {
      return _MoveLadder(
        sanSize: 12.sp,
        sanWeight: FontWeight.w500,
        sanLetterSpacing: 0.0,
        numberSize: 11.sp,
        numberAlpha: 0.40,
      );
    }
    return _MoveLadder(
      sanSize: 11.5.sp,
      sanWeight: FontWeight.w500,
      sanLetterSpacing: 0.0,
      numberSize: 10.5.sp,
      numberAlpha: 0.35,
    );
  }

  LichessMoveAnnotation? _resolveLichessAnnotation(
    NotationDisplayToken token,
    Map<int, LichessMoveAnnotation> annotations,
  ) {
    final node = token.node;
    if (node == null || !node.isMainline) return null;
    final moveIndex = token.moveIndex;
    if (moveIndex == null) return null;
    final result = annotations[moveIndex];
    // Debug: Only log when we should find an annotation but don't
    if (result == null && annotations.containsKey(moveIndex)) {
      debugPrint(
        '⚠️ [Annotation] MISMATCH: moveIndex=$moveIndex exists in annotations but lookup returned null',
      );
    }
    return result;
  }

  void _schedulePointerScroll(ChessMovePointer pointer, String? pointerId) {
    if (widget.index != widget.currentPageIndex) return;
    if (pointerId == null) return;
    if (_lastPointer != null &&
        _pointerEquality.equals(_lastPointer!, pointer)) {
      return;
    }
    _lastPointer = List.of(pointer);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToPointer(
        pointerId,
        isInitialScroll: !_hasInitiallyScrolled,
        alignment: _hasInitiallyScrolled ? 0.5 : 1.0,
      );
    });
  }

  void _scrollToPointer(
    String pointerId, {
    bool isInitialScroll = false,
    double alignment = 0.5,
  }) {
    if (!_scrollController.hasClients) {
      if (isInitialScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToPointer(
            pointerId,
            isInitialScroll: true,
            alignment: alignment,
          );
        });
      }
      return;
    }

    final key = _moveKeys[pointerId];
    final context = key?.currentContext;
    if (context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToPointer(
          pointerId,
          isInitialScroll: isInitialScroll,
          alignment: alignment,
        );
      });
      return;
    }

    final targetContext = context;
    final isTablet = ResponsiveHelper.isTablet;

    Future.microtask(() {
      if (!mounted) return;
      if (!targetContext.mounted) return;

      // On tablets, use direct scroll controller manipulation to prevent
      // Scrollable.ensureVisible from propagating to the parent PageView,
      // which causes the "halfway scroll and snap back" bug.
      if (isTablet) {
        _scrollToTargetOnTablet(
          targetContext,
          alignment: alignment,
          animate: !isInitialScroll,
        );
      } else {
        // On mobile, Scrollable.ensureVisible works fine
        Scrollable.ensureVisible(
          targetContext,
          duration:
              isInitialScroll
                  ? const Duration(milliseconds: 1)
                  : const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: alignment,
        );
      }
      _hasInitiallyScrolled = true;
    });
  }

  /// Tablet-specific scroll implementation that uses direct controller
  /// manipulation instead of Scrollable.ensureVisible to prevent
  /// the scroll from propagating to parent scrollables (PageView).
  void _scrollToTargetOnTablet(
    BuildContext targetContext, {
    double alignment = 0.5,
    bool animate = true,
  }) {
    if (!_scrollController.hasClients) return;

    final targetRenderObject = targetContext.findRenderObject();
    if (targetRenderObject == null) return;

    final scrollableState = Scrollable.maybeOf(targetContext);
    if (scrollableState == null) return;

    final scrollableRenderObject = scrollableState.context.findRenderObject();
    if (scrollableRenderObject == null) return;

    // Get the target's position relative to the scrollable viewport
    final targetBox = targetRenderObject as RenderBox;
    final scrollableBox = scrollableRenderObject as RenderBox;

    // Get the target's position in the scrollable's coordinate space
    final targetOffset = targetBox.localToGlobal(
      Offset.zero,
      ancestor: scrollableBox,
    );

    // Calculate viewport dimensions
    final viewportHeight = _scrollController.position.viewportDimension;
    final targetHeight = targetBox.size.height;

    // Calculate where we want the target to be positioned (based on alignment)
    // alignment 0.0 = top of viewport, 0.5 = center, 1.0 = bottom
    final desiredPosition =
        viewportHeight * alignment - targetHeight * alignment;

    // Calculate the scroll offset needed
    final currentScroll = _scrollController.offset;
    final targetScrollOffset =
        currentScroll + targetOffset.dy - desiredPosition;

    // Clamp to valid scroll range
    final maxScroll = _scrollController.position.maxScrollExtent;
    final clampedOffset = targetScrollOffset.clamp(0.0, maxScroll);

    if (animate) {
      _scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else {
      _scrollController.jumpTo(clampedOffset);
    }
  }

  bool _collectVariationAncestors(
    String? pointerId,
    List<NotationMoveNode> moves,
    Set<String> output,
  ) {
    if (pointerId == null) {
      return false;
    }

    for (final node in moves) {
      final nodeId = NotationPointer.encode(node.pointer);
      if (nodeId == pointerId) {
        return true;
      }
      for (final variation in node.variations) {
        if (_collectVariationAncestors(pointerId, variation.moves, output)) {
          output.add(variation.id);
          return true;
        }
      }
    }
    return false;
  }

  ChessMovePointer? _variantHeadPointerForMove(ChessMovePointer pointer) {
    if (pointer.length < 3) {
      return null;
    }
    for (int i = pointer.length - 2; i >= 0; i--) {
      if (i.isOdd) {
        final head = List<Number>.of(pointer.sublist(0, i + 1));
        head.add(0);
        return head;
      }
    }
    return null;
  }

  ChessMovePointer? _variantHeadPointerForToken(NotationDisplayToken token) {
    final variation = token.variation;
    if (variation != null) {
      final head = <Number>[
        ...variation.parentPointer,
        variation.variationIndex,
        0,
      ];
      return head;
    }
    if (token.pointer != null) {
      return _variantHeadPointerForMove(token.pointer!);
    }
    final head = token.variationHeadPointer;
    return head == null ? null : List<Number>.of(head);
  }

  Duration? _parseClockLabel(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty || cleaned.contains('-')) return null;

    final parts = cleaned.split(':');
    if (parts.length == 2) {
      final minutes = int.tryParse(parts[0]);
      final seconds = int.tryParse(parts[1]);
      if (minutes == null || seconds == null) return null;
      return Duration(minutes: minutes, seconds: seconds);
    }
    if (parts.length == 3) {
      final hours = int.tryParse(parts[0]);
      final minutes = int.tryParse(parts[1]);
      final seconds = int.tryParse(parts[2]);
      if (hours == null || minutes == null || seconds == null) return null;
      return Duration(hours: hours, minutes: minutes, seconds: seconds);
    }
    return null;
  }

  Duration? _parseDurationFromTcToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty || trimmed == '-') return null;
    final parts = trimmed.split(':');
    if (parts.length == 1) {
      final seconds = int.tryParse(parts[0]);
      return seconds != null ? Duration(seconds: seconds) : null;
    }
    if (parts.length == 2) {
      final minutes = int.tryParse(parts[0]);
      final seconds = int.tryParse(parts[1]);
      if (minutes == null || seconds == null) return null;
      return Duration(minutes: minutes, seconds: seconds);
    }
    if (parts.length == 3) {
      final hours = int.tryParse(parts[0]);
      final minutes = int.tryParse(parts[1]);
      final seconds = int.tryParse(parts[2]);
      if (hours == null || minutes == null || seconds == null) return null;
      return Duration(hours: hours, minutes: minutes, seconds: seconds);
    }
    return null;
  }

  _TimeControlSnapshot _parseTimeControlSnapshot() {
    final pgn = widget.state.pgnData ?? widget.game.pgn;
    Duration? base;
    Duration increment = Duration.zero;

    if (pgn != null && pgn.isNotEmpty) {
      final tcMatch = RegExp(
        r'\[TimeControl "([^"]+)"\]',
        multiLine: true,
      ).firstMatch(pgn);
      final raw = tcMatch?.group(1);
      if (raw != null && raw.isNotEmpty && raw != '-') {
        // Only examine the primary phase (before any commas)
        final primaryPhase = raw.split(',').first.trim();

        // Extract increment (after '+') if present
        String baseToken = primaryPhase;
        final plusIndex = primaryPhase.lastIndexOf('+');
        if (plusIndex != -1 && plusIndex < primaryPhase.length - 1) {
          final incToken = primaryPhase.substring(plusIndex + 1);
          increment = _parseDurationFromTcToken(incToken) ?? Duration.zero;
          baseToken = primaryPhase.substring(0, plusIndex);
        }

        // Remove move-count prefix (e.g., "40/7200") to isolate time value
        if (baseToken.contains('/')) {
          final segments = baseToken.split('/');
          baseToken = segments.isNotEmpty ? segments.last : baseToken;
        }

        base = _parseDurationFromTcToken(baseToken);
      }
    }

    return _TimeControlSnapshot(base: base, increment: increment);
  }

  String _formatDurationLabel(Duration duration) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
    }
    return '${duration.inMinutes}:${twoDigits(duration.inSeconds.remainder(60))}';
  }

  String? _buildTimeSpentLabel(ChessMovePointer pointer, bool isMainlineMove) {
    if (!isMainlineMove || pointer.isEmpty) return null;

    final moveIndex = pointer.first.toInt();
    if (moveIndex < 0 || moveIndex >= widget.state.moveTimes.length) {
      return null;
    }

    final currentClock = _parseClockLabel(widget.state.moveTimes[moveIndex]);
    if (currentClock == null) return null;

    Duration? previousClock;
    for (int i = moveIndex - 2; i >= 0; i -= 2) {
      previousClock = _parseClockLabel(widget.state.moveTimes[i]);
      if (previousClock != null) break;
    }

    final timeControl = _parseTimeControlSnapshot();
    final startingClock = previousClock ?? timeControl.base;
    if (startingClock == null) return null;

    final spentSeconds =
        startingClock.inSeconds +
        timeControl.increment.inSeconds -
        currentClock.inSeconds;
    final safeSeconds = spentSeconds < 0 ? 0 : spentSeconds;

    return _formatDurationLabel(Duration(seconds: safeSeconds));
  }

  Future<void> _showMoveActions(
    ChessBoardProviderParams params,
    ChessMovePointer pointer,
    String moveText,
    bool isNullMove,
    bool isMainlineMove,
    ChessMovePointer? variantHeadOverride,
  ) async {
    final hostContext = context;
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    final variantHeadPointer =
        variantHeadOverride ?? _variantHeadPointerForMove(pointer);
    final canModifyVariant = variantHeadPointer != null && !isMainlineMove;
    final pointerId = NotationPointer.encode(pointer);
    final currentComment = widget.state.variationComments[pointerId] ?? '';
    final timeSpentLabel = _buildTimeSpentLabel(pointer, isMainlineMove);

    final commentConfig = _VariationCommentSheetConfig(
      initialValue: currentComment,
      onSubmit: (ctx, value) async {
        if (!mounted) return;
        final trimmed = value.trim();
        final normalizedInitial = currentComment.trim();
        if (trimmed == normalizedInitial) {
          _showInfoSnack(hostContext, 'No changes');
          return;
        }
        final limited =
            trimmed.length > _variationCommentMaxChars
                ? trimmed.substring(0, _variationCommentMaxChars)
                : trimmed;
        notifier.updateVariationComment(
          variationId: pointerId,
          comment: limited,
        );
        if (limited.isEmpty) {
          _showInfoSnack(hostContext, 'Comment removed');
        } else {
          _showInfoSnack(hostContext, 'Comment added');
        }
      },
    );

    final actions = <_NotationActionItem>[
      _NotationActionItem(
        icon: Icons.delete_outline,
        label: 'Delete from here',
        color: kRedColor,
        onSelected: (_) async {
          await notifier.deleteContinuationFromPointer(
            List<Number>.of(pointer),
          );
        },
      ),
      _NotationActionItem(
        icon: Icons.block,
        label: 'Add null move after',
        color: kPrimaryColor,
        onSelected: (_) async {
          await notifier.insertNullMoveAfterPointer(List<Number>.of(pointer));
        },
      ),
      _NotationActionItem(
        icon: Icons.label_important_outline_rounded,
        label: 'Annotate (!?, ±, …)',
        color: const Color(0xFF22AC38),
        onSelected: (_) async {
          if (!mounted) return;
          await _showNagPicker(
            params: params,
            pointer: List<Number>.of(pointer),
            pointerId: pointerId,
            moveText: isNullMove ? 'Null move' : moveText,
          );
        },
      ),
      _NotationActionItem(
        icon: Icons.add_comment_outlined,
        label: 'Add comment',
        color: context.colors.textPrimary,
        triggersCommentEditor: true,
        onSelected: (_) async {},
      ),
      if (canModifyVariant)
        _NotationActionItem(
          icon: Icons.delete_forever,
          label: 'Delete variant',
          color: kRedColor,
          onSelected: (_) async {
            final snapshot = notifier.navigatorStateSnapshot();
            await notifier.deleteVariationAtPointer(
              List<Number>.of(variantHeadPointer),
            );
            if (!mounted) return;
            final currentContext = this.context;
            if (snapshot != null) {
              _showUndoSnackBar(
                currentContext,
                params,
                snapshot,
                'Variant removed',
              );
            } else {
              _showInfoSnack(currentContext, 'Variant removed');
            }
          },
        ),
      // if (canModifyVariant)
      //   _NotationActionItem(
      //     icon: Icons.trending_up_rounded,
      //     label: 'Promote variant',
      //     color: kPrimaryColor,
      //     onSelected: (_) async {
      //       await notifier.promoteVariationAtPointer(
      //         List<Number>.of(variantHeadPointer),
      //       );
      //     },
      //   ),
      if (!isMainlineMove)
        _NotationActionItem(
          icon: Icons.upgrade_rounded,
          label: 'Promote main variant',
          color: kPrimaryColor,
          onSelected: (_) async {
            await notifier.promoteBranchToMainVariant(List<Number>.of(pointer));
          },
        ),
    ];

    final hasExpandedOptions = actions.length > 3;
    final initialSheetFraction =
        hasExpandedOptions
            ? _variantActionSheetInitialFraction
            : _mainlineActionSheetInitialFraction;

    await _showNotationActionSheet(
      context: hostContext,
      title: isNullMove ? 'Null move' : moveText,
      subtitle: 'Move options',
      actions: actions,
      commentConfig: commentConfig,
      timeSpentLabel: timeSpentLabel,
      initialSheetFraction: initialSheetFraction,
    );
  }

  /// Open the NAG picker for a single move. Lets the user toggle quality,
  /// evaluation, and observation glyphs on/off — at most one per category.
  Future<void> _showNagPicker({
    required ChessBoardProviderParams params,
    required ChessMovePointer pointer,
    required String pointerId,
    required String moveText,
  }) async {
    HapticFeedback.selectionClick();
    ref
        .read(chessBoardScreenProviderNew(params).notifier)
        .goToMovePointer(List<Number>.of(pointer));
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder:
          (sheetContext) => _NagPickerSheet(
            moveText: moveText,
            params: params,
            pointerId: pointerId,
          ),
    );
  }

  Future<void> _showVariationActions(NotationDisplayToken token) async {
    final variation = token.variation;
    final headPointer = _variantHeadPointerForToken(token);
    if (variation == null || headPointer == null) {
      return;
    }
    final hostContext = context;
    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.index,
    );
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    final commentConfig = _buildVariationCommentConfig(
      variation: variation,
      notifier: notifier,
      hostContext: hostContext,
    );
    final actions = <_NotationActionItem>[
      _NotationActionItem(
        icon: Icons.add_comment_outlined,
        label: 'Add comment',
        color: context.colors.textPrimary,
        onSelected: (_) async {},
        triggersCommentEditor: true,
      ),
      _NotationActionItem(
        icon: Icons.delete_forever,
        label: 'Delete variant',
        color: kRedColor,
        onSelected: (_) async {
          final snapshot = notifier.navigatorStateSnapshot();
          await notifier.deleteVariationAtPointer(List<Number>.of(headPointer));
          if (!mounted) return;
          final currentContext = this.context;
          if (snapshot != null) {
            _showUndoSnackBar(
              currentContext,
              params,
              snapshot,
              'Variation removed',
            );
          } else {
            _showInfoSnack(currentContext, 'Variation removed');
          }
        },
      ),
      _NotationActionItem(
        icon: Icons.upgrade_rounded,
        label: 'Promote main variant',
        color: kPrimaryColor,
        onSelected: (_) async {
          await notifier.promoteBranchToMainVariant(
            List<Number>.of(headPointer),
          );
        },
      ),
    ];

    final hasExpandedOptions = actions.length > 3;
    final initialSheetFraction =
        hasExpandedOptions
            ? _variantActionSheetInitialFraction
            : _mainlineActionSheetInitialFraction;

    await _showNotationActionSheet(
      context: hostContext,
      title: 'Variation',
      subtitle: 'Variation options',
      actions: actions,
      commentConfig: commentConfig,
      initialSheetFraction: initialSheetFraction,
    );
  }

  _VariationCommentSheetConfig _buildVariationCommentConfig({
    required NotationVariationNode variation,
    required ChessBoardScreenNotifierNew notifier,
    required BuildContext hostContext,
  }) {
    final initialComment = widget.state.variationComments[variation.id] ?? '';
    return _VariationCommentSheetConfig(
      initialValue: initialComment,
      onSubmit: (ctx, value) async {
        if (!mounted) return;
        final trimmed = value.trim();
        final normalizedInitial = initialComment.trim();
        if (trimmed == normalizedInitial) {
          _showInfoSnack(hostContext, 'No changes');
          return;
        }
        final limited =
            trimmed.length > _variationCommentMaxChars
                ? trimmed.substring(0, _variationCommentMaxChars)
                : trimmed;
        notifier.updateVariationComment(
          variationId: variation.id,
          comment: limited,
        );
        if (limited.isEmpty) {
          _showInfoSnack(hostContext, 'Comment removed');
        } else {
          _showInfoSnack(hostContext, 'Comment added');
        }
      },
    );
  }

  Widget _buildMovesLoadingSkeleton() {
    return Container(
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.all(20.sp),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SkeletonContainer(height: 16.h, width: 80.w, borderRadius: 4.sp),
            SizedBox(height: 12.h),
            ...List.generate(6, (rowIndex) {
              return Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Wrap(
                  spacing: 8.sp,
                  children: [
                    _SkeletonContainer(
                      height: 14.h,
                      width: (60 + (rowIndex % 3) * 20).w,
                      borderRadius: 3.sp,
                    ),
                    _SkeletonContainer(
                      height: 14.h,
                      width: (45 + (rowIndex % 4) * 15).w,
                      borderRadius: 3.sp,
                    ),
                  ],
                ),
              );
            }),
            SizedBox(height: 8.h),
            Wrap(
              spacing: 6.sp,
              runSpacing: 6.sp,
              children: List.generate(8, (index) {
                return _SkeletonContainer(
                  height: 14.h,
                  width: (35 + (index % 5) * 20).w,
                  borderRadius: 3.sp,
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  void _showUndoSnackBar(
    BuildContext context,
    ChessBoardProviderParams params,
    ChessGameNavigatorState snapshot,
    String message,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.surface.withValues(alpha: 0.95),
        elevation: 2,
        margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.sp),
          side: BorderSide(
            color: context.colors.textPrimary.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        content: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.sp),
              decoration: BoxDecoration(
                color: kRedColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8.sp),
              ),
              child: Icon(Icons.delete_outline, color: kRedColor, size: 18.ic),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                message,
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                ref
                    .read(chessBoardScreenProviderNew(params).notifier)
                    .restoreNavigatorState(snapshot);
                messenger.hideCurrentSnackBar();
              },
              style: TextButton.styleFrom(
                foregroundColor: kPrimaryColor,
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'UNDO',
                style: AppTypography.textSmBold.copyWith(color: kPrimaryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoSnack(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.surface.withValues(alpha: 0.95),
        elevation: 0,
        duration: const Duration(seconds: 2),
        margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18.sp),
          side: BorderSide(
            color: context.colors.textPrimary.withValues(alpha: 0.08),
          ),
        ),
        content: Row(
          children: [
            Container(
              padding: EdgeInsets.all(6.sp),
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10.sp),
              ),
              child: Icon(
                Icons.info_outline,
                size: 16.ic,
                color: kPrimaryColor,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                message,
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectCommentSheet extends ConsumerWidget {
  final _VariationCommentSheetConfig config;
  final BuildContext hostContext;

  const _DirectCommentSheet({required this.config, required this.hostContext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigator = Navigator(
      onGenerateInitialRoutes:
          (_, __) => [
            SpringPagedSheetRoute(
              scrollConfiguration: const SheetScrollConfiguration(),
              dragConfiguration: ChessSheetConfigs.commentEditor,
              initialOffset: const SheetOffset.proportionalToViewport(0.8),
              snapGrid: ChessSheetConfigs.commentEditorSnaps(
                minFlingSpeed: 650.0,
              ),
              builder:
                  (context) => _NotationCommentPage(
                    config: config,
                    hostContext: hostContext,
                  ),
            ),
          ],
    );

    return SheetKeyboardDismissible(
      dismissBehavior: const DragDownSheetKeyboardDismissBehavior(
        isContentScrollAware: true,
      ),
      child: PagedSheet(
        decoration: ChessSheetDecoration.dark(
          context,
          alpha: 0.97,
          borderRadius: 28.sp,
        ),
        shrinkChildToAvoidDynamicOverlap: true,
        navigator: navigator,
      ),
    );
  }
}

const int _variationCommentPreviewChars = 80;
const int _variationCommentMaxChars = 280;

class _PrincipalVariationList extends ConsumerStatefulWidget {
  final int index;
  final ChessBoardStateNew state;
  final GamesTourModel game;

  const _PrincipalVariationList({
    super.key,
    required this.index,
    required this.state,
    required this.game,
  });

  @override
  ConsumerState<_PrincipalVariationList> createState() =>
      _PrincipalVariationListState();
}

class _PrincipalVariationListState
    extends ConsumerState<_PrincipalVariationList> {
  late PageController _pageController;
  int _currentPage = 0;
  int? _lastUserSelectedIndex;
  int? _pendingPageJump;
  bool _pendingPageJumpAnimated = false;
  int? _pendingVariantSelectionIndex;
  List<AnalysisLine> _lastNonEmptyLines = const [];
  String? _lastPositionKey;

  // Preview card notation scroll support
  final ScrollController _previewScrollController = ScrollController();
  final Map<int, GlobalKey> _previewMoveKeys = {};
  int? _lastScrolledPreviewIndex;
  int? _pressedVariantIndex;

  void _setCardPressed(int? index) {
    if (_pressedVariantIndex == index) return;
    setState(() {
      _pressedVariantIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    final lines = widget.state.principalVariations.toList(growable: false);
    final initialIndex = widget.state.selectedVariantIndex ?? 0;
    // Ensure initial page is within bounds
    if (lines.isEmpty) {
      _currentPage = 0;
    } else if (initialIndex < 0) {
      _currentPage = 0;
    } else if (initialIndex >= lines.length) {
      _currentPage = lines.length - 1;
    } else {
      _currentPage = initialIndex;
    }
    _lastNonEmptyLines = lines;
    _lastUserSelectedIndex = lines.isEmpty ? null : _currentPage;
    _pageController = PageController(initialPage: _currentPage);
    _lastPositionKey = _derivePositionKey(widget.state);
  }

  @override
  void didUpdateWidget(_PrincipalVariationList oldWidget) {
    super.didUpdateWidget(oldWidget);

    // When entering preview mode with locked PV, jump to page 0
    final wasPreviewActive = oldWidget.state.isPvPreviewActive;
    final isPreviewActive = widget.state.isPvPreviewActive;
    final hasLockedPv = widget.state.lockedPvLine != null;

    if (!wasPreviewActive && isPreviewActive && hasLockedPv) {
      _currentPage = 0;
      _lastUserSelectedIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
    }

    // Auto-scroll preview card notation when navigation index changes
    final oldNavIndex = oldWidget.state.lockedPvNavigationIndex;
    final newNavIndex = widget.state.lockedPvNavigationIndex;
    if (isPreviewActive &&
        hasLockedPv &&
        newNavIndex != null &&
        newNavIndex != oldNavIndex &&
        newNavIndex != _lastScrolledPreviewIndex) {
      _lastScrolledPreviewIndex = newNavIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToPreviewMove(newNavIndex);
      });
    }

    if (isPreviewActive && hasLockedPv) {
      if (_currentPage != 0) {
        _currentPage = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        });
      }
      _lastPositionKey = _derivePositionKey(widget.state);
      return;
    }

    final lines = widget.state.principalVariations.toList(growable: false);
    final pageCount = lines.length;
    final positionKey = _derivePositionKey(widget.state);
    final positionChanged = positionKey != _lastPositionKey;
    _lastPositionKey = positionKey;

    // Update cached lines: clear on position change, update when new lines available
    if (positionChanged) {
      // Clear cached lines when position changes to avoid showing PV lines from wrong position
      _lastNonEmptyLines = const [];
    }
    if (lines.isNotEmpty) {
      _lastNonEmptyLines = lines;
    }

    // Preserve user selection reference when PV list temporarily empties
    if (pageCount == 0) {
      _lastUserSelectedIndex ??=
          oldWidget.state.selectedVariantIndex ?? _currentPage;
      return;
    }

    final int maxIndex = pageCount - 1;

    if (_currentPage > maxIndex) {
      _currentPage = pageCount - 1;
    }

    final oldSelectedIndex = oldWidget.state.selectedVariantIndex;
    final newSelectedIndex = widget.state.selectedVariantIndex;
    final selectedIndexChanged = oldSelectedIndex != newSelectedIndex;
    final userSelected = _lastUserSelectedIndex;
    final ignoreSelectedChangeAfterPosition =
        positionChanged && userSelected != null;

    int targetIndex;

    // CRITICAL FIX: Only jump pages when position changes or user explicitly selects a variant
    // During silent updates (depth increases), preserve the user's current scroll position
    if (positionChanged) {
      // Position changed - keep the user's last viewed variant when possible
      final desiredIndex =
          _lastUserSelectedIndex ?? newSelectedIndex ?? _currentPage;
      targetIndex = desiredIndex.clamp(0, maxIndex);
      _lastUserSelectedIndex ??= desiredIndex;
    } else if (selectedIndexChanged &&
        newSelectedIndex != null &&
        newSelectedIndex <= maxIndex) {
      // If position just changed, prefer the user's last selection to avoid flicker
      if (ignoreSelectedChangeAfterPosition && userSelected != null) {
        targetIndex = userSelected;
      } else {
        // User explicitly selected a variant (selectedVariantIndex changed) - honor that selection
        targetIndex = newSelectedIndex;
        _lastUserSelectedIndex = newSelectedIndex;
      }
    } else if (userSelected != null && userSelected <= maxIndex) {
      // Silent update (e.g., depth increase) - preserve user's current position
      targetIndex = userSelected;
    } else if (_currentPage > maxIndex) {
      // Current page out of bounds - clamp to max
      targetIndex = maxIndex;
    } else {
      // Preserve current page during silent updates
      targetIndex = _currentPage;
    }

    if (targetIndex != _currentPage) {
      // Only animate when user explicitly selects a variant
      final animate =
          !positionChanged &&
          selectedIndexChanged &&
          newSelectedIndex != null &&
          newSelectedIndex == targetIndex;
      _currentPage = targetIndex;
      _jumpToPage(targetIndex, animate: animate);
    }

    // Only schedule variant selection if:
    // 1. Not in preview mode (preview mode handles its own variant selection in onPageChanged)
    // 2. The provider's selectedVariantIndex doesn't match our target
    // 3. We have a valid user selection to apply
    final isInPreview = widget.state.isPvPreviewActive;
    if (!isInPreview &&
        (newSelectedIndex == null || newSelectedIndex != targetIndex) &&
        _lastUserSelectedIndex != null &&
        _lastUserSelectedIndex! <= maxIndex) {
      _scheduleVariantSelection(_lastUserSelectedIndex!);
    }
  }

  void _scrollToPreviewMove(int moveIndex) {
    if (!_previewScrollController.hasClients) return;
    if (!mounted) return;

    final key = _previewMoveKeys[moveIndex];
    final context = key?.currentContext;
    if (context == null) {
      // Context not ready yet, try again
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToPreviewMove(moveIndex);
      });
      return;
    }

    final targetContext = context;
    final isTablet = ResponsiveHelper.isTablet;

    Future.microtask(() {
      if (!mounted) return;
      if (!targetContext.mounted) return;

      // On tablets, use direct scroll controller manipulation to prevent
      // Scrollable.ensureVisible from propagating to the parent PageView.
      if (isTablet) {
        _scrollToPreviewMoveOnTablet(targetContext);
      } else {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: 0.5, // Center the move in the viewport
        );
      }
    });
  }

  /// Tablet-specific scroll for preview moves that uses direct controller
  /// manipulation instead of Scrollable.ensureVisible.
  void _scrollToPreviewMoveOnTablet(BuildContext targetContext) {
    if (!_previewScrollController.hasClients) return;

    final targetRenderObject = targetContext.findRenderObject();
    if (targetRenderObject == null) return;

    final scrollableState = Scrollable.maybeOf(targetContext);
    if (scrollableState == null) return;

    final scrollableRenderObject = scrollableState.context.findRenderObject();
    if (scrollableRenderObject == null) return;

    final targetBox = targetRenderObject as RenderBox;
    final scrollableBox = scrollableRenderObject as RenderBox;

    final targetOffset = targetBox.localToGlobal(
      Offset.zero,
      ancestor: scrollableBox,
    );

    // For horizontal scroll, use width instead of height
    final viewportWidth = _previewScrollController.position.viewportDimension;
    final targetWidth = targetBox.size.width;

    // Center the target (alignment 0.5)
    const alignment = 0.5;
    final desiredPosition = viewportWidth * alignment - targetWidth * alignment;

    final currentScroll = _previewScrollController.offset;
    final targetScrollOffset =
        currentScroll + targetOffset.dx - desiredPosition;

    final maxScroll = _previewScrollController.position.maxScrollExtent;
    final clampedOffset = targetScrollOffset.clamp(0.0, maxScroll);

    _previewScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _previewScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.index,
    );
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    final position =
        widget.state.isAnalysisMode
            ? widget.state.analysisState.position
            : widget.state.position;
    final baseMoveNumber = position?.fullmoves ?? 1;
    final isWhiteToMove = (position?.turn ?? Side.white) == Side.white;

    // Get user's PV count setting (caps at 5)
    final engineSettings = ref.watch(engineSettingsProviderNew).valueOrNull;
    final multiPV = engineSettings?.multiPvForLichess() ?? 3;

    // Get figurine notation setting and piece assets for PV card rendering
    final useFigurine = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.useFigurine ?? const BoardSettingsNew().useFigurine,
      ),
    );
    final pieceAssets = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.pieceAssets ?? const BoardSettingsNew().pieceAssets,
      ),
    );

    // Check if position is terminal (game over)
    final isGameOver = position?.isGameOver ?? false;

    const double basePvHeight = 78;
    final double pvCardHeight = basePvHeight.h;

    // Clamp PVs to user preference
    final clampedLines =
        (widget.state.principalVariations.length > multiPV)
            ? widget.state.principalVariations
                .take(multiPV)
                .toList(growable: false)
            : widget.state.principalVariations.toList(growable: false);

    final hasActivePvs = clampedLines.isNotEmpty;
    final fallbackLines =
        (!hasActivePvs && _lastNonEmptyLines.isNotEmpty)
            ? (_lastNonEmptyLines.length > multiPV
                ? _lastNonEmptyLines.take(multiPV).toList(growable: false)
                : _lastNonEmptyLines.toList(growable: false))
            : const <AnalysisLine>[];
    final displayLines = hasActivePvs ? clampedLines : fallbackLines;
    // Determine loading state for PV cards
    final showEndOfGame = isGameOver && widget.state.isAnalysisMode;
    final showSkeleton =
        !showEndOfGame &&
        !hasActivePvs &&
        _lastNonEmptyLines.isEmpty &&
        widget.state.isEvaluating;
    final showEmptyState =
        !showEndOfGame &&
        displayLines.isEmpty &&
        !widget.state.isEvaluating &&
        _lastNonEmptyLines.isEmpty;
    // Add 1 to pageCount when in preview mode for the static PV card
    final hasLockedPv =
        widget.state.isPvPreviewActive && widget.state.lockedPvLine != null;
    final basePageCount =
        (showSkeleton || showEmptyState) ? 1 : displayLines.length;
    // During preview mode, only show the static preview card (pageCount = 1)
    final pageCount = hasLockedPv ? 1 : basePageCount;

    List<InlineSpan> buildPreviewCardSpans(
      List<_PvToken> tokens,
      Color variantColor,
    ) {
      final spans = <InlineSpan>[];
      final baseStyle = AppTypography.textXsMedium.copyWith(
        color: context.colors.textPrimary.withValues(alpha: 0.95),
        fontWeight: FontWeight.w600,
      );

      final currentNavIndex = widget.state.lockedPvNavigationIndex ?? -1;

      // Clear old keys before rebuilding
      _previewMoveKeys.clear();

      for (final token in tokens) {
        final isMove = token.moveIndex != null;
        final isSelectedMove = isMove && token.moveIndex == currentNavIndex;

        if (!isMove) {
          spans.add(TextSpan(text: '${token.text} ', style: baseStyle));
          continue;
        }

        // Add selected state highlighting - use same variant color as main variant
        final moveStyle =
            isSelectedMove
                ? baseStyle.copyWith(
                  backgroundColor: variantColor.withValues(alpha: 0.4),
                  color: context.colors.textPrimary,
                )
                : baseStyle;

        // Create GlobalKey for this move to enable scrolling
        final key = GlobalKey();
        _previewMoveKeys[token.moveIndex!] = key;

        // Build move content - either with figurine pieces or plain text
        Widget moveContent;
        if (useFigurine) {
          final figurineSpans = buildFigurineSpans(
            text: token.text,
            pieceAssets: pieceAssets,
            style: moveStyle,
            pieceSize: 12.sp,
          );
          moveContent = Text.rich(
            TextSpan(
              children: [
                ...figurineSpans,
                TextSpan(text: ' ', style: moveStyle),
              ],
            ),
          );
        } else {
          moveContent = Text('${token.text} ', style: moveStyle);
        }

        // Wrap move text in a widget with key for scroll targeting
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              key: key,
              onTap: () {
                HapticFeedback.lightImpact();
                // Navigate to this position in the preview card
                notifier.navigateToPreviewCardIndex(token.moveIndex!);
              },
              child: moveContent,
            ),
          ),
        );
      }
      return spans;
    }

    Widget buildStaticPvCard() {
      final lockedLine = widget.state.lockedPvLine;
      final mergedPositions = widget.state.lockedPvMergedPositions;
      final baseMoveCount = widget.state.lockedPvBaseMoveCount ?? 0;
      final previewVariantIndex = widget.state.pvPreviewVariantIndex ?? 0;

      if (lockedLine == null ||
          mergedPositions == null ||
          mergedPositions.isEmpty) {
        return const SizedBox.shrink();
      }

      // Format only the PV moves for display using the position where the
      // preview started (moves before the PV are hidden from the notation).
      final pvStartIndex =
          baseMoveCount.clamp(0, mergedPositions.length - 1).toInt();
      final startingPosition = mergedPositions[pvStartIndex];
      final startMoveNumber = startingPosition.fullmoves;
      final isWhiteToMove = startingPosition.turn == Side.white;
      final sanMoves = _formatPv(
        lockedLine.sanMoves,
        startMoveNumber,
        isWhiteToMove,
        isThreatsMode: widget.state.isThreatsMode,
      );
      final evalText = _formatEvalLabel(lockedLine);

      // Use the same color as the originating PV card
      final variantColor = notifier.getVariantColor(previewVariantIndex, true);
      final opacityScale = 0.7;
      final borderColor = variantColor.withValues(alpha: opacityScale);
      final backgroundColor = variantColor.withValues(alpha: 0.15);
      final badgeBackgroundColor = variantColor.withValues(alpha: 0.3);
      final badgeBorderColor = variantColor.withValues(alpha: 0.6);
      final pvTokens = _buildPvTokens(sanMoves);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () {
          HapticFeedback.heavyImpact();
          notifier.applyPreviewHistoryAndInsertMove(lockedLine);
        },
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.symmetric(horizontal: 2.sp),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 1.5),
            borderRadius: BorderRadius.circular(6.sp),
            color: backgroundColor,
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              // Subtle left accent border for preview indication
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3.sp,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        variantColor.withValues(alpha: 0.9),
                        variantColor.withValues(alpha: 0.6),
                      ],
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(6.sp),
                      bottomLeft: Radius.circular(6.sp),
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Evaluation badge - non-interactive for static card
                        Padding(
                          padding: EdgeInsets.fromLTRB(12.sp, 10.sp, 0, 10.sp),
                          child: Container(
                            margin: EdgeInsets.only(right: 10.sp),
                            padding: EdgeInsets.symmetric(
                              horizontal: 8.sp,
                              vertical: 4.sp,
                            ),
                            decoration: BoxDecoration(
                              color: badgeBackgroundColor,
                              borderRadius: BorderRadius.circular(4.sp),
                              border: Border.all(
                                color: badgeBorderColor,
                                width: 1.0,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              evalText,
                              style: AppTypography.textXsMedium.copyWith(
                                color: context.colors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        // Notation text - shows merged PGN + PV moves
                        Expanded(
                          child: ClipRect(
                            child: SingleChildScrollView(
                              controller: _previewScrollController,
                              primary: false,
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              padding: EdgeInsets.fromLTRB(
                                0,
                                10.sp,
                                12.sp,
                                10.sp,
                              ),
                              child: RichText(
                                text: TextSpan(
                                  style: AppTypography.textXsMedium.copyWith(
                                    color: context.colors.textPrimary
                                        .withValues(alpha: 0.95),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  children: buildPreviewCardSpans(
                                    pvTokens,
                                    variantColor,
                                  ),
                                ),
                                softWrap: true,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    Widget buildVariantCard({
      required AnalysisLine line,
      required int variantIndex,
      required bool isSelected,
      required bool hasLockedPreview,
    }) {
      final sanMoves = _formatPv(
        line.sanMoves,
        baseMoveNumber,
        isWhiteToMove,
        isThreatsMode: widget.state.isThreatsMode,
      );
      final evalText = _formatEvalLabel(line);
      final activeVariantColor = notifier.getVariantColor(variantIndex, true);
      final opacityScale = 0.7;
      final borderColor = activeVariantColor.withValues(alpha: opacityScale);
      final backgroundColor = activeVariantColor.withValues(alpha: 0.15);
      final pvTokens = _buildPvTokens(sanMoves);

      // Check if any move in this variant is selected for preview
      final isPreviewingThisVariant =
          widget.state.isPvPreviewActive &&
          widget.state.pvPreviewVariantIndex == variantIndex;

      final isPressed = _pressedVariantIndex == variantIndex;

      return GestureDetector(
        onTapDown: (_) => _setCardPressed(variantIndex),
        onTapUp: (_) => _setCardPressed(null),
        onTapCancel: () => _setCardPressed(null),
        onLongPressStart: (_) => _setCardPressed(variantIndex),
        onLongPressEnd: (_) => _setCardPressed(null),
        onTap: () {
          HapticFeedback.lightImpact();
          notifier.clearPvPreview();
          notifier.playPrincipalVariationMove(line);
        },
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _PvToken? focusToken;
          for (final token in pvTokens.reversed) {
            if (token.moveIndex != null) {
              focusToken = token;
              break;
            }
          }
          if (focusToken == null || focusToken.moveIndex == null) {
            return;
          }
          _showPvMoveActionSheet(
            context,
            focusToken.text,
            line,
            variantIndex,
            focusToken.moveIndex!,
            notifier,
            activeVariantColor,
          );
        },
        child: AnimatedScale(
          scale: isPressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Container(
            width: double.infinity,
            margin: EdgeInsets.symmetric(horizontal: 2.sp),
            decoration: BoxDecoration(
              border: Border.all(
                color: borderColor,
                width: isSelected ? 2.0 : 1.5,
              ),
              borderRadius: BorderRadius.circular(6.sp),
              color: backgroundColor,
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Compact evaluation badge on the left
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _lastUserSelectedIndex =
                              hasLockedPreview
                                  ? variantIndex + 1
                                  : variantIndex;
                        });
                        if (widget.state.isPvPreviewActive &&
                            widget.state.lockedPvLine != null) {
                          notifier.previewPrincipalVariationMoveAt(
                            line,
                            variantIndex,
                            0,
                          );
                        } else {
                          notifier.clearPvPreview();
                          notifier.playPrincipalVariationMove(line);
                        }
                      },
                      child: Container(
                        width: 48.sp,
                        decoration: BoxDecoration(
                          color: activeVariantColor.withValues(alpha: 0.25),
                          border: Border(
                            right: BorderSide(
                              color: activeVariantColor.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            evalText,
                            style: AppTypography.textSmBold.copyWith(
                              color: context.colors.textPrimary,
                              fontSize: 12.sp,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Notation text - vertically scrollable middle section
                    Expanded(
                      child: SingleChildScrollView(
                        primary: false,
                        scrollDirection: Axis.vertical,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.sp,
                          vertical: 10.sp,
                        ),
                        child: RichText(
                          text: TextSpan(
                            style: AppTypography.textXsMedium.copyWith(
                              color: context.colors.textPrimary.withValues(
                                alpha: 0.95,
                              ),
                              fontWeight: FontWeight.w600,
                            ),
                            children: _buildPvSpans(
                              tokens: pvTokens,
                              notifier: notifier,
                              line: line,
                              variantIndex: variantIndex,
                              variantColor: activeVariantColor,
                              previewMoveIndex:
                                  isPreviewingThisVariant
                                      ? widget.state.pvPreviewMoveIndex
                                      : null,
                              useFigurine: useFigurine,
                              pieceAssets: pieceAssets,
                            ),
                          ),
                          softWrap: true,
                        ),
                      ),
                    ),
                    // '+' button on the right - inserts next best move
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _lastUserSelectedIndex =
                                hasLockedPreview
                                    ? variantIndex + 1
                                    : variantIndex;
                          });
                          notifier.clearPvPreview();
                          notifier.playPrincipalVariationMove(line);
                        },
                        splashColor: activeVariantColor.withValues(alpha: 0.3),
                        highlightColor: activeVariantColor.withValues(
                          alpha: 0.2,
                        ),
                        child: Container(
                          width: 40.sp,
                          decoration: BoxDecoration(
                            color: activeVariantColor.withValues(alpha: 0.2),
                            border: Border(
                              left: BorderSide(
                                color: activeVariantColor.withValues(
                                  alpha: 0.4,
                                ),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.add_rounded,
                              color: context.colors.textPrimary.withValues(
                                alpha: 0.9,
                              ),
                              size: 20.sp,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      // CRITICAL: No key here! Adding a key that changes with eval causes Flutter
      // to rebuild the entire widget tree, resetting PageController position.
      // State is already managed via _currentPage and _lastUserSelectedIndex.
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.sp, 8.sp, 16.sp, 4.h),
          child: SizedBox(
            height: pvCardHeight,
            child:
                showEndOfGame
                    ? Center(
                      child: Container(
                        width: double.infinity,
                        margin: EdgeInsets.symmetric(horizontal: 2.sp),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: kPrimaryColor.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(6.sp),
                          color: kPrimaryColor.withValues(alpha: 0.1),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.sp,
                          vertical: 10.sp,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.flag_outlined,
                              color: kPrimaryColor,
                              size: 20.sp,
                            ),
                            SizedBox(width: 8.w),
                            Text(
                              'Game Over',
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    : PageView.builder(
                      controller: _pageController,
                      physics:
                          hasLockedPv
                              ? const NeverScrollableScrollPhysics()
                              : const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                      padEnds: false,
                      onPageChanged: (pageIndex) {
                        setState(() {
                          _currentPage = pageIndex;
                          _lastUserSelectedIndex = pageIndex;
                        });

                        // Static preview card at index 0
                        if (hasLockedPv && pageIndex == 0) {
                          return;
                        }

                        if (clampedLines.isEmpty) {
                          return;
                        }

                        // Adjust index for dynamic PV cards when static card is present
                        final variantIndex = (hasLockedPv
                                ? pageIndex - 1
                                : pageIndex)
                            .clamp(0, clampedLines.length - 1);

                        if (!widget.state.isPvPreviewActive) {
                          notifier.selectVariant(
                            variantIndex,
                            preservePreview: hasLockedPv,
                          );
                        }
                      },
                      itemCount: pageCount,
                      itemBuilder: (context, index) {
                        // Show static PV card at index 0 when in preview mode
                        if (hasLockedPv && index == 0) {
                          return buildStaticPvCard();
                        }

                        // Adjust index for dynamic PV cards when static card is present
                        final dynamicIndex = hasLockedPv ? index - 1 : index;

                        if (showSkeleton) {
                          final placeholderLine =
                              displayLines.isNotEmpty
                                  ? displayLines.first
                                  : _lastNonEmptyLines.isNotEmpty
                                  ? _lastNonEmptyLines.first
                                  : const AnalysisLine(
                                    sanMoves: ['...'],
                                    evaluation: 0,
                                  );
                          return Skeletonizer(
                            enabled: true,
                            child: buildVariantCard(
                              line: placeholderLine,
                              variantIndex: 0,
                              isSelected: false,
                              hasLockedPreview: hasLockedPv,
                            ),
                          );
                        }
                        if (showEmptyState) {
                          final placeholderLine = const AnalysisLine(
                            sanMoves: ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'],
                            evaluation: 35,
                          );
                          return Skeletonizer(
                            enabled: true,
                            effect: ShimmerEffect(
                              baseColor: context.colors.textPrimary.withValues(
                                alpha: 0.05,
                              ),
                              highlightColor: context.colors.textPrimary
                                  .withValues(alpha: 0.1),
                              duration: const Duration(milliseconds: 1500),
                            ),
                            child: buildVariantCard(
                              line: placeholderLine,
                              variantIndex: 0,
                              isSelected: false,
                              hasLockedPreview: false,
                            ),
                          );
                        }

                        final variantIndex = dynamicIndex;
                        final line = displayLines[dynamicIndex];
                        final isSelected =
                            hasActivePvs &&
                            widget.state.selectedVariantIndex == variantIndex;

                        return buildVariantCard(
                          line: line,
                          variantIndex: variantIndex,
                          isSelected: isSelected,
                          hasLockedPreview: hasLockedPv,
                        );
                      },
                    ),
          ),
        ),
        SizedBox(height: 4.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pageCount > 0 ? pageCount : 1, (index) {
            if (pageCount == 0) {
              return Container(
                margin: EdgeInsets.symmetric(horizontal: 4.sp),
                width: 6.w,
                height: 6.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.textPrimary.withValues(alpha: 0.1),
                ),
              );
            }
            final isLockedDot = hasLockedPv && index == 0;
            final isActive = index == _currentPage;
            final dynamicIndex = hasLockedPv ? index - 1 : index;

            Color dotColor;
            Border? border;

            if (isLockedDot) {
              dotColor =
                  isActive
                      ? context.colors.textPrimary.withValues(alpha: 0.95)
                      : context.colors.textPrimary.withValues(alpha: 0.35);
              border = Border.all(
                color: context.colors.textPrimary.withValues(
                  alpha: isActive ? 1.0 : 0.65,
                ),
                width: isActive ? 1.5 : 1,
              );
            } else if (displayLines.isNotEmpty) {
              final variantColor = notifier.getVariantColor(
                dynamicIndex.clamp(0, displayLines.length - 1),
                true,
              );
              dotColor =
                  isActive
                      ? variantColor
                      : variantColor.withValues(alpha: 0.35);
            } else {
              dotColor =
                  isActive
                      ? context.colors.textPrimary.withValues(alpha: 0.85)
                      : context.colors.textPrimary.withValues(alpha: 0.3);
            }

            final double size = isLockedDot ? 8.w : 6.w;
            return GestureDetector(
              onTap: () {
                if (!hasLockedPv ||
                    widget.state.isPvPreviewActive == false ||
                    index != 0) {
                  _lastUserSelectedIndex = index;
                }
                if (_pageController.hasClients && pageCount > 0) {
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: EdgeInsets.symmetric(horizontal: 4.sp),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                  border: border,
                ),
              ),
            );
          }),
        ),
        SizedBox(height: 4.h),
      ],
    );
  }

  List<_PvToken> _buildPvTokens(List<String> formattedMoves) {
    final tokens = <_PvToken>[];
    var moveCursor = -1;
    for (final entry in formattedMoves) {
      if (entry.trim().isEmpty) continue;
      final trimmed = entry.trim();
      // Check if this is a move number (white or black)
      // White: "1.", "2.", etc. (number followed by single period)
      // Black: "1...", "2...", etc. (number followed by three periods)
      final isNumber = RegExp(r'^\d+\.\.?\.?$').hasMatch(trimmed);
      if (isNumber) {
        tokens.add(_PvToken(text: entry));
      } else {
        moveCursor++;
        tokens.add(_PvToken(text: entry, moveIndex: moveCursor));
      }
    }
    return tokens;
  }

  List<InlineSpan> _buildPvSpans({
    required List<_PvToken> tokens,
    required ChessBoardScreenNotifierNew notifier,
    required AnalysisLine line,
    required int variantIndex,
    required Color variantColor,
    int? previewMoveIndex,
    bool useFigurine = true,
    PieceAssets? pieceAssets,
  }) {
    final spans = <InlineSpan>[];
    // Use consistent styling for all text in PV notation
    final baseStyle = AppTypography.textXsMedium.copyWith(
      color: context.colors.textPrimary.withValues(alpha: 0.95),
      fontWeight: FontWeight.w600,
    );

    for (final token in tokens) {
      final isMove = token.moveIndex != null;
      final isSelectedMove = isMove && token.moveIndex == previewMoveIndex;

      if (!isMove) {
        spans.add(
          TextSpan(
            text: '${token.text} ',
            style: baseStyle, // Same style as moves
          ),
        );
        continue;
      }

      // Add selected state highlighting
      final moveStyle =
          isSelectedMove
              ? baseStyle.copyWith(
                backgroundColor: kPrimaryColor.withValues(alpha: 0.4),
                color: context.colors.textPrimary,
              )
              : baseStyle;

      // Build move content - either with figurine pieces or plain text
      Widget moveContent;
      if (useFigurine && pieceAssets != null) {
        final figurineSpans = buildFigurineSpans(
          text: token.text,
          pieceAssets: pieceAssets,
          style: moveStyle,
          pieceSize: 12.sp,
        );
        moveContent = Text.rich(
          TextSpan(
            children: [...figurineSpans, TextSpan(text: ' ', style: moveStyle)],
          ),
        );
      } else {
        moveContent = Text('${token.text} ', style: moveStyle);
      }

      // Use WidgetSpan with GestureDetector to handle tap and long press
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              // Single tap: Enter preview mode and navigate to the tapped move
              notifier.previewPrincipalVariationMoveAt(
                line,
                variantIndex,
                token.moveIndex ?? 0,
              );
            },
            onLongPress: () {
              HapticFeedback.mediumImpact();
              _showPvMoveActionSheet(
                context,
                token.text,
                line,
                variantIndex,
                token.moveIndex!,
                notifier,
                variantColor,
              );
            },
            child: Material(color: Colors.transparent, child: moveContent),
          ),
        ),
      );
    }
    return spans;
  }

  List<String> _formatPv(
    List<String> sanMoves,
    int baseMoveNumber,
    bool whiteToMove, {
    bool isThreatsMode = false,
  }) {
    // In threats mode the engine analyses a flipped FEN, so the PV moves
    // belong to the opposite side from what the position indicates.
    final effectiveWhiteToMove = isThreatsMode ? !whiteToMove : whiteToMove;

    final formatted = <String>[];
    for (var i = 0; i < sanMoves.length; i++) {
      final isWhiteMove = effectiveWhiteToMove ? i.isEven : i.isOdd;

      final moveNumber =
          effectiveWhiteToMove
              ? baseMoveNumber + (i ~/ 2)
              : baseMoveNumber + ((i + 1) ~/ 2);

      if (isWhiteMove) {
        formatted.add('$moveNumber.');
      } else if (i == 0 && isThreatsMode && !effectiveWhiteToMove) {
        // Threats mode, black moves first: prefix with "N…" per standard
        // notation (e.g. 4…Nf6 5.Nf3).
        formatted.add('$moveNumber\u2026');
      }

      formatted.add(sanMoves[i]);
    }
    return formatted;
  }

  Future<void> _showPvMoveActionSheet(
    BuildContext context,
    String moveLabel,
    AnalysisLine line,
    int variantIndex,
    int moveIndex,
    ChessBoardScreenNotifierNew notifier,
    Color accentColor,
  ) async {
    final hostContext = context;
    final isThreatsMode = widget.state.isThreatsMode;
    final actions = <_NotationActionItem>[
      _NotationActionItem(
        icon: Icons.visibility_rounded,
        label: 'Preview from here',
        color: accentColor,
        onSelected: (_) async {
          notifier.previewPrincipalVariationMoveAt(
            line,
            variantIndex,
            moveIndex,
          );
        },
      ),
      _NotationActionItem(
        icon: Icons.playlist_add_check_circle_rounded,
        label: 'Insert entire line',
        color: kPrimaryColor,
        onSelected: (_) async {
          notifier.clearPvPreview();
          notifier.insertPvMoves(line);
        },
      ),
      _NotationActionItem(
        icon: isThreatsMode ? Icons.gps_off : Icons.gps_fixed,
        label: isThreatsMode ? 'Hide Threats' : 'Show Threats',
        color: Colors.red,
        onSelected: (_) async {
          notifier.toggleThreatsMode();
        },
      ),
    ];

    await _showNotationActionSheet(
      context: hostContext,
      title: moveLabel,
      subtitle: 'Engine line options',
      actions: actions,
    );
  }

  void _jumpToPage(int targetPage, {required bool animate}) {
    if (!mounted) return;
    if (_lastNonEmptyLines.isEmpty) return;
    final clampedTarget = targetPage.clamp(0, maxPageIndex);
    if (_pendingPageJump == clampedTarget &&
        _pendingPageJumpAnimated == animate) {
      return;
    }
    _pendingPageJump = clampedTarget;
    _pendingPageJumpAnimated = animate;

    void performJump() {
      if (!mounted) return;
      if (!_pageController.hasClients) {
        _pendingPageJump = null;
        return;
      }

      final current =
          _pageController.page?.round() ?? _pageController.initialPage;
      if (current == clampedTarget) {
        _pendingPageJump = null;
        return;
      }

      if (animate) {
        _pageController.animateToPage(
          clampedTarget,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        _pageController.jumpToPage(clampedTarget);
      }
      _pendingPageJump = null;
    }

    if (_pageController.hasClients) {
      performJump();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => performJump());
    }
  }

  void _scheduleVariantSelection(int index) {
    if (!mounted) return;
    if (_pendingVariantSelectionIndex == index) return;
    _pendingVariantSelectionIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final params = ChessBoardProviderParams(
        game: widget.game,
        index: widget.index,
      );
      // Preserve preview mode when switching variants during preview
      final shouldPreserve = widget.state.isPvPreviewActive;
      ref
          .read(chessBoardScreenProviderNew(params).notifier)
          .selectVariant(index, preservePreview: shouldPreserve);
      _pendingVariantSelectionIndex = null;
    });
  }

  int get maxPageIndex {
    final count = _lastNonEmptyLines.length;
    return count == 0 ? 0 : count - 1;
  }

  String _derivePositionKey(ChessBoardStateNew state) {
    // In preview mode, use the locked PV line's base position as the key
    // This ensures switching between PV cards doesn't trigger position change logic
    if (state.isPvPreviewActive && state.lockedPvLine != null) {
      // Use a stable key that represents "preview mode at base position"
      // This prevents the PV list from jumping pages when navigating within preview
      final basePos =
          state.isAnalysisMode ? state.analysisState.position : state.position;
      return 'preview:${state.lockedPvLine.hashCode}:${basePos?.fen ?? ''}';
    }

    final pos =
        state.isAnalysisMode ? state.analysisState.position : state.position;
    return pos?.fen ?? state.game.fen ?? '';
  }

  String _formatEvalLabel(AnalysisLine line) {
    if (line.isMate) {
      final mate = line.mate ?? 0;
      final absMate = mate.abs();
      final prefix = mate >= 0 ? '#+' : '#-';
      return '$prefix$absMate';
    }

    final eval = line.evaluation;
    if (eval == null) {
      return '--';
    }

    final formatted = eval.abs().toStringAsFixed(1);
    return eval >= 0 ? '+$formatted' : '-$formatted';
  }
}

class _PvToken {
  final String text;
  final int? moveIndex;

  const _PvToken({required this.text, this.moveIndex});
}

/// Blinking red dot indicator widget to show unseen moves
class _BlinkingRedDot extends StatefulWidget {
  final double size;

  const _BlinkingRedDot({this.size = 8.0});

  @override
  State<_BlinkingRedDot> createState() => _BlinkingRedDotState();
}

class _BlinkingRedDotState extends State<_BlinkingRedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: _animation.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: _animation.value * 0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShareGameScreen extends ConsumerWidget {
  final GamesTourModel game;
  final _ResolvedAppBarShareData shareData;

  const _ShareGameScreen({required this.game, required this.shareData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get board settings for creating the board widget
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);
    final boardSettingsNew =
        boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();

    // Get the base color scheme from settings
    final baseColorScheme = boardSettingsNew.colorScheme;

    // Build board settings for the share overlay board (sized responsively inside the overlay)
    // We use the theme colors but hide all highlights for clean screenshots
    // IMPORTANT: Disable animations for instant static frame capture in GIF generation
    final chessboardSettings = ChessboardSettings(
      enableCoordinates: false,
      animationDuration: Duration.zero, // Disable animations for screenshot/GIF
      colorScheme: ChessboardColorScheme(
        lightSquare: baseColorScheme.lightSquare,
        darkSquare: baseColorScheme.darkSquare,
        background: baseColorScheme.background,
        whiteCoordBackground: baseColorScheme.whiteCoordBackground,
        blackCoordBackground: baseColorScheme.blackCoordBackground,
        // Hide most highlights for clean screenshots, but show last move
        lastMove: baseColorScheme.lastMove,
        selected: HighlightDetails(
          solidColor: baseColorScheme.lightSquare.withValues(alpha: 0),
        ),
        validMoves: baseColorScheme.lightSquare.withValues(alpha: 0),
        validPremoves: baseColorScheme.lightSquare.withValues(alpha: 0),
      ),
      // Use piece set from settings
      pieceAssets: boardSettingsNew.pieceAssets,
      borderRadius: const BorderRadius.all(Radius.circular(0)),
      boxShadow: const [],
    );

    // Calculate clock times at current position (same logic as PlayerFirstRowDetailWidget)
    final effectiveMoveIndex = shareData.snapshot.currentMoveIndex;

    String? whiteTime;
    String? blackTime;

    if (shareData.snapshot.moveTimes.isNotEmpty) {
      // Find white player's most recent move up to current position
      for (int i = effectiveMoveIndex; i >= 0; i--) {
        final isWhiteMove = i % 2 == 0;
        if (isWhiteMove && i < shareData.snapshot.moveTimes.length) {
          whiteTime = shareData.snapshot.moveTimes[i];
          break;
        }
      }

      // Find black player's most recent move up to current position
      for (int i = effectiveMoveIndex; i >= 0; i--) {
        final isBlackMove = i % 2 == 1;
        if (isBlackMove && i < shareData.snapshot.moveTimes.length) {
          blackTime = shareData.snapshot.moveTimes[i];
          break;
        }
      }
    }

    // Fallback to game model's time display
    whiteTime ??= game.whiteTimeDisplay;
    blackTime ??= game.blackTimeDisplay;

    // Format tournament and round names for better display
    final tournamentName =
        game.tourSlug != null ? StringUtils.slugToTitle(game.tourSlug!) : null;
    final roundInfo =
        game.roundSlug != null
            ? StringUtils.formatRoundLabel(game.roundSlug)
            : null;

    return ShareGameCardOverlay(
      boardSettings: chessboardSettings,
      positionFen: shareData.snapshot.positionFen,
      lastMove: shareData.snapshot.lastMove,
      pgn: shareData.pgn,
      moveSans: shareData.snapshot.moveSans,
      moveTimes: shareData.snapshot.moveTimes,
      whitePlayerName: game.whitePlayer.name,
      blackPlayerName: game.blackPlayer.name,
      // Use countryCode first (inactive profile games often only populate this),
      // then fall back to federation for older payloads.
      whitePlayerCountry:
          game.whitePlayer.countryCode.isNotEmpty
              ? game.whitePlayer.countryCode
              : game.whitePlayer.federation,
      blackPlayerCountry:
          game.blackPlayer.countryCode.isNotEmpty
              ? game.blackPlayer.countryCode
              : game.blackPlayer.federation,
      whitePlayerElo:
          game.whitePlayer.rating > 0
              ? game.whitePlayer.rating.toString()
              : null,
      blackPlayerElo:
          game.blackPlayer.rating > 0
              ? game.blackPlayer.rating.toString()
              : null,
      whitePlayerTitle: game.whitePlayer.title,
      blackPlayerTitle: game.blackPlayer.title,
      whitePlayerClock: whiteTime,
      blackPlayerClock: blackTime,
      tournamentName: tournamentName,
      roundInfo: roundInfo,
      currentMoveIndex: shareData.snapshot.currentMoveIndex,
      evaluation: shareData.evaluation,
      mate: shareData.mate,
      isFlipped: shareData.isFlipped,
      gameStatus: game.gameStatus,
      isAtGameEnd: shareData.isAtGameEnd,
      shareUrl: shareData.shareUrl,
      gameId: game.gameId, // Pass game ID for correct eval display
      startingFen: shareData.snapshot.startingFen,
      onClose: () => Navigator.of(context).pop(),
    );
  }
}

const double _mainlineActionSheetInitialFraction = 0.45;
const double _variantActionSheetInitialFraction = 0.55;

class _TimeControlSnapshot {
  final Duration? base;
  final Duration increment;

  const _TimeControlSnapshot({required this.base, required this.increment});
}

class _NotationActionItem {
  final IconData icon;
  final String label;
  final Color color;
  final FutureOr<void> Function(BuildContext hostContext) onSelected;
  final bool triggersCommentEditor;

  const _NotationActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onSelected,
    this.triggersCommentEditor = false,
  });
}

Future<void> _showNotationActionSheet({
  required BuildContext context,
  required String title,
  String? subtitle,
  required List<_NotationActionItem> actions,
  _VariationCommentSheetConfig? commentConfig,
  String? timeSpentLabel,
  double initialSheetFraction = _mainlineActionSheetInitialFraction,
}) async {
  final hostContext = context;
  final route = ChessSheetRoutes.actionMenu(
    context: context,
    builder:
        (_) => _NotationActionSheet(
          title: title,
          subtitle: subtitle,
          actions: actions,
          hostContext: hostContext,
          commentConfig: commentConfig,
          timeSpentLabel: timeSpentLabel,
          initialSheetFraction: initialSheetFraction,
        ),
  );

  await Navigator.of(context).push(route);
}

class _VariationCommentSheetConfig {
  final String? initialValue;
  final FutureOr<void> Function(BuildContext context, String value) onSubmit;

  const _VariationCommentSheetConfig({
    this.initialValue,
    required this.onSubmit,
  });
}

class _NotationActionSheet extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final List<_NotationActionItem> actions;
  final BuildContext hostContext;
  final _VariationCommentSheetConfig? commentConfig;
  final String? timeSpentLabel;
  final double initialSheetFraction;

  const _NotationActionSheet({
    required this.title,
    this.subtitle,
    required this.actions,
    required this.hostContext,
    this.commentConfig,
    this.timeSpentLabel,
    required this.initialSheetFraction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clampedInitial = initialSheetFraction.clamp(0.25, 0.9).toDouble();
    final snapFractions = <double>{0.35, 0.75, clampedInitial}.toList()..sort();
    final snapGrid = SheetSnapGrid(
      snaps:
          snapFractions
              .map((value) => SheetOffset.proportionalToViewport(value))
              .toList(),
      minFlingSpeed: 850.0,
    );

    final navigator = Navigator(
      onGenerateInitialRoutes:
          (_, __) => [
            SpringPagedSheetRoute(
              scrollConfiguration: const SheetScrollConfiguration(),
              dragConfiguration: ChessSheetConfigs.actionMenu,
              initialOffset: SheetOffset.proportionalToViewport(clampedInitial),
              snapGrid: snapGrid,
              builder:
                  (context) => _NotationActionListPage(
                    title: title,
                    subtitle: subtitle,
                    actions: actions,
                    commentConfig: commentConfig,
                    hostContext: hostContext,
                    timeSpentLabel: timeSpentLabel,
                  ),
            ),
          ],
    );

    return SheetKeyboardDismissible(
      dismissBehavior: const DragDownSheetKeyboardDismissBehavior(
        isContentScrollAware: true,
      ),
      child: PagedSheet(
        decoration: ChessSheetDecoration.dark(
          context,
          alpha: 0.97,
          borderRadius: 28.sp,
        ),
        shrinkChildToAvoidDynamicOverlap: true,
        navigator: navigator,
      ),
    );
  }
}

class _NotationActionListPage extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final List<_NotationActionItem> actions;
  final _VariationCommentSheetConfig? commentConfig;
  final BuildContext hostContext;
  final String? timeSpentLabel;

  const _NotationActionListPage({
    required this.title,
    required this.actions,
    required this.hostContext,
    this.subtitle,
    this.commentConfig,
    this.timeSpentLabel,
  });

  Future<void> _handleActionTap(
    BuildContext context,
    _NotationActionItem action,
  ) async {
    HapticFeedback.selectionClick();

    if (action.triggersCommentEditor && commentConfig != null) {
      await Navigator.of(context).push(
        SpringPagedSheetRoute(
          scrollConfiguration: const SheetScrollConfiguration(),
          dragConfiguration: ChessSheetConfigs.commentEditor,
          initialOffset: const SheetOffset.proportionalToViewport(0.8),
          snapGrid: ChessSheetConfigs.commentEditorSnaps(minFlingSpeed: 650.0),
          builder:
              (context) => _NotationCommentPage(
                config: commentConfig!,
                hostContext: hostContext,
              ),
        ),
      );
      return;
    }

    Navigator.of(hostContext).pop();
    await Future.sync(() => action.onSelected(hostContext));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    // When keyboard is visible, add its height to bottom padding so sheet rides with keyboard
    final bottomPadding =
        viewInsets.bottom > 0
            ? viewInsets.bottom + 12.sp
            : math.max(20.sp, safeBottom + 8.sp);

    return Padding(
      padding: EdgeInsets.fromLTRB(20.sp, 12.sp, 20.sp, bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.textLgBold.copyWith(
                        color: context.colors.textPrimary,
                        letterSpacing: 0.25,
                      ),
                    ),
                    if (subtitle != null) ...[
                      SizedBox(height: 4.h),
                      Text(
                        subtitle!,
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textPrimaryMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (timeSpentLabel != null) ...[
                SizedBox(width: 12.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Time spent',
                      style: AppTypography.textXsMedium.copyWith(
                        color: context.colors.textPrimaryMuted,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      timeSpentLabel!,
                      style: AppTypography.textSmMedium.copyWith(
                        color: context.colors.textPrimary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (actions.isNotEmpty) ...[
            SizedBox(height: 12.h),
            for (var i = 0; i < actions.length; i++) ...[
              _NotationActionTile(
                action: actions[i],
                onTap: () => _handleActionTap(context, actions[i]),
              ),
              if (i != actions.length - 1) SizedBox(height: 8.h),
            ],
          ],
        ],
      ),
    );
  }
}

class _NotationActionTile extends StatefulWidget {
  final _NotationActionItem action;
  final VoidCallback onTap;

  const _NotationActionTile({required this.action, required this.onTap});

  @override
  State<_NotationActionTile> createState() => _NotationActionTileState();
}

class _NotationActionTileState extends State<_NotationActionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    // Use spring curve for natural bouncy feel
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: ChessSheetCurves.bouncy),
    );

    _glowAnimation = Tween<double>(
      begin: 0.02,
      end: 0.08,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14.sp),
              onTapDown: _onTapDown,
              onTapUp: _onTapUp,
              onTapCancel: _onTapCancel,
              onTap: widget.onTap,
              splashColor: widget.action.color.withValues(alpha: 0.1),
              highlightColor: widget.action.color.withValues(alpha: 0.05),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 12.sp,
                  vertical: 14.sp,
                ),
                decoration: BoxDecoration(
                  color: context.colors.textPrimary.withValues(
                    alpha: _glowAnimation.value,
                  ),
                  borderRadius: BorderRadius.circular(14.sp),
                  border: Border.all(
                    color: context.colors.textPrimary.withValues(
                      alpha: 0.05 + (_controller.value * 0.05),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: widget.action.color.withValues(
                          alpha: 0.15 + (_controller.value * 0.05),
                        ),
                        borderRadius: BorderRadius.circular(10.sp),
                      ),
                      padding: EdgeInsets.all(8.sp),
                      child: Icon(
                        widget.action.icon,
                        color: widget.action.color,
                        size: 18.ic,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(
                        widget.action.label,
                        style: AppTypography.textMdMedium.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      widget.action.triggersCommentEditor
                          ? Icons.drive_file_rename_outline
                          : Icons.arrow_forward_ios_rounded,
                      color: context.colors.textPrimary.withValues(alpha: 0.35),
                      size: 14.ic,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NotationCommentPage extends ConsumerStatefulWidget {
  final _VariationCommentSheetConfig config;
  final BuildContext hostContext;

  const _NotationCommentPage({required this.config, required this.hostContext});

  @override
  ConsumerState<_NotationCommentPage> createState() =>
      _NotationCommentPageState();
}

class _NotationCommentPageState extends ConsumerState<_NotationCommentPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isSaving = false;
  bool _hasEdited = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.config.initialValue ?? '')
      ..addListener(_onChanged);

    _focusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    final baseValue = widget.config.initialValue ?? '';
    final edited = _controller.text != baseValue;
    if (edited != _hasEdited) {
      setState(() => _hasEdited = edited);
    }
  }

  Future<void> _handleSave() async {
    if (_isSaving || !_hasEdited) return;
    setState(() => _isSaving = true);
    try {
      await Future.sync(
        () => widget.config.onSubmit(widget.hostContext, _controller.text),
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
    } catch (error, stackTrace) {
      setState(() => _isSaving = false);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('Saving notation comment'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    // When keyboard appears, push content up so TextField stays visible above keyboard
    // Extra padding ensures buttons are well above keyboard on all devices
    final bottomPadding =
        viewInsets.bottom > 0
            ? viewInsets.bottom + 52.sp
            : math.max(20.sp, safeBottom + 8.sp);

    return Padding(
      padding: EdgeInsets.fromLTRB(20.sp, 16.sp, 20.sp, bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with back button and title
          Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: context.colors.textPrimary,
                  size: 18.ic,
                ),
                onPressed: () {
                  // Try to pop from current navigator first (for paged sheets)
                  // If that fails, pop from root navigator (for direct sheets)
                  if (!Navigator.of(context).canPop()) {
                    Navigator.of(context, rootNavigator: true).pop();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
                splashRadius: 20.sp,
              ),
              SizedBox(width: 4.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Variant comment',
                      style: AppTypography.textLgBold.copyWith(
                        color: context.colors.textPrimary,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Leave a note for this branch.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textPrimaryMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Divider(color: context.colors.textPrimary.withValues(alpha: 0.08)),
          SizedBox(height: 12.h),

          // Text field - flexible height but not taking all space
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: 120.h, maxHeight: 280.h),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: null,
              minLines: 4,
              maxLength: _variationCommentMaxChars,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary,
              ),
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                filled: true,
                fillColor: context.colors.surface.withValues(alpha: 0.6),
                hintText: 'Add a quick thought…',
                hintStyle: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textPrimaryMuted,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.sp),
                  borderSide: BorderSide(
                    color: context.colors.textPrimary.withValues(alpha: 0.1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.sp),
                  borderSide: BorderSide(
                    color: kPrimaryColor.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 12.h),

          // Action buttons
          Row(
            children: [
              // Clear button - clears the text field
              TextButton(
                onPressed:
                    _controller.text.isEmpty
                        ? null
                        : () {
                          HapticFeedback.selectionClick();
                          _controller.clear();
                        },
                child: const Text('Clear'),
              ),
              const Spacer(),
              // Delete button - directly removes the comment (only shown if there's an existing comment)
              if (widget.config.initialValue != null &&
                  widget.config.initialValue!.trim().isNotEmpty) ...[
                IconButton(
                  onPressed:
                      _isSaving
                          ? null
                          : () async {
                            HapticFeedback.mediumImpact();
                            setState(() => _isSaving = true);
                            try {
                              // Submit empty string to remove the comment
                              await Future.sync(
                                () => widget.config.onSubmit(
                                  widget.hostContext,
                                  '',
                                ),
                              );
                              if (!mounted) return;
                              Navigator.of(context, rootNavigator: true).pop();
                            } catch (error, stackTrace) {
                              setState(() => _isSaving = false);
                              FlutterError.reportError(
                                FlutterErrorDetails(
                                  exception: error,
                                  stack: stackTrace,
                                  context: ErrorDescription(
                                    'Removing notation comment',
                                  ),
                                ),
                              );
                            }
                          },
                  icon: Icon(
                    Icons.delete_outline,
                    color: kRedColor.withValues(alpha: 0.8),
                  ),
                  tooltip: 'Remove comment',
                ),
                SizedBox(width: 8.w),
              ],
              FilledButton(
                onPressed: _isSaving || !_hasEdited ? null : _handleSave,
                style: FilledButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  foregroundColor: context.colors.textPrimary,
                  padding: EdgeInsets.symmetric(
                    horizontal: 18.w,
                    vertical: 10.h,
                  ),
                ),
                child:
                    _isSaving
                        ? SizedBox(
                          height: 14.h,
                          width: 14.h,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.colors.textPrimary,
                          ),
                        )
                        : const Text('Save comment'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// DEPRECATED: Old dialog-based comment approach replaced with smooth bottom sheet
// Keeping for reference - can be removed in future cleanup
/*
class _CommentDialog extends ConsumerStatefulWidget {
  final String initialComment;
  final ValueChanged<String> onSave;
  final FocusNode focusNode;

  const _CommentDialog({
    required this.initialComment,
    required this.onSave,
    required this.focusNode,
  });

  @override
  ConsumerState<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends ConsumerState<_CommentDialog>
    with SingleTickerProviderStateMixin {
  late TextEditingController _controller;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialComment);
    _controller.addListener(_onTextChanged);

    // Setup entrance animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const SnappySpringCurve(),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    // Start animation and focus field
    _animationController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.focusNode.requestFocus();
    });
  }

  void _onTextChanged() {
    final hasChanges = _controller.text != widget.initialComment;
    if (_hasChanges != hasChanges) {
      setState(() {
        _hasChanges = hasChanges;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }

    HapticFeedback.mediumImpact();
    await _animationController.reverse();
    if (!mounted) return;

    widget.onSave(_controller.text);
    Navigator.of(context).pop();
  }

  Future<void> _handleCancel() async {
    HapticFeedback.lightImpact();
    await _animationController.reverse();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Get platform-specific keyboard height default
    final keyboardTotalHeight = ref.watch(keyboardTotalHeightProvider);

    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      removeTop: true,
      child: GestureDetector(
        onTap: _handleCancel,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            FadeTransition(
              opacity: _fadeAnimation,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(color: Colors.black.withValues(alpha: 0.6)),
              ),
            ),
            Positioned.fill(
            child: KeyboardAnimationBuilder(
              focusNode: _focusNode,
              keyboardTotalHeight: keyboardTotalHeight,
              interpolateLastPart: Platform.isIOS,
              interpolationConfig: InterpolationConfig.fidelity,
              warmUpFrame: true,
              onChange: (height) {
                if (height > 0) {
                  ref
                      .read(keyboardTotalHeightProvider.notifier)
                      .update(height);
                }
              },
                builder: (context, keyboardHeight) {
                final safePadding = MediaQuery.paddingOf(context);
                final screenSize = MediaQuery.sizeOf(context);
                final effectiveKeyboardHeight =
                    keyboardHeight.clamp(0.0, keyboardTotalHeight);

                // Calculate lift to center in available space
                // Available space center is (screenHeight - keyboardHeight) / 2
                // Current center is screenHeight / 2
                // Lift = Current - Available = keyboardHeight / 2
                final double liftDistance = effectiveKeyboardHeight / 2;

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    20.sp,
                    safePadding.top + 24.h,
                    20.sp,
                    safePadding.bottom + 24.h,
                  ),
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth:
                            math.min(520.w, screenSize.width - 32.w),
                        maxHeight: screenSize.height * 0.65,
                      ),
                      child: GestureDetector(
                        onTap: () {},
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          alignment: Alignment.center,
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: Transform.translate(
                              offset: Offset(0, -liftDistance),
                              child: _buildCommentDialogCard(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentDialogCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(24.sp),
        border: Border.all(
          color: kPrimaryColor.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 40,
            offset: const Offset(0, -10),
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: EdgeInsets.only(top: 12.sp, bottom: 8.sp),
              width: 36.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2.sp),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.sp, 8.sp, 20.sp, 12.sp),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.sp),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12.sp),
                  ),
                  child: Icon(
                    Icons.comment_outlined,
                    color: kPrimaryColor,
                    size: 20.sp,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Comment',
                        style: AppTypography.textLgBold.copyWith(
                          color: context.colors.textPrimary,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Text(
                        'Share your thoughts on this position',
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.textPrimary.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            margin: EdgeInsets.symmetric(horizontal: 20.sp),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  context.colors.textPrimary.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20.sp),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: AppTypography.textMdRegular.copyWith(
                  color: context.colors.textPrimary,
                  height: 1.5,
                ),
                maxLines: null,
                minLines: 3,
                maxLength: _variationCommentMaxChars,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'What do you think about this position?',
                  hintStyle: AppTypography.textMdRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.4),
                  ),
                  filled: true,
                  fillColor: context.colors.textPrimary.withValues(alpha: 0.03),
                  contentPadding: EdgeInsets.all(16.sp),
                  counterStyle: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.sp),
                    borderSide: BorderSide(
                      color: context.colors.textPrimary.withValues(alpha: 0.1),
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.sp),
                    borderSide: BorderSide(
                      color: kPrimaryColor.withValues(alpha: 0.6),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              20.sp,
              12.sp,
              20.sp,
              20.sp + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: context.colors.textPrimary.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                if (_controller.text.isNotEmpty)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        _controller.clear();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: context.colors.textPrimary.withValues(alpha: 0.7),
                        padding: EdgeInsets.symmetric(vertical: 14.sp),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.sp),
                        ),
                      ),
                      icon: Icon(Icons.clear, size: 18.sp),
                      label: Text(
                        'Clear',
                        style: AppTypography.textSmMedium,
                      ),
                    ),
                  ),
                if (_controller.text.isNotEmpty) SizedBox(width: 12.w),
                Expanded(
                  child: TextButton(
                    onPressed: _handleCancel,
                    style: TextButton.styleFrom(
                      foregroundColor: context.colors.textPrimary.withValues(alpha: 0.8),
                      padding: EdgeInsets.symmetric(vertical: 14.sp),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.sp),
                        side: BorderSide(
                          color: context.colors.textPrimary.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: AppTypography.textSmMedium,
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _handleSave,
                    style: FilledButton.styleFrom(
                      backgroundColor: _hasChanges
                          ? kPrimaryColor
                          : context.colors.textPrimary.withValues(alpha: 0.1),
                      foregroundColor: _hasChanges
                          ? context.colors.textPrimary
                          : context.colors.textPrimary.withValues(alpha: 0.4),
                      padding: EdgeInsets.symmetric(vertical: 14.sp),
                      elevation: _hasChanges ? 4 : 0,
                      shadowColor: _hasChanges
                          ? kPrimaryColor.withValues(alpha: 0.5)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.sp),
                      ),
                    ),
                    icon: Icon(Icons.check_circle_outline, size: 20.sp),
                    label: Text(
                      _hasChanges ? 'Save Comment' : 'No Changes',
                      style: AppTypography.textSmBold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
*/
// End of deprecated _CommentDialog class

/// Provider to fetch tour info by tour ID or name - used by the event info sheet
final _tourInfoByIdProvider = FutureProvider.autoDispose.family<
  AboutTourModel?,
  String
>((ref, tourId) async {
  if (tourId.isEmpty) return null;

  final repo = ref.read(tourRepositoryProvider);

  try {
    // 1. Try fetching by UUID first (exact match)
    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );

    if (uuidPattern.hasMatch(tourId.trim())) {
      final tours = await repo.getToursByIds([tourId.trim()]);
      if (tours.isNotEmpty) {
        return AboutTourModel.fromTour(tours.first);
      }
    }

    // 2. Fallback: Try searching by name if it's not a UUID or not found by UUID
    // This handles legacy games or games from Gamebase where we only have the name.
    final searchResults = await repo.searchTours(
      query: tourId.trim(),
      limit: 1,
    );
    if (searchResults.isNotEmpty) {
      // Verify it's a reasonably close match (simple containment check)
      final bestMatch = searchResults.first;
      final normalizedQuery = tourId.trim().toLowerCase();
      final normalizedMatch = bestMatch.name.toLowerCase();

      if (normalizedMatch.contains(normalizedQuery) ||
          normalizedQuery.contains(normalizedMatch)) {
        return AboutTourModel.fromTour(bestMatch);
      }
    }
  } catch (e) {
    debugPrint('Failed to fetch tour info for $tourId: $e');
  }
  return null;
});

/// Event info sheet - displays tournament/event details
class _EventInfoSheet extends ConsumerWidget {
  final GamesTourModel game;
  final String? pgn;

  const _EventInfoSheet({required this.game, this.pgn});

  /// Parse headers from PGN
  Map<String, String> _parseHeadersFromPgn() {
    final pgnString = pgn ?? game.pgn;
    if (pgnString == null || pgnString.isEmpty) {
      return {};
    }

    try {
      final pgnGame = PgnGame.parsePgn(pgnString);
      return pgnGame.headers;
    } catch (e) {
      // Fallback to regex parsing if dartchess fails
      final headers = <String, String>{};
      final matches = RegExp(r'\[(\w+)\s+"([^"]+)"\]').allMatches(pgnString);
      for (final match in matches) {
        headers[match.group(1)!] = match.group(2)!;
      }
      return headers;
    }
  }

  /// Navigate to the tournament detail screen
  Future<void> _navigateToTournament(
    BuildContext context,
    WidgetRef ref,
    AboutTourModel aboutModel,
  ) async {
    final navigator = Navigator.of(context);

    final targetId =
        aboutModel.groupBroadcastId?.isNotEmpty == true
            ? aboutModel.groupBroadcastId!
            : (aboutModel.id.isNotEmpty ? aboutModel.id : game.tourId);

    if (targetId.isEmpty) {
      return;
    }

    GroupBroadcast groupBroadcast;
    try {
      groupBroadcast = await ref
          .read(groupBroadcastRepositoryProvider)
          .getGroupBroadcastById(targetId);
    } catch (e) {
      debugPrint('Failed to fetch group broadcast for $targetId: $e');
      groupBroadcast = GroupBroadcast(
        id: targetId,
        createdAt: DateTime.now(),
        name: aboutModel.name,
        search: [aboutModel.name],
        timeControl:
            aboutModel.timeControl.isNotEmpty ? aboutModel.timeControl : null,
        maxAvgElo: null,
        dateStart: null,
        dateEnd: null,
      );
    }

    if (!context.mounted) return;

    ref.read(selectedBroadcastModelProvider.notifier).state = groupBroadcast;

    navigator.pop(); // Close the sheet
    if (ref.read(selectedBroadcastModelProvider) != null) {
      navigator.pushNamed('/tournament_detail_screen');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // First try tourDetailScreenProvider (works when navigating from tour detail)
    final tourDetail = ref.watch(tourDetailScreenProvider);
    final tourDetailAboutModel = tourDetail.valueOrNull?.aboutTourModel;

    // If tourDetailScreenProvider doesn't have data, fetch independently by tourId
    final tourInfoAsync = ref.watch(_tourInfoByIdProvider(game.tourId));

    // Use tourDetailAboutModel only if it matches the current game's tourId
    final matchesCachedTour =
        tourDetailAboutModel?.id.isNotEmpty == true &&
        tourDetailAboutModel?.id == game.tourId;
    final aboutModel =
        matchesCachedTour ? tourDetailAboutModel : tourInfoAsync.valueOrNull;

    // Check if we're still loading
    final isLoading = !matchesCachedTour && tourInfoAsync.isLoading;

    final locationService = ref.read(locationServiceProvider);
    final urlLauncher = ref.read(urlLauncherProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder:
          (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16.sp)),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  width: 40.sp,
                  height: 4.sp,
                  margin: EdgeInsets.symmetric(vertical: 12.sp),
                  decoration: BoxDecoration(
                    color: context.colors.textPrimary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2.sp),
                  ),
                ),
                // Content
                Expanded(
                  child:
                      isLoading
                          ? Center(
                            child: CircularProgressIndicator(
                              color: kPrimaryColor,
                              strokeWidth: 2,
                            ),
                          )
                          : aboutModel == null
                          ? _buildFallbackContent(
                            context,
                            scrollController,
                            locationService,
                          )
                          : _buildTourContent(
                            context,
                            ref,
                            scrollController,
                            aboutModel,
                            locationService,
                            urlLauncher,
                          ),
                ),
              ],
            ),
          ),
    );
  }

  /// Fallback content when tour info is not available - shows game info from GamesTourModel
  Widget _buildFallbackContent(
    BuildContext context,
    ScrollController scrollController,
    LocationService locationService,
  ) {
    final headers = _parseHeadersFromPgn();

    // Determine event name. In TWIC player-profile routes, raw PGN Event can
    // be a per-round/pairing label; prefer the canonical event from the game
    // list when that happens.
    final pgnEvent = headers['Event'];
    final eventName = preferredTwicEventTitle(
      pgnEvent: pgnEvent,
      tourSlug: game.tourSlug,
      tourId: game.tourId,
      site: headers['Site'],
      fallback: 'Game Info',
    );

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.symmetric(horizontal: 20.sp),
      children: [
        // Game header
        Text(
          eventName,
          style: AppTypography.textLgBold.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
        SizedBox(height: 16.h),
        // Round info
        _EventInfoRow(
          icon: Icons.format_list_numbered_rounded,
          label: 'Round',
          value:
              game.roundSlug != null
                  ? StringUtils.formatRoundLabel(game.roundSlug)
                  : (headers['Round'] ?? game.roundDisplayName),
        ),
        SizedBox(height: 12.h),
        // Board number
        if (game.boardNr != null || headers['Board'] != null) ...[
          _EventInfoRow(
            icon: Icons.grid_on_rounded,
            label: 'Board',
            value:
                game.boardNr != null
                    ? 'Board ${game.boardNr}'
                    : 'Board ${headers['Board']}',
          ),
          SizedBox(height: 12.h),
        ],
        // Opening info from PGN
        ..._buildOpeningInfoRows(headers),

        // Date info
        if (headers['Date'] != null &&
            headers['Date'] != '????.??.??' &&
            headers['Date'] != '?') ...[
          _EventInfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Date',
            value: headers['Date']!,
          ),
          SizedBox(height: 12.h),
        ],

        // Location info
        if (headers['Site'] != null && headers['Site'] != '?') ...[
          _buildLocationRow(headers['Site']!, locationService),
          SizedBox(height: 12.h),
        ],

        // Time control info
        if (game.timeControl != null ||
            (headers['TimeControl'] != null &&
                headers['TimeControl'] != '?')) ...[
          _EventInfoRow(
            icon: Icons.access_time_rounded,
            label: 'Time Control',
            value: StringUtils.capitalizeWords(
              headers['TimeControl'] ?? game.timeControl!,
            ),
          ),
          SizedBox(height: 12.h),
        ],

        // Players section
        SizedBox(height: 8.h),
        Text(
          'Players',
          style: AppTypography.textSmMedium.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.6),
          ),
        ),
        SizedBox(height: 12.h),
        // White player
        _buildPlayerRow(context, game.whitePlayer, 'White', locationService),
        SizedBox(height: 8.h),
        // Black player
        _buildPlayerRow(context, game.blackPlayer, 'Black', locationService),
        SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16.h),
      ],
    );
  }

  /// Build opening info rows if available in PGN
  List<Widget> _buildOpeningInfoRows([Map<String, String>? headers]) {
    final effectiveHeaders = headers ?? _parseHeadersFromPgn();
    final eco = effectiveHeaders['ECO'];
    final opening = effectiveHeaders['Opening'];

    final List<Widget> rows = [];

    if (eco != null || opening != null) {
      // Combine ECO and Opening name
      String openingDisplay = '';
      if (eco != null && opening != null) {
        openingDisplay = '$eco: $opening';
      } else if (opening != null) {
        openingDisplay = opening;
      } else if (eco != null) {
        openingDisplay = eco;
      }

      if (openingDisplay.isNotEmpty) {
        rows.add(
          _EventInfoRow(
            icon: Icons.menu_book_rounded,
            label: 'Opening',
            value: openingDisplay,
          ),
        );
        rows.add(SizedBox(height: 12.h));
      }
    }

    return rows;
  }

  Widget _buildPlayerRow(
    BuildContext context,
    PlayerCard player,
    String side,
    LocationService locationService,
  ) {
    // Use the same validation as PlayerFirstRowDetailWidget
    final validCountryCode = locationService.getValidCountryCode(
      player.countryCode,
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
      decoration: BoxDecoration(
        color: context.colors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8.sp),
      ),
      child: Row(
        children: [
          // Side indicator
          Container(
            width: 8.sp,
            height: 8.sp,
            decoration: BoxDecoration(
              color:
                  side == 'White'
                      ? context.colors.textPrimary
                      : context.colors.surface,
              border: Border.all(
                color: context.colors.textPrimary.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(2.sp),
            ),
          ),
          SizedBox(width: 10.w),
          // Country flag - handle FID (FIDE) specially like PlayerFirstRowDetailWidget
          if (player.countryCode.toUpperCase() == 'FID') ...[
            Image.asset(
              PngAsset.fideLogo,
              height: 14.h,
              width: 20.w,
              fit: BoxFit.cover,
              cacheWidth: 48,
              cacheHeight: 36,
            ),
            SizedBox(width: 8.w),
          ] else if (validCountryCode.isNotEmpty) ...[
            CountryFlag.fromCountryCode(
              validCountryCode,
              theme: ImageTheme(width: 20.w, height: 14.h),
            ),
            SizedBox(width: 8.w),
          ],
          // Title
          if (player.title.isNotEmpty) ...[
            Text(
              player.title,
              style: AppTypography.textSmMedium.copyWith(color: kPrimaryColor),
            ),
            SizedBox(width: 6.w),
          ],
          // Name
          Expanded(
            child: Text(
              player.name,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Rating
          Text(
            player.displayRating,
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTourContent(
    BuildContext context,
    WidgetRef ref,
    ScrollController scrollController,
    AboutTourModel aboutModel,
    dynamic locationService,
    dynamic urlLauncher,
  ) {
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.symmetric(horizontal: 20.sp),
      children: [
        // Event image
        if (aboutModel.imageUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12.sp),
            child: SizedBox(
              height: 140.h,
              width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: aboutModel.imageUrl,
                fit: BoxFit.cover,
                memCacheWidth:
                    (MediaQuery.sizeOf(context).width *
                            MediaQuery.devicePixelRatioOf(context))
                        .toInt(),
                alignment: Alignment.topCenter,
                placeholder:
                    (_, __) => Container(
                      color: context.colors.surface,
                      child: Center(
                        child: Icon(
                          Icons.image,
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.3,
                          ),
                          size: 40.sp,
                        ),
                      ),
                    ),
                errorWidget: (_, __, ___) => const LogoPatternFallback(),
              ),
            ),
          ),
        SizedBox(height: 16.h),
        // Event name - clickable to navigate to tournament
        GestureDetector(
          onTap: () => _navigateToTournament(context, ref, aboutModel),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  aboutModel.name,
                  style: AppTypography.textLgBold.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.colors.textPrimary.withValues(alpha: 0.5),
                size: 20.sp,
              ),
            ],
          ),
        ),
        SizedBox(height: 12.h),
        // Round info from game
        _EventInfoRow(
          icon: Icons.format_list_numbered_rounded,
          label: 'Round',
          value:
              game.roundSlug != null
                  ? StringUtils.formatRoundLabel(game.roundSlug)
                  : game.roundDisplayName,
        ),
        SizedBox(height: 12.h),
        // Board number
        if (game.boardNr != null) ...[
          _EventInfoRow(
            icon: Icons.grid_on_rounded,
            label: 'Board',
            value: 'Board ${game.boardNr}',
          ),
          SizedBox(height: 12.h),
        ],
        // Opening info from PGN
        ..._buildOpeningInfoRows(),
        // Description
        if (aboutModel.description.isNotEmpty) ...[
          Text(
            aboutModel.description,
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.7),
            ),
          ),
          SizedBox(height: 16.h),
        ],
        // Info rows
        if (aboutModel.timeControl.isNotEmpty) ...[
          _EventInfoRow(
            icon: Icons.access_time_rounded,
            label: 'Time Control',
            value: StringUtils.capitalizeWords(aboutModel.timeControl),
          ),
          SizedBox(height: 12.h),
        ],
        if (aboutModel.date.isNotEmpty) ...[
          _EventInfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Date',
            value: aboutModel.date,
          ),
          SizedBox(height: 12.h),
        ],
        if (aboutModel.location.isNotEmpty)
          _buildLocationRow(aboutModel.location, locationService),
        // Players section with game players highlighted
        SizedBox(height: 16.h),
        Text(
          'Players',
          style: AppTypography.textSmMedium.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.6),
          ),
        ),
        SizedBox(height: 8.h),
        // White player
        _buildPlayerRow(context, game.whitePlayer, 'White', locationService),
        SizedBox(height: 8.h),
        // Black player
        _buildPlayerRow(context, game.blackPlayer, 'Black', locationService),
        // Top players from tournament
        if (aboutModel.players.isNotEmpty) ...[
          SizedBox(height: 16.h),
          Text(
            'Top Players in Event',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.6),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            aboutModel.players
                .where((p) => p.rating != null)
                .take(4)
                .map((p) => p.displayName)
                .join(', '),
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
        ],
        // Website button
        if (aboutModel.websiteUrl.isNotEmpty) ...[
          SizedBox(height: 20.h),
          GestureDetector(
            onTap: () => urlLauncher.launchCustomUrl(aboutModel.websiteUrl),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8.sp),
                border: Border.all(color: kPrimaryColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.language_rounded,
                    color: kPrimaryColor,
                    size: 18.sp,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    aboutModel.extractDomain(),
                    style: AppTypography.textSmMedium.copyWith(
                      color: kPrimaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16.h),
      ],
    );
  }

  Widget? _buildCountryFlag(String countryCode) {
    if (countryCode.isEmpty) return null;
    return CountryFlag.fromCountryCode(
      countryCode,
      theme: ImageTheme(width: 20.w, height: 14.h),
    );
  }

  // Online events have `location` set to a platform host (Chess.com,
  // lichess.org, tcec-chess.com, ...) rather than a city. Render those with
  // a globe icon and an "Online" label so the row stops looking like a
  // broken hyperlink with no flag.
  Widget _buildLocationRow(String location, LocationService locationService) {
    if (locationService.isOnlinePlatform(location)) {
      return _EventInfoRow(
        icon: Icons.language_rounded,
        label: 'Online',
        value: locationService.prettifyPlatformName(location),
      );
    }
    return _EventInfoRow(
      icon: Icons.location_on_rounded,
      label: 'Location',
      value: location,
      trailing: _buildCountryFlag(locationService.getCountryCode(location)),
    );
  }
}

class _EventInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  const _EventInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: context.colors.textPrimary.withValues(alpha: 0.5),
          size: 18.sp,
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textPrimary.withValues(alpha: 0.5),
                ),
              ),
              SizedBox(height: 2.h),
              Row(
                children: [
                  if (trailing != null) ...[trailing!, SizedBox(width: 6.w)],
                  Expanded(
                    child: Text(
                      value,
                      style: AppTypography.textSmMedium.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// NAG picker — manual annotation entry. The user long-presses a move chip,
// taps "Annotate", then sees this sheet. Three groups (quality / evaluation /
// observation), one slot per group; tap to toggle. State changes propagate
// live through the chess board provider so the move list and on-board badge
// update instantly without closing the sheet.
// ===========================================================================

class _NagPickerSheet extends ConsumerWidget {
  static const List<int> _qualityNags = [3, 1, 5, 6, 2, 4, 7];
  static const List<int> _evaluationNags = [
    14,
    15,
    16,
    17,
    18,
    19,
    10,
    13,
    22,
    44,
  ];
  static const List<int> _observationNags = [146, 140, 36, 40, 132, 32, 138];

  final String moveText;
  final ChessBoardProviderParams params;
  final String pointerId;

  const _NagPickerSheet({
    required this.moveText,
    required this.params,
    required this.pointerId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(chessBoardScreenProviderNew(params));
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    final activeNags =
        stateAsync.valueOrNull?.moveNags[pointerId] ?? const <int>[];
    final activeSet = activeNags.toSet();

    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.sp)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: context.colors.surface.withValues(alpha: 0.92),
            padding: EdgeInsets.fromLTRB(20.sp, 8.sp, 20.sp, 18.sp),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36.sp,
                    height: 4.sp,
                    margin: EdgeInsets.only(bottom: 14.sp),
                    decoration: BoxDecoration(
                      color: context.colors.textPrimary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.label_important_outline_rounded,
                      size: 16.sp,
                      color: const Color(0xFF22AC38),
                    ),
                    SizedBox(width: 6.sp),
                    Text(
                      'Annotate',
                      style: AppTypography.textSmMedium.copyWith(
                        color: context.colors.textPrimary.withValues(
                          alpha: 0.55,
                        ),
                        letterSpacing: 1.2,
                        fontSize: 11.sp,
                      ),
                    ),
                    SizedBox(width: 8.sp),
                    Expanded(
                      child: Text(
                        moveText,
                        style: AppTypography.textMdBold.copyWith(
                          color: context.colors.textPrimary,
                          fontSize: 16.sp,
                          letterSpacing: -0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (activeNags.isNotEmpty)
                      _NagPickerClearButton(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          notifier.clearMoveNags(pointerId);
                        },
                      ),
                    SizedBox(width: 6.sp),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Done',
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).pop();
                      },
                      icon: Icon(
                        Icons.check_rounded,
                        size: 18.sp,
                        color: context.colors.textPrimary.withValues(
                          alpha: 0.82,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14.sp),
                _NagGroup(
                  label: 'Quality',
                  hint: 'How good was the move?',
                  nags: _qualityNags,
                  activeSet: activeSet,
                  onTap: (nag) {
                    HapticFeedback.selectionClick();
                    notifier.toggleMoveNag(pointerId: pointerId, nag: nag);
                  },
                ),
                SizedBox(height: 14.sp),
                _NagGroup(
                  label: 'Position assessment',
                  hint: 'Who stands better?',
                  nags: _evaluationNags,
                  activeSet: activeSet,
                  onTap: (nag) {
                    HapticFeedback.selectionClick();
                    notifier.toggleMoveNag(pointerId: pointerId, nag: nag);
                  },
                ),
                SizedBox(height: 14.sp),
                _NagGroup(
                  label: 'Observation',
                  hint: 'Theme of the move',
                  nags: _observationNags,
                  activeSet: activeSet,
                  onTap: (nag) {
                    HapticFeedback.selectionClick();
                    notifier.toggleMoveNag(pointerId: pointerId, nag: nag);
                  },
                ),
                SizedBox(height: 18.sp),
                Center(
                  child: Text(
                    'One glyph per category. Tap a glyph again to remove it.',
                    style: AppTypography.textXsRegular.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.4),
                      fontSize: 10.5.sp,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NagPickerClearButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NagPickerClearButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 9.sp, vertical: 5.sp),
        decoration: BoxDecoration(
          color: context.colors.textPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.close_rounded,
              size: 12.sp,
              color: context.colors.textPrimary.withValues(alpha: 0.7),
            ),
            SizedBox(width: 3.sp),
            Text(
              'Clear',
              style: AppTypography.textXsMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.7),
                fontSize: 11.sp,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NagGroup extends StatelessWidget {
  final String label;
  final String hint;
  final List<int> nags;
  final Set<int> activeSet;
  final void Function(int nag) onTap;

  const _NagGroup({
    required this.label,
    required this.hint,
    required this.nags,
    required this.activeSet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 2.sp, bottom: 8.sp),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTypography.textXsMedium.copyWith(
                  color: context.colors.textPrimary.withValues(alpha: 0.55),
                  fontSize: 10.sp,
                  letterSpacing: 1.4,
                ),
              ),
              SizedBox(width: 8.sp),
              Expanded(
                child: Text(
                  hint,
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.32),
                    fontSize: 10.sp,
                    letterSpacing: 0.0,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8.sp,
          runSpacing: 8.sp,
          children: [
            for (final nag in nags)
              _NagChip(
                nag: nag,
                isActive: activeSet.contains(nag),
                onTap: () => onTap(nag),
              ),
          ],
        ),
      ],
    );
  }
}

class _NagChip extends StatelessWidget {
  final int nag;
  final bool isActive;
  final VoidCallback onTap;

  const _NagChip({
    required this.nag,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final display = getNagDisplay(nag);
    if (display == null) return const SizedBox.shrink();

    final activeBg = display.color;
    final inactiveBg = display.color.withValues(alpha: 0.10);
    final inactiveBorder = display.color.withValues(alpha: 0.45);
    final width = display.symbol.length > 1 ? 50.sp : 42.sp;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        width: width,
        height: 38.sp,
        decoration: BoxDecoration(
          color: isActive ? activeBg : inactiveBg,
          borderRadius: BorderRadius.circular(10.sp),
          border: Border.all(
            color:
                isActive
                    ? Colors.white.withValues(alpha: 0.25)
                    : inactiveBorder,
            width: 1,
          ),
          boxShadow:
              isActive
                  ? [
                    BoxShadow(
                      color: display.color.withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                  : const [],
        ),
        child: Center(
          child: Text(
            display.symbol,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: display.symbol.length > 1 ? 14.sp : 17.sp,
              color:
                  isActive
                      ? Colors.white
                      : display.color.withValues(alpha: 0.95),
              fontWeight: FontWeight.w800,
              height: 1.0,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }
}
