import 'package:chessever2/widgets/paywall/pgn_import_access.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/pgn_import_preview_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/utils/pgn_multi_parser.dart';
import 'package:chessever2/utils/pgn_clock_utils.dart';
import 'package:chessever2/utils/pgn_time_control.dart';
import 'package:chessever2/utils/event_time_control.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Convert a parsed [ChessGame] into the [GamesTourModel] shape that
/// [ChessBoardScreenNew] and [PgnImportPreviewScreen] expect when rendering
/// cards + boards for imported games (no Supabase round/tour row behind it).
///
/// Kept as a top-level function so both the intake service and the preview
/// screen can use the same mapping, guaranteeing cards look identical.
GamesTourModel chessGameToImportedGamesTourModel(ChessGame game) {
  final md = game.metadata;
  PlayerCard player(String side) {
    final name = _firstNonEmpty([md[side]]);
    final federation = _firstNonEmpty([
      md['${side}Fed'],
      md['${side}Federation'],
      md['${side}Country'],
      md['${side}FideFederation'],
      md['${side}Nationality'],
    ]);
    return PlayerCard(
      name: name.isEmpty ? side : name,
      federation: federation,
      title: _firstNonEmpty([md['${side}Title']]),
      rating: _parseFideId(md['${side}Elo']) ?? 0,
      countryCode: federation,
      fideId: _parseFideId(md['${side}FideId']),
      team: _knownHeader(md['${side}Team']),
    );
  }

  final status = GameStatus.fromString(_knownHeader(md['Result']) ?? '*');
  final parsedDate =
      _parsePgnDate(_knownHeader(md['Date'])) ??
      _parsePgnDate(_knownHeader(md['UTCDate']));
  final last = game.mainline.lastOrNull;
  int? whiteClock = parsePgnClockToSeconds(_knownHeader(md['WhiteClock']));
  int? blackClock = parsePgnClockToSeconds(_knownHeader(md['BlackClock']));
  for (final move in game.mainline) {
    final seconds = parsePgnClockToSeconds(move.clockTime);
    if (seconds == null) continue;
    // ChessMove.turn identifies the side that made this move, including a
    // PGN whose supplied starting position has Black to move.
    if (move.turn == ChessColor.white) {
      whiteClock = seconds;
    } else {
      blackClock = seconds;
    }
  }
  final rawTimeControl = _knownHeader(md['TimeControl']);

  return GamesTourModel(
    gameId: game.gameId,
    source: GameSource.boardEditor,
    whitePlayer: player('White'),
    blackPlayer: player('Black'),
    whiteTimeDisplay: whiteClock == null
        ? '--:--'
        : formatClockDisplayFromSeconds(whiteClock),
    blackTimeDisplay: blackClock == null
        ? '--:--'
        : formatClockDisplayFromSeconds(blackClock),
    whiteClockCentiseconds: (whiteClock ?? 0) * 100,
    blackClockCentiseconds: (blackClock ?? 0) * 100,
    whiteClockSeconds: whiteClock,
    blackClockSeconds: blackClock,
    gameStatus: status,
    roundId: _knownHeader(md['Round']) ?? 'import_preview',
    tourId: _knownHeader(md['Event']) ?? 'import_preview',
    boardNr: _parseFideId(md['Board']) ?? _parseFideId(md['BoardNumber']),
    timeControl:
        _pgnTimeControlCategory(_knownHeader(md['TcCategory'])) ??
        _pgnTimeControlCategory(rawTimeControl),
    timeControlText: rawTimeControl,
    pgn: exportGameToPgn(game),
    fen: last?.fen ?? game.startingFen,
    lastMove: last?.uci,
    eco: _knownHeader(md['ECO']),
    openingName: _knownHeader(md['Opening']),
    lastMoveTime: parsedDate,
    gameDay: parsedDate,
    dateStart: parsedDate,
  );
}

String? _knownHeader(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty || text == '?' || text == '-' ? null : text;
}

