/// Toby's prediction of the next move: the request a board builds, the
/// reading Gamebase answers, and the polling loop between them.
///
/// The loop follows the protocol-2 contract of `POST /api/next-move`:
/// nothing is sent until a position has been on screen for
/// [tobySettleDelay]; a held poll answers with Toby's quick network stage
/// first and its final reading after; "pending" answers are polled again
/// after `Retry-After` plus a little jitter; and a position gets
/// [tobyPositionBudget] before it reads as busy. Final readings are kept in
/// a small in-memory cache, so revisiting a position costs no request.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show Side, kInitialFEN;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';

/// Whether the app believes the reader has Premium (a subscription, or an
/// active rewarded unlock). It gates nothing: Gamebase decides who may read.
/// When Gamebase refuses a reading (403) it decides whether that earns one
/// fresh membership re-check (a purchase or renewal can lag on either side).
final tobyReaderHasPremiumProvider = Provider<bool>(
  (ref) => ref.watch(premiumAccessProvider),
);

/// Credit owed wherever a Toby result is shown.
const String kTobyAttribution =
    'Toby \u00a9 Yosha Iglesias, toby.tribychess.org';

/// Quiet time after the last position change before the first request.
/// Stepping through a game faster than this never reaches the server. The
/// first request after the reader opens the panel skips it
/// ([TobyReadingNotifier.askNow]).
const Duration tobySettleDelay = Duration(milliseconds: 180);

/// How long one position may take, polls and retries included, before the
/// panel says Toby is busy.
const Duration tobyPositionBudget = Duration(seconds: 20);

/// Final readings kept for instant revisits.
const int tobyReadingCacheCapacity = 256;

/// The ratings the what-if menu offers. One choice sets both players.
const List<int> kTobyRatingOverrides = <int>[1200, 1600, 2000, 2400, 2800];

/// The longest move list and start FEN Gamebase accepts.
const int tobyMaxMoves = 600;
const int tobyMaxFenLength = 160;

/// The highest rating Toby reads. A PGN Elo above it is a typo, not a
/// player, and reads as unknown.
const int tobyMaxRating = 3600;

/// The longest game facts Gamebase accepts: the time control and speed
/// label, and the `Site` and `Event` tags. Longer values are cut to fit, so
/// one odd tag never costs the whole game its readings.
const int tobyMaxCadenceTextLength = 128;
const int tobyMaxSourceTextLength = 1000;

const List<Duration> _failureBackoff = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
];
const int _maxJitterMs = 250;
const Duration _pendingFallbackWait = Duration(seconds: 1);
const Duration _busyFallbackWait = Duration(seconds: 2);
const int _maxCandidates = 24;

final math.Random _jitter = math.Random();
final RegExp _uciPattern = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');
final RegExp _sessionPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
final RegExp _nonStandardVariant = RegExp(
  r'960|fischer|crazyhouse|atomic|antichess|horde|racing kings|three.check|king of the hill',
  caseSensitive: false,
);

/// Whether Toby reads games of [variant] (a PGN `Variant` tag). Toby knows
/// standard chess only; an absent tag is standard.
bool tobyReadsVariant(String? variant) =>
    variant == null || !_nonStandardVariant.hasMatch(variant);

