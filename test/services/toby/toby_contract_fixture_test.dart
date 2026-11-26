// The Gamebase next-move contract, version 2, as this client reads it: real
// responses captured from Gamebase end to end (test/fixtures/toby, each
// `{status, headers, body}`) go through the mobile repository (Dio) and the
// reply interpreter into a TobyReading, and the body this client sends for a
// sample board is checked against the shape Gamebase accepts.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/services/toby/toby_prediction.dart';
import 'package:dartchess/dartchess.dart' show Side, kInitialFEN;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _fixtures = 'test/fixtures/toby';
const _sicilian = <String>[
  'e2e4', 'c7c5', 'g1f3', 'd7d6', 'd2d4', 'c5d4', //
  'f3d4', 'g8f6', 'b1c3', 'a7a6', 'c1e3', 'e7e5',
];

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('$_fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

/// Answers every request with one captured Gamebase response and keeps the
/// bytes the repository put on the wire.
class _FixtureAdapter implements HttpClientAdapter {
  _FixtureAdapter(this.fixture);

  final Map<String, dynamic> fixture;
  String? wireBody;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    if (requestStream != null) {
      final bytes = await requestStream.fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );
      wireBody = utf8.decode(bytes);
    }
    final headers = <String, List<String>>{
      for (final entry in (fixture['headers'] as Map).entries)
        entry.key as String: <String>[entry.value as String],
    };
    return ResponseBody.fromString(
      jsonEncode(fixture['body']),
      fixture['status'] as int,
      headers: headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The board pane's request for a game with no source game: PGN tags only
/// .
TobyRequest _sampleRequest() => TobyRequest(
  startFen: kInitialFEN,
  moves: _sicilian,
  whiteRating: tobyRating(int.tryParse('2650')),
  blackRating: tobyRating(int.tryParse('2610')),
  timeControl: '5400+30',
  site: 'Wijk aan Zee',
);

Future<({TobyReplyOutcome outcome, _FixtureAdapter adapter})> _through(
  String fixtureName,
) async {
  final adapter = _FixtureAdapter(_fixture(fixtureName));
  final dio = Dio()..httpClientAdapter = adapter;
  final repository = GamebaseRepository(
    dio,
    baseUrl: 'http://gamebase.test',
    apiKey: 'test-key',
  );
  final reply = await repository.getTobyReading(
    _sampleRequest().toBody(session: newTobySession(), have: TobyHave.none),
    CancelToken(),
  );
  return (outcome: interpretTobyReply(reply), adapter: adapter);
}

void _expectInputs(TobyInputs? inputs) {
  expect(inputs, isNotNull);
  expect(inputs!.whiteRating, 2650);
  expect(inputs.blackRating, 2610);
  expect(inputs.ratingsKnown, isTrue);
  expect(inputs.cadence, TobyCadence.classical);
  expect(inputs.ratingSource, 'FIDE');
  expect(inputs.baseTimeSeconds, 5400);
  expect(inputs.incrementSeconds, 30);
  expect(inputs.label, '2650 v 2610 · Classical');
}

void _expectWdl(TobyWdl? wdl, double white, double draw, double black) {
  expect(wdl, isNotNull);
  expect(wdl!.white, closeTo(white, 1e-9));
  expect(wdl.draw, closeTo(draw, 1e-9));
  expect(wdl.black, closeTo(black, 1e-9));
}

/// Plays captured responses in order, one per request, recording `have`.
class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.fixtures);

  final List<Map<String, dynamic>> fixtures;
  final haves = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    haves.add((options.data as Map)['have'] as String);
    final fixture = fixtures[haves.length - 1];
    return _FixtureAdapter(fixture).fetch(options, null, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(tobyReadingCache.clear);

  test('the provider loop: 202 network -> have:network -> 202 pending -> '
      '200 final, through the real repository', () async {
    final adapter = _SequenceAdapter([
      _fixture('network-202.json'),
      _fixture('pending-202.json'),
      _fixture('final-200.json'),
    ]);
    final container = ProviderContainer(
      overrides: [
        gamebaseRepositoryProvider.overrideWithValue(
          GamebaseRepository(
            Dio()..httpClientAdapter = adapter,
            baseUrl: 'http://gamebase.test',
            apiKey: 'test-key',
          ),
        ),
        tobyReaderHasPremiumProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    final provider = tobyReadingProvider(
      TobyQuery(request: _sampleRequest(), session: newTobySession()),
    );
    final states = <TobyStatus>[];
    container.listen<TobyReadingState>(
      provider,
      (_, next) => states.add(next.status),
      fireImmediately: true,
    );
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (container.read(provider).status != TobyStatus.ready &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final state = container.read(provider);
    expect(state.status, TobyStatus.ready);
    expect(state.reading!.isFinal, isTrue);
    expect(state.reading!.candidates.first.uci, 'e2e4');
    _expectInputs(state.reading!.inputs);
    expect(adapter.haves, ['none', 'network', 'network']);
    expect(states, [TobyStatus.thinking, TobyStatus.network, TobyStatus.ready]);
    expect(
      tobyReadingCache.lookup(_sampleRequest().cacheKey),
      same(state.reading),
    );
  });

  test('200 final fixture -> final TobyReading', () async {
    final result = await _through('final-200.json');
    final outcome = result.outcome;
    expect(outcome, isA<TobyReplyReading>());
    final reading = (outcome as TobyReplyReading).reading;
    expect(reading.isFinal, isTrue);
    expect(reading.sideToMove, Side.white);
    expect(reading.candidates.map((c) => c.uci), ['e2e4', 'd2d4', 'g1f3']);
    expect(reading.candidates.map((c) => c.san), ['e4', 'd4', 'Nf3']);
    expect(reading.candidates.map((c) => c.probability), [0.45, 0.38, 0.0005]);
    expect(reading.candidates.map((c) => c.prior), [0.41, 0.35, 0.002]);
    _expectWdl(reading.candidates[0].wdl, 0.31, 0.46, 0.23);
    _expectWdl(reading.candidates[1].wdl, 0.30, 0.47, 0.23);
    _expectWdl(reading.candidates[2].wdl, 0.29, 0.47, 0.24);
    expect(reading.candidates[2].percentage, '<0.1%');
    expect(reading.candidates[0].percentage, '45.0%');
    _expectWdl(reading.positionWdl, 0.305, 0.465, 0.23);
    expect(reading.positionWdl!.percentages, (white: 31, draw: 46, black: 23));
    expect(reading.otherProbability, 0.1695);
    expect(reading.otherMoveCount, 17);
    _expectInputs(reading.inputs);
    // The cache path the loop uses for finals.
    final cache = TobyReadingCache(4)
      ..store(_sampleRequest().cacheKey, reading);
    expect(cache.lookup(_sampleRequest().cacheKey), same(reading));
  });

  test('202 network fixture -> network TobyReading (muted stage)', () async {
    final result = await _through('network-202.json');
    final outcome = result.outcome;
    expect(outcome, isA<TobyReplyReading>());
    final reading = (outcome as TobyReplyReading).reading;
    expect(reading.isFinal, isFalse);
    expect(reading.sideToMove, Side.white);
    expect(reading.candidates.map((c) => c.uci), ['e2e4', 'd2d4', 'c2c4']);
    expect(reading.candidates.map((c) => c.probability), [0.41, 0.35, 0.12]);
    expect(reading.candidates.map((c) => c.prior), [0.41, 0.35, 0.12]);
    expect(reading.candidates.every((c) => c.wdl == null), isTrue);
    _expectWdl(reading.positionWdl, 0.30, 0.45, 0.25);
    expect(reading.otherProbability, 0.12);
    expect(reading.otherMoveCount, 17);
    _expectInputs(reading.inputs);
  });

  test('202 pending fixtures -> pending with Retry-After', () async {
    final queued = await _through('pending-202.json');
    expect(queued.outcome, isA<TobyReplyPending>());
    expect(
      (queued.outcome as TobyReplyPending).wait,
      const Duration(seconds: 1),
    );
    final busy = await _through('pending-busy-202.json');
    expect(busy.outcome, isA<TobyReplyPending>());
    expect((busy.outcome as TobyReplyPending).wait, const Duration(seconds: 2));
  });

  test('the v2 body on the wire has only the keys Gamebase accepts', () async {
    final result = await _through('final-200.json');
    final adapter = result.adapter;
    expect(adapter.request!.method, 'POST');
    expect(
      adapter.request!.uri.toString(),
      'http://gamebase.test/api/next-move',
    );
    final wire = jsonDecode(adapter.wireBody!) as Map<String, dynamic>;
    // Gamebase's schema is strict: an unknown key is a 400.
    expect(wire.keys.toSet(), {'version', 'session', 'have', 'moves', 'game'});
    expect(wire['version'], 2);
    expect(wire['have'], 'none');
    expect(wire['session'], matches(RegExp(r'^[A-Za-z0-9_-]{8,64}$')));
    expect(
      wire.containsKey('fen'),
      isFalse,
      reason: 'standard start is sent as no fen',
    );
    expect(wire['moves'], _sicilian);
    expect(wire['game'], {
      'whiteRating': 2650,
      'blackRating': 2610,
      'timeControl': '5400+30',
      'category': null,
      'site': 'Wijk aan Zee',
      'event': null,
    });
    // What the panel shows until the reading arrives matches the inputs
    // Gamebase reported for this body.
    final reported = (_fixture('final-200.json')['body'] as Map)['inputs'];
    expect(
      TobyInputs.expectedFor(_sampleRequest()),
      TobyInputs.fromJson(reported),
    );
  });
}