String? _pgnTimeControlCategory(String? value) {
  final category = timeControlBucketFor(value);
  if (category != null) {
    return category == TimeControlBucket.classical ? 'standard' : category.name;
  }
  // Actual PGN fields use seconds. The general parser also accepts human
  // minute shorthand, so parse a valid numeric field without that ambiguity.
  final numeric = RegExp(
    r'^(?:(\d+)/)?(\d+)(?:\+(\d+))?$',
  ).firstMatch(value?.split(':').first.trim() ?? '');
  final periods = numeric == null
      ? parsePgnTimeControlPeriods(value)
      : [
          PgnTimeControlPeriod(
            seconds: int.parse(numeric.group(2)!),
            moves: int.tryParse(numeric.group(1) ?? ''),
            incrementSeconds: int.tryParse(numeric.group(3) ?? ''),
          ),
        ];
  if (periods.isEmpty) return null;
  final first = periods.first;
  // The same 60-move duration used to classify FIDE time controls.
  final base = first.moves != null && first.moves! > 0
      ? first.seconds * 60 / first.moves!
      : first.seconds;
  final duration = base + 60 * (first.incrementSeconds ?? 0);
  if (duration <= 600) return 'blitz';
  if (duration < 3600) return 'rapid';
  return 'standard';
}

String _firstNonEmpty(List<dynamic> candidates) {
  for (final c in candidates) {
    final s = _knownHeader(c);
    if (s != null) return s;
  }
  return '';
}

int? _parseFideId(dynamic raw) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty || s == '?' || s == '0') return null;
  final parsed = int.tryParse(s);
  return (parsed != null && parsed > 0) ? parsed : null;
}

DateTime? _parsePgnDate(String? date) {
  if (date == null || date.isEmpty) return null;
  try {
    if (date.contains('.')) {
      final parts = date.split('.');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) {
          final parsed = DateTime(y, m, d);
          if (y > 0 && parsed.year == y && parsed.month == m && parsed.day == d) {
            return parsed;
          }
          return null;
        }
      }
    }
    return DateTime.tryParse(date);
  } catch (_) {
    return null;
  }
}

/// Centralizes "take a PGN blob and route the user somewhere sensible".
///
/// Used by:
/// - In-app file picker (from the Add-to-Library sheet) — always routes to
///   [PgnImportPreviewScreen] so the UX matches clipboard paste.
/// - OS "Open with ChessEver" from Files.app / Android file managers — routes
///   single-game PGNs directly to [ChessBoardScreenNew] and multi-game PGNs to
///   [PgnImportPreviewScreen], per product spec.
class PgnFileIntakeService {
  PgnFileIntakeService._();

  static final PgnFileIntakeService instance = PgnFileIntakeService._();

  StreamSubscription<List<SharedMediaFile>>? _intentStreamSub;
  bool _isInitialized = false;