/// A fresh id for one Toby panel. Gamebase drops a panel's previous position
/// as soon as the same panel asks for a new one, so two panels on screen at
/// once (a split board) each need their own.
String newTobySession([math.Random? random]) {
  final source = random ?? math.Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Toby's time-control buckets.
enum TobyCadence {
  classical('classical', 'Classical'),
  rapid('rapid', 'Rapid'),
  blitz('blitz', 'Blitz');

  const TobyCadence(this.wire, this.label);

  /// The value Gamebase speaks.
  final String wire;

  /// How the panel names it.
  final String label;

  static TobyCadence? fromWire(Object? value) {
    for (final cadence in values) {
      if (cadence.wire == value) return cadence;
    }
    return null;
  }
}

/// Which stage of the current position the client already shows. Not part
/// of the position's identity.
enum TobyHave {
  none('none'),
  network('network');

  const TobyHave(this.wire);

  final String wire;
}

/// One position to read, with the raw game facts Gamebase derives Toby's
/// inputs from (ratings, cadence, rating pool) and the reader's what-if
/// choices.
///
/// Immutable and compared by value, so it can key a provider family. Build
/// it where the board knows its game; nothing here watches a provider.
@immutable
class TobyRequest {
  TobyRequest({
    String? startFen,
    required List<String> moves,
    int? whiteRating,
    int? blackRating,
    String? timeControl,
    String? category,
    String? site,
    String? event,
    this.ratingOverride,
    this.cadenceOverride,
  }) : assert(
         ratingOverride == null ||
             kTobyRatingOverrides.contains(ratingOverride),
         'Unsupported Toby rating override: $ratingOverride',
       ),
       startFen = _startFen(startFen),
       moves = List<String>.unmodifiable(moves),
       whiteRating = tobyRating(whiteRating),
       blackRating = tobyRating(blackRating),
       timeControl = _text(timeControl, tobyMaxCadenceTextLength),
       category = _text(category, tobyMaxCadenceTextLength),
       site = _text(site, tobyMaxSourceTextLength),
       event = _text(event, tobyMaxSourceTextLength);

  /// The position the moves start from. Null is the standard start.
  final String? startFen;

  /// UCI moves from [startFen] to the position read.
  final List<String> moves;

  /// The players' ratings as the game knows them. Null when unknown.
  final int? whiteRating;
  final int? blackRating;

  /// The PGN `TimeControl` tag, verbatim.
  final String? timeControl;

  /// The event's or game's speed label ("Classical", "Rapid", "Blitz",
  /// "Bullet").
  final String? category;

  /// The PGN `Site` and `Event` tags. They tell a Lichess or Chess.com game
  /// from an over-the-board one.
  final String? site;
  final String? event;

  /// What-if: read the position as if both players were rated this.
  final int? ratingOverride;

  /// What-if: read the position at this cadence.
  final TobyCadence? cadenceOverride;

  /// Whether Gamebase accepts this request at all.
  bool get isSupported =>
      moves.length <= tobyMaxMoves &&
      (startFen == null || startFen!.length <= tobyMaxFenLength) &&
      moves.every(_uciPattern.hasMatch);

  /// Identity of the reading this request asks for: the request body
  /// without the panel's session and stage. Equal keys read the same.
  late final String cacheKey = jsonEncode(_positionBody());

  TobyRequest copyWith({
    Object? ratingOverride = _keep,
    Object? cadenceOverride = _keep,
  }) => TobyRequest(
    startFen: startFen,
    moves: moves,
    whiteRating: whiteRating,
    blackRating: blackRating,
    timeControl: timeControl,
    category: category,
    site: site,
    event: event,
    ratingOverride: identical(ratingOverride, _keep)
        ? this.ratingOverride
        : ratingOverride as int?,
    cadenceOverride: identical(cadenceOverride, _keep)
        ? this.cadenceOverride
        : cadenceOverride as TobyCadence?,
  );

  /// The request body for one poll from the panel [session].
  Map<String, Object?> toBody({
    required String session,
    required TobyHave have,
  }) {
    assert(_sessionPattern.hasMatch(session), 'Invalid Toby session id');
    return <String, Object?>{
      'version': 2,
      'session': session,
      'have': have.wire,
      ..._positionBody(),
    };
  }

  Map<String, Object?> _positionBody() => <String, Object?>{
    if (startFen != null) 'fen': startFen,
    'moves': moves,
    'game': <String, Object?>{
      'whiteRating': whiteRating,
      'blackRating': blackRating,
      'timeControl': timeControl,
      'category': category,
      'site': site,
      'event': event,
    },
    if (ratingOverride != null || cadenceOverride != null)
      'overrides': <String, Object?>{
        if (ratingOverride != null) 'rating': ratingOverride,
        if (cadenceOverride != null) 'timeControl': cadenceOverride!.wire,
      },
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TobyRequest && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;

  @override
  String toString() => 'TobyRequest($cacheKey)';

  static const Object _keep = Object();

  static String? _startFen(String? fen) {
    final value = _text(fen);
    return value == null || value == kInitialFEN ? null : value;
  }

  /// [value] trimmed, null when empty, and cut to [maxLength] UTF-16 units
  /// (Gamebase's measure) without splitting a surrogate pair.
  static String? _text(String? value, [int? maxLength]) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (maxLength == null || trimmed.length <= maxLength) return trimmed;
    var end = maxLength;
    final last = trimmed.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return trimmed.substring(0, end).trimRight();
  }
}

/// A player's rating as Toby can use it: null when unknown or implausible
/// (zero, negative, or above [tobyMaxRating]), so Gamebase mirrors the other
/// side or assumes a default.
int? tobyRating(int? rating) =>
    rating == null || rating <= 0 || rating > tobyMaxRating ? null : rating;

/// Win, draw and loss chances in White's and Black's terms. The three add
/// up to one.
@immutable
class TobyWdl {
  const TobyWdl({required this.white, required this.draw, required this.black});

  final double white;
  final double draw;
  final double black;

  /// Whole percentages that add up to 100, for "W 28 · D 57 · B 15".
  ///
  /// Largest remainder, the same in every client: each chance is first
  /// rounded to a thousandth of a percent (so float noise such as
  /// 30.499999… for 0.305 cannot decide it), floored, and the points still
  /// missing go to the largest remainders, ties to White, then Draw, then
  /// Black.
  ({int white, int draw, int black}) get percentages {
    const unitsPerPoint = 1000;
    final units = [
      for (final chance in [white, draw, black])
        (chance * 100 * unitsPerPoint).round(),
    ];
    final whole = [for (final value in units) value ~/ unitsPerPoint];
    var left = 100 - whole.fold<int>(0, (sum, value) => sum + value);
    int remainder(int index) => units[index] - whole[index] * unitsPerPoint;
    final byRemainder = [0, 1, 2]
      ..sort((a, b) {
        final byValue = remainder(b).compareTo(remainder(a));
        return byValue != 0 ? byValue : a.compareTo(b);
      });
    for (final index in byRemainder) {
      if (left <= 0) break;
      whole[index]++;
      left--;
    }
    return (white: whole[0], draw: whole[1], black: whole[2]);
  }

  /// Reads `{white, draw, black}`. Any scale is accepted (fractions or per
  /// mille) and normalised; anything else is null.
  static TobyWdl? fromJson(Object? json) {
    if (json is! Map) return null;
    final white = _finite(json['white']);
    final draw = _finite(json['draw']);
    final black = _finite(json['black']);
    if (white == null || draw == null || black == null) return null;
    if (white < 0 || draw < 0 || black < 0) return null;
    final total = white + draw + black;
    if (total <= 0) return null;
    return TobyWdl(
      white: white / total,
      draw: draw / total,
      black: black / total,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TobyWdl &&
      other.white == white &&
      other.draw == draw &&
      other.black == black;

  @override
  int get hashCode => Object.hash(white, draw, black);
}

/// One move Toby expects might be played.
@immutable
class TobyCandidate {
  const TobyCandidate({
    required this.uci,
    required this.san,
    required this.probability,
    this.prior,
    this.wdl,
  });

  /// The move in UCI. Castling is in the king-to-g/c form (`e1g1`).
  final String uci;
  final String san;

  /// Chance this move is played, 0..1.
  final double probability;

  /// The chance before Toby checked the moves with an engine ("first
  /// instinct"), 0..1. Null when not reported.
  final double? prior;

  /// How the game tends to end after this move. Null in the network stage.
  final TobyWdl? wdl;

  /// "71.2%", or "<0.1%" for a sliver.
  String get percentage => tobyPercentage(probability);

  /// Whether first instinct and the checked chance differ by five points or
  /// more, enough to mark. (The tolerance keeps 25% against 20% a difference
  /// of five points in floating point too.)
  bool get priorDiffers =>
      prior != null && (prior! - probability).abs() >= 0.05 - 1e-9;

  @override
  bool operator ==(Object other) =>
      other is TobyCandidate &&
      other.uci == uci &&
      other.san == san &&
      other.probability == probability &&
      other.prior == prior &&
      other.wdl == wdl;

  @override
  int get hashCode => Object.hash(uci, san, probability, prior, wdl);
}

/// "71.2%", "<0.1%" for a positive chance below a tenth of a percent, or
/// "100%" for a certainty (the only legal move), which drops its decimal to
/// fit the same column as "99.9%".
String tobyPercentage(double probability) {
  if (probability > 0 && probability < .001) return '<0.1%';
  final tenths = (probability * 100).toStringAsFixed(1);
  return tenths == '100.0' ? '100%' : '$tenths%';
}

/// The inputs Toby actually read the position with, as Gamebase derived
/// them.
@immutable
class TobyInputs {
  const TobyInputs({
    required this.whiteRating,
    required this.blackRating,
    required this.ratingsKnown,
    required this.cadence,
    required this.ratingSource,
    this.baseTimeSeconds,
    this.incrementSeconds,
  });

  final int whiteRating;
  final int blackRating;

  /// False when neither player had a rating and a default was assumed.
  final bool ratingsKnown;
  final TobyCadence cadence;

  /// The rating pool ("FIDE", "Lichess Classical", "Chess.com Blitz", ...).
  final String ratingSource;
  final int? baseTimeSeconds;
  final int? incrementSeconds;

  /// "2650 v 2610 · Classical", or "Ratings unknown · Classical".
  String get label => ratingsKnown
      ? '$whiteRating v $blackRating · ${cadence.label}'
      : 'Ratings unknown · ${cadence.label}';

  /// The inputs Gamebase derives from [request], shown until a reading
  /// reports the ones it used.
  ///
  /// Mirrors `deriveTobyInputs` in Gamebase's `next-move-derive.ts`, which
  /// stays the source of truth: the request carries the raw game facts, and
  /// a reading's own `inputs` always replace these.
  factory TobyInputs.expectedFor(TobyRequest request) {
    final site = _onlineSite(request.site, request.event);
    final minutes = site == null;
    final period =
        _timeControlPeriod(request.timeControl, minutes: minutes) ??
        _timeControlPeriod(request.category, minutes: minutes);
    // Lichess writes the speed into every game's Event ("Rated Blitz game").
    final gameCadence =
        _cadenceOfLabel(request.category) ??
        (site == _OnlineSite.lichess ? _cadenceOfLabel(request.event) : null) ??
        (period == null
            ? TobyCadence.classical
            : _cadenceOfPeriod(period, site));
    final cadence = request.cadenceOverride ?? gameCadence;
    // A what-if cadence does not keep the game's clock.
    final clock = cadence == gameCadence ? period : null;
    final override = request.ratingOverride;
    final white = request.whiteRating ?? request.blackRating;
    final black = request.blackRating ?? request.whiteRating;
    final known = override != null || white != null;
    int rated(int? rating) =>
        override ??
        (rating == null
            ? _unknownRating
            : ((rating / 10).round() * 10).clamp(1, tobyMaxRating));
    return TobyInputs(
      whiteRating: rated(white),
      blackRating: rated(black),
      ratingsKnown: known,
      cadence: cadence,
      // A chosen rating is a FIDE rating, whatever site the game came from.
      ratingSource: override != null ? 'FIDE' : _ratingSource(site, cadence),
      baseTimeSeconds: clock != null && clock.base >= 1 && clock.base <= 36000
          ? clock.base
          : null,
      incrementSeconds: clock != null && clock.increment <= 600
          ? clock.increment
          : null,
    );
  }

  static TobyInputs? fromJson(Object? json) {
    if (json is! Map) return null;
    final white = _whole(json['whiteRating']);
    final black = _whole(json['blackRating']);
    final cadence = TobyCadence.fromWire(json['timeControl']);
    final source = json['ratingSource'];
    if (white == null ||
        black == null ||
        cadence == null ||
        source is! String) {
      return null;
    }
    return TobyInputs(
      whiteRating: white,
      blackRating: black,
      ratingsKnown: json['ratingsKnown'] != false,
      cadence: cadence,
      ratingSource: source,
      baseTimeSeconds: _whole(json['baseTimeSeconds']),
      incrementSeconds: _whole(json['incrementSeconds']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TobyInputs &&
      other.whiteRating == whiteRating &&
      other.blackRating == blackRating &&
      other.ratingsKnown == ratingsKnown &&
      other.cadence == cadence &&
      other.ratingSource == ratingSource &&
      other.baseTimeSeconds == baseTimeSeconds &&
      other.incrementSeconds == incrementSeconds;

  @override
  int get hashCode => Object.hash(
    whiteRating,
    blackRating,
    ratingsKnown,
    cadence,
    ratingSource,
    baseTimeSeconds,
    incrementSeconds,
  );
}

/// The rating both sides get when the game names neither.
const int _unknownRating = 2000;

enum _OnlineSite { lichess, chessCom }

final RegExp _lichessBroadcast = RegExp(r'lichess\.org/broadcast\S*');
final RegExp _timeControlPeriodPattern = RegExp(
  r'^(?:\d+\s*/\s*)?(\d+)(?:\s*\+\s*(\d+))?$',
);

/// The online site a game was played on, from its PGN Site or Event. A
/// Lichess broadcast URL is an over-the-board relay, not a Lichess game.
_OnlineSite? _onlineSite(String? site, String? event) {
  final text = '${site ?? ''} ${event ?? ''}'.toLowerCase().replaceAll(
    _lichessBroadcast,
    '',
  );
  if (text.contains('lichess')) return _OnlineSite.lichess;
  if (text.contains('chess.com')) return _OnlineSite.chessCom;
  return null;
}

/// The first period of a time control: `5400+30`, `40/5400+30:1800+30`,
/// `600`, or (when [minutes] allows it, over the board) minute shorthand
/// such as `15+10`. `-`, `?` and empty mean none.
({int base, int increment})? _timeControlPeriod(
  String? text, {
  required bool minutes,
}) {
  final first = text?.trim().split(':').first.trim();
  if (first == null || first.isEmpty || first == '-' || first == '?') {
    return null;
  }
  final match = _timeControlPeriodPattern.firstMatch(first);
  if (match == null) return null;
  final base = int.tryParse(match.group(1)!);
  final incrementText = match.group(2);
  final increment = incrementText == null ? 0 : int.tryParse(incrementText);
  if (base == null || increment == null) return null;
  final shorthand = minutes && incrementText != null && base > 0 && base <= 60;
  return (base: shorthand ? base * 60 : base, increment: increment);
}

TobyCadence? _cadenceOfLabel(String? label) {
  final text = label?.toLowerCase() ?? '';
  if (text.contains('bullet') || text.contains('blitz')) {
    return TobyCadence.blitz;
  }
  if (text.contains('rapid')) return TobyCadence.rapid;
  if (text.contains('classical') || text.contains('standard')) {
    return TobyCadence.classical;
  }
  return null;
}

/// From base + 40 × increment seconds: FIDE's bands over the board, the
/// site's own bands online (they decide the players' rating pool).
TobyCadence _cadenceOfPeriod(
  ({int base, int increment}) period,
  _OnlineSite? site,
) {
  final estimated = period.base + 40 * period.increment;
  return switch (site) {
    _OnlineSite.lichess =>
      estimated < 480
          ? TobyCadence.blitz
          : estimated < 1500
          ? TobyCadence.rapid
          : TobyCadence.classical,
    _OnlineSite.chessCom =>
      estimated < 600
          ? TobyCadence.blitz
          : estimated < 86400
          ? TobyCadence.rapid
          : TobyCadence.classical,
    null =>
      estimated <= 600
          ? TobyCadence.blitz
          : estimated < 3600
          ? TobyCadence.rapid
          : TobyCadence.classical,
  };
}

String _ratingSource(_OnlineSite? site, TobyCadence cadence) =>
    switch ((site, cadence)) {
      (_OnlineSite.lichess, TobyCadence.blitz) => 'Lichess Blitz',
      (_OnlineSite.lichess, TobyCadence.rapid) => 'Lichess Rapid',
      (_OnlineSite.lichess, TobyCadence.classical) => 'Lichess Classical',
      (_OnlineSite.chessCom, TobyCadence.blitz) => 'Chess.com Blitz',
      (_OnlineSite.chessCom, TobyCadence.rapid) => 'Chess.com Rapid',
      _ => 'FIDE',
    };

/// One move's outcome in a reading: how games tend to end after it.
typedef TobyMoveOutcome = ({String uci, TobyWdl wdl});

/// Toby's reading of one position: the network stage (quick, muted, no
/// per-move outcomes) or the final reading.
@immutable
class TobyReading {
  const TobyReading({
    required this.isFinal,
    required this.sideToMove,
    required this.candidates,
    required this.otherProbability,
    required this.otherMoveCount,
    this.positionWdl,
    this.inputs,
    this.allOutcomes,
  });

  /// True for the final stage, false for the network stage.
  final bool isFinal;
  final Side sideToMove;

  /// Most likely first, at most 24.
  final List<TobyCandidate> candidates;

  /// How the game tends to end from here. White's and Black's terms.
  final TobyWdl? positionWdl;

  /// The chance and number of moves not listed.
  final double otherProbability;
  final int otherMoveCount;

  /// The inputs Toby used. Null when Gamebase did not report them.
  final TobyInputs? inputs;

  /// EVERY move the payload sent with an outcome, taken before [candidates]
  /// is cut to 24, in the payload's order of likelihood. Null for a reading
  /// built by hand; read [outcomes].
  final List<TobyMoveOutcome>? allOutcomes;

  /// Every move with an outcome: the lines the move classes compare each
  /// candidate against (`toby_classes.dart`), so a strong move past the cut
  /// still counts, as on the web (which keeps every move). [allOutcomes]
  /// when the parser kept them, otherwise the [candidates] that carry one.
  List<TobyMoveOutcome> get outcomes =>
      allOutcomes ??
      [
        for (final candidate in candidates)
          if (candidate.wdl case final wdl?) (uci: candidate.uci, wdl: wdl),
      ];

  TobyCandidate? candidate(String uci) {
    for (final candidate in candidates) {
      if (candidate.uci == uci) return candidate;
    }
    return null;
  }

  /// Reads a protocol-2 payload. Null when anything required is missing or
  /// out of range: a half-valid reading is never shown.
  static TobyReading? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final stage = json['stage'];
    if (stage != 'network' && stage != 'final') return null;
    final side = switch (json['sideToMove']) {
      'white' => Side.white,
      'black' => Side.black,
      _ => null,
    };
    final rows = json['moves'];
    final other = _chance(json['otherProbability']);
    final otherCount = _whole(json['otherMoveCount']);
    if (side == null ||
        rows is! List ||
        other == null ||
        otherCount == null ||
        otherCount < 0) {
      return null;
    }
    final candidates = <TobyCandidate>[];
    for (final row in rows) {
      if (row is! Map) return null;
      final uci = row['uci'];
      final san = row['san'];
      final probability = _chance(row['probability']);
      final rawPrior = row['prior'];
      final prior = rawPrior == null ? null : _chance(rawPrior);
      final rawWdl = row['wdl'];
      final wdl = rawWdl == null ? null : TobyWdl.fromJson(rawWdl);
      if (uci is! String ||
          !_uciPattern.hasMatch(uci) ||
          san is! String ||
          san.isEmpty ||
          probability == null ||
          (rawPrior != null && prior == null) ||
          (rawWdl != null && wdl == null)) {
        return null;
      }
      candidates.add(
        TobyCandidate(
          uci: uci,
          san: san,
          probability: probability,
          prior: prior,
          wdl: wdl,
        ),
      );
    }
    candidates.sort((a, b) => b.probability.compareTo(a.probability));
    final outcomes = <TobyMoveOutcome>[
      for (final candidate in candidates)
        if (candidate.wdl case final wdl?) (uci: candidate.uci, wdl: wdl),
    ];
    final rawPositionWdl = json['positionWdl'];
    final positionWdl = rawPositionWdl == null
        ? null
        : TobyWdl.fromJson(rawPositionWdl);
    if (rawPositionWdl != null && positionWdl == null) return null;
    return TobyReading(
      isFinal: stage == 'final',
      sideToMove: side,
      candidates: List<TobyCandidate>.unmodifiable(
        candidates.take(_maxCandidates),
      ),
      positionWdl: positionWdl,
      otherProbability: other,
      otherMoveCount: otherCount,
      inputs: TobyInputs.fromJson(json['inputs']),
      allOutcomes: List<TobyMoveOutcome>.unmodifiable(outcomes),
    );
  }
}

double? _finite(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;

double? _chance(Object? value) {
  final chance = _finite(value);
  if (chance == null || chance < -1e-9 || chance > 1 + 1e-9) return null;
  return chance.clamp(0.0, 1.0);
}

int? _whole(Object? value) {
  if (value is int) return value;
  if (value is double && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return null;
}

/// What one poll's answer means for the loop.
sealed class TobyReplyOutcome {
  const TobyReplyOutcome();
}

/// A reading arrived: the network stage, or the final one.
final class TobyReplyReading extends TobyReplyOutcome {
  const TobyReplyReading(this.reading);

  final TobyReading reading;
}

/// Nothing new yet. Poll again after [wait] (plus jitter).
final class TobyReplyPending extends TobyReplyOutcome {
  const TobyReplyPending(this.wait);

  final Duration wait;
}

/// The service refused the reader (401/403): its access setting is stricter
/// than the client's. [signIn] when it wants an account (401,
/// `unauthorized`); otherwise it wants Premium (403, `premium_required`).
final class TobyReplyDenied extends TobyReplyOutcome {
  const TobyReplyDenied({required this.signIn});

  final bool signIn;
}

/// The poll failed. [retryable] failures back off and try again within the
/// position's budget; the rest stop.
final class TobyReplyFailed extends TobyReplyOutcome {
  const TobyReplyFailed({required this.retryable});

  final bool retryable;
}

/// Reads one poll's answer. Pure, so the protocol can be tested apart from
/// the loop.
TobyReplyOutcome interpretTobyReply(GamebaseTobyReply reply) {
  final status = reply.statusCode;
  if (status == null) return const TobyReplyFailed(retryable: true);
  if (status == 401 || status == 403) {
    final signIn = status == 401 || reply.data?['error'] == 'unauthorized';
    return TobyReplyDenied(signIn: signIn);
  }
  if (status == 200) {
    final reading = TobyReading.fromJson(reply.data);
    return reading == null
        ? const TobyReplyFailed(retryable: false)
        : TobyReplyReading(reading);
  }
  if (status == 202) {
    final data = reply.data;
    if (data != null && data.containsKey('stage')) {
      final reading = TobyReading.fromJson(data);
      if (reading != null) return TobyReplyReading(reading);
    }
    return TobyReplyPending(
      reply.retryAfter ??
          (data?['reason'] == 'busy'
              ? _busyFallbackWait
              : _pendingFallbackWait),
    );
  }
  if (status == 429 || status >= 500) {
    return const TobyReplyFailed(retryable: true);
  }
  return const TobyReplyFailed(retryable: false);
}

/// Where a panel stands with its position.
enum TobyStatus {
  /// Waiting for the first stage. Also the settle time before any request.
  thinking,

  /// Showing the network stage while the final reading is computed.
  network,

  /// Showing the final reading.
  ready,

  /// The position ran out of its budget. [TobyReadingState.reading] keeps
  /// a network stage when one arrived.
  busy,

  /// The service cannot read this position (or answered nonsense).
  unavailable,

  /// The service did not confirm Premium, after one fresh re-check, for a
  /// reader the app believes has it. Never a paywall.
  premiumUnconfirmed,

  /// The service wants Premium (its access setting) from a reader without
  /// it. The view offers the upgrade; nothing is asked until then.
  premiumRequired,

  /// The service wants an account (its access setting). The view offers
  /// sign-in; nothing is asked until then.
  signInRequired,

  /// Toby cannot read this request (too long a game, an unusable FEN). No
  /// request is made.
  notApplicable,
}

@immutable
class TobyReadingState {
  const TobyReadingState(this.status, {this.reading});

  const TobyReadingState.ready(TobyReading this.reading)
    : status = TobyStatus.ready;

  final TobyStatus status;

  /// The final reading when [status] is [TobyStatus.ready]; the network
  /// stage while [status] is [TobyStatus.network], kept through
  /// [TobyStatus.busy]; otherwise null.
  final TobyReading? reading;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TobyReadingState &&
          other.status == status &&
          identical(other.reading, reading);

  @override
  int get hashCode => Object.hash(status, identityHashCode(reading));

  @override
  String toString() =>
      'TobyReadingState(${status.name}'
      '${reading == null ? '' : ', ${reading!.candidates.length} moves'})';
}

/// One panel asking about one position. [session] is the panel's own id
/// ([newTobySession]), so two panels on the same position each get their
/// own provider and the service can drop each panel's old position.
@immutable
class TobyQuery {
  const TobyQuery({required this.request, required this.session});

  final TobyRequest request;
  final String session;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TobyQuery &&
          other.session == session &&
          other.request == request;

  @override
  int get hashCode => Object.hash(request, session);
}

/// Final readings by [TobyRequest.cacheKey], least recently used first.
class TobyReadingCache {
  TobyReadingCache(this.capacity);

  final int capacity;
  final LinkedHashMap<String, TobyReading> _entries =
      LinkedHashMap<String, TobyReading>();

  int get length => _entries.length;

  TobyReading? lookup(String key) {
    final reading = _entries.remove(key);
    if (reading != null) _entries[key] = reading;
    return reading;
  }

  void store(String key, TobyReading reading) {
    assert(reading.isFinal, 'Only final readings are cached');
    _entries.remove(key);
    _entries[key] = reading;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}

/// Shared by every reader of Toby in the app (one loop per position).
final TobyReadingCache tobyReadingCache = TobyReadingCache(
  tobyReadingCacheCapacity,
);

/// Toby's reading for one view and position.
///
/// Watched while the Toby Predicts tab or the Toby bar beside the board is
/// shown, both through `tobyQueryFor` (so one board runs one loop for both):
/// it is auto-disposed, and an unobserved instance sends nothing (or cancels
/// what it sent). A new position is a new [TobyQuery], so the old instance's
/// request is cancelled as the view moves on. Who may read is Gamebase's
/// call; a refusal ends in [TobyStatus.signInRequired] or
/// [TobyStatus.premiumRequired] (or [TobyStatus.premiumUnconfirmed]).
final tobyReadingProvider = NotifierProvider.autoDispose
    .family<TobyReadingNotifier, TobyReadingState, TobyQuery>(
      TobyReadingNotifier.new,
    );

class TobyReadingNotifier
    extends AutoDisposeFamilyNotifier<TobyReadingState, TobyQuery> {
  /// Bumped whenever the running loop must stop: dispose, budget, retry.
  int _run = 0;
  CancelToken? _inFlight;
  Timer? _sleepTimer;
  Completer<void>? _sleepDone;
  Timer? _budget;

  /// Whether the loop is waiting out the settle delay.
  bool _settling = false;

  @override
  TobyReadingState build(TobyQuery query) {
    ref.onDispose(_halt);
    final cached = tobyReadingCache.lookup(query.request.cacheKey);
    if (cached != null) return TobyReadingState.ready(cached);
    if (!query.request.isSupported) {
      return const TobyReadingState(TobyStatus.notApplicable);
    }
    unawaited(_poll(++_run, settle: true));
    return const TobyReadingState(TobyStatus.thinking);
  }

  /// Sends the first request now instead of after the settle delay: the
  /// reader just opened the panel, so there is no navigation to wait out.
  /// Does nothing once the request is out (or when none is needed).
  void askNow() {
    if (_settling) _wake();
  }

  /// "Try again" after busy, unavailable or an unconfirmed membership: a
  /// fresh budget for the same position, without the settle delay. A
  /// network stage already shown stays up while it runs.
  void retry() {
    switch (state.status) {
      case TobyStatus.busy:
      case TobyStatus.unavailable:
      case TobyStatus.premiumUnconfirmed:
      case TobyStatus.premiumRequired:
      case TobyStatus.signInRequired:
        _halt();
        final network = state.reading;
        state = network == null
            ? const TobyReadingState(TobyStatus.thinking)
            : TobyReadingState(TobyStatus.network, reading: network);
        unawaited(_poll(++_run, settle: false));
      case TobyStatus.thinking:
      case TobyStatus.network:
      case TobyStatus.ready:
      case TobyStatus.notApplicable:
        return;
    }
  }

  Future<void> _poll(int run, {required bool settle}) async {
    bool live() => run == _run;
    if (settle) {
      _settling = true;
      await _sleep(tobySettleDelay);
      _settling = false;
      if (!live()) return;
    }
    final repository = ref.read(gamebaseRepositoryProvider);
    if (!repository.hasApiKey) {
      // No proxy key in this build: nothing can ever be sent, so say so at
      // once instead of retrying a request that never leaves the device.
      _finish(const TobyReadingState(TobyStatus.unavailable));
      return;
    }
    final request = arg.request;
    _budget = Timer(tobyPositionBudget, () => _giveUp(run));
    var have = state.reading == null ? TobyHave.none : TobyHave.network;
    var failures = 0;
    var recheckAccess = false;
    var recheckedAccess = false;
    while (live()) {
      final cancelToken = CancelToken();
      _inFlight = cancelToken;
      final reply = await repository.getTobyReading(
        request.toBody(session: arg.session, have: have),
        cancelToken,
        recheckAccess: recheckAccess,
      );
      if (!live()) return;
      _inFlight = null;
      recheckAccess = false;
      switch (interpretTobyReply(reply)) {
        case TobyReplyReading(:final reading) when reading.isFinal:
          tobyReadingCache.store(request.cacheKey, reading);
          _finish(TobyReadingState.ready(reading));
          return;
        case TobyReplyReading(:final reading):
          // The network stage is answered at once; ask again right away for
          // the final one. A service that repeats the network stage instead
          // of holding the poll is paced like a pending answer.
          final repeated = have == TobyHave.network;
          state = TobyReadingState(TobyStatus.network, reading: reading);
          have = TobyHave.network;
          failures = 0;
          if (repeated) await _sleep(_withJitter(_pendingFallbackWait));
        case TobyReplyPending(:final wait):
          failures = 0;
          await _sleep(_withJitter(wait));
        case TobyReplyDenied(signIn: true):
          // The service wants an account: the view offers sign-in.
          _finish(const TobyReadingState(TobyStatus.signInRequired));
          return;
        case TobyReplyDenied():
          // The service wants Premium. Membership can lag behind a purchase
          // or a renewal on either side, so a reader the app believes is
          // Premium gets one fresh re-check, never a loop and never a
          // paywall; anyone else is offered the upgrade by the view.
          final premium = ref.read(tobyReaderHasPremiumProvider);
          if (premium && !recheckedAccess) {
            recheckedAccess = true;
            recheckAccess = true;
            continue;
          }
          _finish(
            TobyReadingState(
              premium
                  ? TobyStatus.premiumUnconfirmed
                  : TobyStatus.premiumRequired,
            ),
          );
          return;
        case TobyReplyFailed(retryable: false):
          _finish(const TobyReadingState(TobyStatus.unavailable));
          return;
        case TobyReplyFailed():
          await _sleep(
            _failureBackoff[math.min(failures, _failureBackoff.length - 1)],
          );
          failures++;
      }
    }
  }

  static Duration _withJitter(Duration wait) =>
      wait + Duration(milliseconds: _jitter.nextInt(_maxJitterMs + 1));

  void _finish(TobyReadingState next) {
    _budget?.cancel();
    _budget = null;
    state = next;
  }

  void _giveUp(int run) {
    if (run != _run) return;
    _halt();
    state = TobyReadingState(TobyStatus.busy, reading: state.reading);
  }

  /// Stops the running loop: cancels its request and wakes its sleep so it
  /// sees it is no longer current.
  void _halt() {
    _run++;
    _budget?.cancel();
    _budget = null;
    _inFlight?.cancel();
    _inFlight = null;
    _wake();
  }

  /// Ends the current sleep early.
  void _wake() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    final sleeping = _sleepDone;
    _sleepDone = null;
    if (sleeping != null && !sleeping.isCompleted) sleeping.complete();
  }

  Future<void> _sleep(Duration duration) {
    final done = Completer<void>();
    _sleepDone = done;
    _sleepTimer = Timer(duration, () {
      _sleepTimer = null;
      _sleepDone = null;
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }
}