  /// Start listening for OS file-open / share intents. Idempotent.
  Future<void> initialize(
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Cold start: app launched by tapping a .pgn file.
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) {
        unawaited(
          _handleSharedMedia(initial, navigatorKey, waitAppReady: true),
        );
      }
      ReceiveSharingIntent.instance.reset();
    } catch (e) {
      debugPrint('PgnFileIntakeService: getInitialMedia failed: $e');
    }

    // Warm start: file-open arrives while app is running.
    _intentStreamSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) => unawaited(
        _handleSharedMedia(files, navigatorKey, waitAppReady: false),
      ),
      onError: (Object error) {
        debugPrint('PgnFileIntakeService: media stream error: $error');
      },
    );
  }

  void dispose() {
    _intentStreamSub?.cancel();
    _intentStreamSub = null;
    _isInitialized = false;
  }

  /// In-app entry point: user pasted/picked a PGN blob. Always routes to the
  /// preview screen (even for a single game), matching the clipboard flow.
  Future<bool> ingestPgnTextFromContext({
    required BuildContext context,
    required String text,
    String? sourceLabel,
    String? initialFolderId,
  }) async {
    if (!await ensurePgnImportAccess(context) || !context.mounted) return false;
    final parsed = parsePgnsToChessGames(text);
    if (parsed.isEmpty) {
      if (context.mounted) {
        showAppSnack(
          context,
          'That file does not contain a valid PGN',
          tone: AppSnackTone.danger,
        );
      }
      return false;
    }

    if (!context.mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PgnImportPreviewScreen(
          games: parsed.map((e) => e.chessGame).toList(),
          initialFolderId: initialFolderId,
          sourceLabel: sourceLabel,
        ),
      ),
    );
    return true;
  }

  /// Read a PGN file by path, decode as UTF-8 (lenient), and route through
  /// [ingestPgnTextFromContext]. Returns false on I/O or decode failure.
  Future<bool> ingestPgnFileFromContext({
    required BuildContext context,
    required String path,
    String? sourceLabel,
    String? initialFolderId,
  }) async {
    final text = await _readPgnFile(path);
    if (text == null) {
      if (context.mounted) {
        showAppSnack(
          context,
          'Could not read that file.',
          tone: AppSnackTone.danger,
        );
      }
      return false;
    }
    if (!context.mounted) return false;
    return ingestPgnTextFromContext(
      context: context,
      text: text,
      sourceLabel: sourceLabel ?? 'file',
      initialFolderId: initialFolderId,
    );
  }

  Future<String?> _readPgnFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      // Most PGNs are ASCII/UTF-8; a few TWIC files are latin1. Try UTF-8
      // first (allowMalformed so a stray byte doesn't kill the whole file),
      // fall back to latin1 if the result is empty after trim.
      final utf = utf8.decode(bytes, allowMalformed: true);
      if (utf.trim().isNotEmpty) return utf;
      return latin1.decode(bytes, allowInvalid: true);
    } catch (e) {
      debugPrint('PgnFileIntakeService: failed reading $path: $e');
      return null;
    }
  }

  Future<void> _handleSharedMedia(
    List<SharedMediaFile> files,
    GlobalKey<NavigatorState> navigatorKey, {
    required bool waitAppReady,
  }) async {
    if (files.isEmpty) return;
    final pgnFile = files.firstWhere(
      (f) => _looksLikePgn(f),
      orElse: () => files.first,
    );
    if (pgnFile.path.isEmpty) return;

    await handlePgnFilePath(
      pgnFile.path,
      navigatorKey,
      waitAppReady: waitAppReady,
    );
  }

  /// Public entry point for iOS file-open URLs delivered via app_links
  /// (DeepLinkService routes `file://` URIs here) and any other path-only
  /// caller. Reads the file, parses, then routes single-game PGNs to the
  /// board and multi-game PGNs to the preview screen — same behavior as
  /// the share-intent flow.
  Future<void> handlePgnFilePath(
    String path,
    GlobalKey<NavigatorState> navigatorKey, {
    required bool waitAppReady,
  }) async {
    if (path.isEmpty) return;

    final text = await _readPgnFile(path);
    if (text == null) return;

    final parsed = parsePgnsToChessGames(text);
    if (parsed.isEmpty) return;

    if (waitAppReady) {
      try {
        await DeepLinkService.awaitAppReady().timeout(
          const Duration(seconds: 30),
        );
      } catch (_) {
        // Proceed anyway — worst case the push is deferred by the navigator.
      }
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null || !navigator.mounted) return;
    if (!await ensurePgnImportAccess(navigator.context) || !navigator.mounted) {
      return;
    }

    final games = parsed.map((e) => e.chessGame).toList();

    if (games.length == 1) {
      // Single-game file open → straight to the board, per spec.
      _openSingleGameOnBoard(navigator, games.single);
    } else {
      navigator.push(
        MaterialPageRoute(
          builder: (_) =>
              PgnImportPreviewScreen(games: games, sourceLabel: 'shared file'),
        ),
      );
    }
  }

  void _openSingleGameOnBoard(NavigatorState navigator, ChessGame game) {
    final tourModel = chessGameToImportedGamesTourModel(game);
    final context = navigator.context;
    final container = ProviderScope.containerOf(context, listen: false);
    container.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

    navigator.push(
      MaterialPageRoute(
        builder: (_) => ChessBoardScreenNew(
          currentIndex: 0,
          games: [tourModel],
          viewSource: ChessboardView.tour,
          showGamebaseButton: false,
          disableGamebaseOverlayByDefault: true,
        ),
      ),
    );
  }

  bool _looksLikePgn(SharedMediaFile f) {
    final lower = f.path.toLowerCase();
    if (lower.endsWith('.pgn')) return true;
    final mime = (f.mimeType ?? '').toLowerCase();
    return mime.contains('pgn');
  }
}
