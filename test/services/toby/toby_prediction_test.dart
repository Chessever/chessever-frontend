import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/services/toby/toby_prediction.dart';
import 'package:dartchess/dartchess.dart' show Side, kInitialFEN;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _session = 'panel-test-0001';

typedef _Call = ({
  Map<String, Object?> body,
  CancelToken cancel,
  bool recheckAccess,
});

class _FakeGamebase extends GamebaseRepository {
  _FakeGamebase(this._answer, {super.apiKey = 'test-key'})
    : super(Dio(), baseUrl: 'http://example.test');

  final FutureOr<GamebaseTobyReply> Function(_Call call, int index) _answer;
  final calls = <_Call>[];

  List<int> get requestedPlies => [
    for (final call in calls) (call.body['moves']! as List).length,
  ];

  @override
  Future<GamebaseTobyReply> getTobyReading(
    Map<String, Object?> body,
    CancelToken cancelToken, {
    bool recheckAccess = false,
  }) async {
    final call = (
      body: body,
      cancel: cancelToken,
      recheckAccess: recheckAccess,
    );
    calls.add(call);
    return _answer(call, calls.length - 1);
  }
}

GamebaseTobyReply _reply(
  int status, [
  Map<String, dynamic>? data,
  Duration? retryAfter,
]) => (statusCode: status, data: data, retryAfter: retryAfter);

/// Answers only when the loop cancels the request.
Future<GamebaseTobyReply> _heldUntilCancelled(_Call call) => call
    .cancel
    .whenCancel
    .then((_) => (statusCode: null, data: null, retryAfter: null));

Map<String, dynamic> _payload({String stage = 'final'}) => {
  'stage': stage,
  'sideToMove': 'white',
  'moves': [
    {
      'uci': 'd2d4',
      'san': 'd4',
      'probability': 0.2,
      'prior': 0.25,
      'wdl': null,
    },
    {
      'uci': 'e2e4',
      'san': 'e4',
      'probability': 0.71,
      'prior': 0.64,
      'wdl': stage == 'final'
          ? {'white': 0.30, 'draw': 0.55, 'black': 0.15}
          : null,
    },
  ],
  'positionWdl': {'white': 0.28, 'draw': 0.57, 'black': 0.15},
  'otherProbability': 0.09,
  'otherMoveCount': 18,
  'inputs': {
    'whiteRating': 2650,
    'blackRating': 2610,
    'ratingsKnown': true,
    'timeControl': 'classical',
    'ratingSource': 'FIDE',
    'baseTimeSeconds': 5400,
    'incrementSeconds': 30,
  },
};

TobyQuery _query(int plies, {String session = _session}) => TobyQuery(
  request: TobyRequest(
    moves: List<String>.generate(plies, (i) => i.isEven ? 'g1f3' : 'g8f6'),
    whiteRating: 2650,
    blackRating: 2610,
    timeControl: '40/5400+30:1800+30',
    category: 'Classical',
  ),
  session: session,
);

/// [premium]: whether the client believes the reader has Premium. It gates
/// nothing; it only shapes what a refusal from Gamebase leads to.
ProviderContainer _container(_FakeGamebase repo, {bool premium = true}) {
  final container = ProviderContainer(
    overrides: [
      gamebaseRepositoryProvider.overrideWithValue(repo),
      tobyReaderHasPremiumProvider.overrideWithValue(premium),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(tobyReadingCache.clear);

  group('the reading loop', () {
    testWidgets('positions passed through ask nothing; the settled one asks '
        'once', (tester) async {
      final repo = _FakeGamebase((_, _) => _reply(200, _payload()));
      final container = _container(repo);
      for (var ply = 0; ply < 12; ply++) {
        final visit = container.listen(
          tobyReadingProvider(_query(ply)),
          (_, _) {},
        );
        await tester.pump(const Duration(milliseconds: 35));
        visit.close();
      }
      await tester.pump(const Duration(seconds: 1));
      expect(repo.calls, isEmpty);

      final settled = tobyReadingProvider(_query(12));
      container.listen(settled, (_, _) {});
      expect(container.read(settled).status, TobyStatus.thinking);
      await tester.pump(const Duration(milliseconds: 179));
      expect(repo.calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 2));

      expect(repo.requestedPlies, [12]);
      final body = repo.calls.single.body;
      expect(body['version'], 2);
      expect(body['session'], _session);
      expect(body['have'], 'none');
      expect(body.containsKey('fen'), isFalse);
      final state = container.read(settled);
      expect(state.status, TobyStatus.ready);
      expect(state.reading!.isFinal, isTrue);
      expect(state.reading!.candidates.first.san, 'e4');
      container.dispose();
    });

    testWidgets('the network stage shows first, then the final reading', (
      tester,
    ) async {
      final finalAnswer = Completer<GamebaseTobyReply>();
      final repo = _FakeGamebase(
        (_, index) => index == 0
            ? _reply(202, _payload(stage: 'network'), Duration.zero)
            : finalAnswer.future,
      );
      final container = _container(repo);
      final provider = tobyReadingProvider(_query(4));
      final seen = <TobyStatus>[];
      container.listen(
        provider,
        (_, next) => seen.add(next.status),
        fireImmediately: true,
      );
      await tester.pump(const Duration(milliseconds: 180));

      expect(repo.calls.map((call) => call.body['have']), ['none', 'network']);
      final network = container.read(provider);
      expect(network.status, TobyStatus.network);
      expect(network.reading!.isFinal, isFalse);

      finalAnswer.complete(_reply(200, _payload()));
      await tester.pump();
      expect(seen, [TobyStatus.thinking, TobyStatus.network, TobyStatus.ready]);
      expect(container.read(provider).reading!.isFinal, isTrue);
      expect(repo.calls, hasLength(2));
      container.dispose();
    });

    testWidgets('a pending answer waits Retry-After plus a little jitter', (
      tester,
    ) async {
      final repo = _FakeGamebase(
        (_, index) => index == 0
            ? _reply(202, {
                'status': 'pending',
                'reason': 'queued',
              }, const Duration(seconds: 2))
            : _reply(200, _payload()),
      );
      final container = _container(repo);
      final provider = tobyReadingProvider(_query(6));
      container.listen(provider, (_, _) {});
      await tester.pump(const Duration(milliseconds: 180));
      expect(repo.calls, hasLength(1));

      await tester.pump(const Duration(milliseconds: 1990));
      expect(repo.calls, hasLength(1));
      await tester.pump(const Duration(milliseconds: 270));
      expect(repo.calls, hasLength(2));
      expect(container.read(provider).status, TobyStatus.ready);
      container.dispose();
    });

    testWidgets('moving to a new position cancels the old request', (
      tester,
    ) async {
      final repo = _FakeGamebase(
        (call, _) => (call.body['moves']! as List).length == 8
            ? _heldUntilCancelled(call)
            : _reply(200, _payload()),
      );
      final container = _container(repo);
      final old = container.listen(tobyReadingProvider(_query(8)), (_, _) {});
      await tester.pump(const Duration(milliseconds: 180));
      expect(repo.requestedPlies, [8]);
      expect(repo.calls.single.cancel.isCancelled, isFalse);

      old.close();
      final next = tobyReadingProvider(_query(9));
      container.listen(next, (_, _) {});
      await tester.pump(const Duration(milliseconds: 1));
      expect(repo.calls.first.cancel.isCancelled, isTrue);

      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump(const Duration(seconds: 5));
      expect(repo.requestedPlies, [8, 9]);
      expect(container.read(next).status, TobyStatus.ready);
      container.dispose();
    });

    testWidgets('closing the panel cancels a pending retry', (tester) async {
      final repo = _FakeGamebase(
        (_, _) => _reply(202, {
          'status': 'pending',
          'reason': 'busy',
        }, const Duration(seconds: 2)),
      );
      final container = _container(repo);
      final panel = container.listen(tobyReadingProvider(_query(3)), (_, _) {});
      await tester.pump(const Duration(milliseconds: 180));
      expect(repo.calls, hasLength(1));

      panel.close();
      await tester.pump(const Duration(seconds: 10));
      expect(repo.calls, hasLength(1));
      container.dispose();
    });

    testWidgets('a refused Premium reader gets one fresh re-check, then '
        'stops without a paywall', (tester) async {
      // Answered a moment later, as over the network, so a loop would show
      // up as a count rather than a hang.
      final repo = _FakeGamebase(
        (_, _) => Future.delayed(
          const Duration(milliseconds: 10),
          () => _reply(403, {'error': 'premium_required'}),
        ),
      );
      final container = _container(repo);
      final provider = tobyReadingProvider(_query(5));
      container.listen(provider, (_, _) {});
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 10));

      expect(repo.calls.map((call) => call.recheckAccess), [false, true]);
      expect(container.read(provider).status, TobyStatus.premiumUnconfirmed);
      await tester.pump(const Duration(seconds: 30));
      expect(repo.calls, hasLength(2));
      container.dispose();
    });

    testWidgets('a Premium refusal for a reader without Premium is not '
        're-checked: the view offers the upgrade', (tester) async {
      final repo = _FakeGamebase(
        (_, _) => Future.delayed(
          const Duration(milliseconds: 10),
          () => _reply(403, {'error': 'premium_required'}),
        ),
      );
      final container = _container(repo, premium: false);
      final provider = tobyReadingProvider(_query(5));
      container.listen(provider, (_, _) {});
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump(const Duration(seconds: 30));

      expect(repo.calls, hasLength(1));
      expect(container.read(provider).status, TobyStatus.premiumRequired);

      // After an upgrade the view asks again.
      container.read(provider.notifier).retry();
      await tester.pump(const Duration(milliseconds: 20));
      expect(repo.calls, hasLength(2));
      container.dispose();
    });

    testWidgets('an account refusal asks for sign-in, with no re-check, '
        'whatever the membership', (tester) async {
      for (final premium in [false, true]) {
        final repo = _FakeGamebase(
          (_, _) => Future.delayed(
            const Duration(milliseconds: 10),
            () => _reply(401, {'error': 'unauthorized'}),
          ),
        );
        final container = _container(repo, premium: premium);
        final provider = tobyReadingProvider(_query(5));
        container.listen(provider, (_, _) {});
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pump(const Duration(seconds: 30));

        expect(repo.calls, hasLength(1));
        expect(container.read(provider).status, TobyStatus.signInRequired);
        container.dispose();
      }
    });

    testWidgets('a revisited position is answered from memory', (tester) async {
      final repo = _FakeGamebase((_, _) => _reply(200, _payload()));
      final container = _container(repo);
      final provider = tobyReadingProvider(_query(10));
      final first = container.listen(provider, (_, _) {});
      await tester.pump(const Duration(milliseconds: 180));
      expect(repo.calls, hasLength(1));
      first.close();
      await tester.pump(const Duration(seconds: 1));

      // Another panel (its own session) on the same position, too.
      for (final session in [_session, 'panel-test-0002']) {
        final again = tobyReadingProvider(_query(10, session: session));
        container.listen(again, (_, _) {});
        expect(container.read(again).status, TobyStatus.ready);
      }
      await tester.pump(const Duration(seconds: 1));
      expect(repo.calls, hasLength(1));
      container.dispose();
    });

    testWidgets('failures back off 1, 2 and 4 s, then read as busy', (
      tester,
    ) async {
      final repo = _FakeGamebase(
        (_, _) => _reply(503, {'error': 'unavailable'}),
      );
      final container = _container(repo);
      final provider = tobyReadingProvider(_query(7));
      container.listen(provider, (_, _) {});
      await tester.pump(const Duration(milliseconds: 180));
      expect(repo.calls, hasLength(1));
      await tester.pump(const Duration(milliseconds: 999));
      expect(repo.calls, hasLength(1));
      await tester.pump(const Duration(milliseconds: 2));
      expect(repo.calls, hasLength(2));
      await tester.pump(const Duration(milliseconds: 1998));
      expect(repo.calls, hasLength(2));
      await tester.pump(const Duration(milliseconds: 2));
      expect(repo.calls, hasLength(3));
      await tester.pump(const Duration(milliseconds: 3998));
      expect(repo.calls, hasLength(3));
      await tester.pump(const Duration(milliseconds: 2));
      expect(repo.calls, hasLength(4));

      await tester.pump(const Duration(seconds: 13));
      expect(container.read(provider).status, TobyStatus.busy);
      final spent = repo.calls.length;
      await tester.pump(const Duration(seconds: 30));
      expect(repo.calls, hasLength(spent));
      container.dispose();
    });

    testWidgets('busy keeps the network stage, and Try again starts over', (
      tester,
    ) async {
      final repo = _FakeGamebase(
        (_, index) => index == 0
            ? _reply(202, _payload(stage: 'network'), Duration.zero)
            : _reply(202, {
                'status': 'pending',
                'reason': 'busy',
              }, const Duration(seconds: 2)),
      );
      final container = _container(repo);
      final provider = tobyReadingProvider(_query(11));
      container.listen(provider, (_, _) {});
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump(tobyPositionBudget);

      final busy = container.read(provider);
      expect(busy.status, TobyStatus.busy);
      expect(busy.reading?.isFinal, isFalse);
      final spent = repo.calls.length;

      container.read(provider.notifier).retry();
      expect(container.read(provider).status, TobyStatus.network);
      await tester.pump();
      expect(repo.calls, hasLength(spent + 1));
      expect(repo.calls.last.body['have'], 'network');
      container.dispose();
    });

    testWidgets('a request Gamebase cannot take is never sent', (tester) async {
      final repo = _FakeGamebase((_, _) => _reply(200, _payload()));
      final container = _container(repo);
      final provider = tobyReadingProvider(_query(tobyMaxMoves + 1));
      container.listen(provider, (_, _) {});
      await tester.pump(const Duration(seconds: 1));
      expect(container.read(provider).status, TobyStatus.notApplicable);
      expect(repo.calls, isEmpty);
      container.dispose();
    });

    testWidgets('no proxy key: unavailable at once, nothing asked', (
      tester,
    ) async {
      final repo = _FakeGamebase((_, _) => _reply(500), apiKey: null);
      final container = _container(repo);
      final provider = tobyReadingProvider(_query(2));
      container.listen(provider, (_, _) {});
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump();
      expect(container.read(provider).status, TobyStatus.unavailable);
      expect(repo.calls, isEmpty);
      container.dispose();
    });

    testWidgets('a nonsense answer reads as unavailable, once', (tester) async {
      final repo = _FakeGamebase((_, _) => _reply(200, {'moves': 'none'}));
      final container = _container(repo);
      final provider = tobyReadingProvider(_query(2));
      container.listen(provider, (_, _) {});
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump(const Duration(seconds: 30));
      expect(container.read(provider).status, TobyStatus.unavailable);
      expect(repo.calls, hasLength(1));
      container.dispose();
    });
  });

  group('the inputs shown before a reading', () {
    // The same cases as Gamebase's next-move-derive tests, which own the
    // rules; these only check the copy the panel shows until a reading
    // reports the inputs it used.
    TobyInputs expected({
      int? white,
      int? black,
      String? timeControl,
      String? category,
      String? site,
      String? event,
      int? rating,
      TobyCadence? cadence,
    }) => TobyInputs.expectedFor(
      TobyRequest(
        moves: const ['e2e4'],
        whiteRating: white,
        blackRating: black,
        timeControl: timeControl,
        category: category,
        site: site,
        event: event,
        ratingOverride: rating,
        cadenceOverride: cadence,
      ),
    );

    test('ratings: rounded to 10, one side mirrors the other, none is '
        'unknown', () {
      expect(
        expected(white: 2783, black: 2706, timeControl: '5400+30'),
        const TobyInputs(
          whiteRating: 2780,
          blackRating: 2710,
          ratingsKnown: true,
          cadence: TobyCadence.classical,
          ratingSource: 'FIDE',
          baseTimeSeconds: 5400,
          incrementSeconds: 30,
        ),
      );
      final mirrored = expected(black: 2655, timeControl: '5400+30');
      expect((mirrored.whiteRating, mirrored.blackRating), (2660, 2660));
      expect(mirrored.ratingsKnown, isTrue);
      final unknown = expected(white: 0);
      expect(unknown.ratingsKnown, isFalse);
      expect(unknown.label, 'Ratings unknown · Classical');
      expect(expected(white: 4, black: 3600).whiteRating, 1);
    });

    test('cadence: the speed label, then the clock, else classical', () {
      TobyCadence cadence({String? timeControl, String? category}) =>
          expected(timeControl: timeControl, category: category).cadence;
      expect(cadence(category: 'Bullet'), TobyCadence.blitz);
      expect(
        cadence(category: 'Blitz', timeControl: '5400+30'),
        TobyCadence.blitz,
      );
      expect(cadence(category: 'Rapid'), TobyCadence.rapid);
      expect(cadence(category: 'Standard'), TobyCadence.classical);
      expect(cadence(timeControl: '180+2'), TobyCadence.blitz);
      expect(cadence(timeControl: '600'), TobyCadence.blitz);
      expect(cadence(timeControl: '900+10'), TobyCadence.rapid);
      expect(cadence(timeControl: '15+10'), TobyCadence.rapid);
      expect(cadence(timeControl: '40/7200:3600'), TobyCadence.classical);
      expect(cadence(category: '15+10'), TobyCadence.rapid);
      expect(cadence(timeControl: '?'), TobyCadence.classical);
      expect(cadence(timeControl: 'G/90'), TobyCadence.classical);
      expect(cadence(), TobyCadence.classical);
      final clock = expected(timeControl: '40/5400+30:1800+30');
      expect((clock.baseTimeSeconds, clock.incrementSeconds), (5400, 30));
      final huge = expected(timeControl: '99999+999');
      expect((huge.baseTimeSeconds, huge.incrementSeconds), (null, null));
    });

    test('online games read in their site\'s pool and bands; a Lichess '
        'broadcast is over the board', () {
      TobyInputs lichess(String timeControl, [String? event]) => expected(
        site: 'https://lichess.org/xyz',
        timeControl: timeControl,
        event: event,
        white: 2500,
      );
      expect(lichess('60+0').ratingSource, 'Lichess Blitz');
      expect(lichess('60+0').baseTimeSeconds, 60);
      expect(lichess('600+0').cadence, TobyCadence.rapid);
      expect(lichess('1800+20').ratingSource, 'Lichess Classical');
      expect(
        lichess('600+0', 'Rated Blitz game').ratingSource,
        'Lichess Blitz',
      );
      TobyInputs chessCom(String timeControl) =>
          expected(site: 'Chess.com', timeControl: timeControl);
      expect(chessCom('180+1').ratingSource, 'Chess.com Blitz');
      expect(chessCom('600').ratingSource, 'Chess.com Rapid');
      expect(chessCom('1/86400').ratingSource, 'FIDE');
      expect(
        expected(
          site: 'https://lichess.org/broadcast/wijk/round-1/abc',
          timeControl: '6000+30',
        ).ratingSource,
        'FIDE',
      );
    });

    test('what-if choices: a rating is FIDE for both, another cadence drops '
        'the clock', () {
      final rated = expected(
        site: 'https://lichess.org/xyz',
        timeControl: '180+2',
        white: 2900,
        black: 2850,
        rating: 1600,
      );
      expect(rated.label, '1600 v 1600 · Blitz');
      expect(rated.ratingSource, 'FIDE');
      expect(rated.baseTimeSeconds, 180);
      final classical = expected(
        site: 'https://lichess.org/xyz',
        timeControl: '180+2',
        cadence: TobyCadence.classical,
      );
      expect(classical.label, 'Ratings unknown · Classical');
      expect(classical.ratingSource, 'Lichess Classical');
      expect(classical.baseTimeSeconds, isNull);
    });
  });

  group('the request', () {
    test('sends the raw game facts and only the keys Gamebase knows', () {
      final request = TobyRequest(
        startFen: '  8/8/8/8/8/8/4k3/4K3 w - - 0 1 ',
        moves: const ['e1d1'],
        whiteRating: 0,
        blackRating: 2105,
        timeControl: ' 15+10 ',
        category: '',
        site: 'https://lichess.org/abcd',
        event: 'Rated rapid game',
        ratingOverride: 2000,
        cadenceOverride: TobyCadence.rapid,
      );
      expect(request.toBody(session: _session, have: TobyHave.network), {
        'version': 2,
        'session': _session,
        'have': 'network',
        'fen': '8/8/8/8/8/8/4k3/4K3 w - - 0 1',
        'moves': ['e1d1'],
        'game': {
          'whiteRating': null,
          'blackRating': 2105,
          'timeControl': '15+10',
          'category': null,
          'site': 'https://lichess.org/abcd',
          'event': 'Rated rapid game',
        },
        'overrides': {'rating': 2000, 'timeControl': 'rapid'},
      });
    });

    test('the standard start and empty overrides are left out', () {
      final body = TobyRequest(
        startFen: kInitialFEN,
        moves: const [],
      ).toBody(session: _session, have: TobyHave.none);
      expect(body.keys, ['version', 'session', 'have', 'moves', 'game']);
    });

    test('equal positions are equal keys, whatever the panel', () {
      final a = TobyRequest(moves: const ['e2e4'], whiteRating: 2500);
      final b = TobyRequest(moves: ['e2e4'], whiteRating: 2500);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.cacheKey.contains('session'), isFalse);
      expect(a.cacheKey.contains('have'), isFalse);
      expect(
        TobyQuery(request: a, session: _session),
        TobyQuery(request: b, session: _session),
      );
      expect(
        TobyQuery(request: a, session: _session) ==
            TobyQuery(request: b, session: 'panel-test-0002'),
        isFalse,
      );

      final whatIf = a.copyWith(cadenceOverride: TobyCadence.blitz);
      expect(whatIf == a, isFalse);
      expect(whatIf.copyWith(cadenceOverride: null), a);
      expect(whatIf.copyWith(ratingOverride: 1600).cadenceOverride, isNotNull);
    });

    test('game facts outside what Gamebase accepts are trimmed to fit', () {
      // An over-long tag cut at its limit, and one whose limit falls inside
      // an emoji (a surrogate pair is never split).
      final event = 'E' * 1200;
      final site = '${'s' * 999}\u{1F600}tail';
      final request = TobyRequest(
        moves: const ['e2e4'],
        whiteRating: 99999,
        blackRating: tobyMaxRating,
        timeControl: '${'40/5400+30:' * 20}1800+30',
        category: 'C' * 200,
        site: site,
        event: event,
      );
      expect(request.whiteRating, isNull);
      expect(request.blackRating, tobyMaxRating);
      expect(request.timeControl!.length, tobyMaxCadenceTextLength);
      expect(request.timeControl, startsWith('40/5400+30:'));
      expect(request.category!.length, tobyMaxCadenceTextLength);
      expect(request.event!.length, tobyMaxSourceTextLength);
      expect(request.site, 's' * 999);
      expect(request.isSupported, isTrue);
      expect(tobyRating(tobyMaxRating + 1), isNull);
      expect(tobyRating(1), 1);
      expect(tobyRating(0), isNull);
      expect(tobyRating(-5), isNull);
    });

    test('session ids fit what Gamebase accepts', () {
      final pattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
      for (var i = 0; i < 20; i++) {
        expect(newTobySession(), matches(pattern));
      }
      expect(newTobySession() == newTobySession(), isFalse);
    });

    test('Toby reads standard chess only', () {
      expect(tobyReadsVariant(null), isTrue);
      expect(tobyReadsVariant('Standard'), isTrue);
      for (final variant in [
        'Chess960',
        'Fischerandom',
        'Crazyhouse',
        'Three-check',
        'King of the Hill',
        'Racing Kings',
      ]) {
        expect(tobyReadsVariant(variant), isFalse, reason: variant);
      }
    });
  });

  group('the reading', () {
    test('parses, sorts by probability, and formats', () {
      final reading = TobyReading.fromJson(_payload())!;
      expect(reading.isFinal, isTrue);
      expect(reading.sideToMove, Side.white);
      expect(reading.candidates.map((c) => c.san), ['e4', 'd4']);
      final top = reading.candidates.first;
      expect(top.percentage, '71.0%');
      expect(top.priorDiffers, isTrue);
      expect(reading.candidate('d2d4')!.priorDiffers, isTrue);
      expect(top.wdl!.percentages, (white: 30, draw: 55, black: 15));
      expect(reading.positionWdl!.percentages, (
        white: 28,
        draw: 57,
        black: 15,
      ));
      expect(reading.otherMoveCount, 18);
      expect(reading.inputs!.label, '2650 v 2610 · Classical');
      expect(tobyPercentage(0.0004), '<0.1%');
      expect(tobyPercentage(0), '0.0%');
      // A certainty drops its decimal so it fits the column "99.9%" does.
      expect(tobyPercentage(1), '100%');
      expect(tobyPercentage(0.9996), '100%');
      expect(tobyPercentage(0.9994), '99.9%');
    });

    test('unknown ratings read as such', () {
      final json = _payload()
        ..['inputs'] = {
          'whiteRating': 2000,
          'blackRating': 2000,
          'ratingsKnown': false,
          'timeControl': 'rapid',
          'ratingSource': 'FIDE',
          'baseTimeSeconds': null,
          'incrementSeconds': null,
        };
      expect(
        TobyReading.fromJson(json)!.inputs!.label,
        'Ratings unknown · Rapid',
      );
    });

    test('outcomes in per mille are normalised, and add up to 100', () {
      final wdl = TobyWdl.fromJson({'white': 333, 'draw': 333, 'black': 334})!;
      expect(wdl.white + wdl.draw + wdl.black, closeTo(1, 1e-9));
      final shown = wdl.percentages;
      expect(shown.white + shown.draw + shown.black, 100);
    });

    test('the verdict rounds the same way in every client and adds up to '
        '100', () {
      ({int white, int draw, int black}) shown(double w, double d, double b) =>
          TobyWdl(white: w, draw: d, black: b).percentages;
      // Rounded separately this would be 31 + 47 + 23 = 101.
      expect(shown(0.305, 0.465, 0.23), (white: 31, draw: 46, black: 23));
      // 0.145 is 14.4999… percent in floating point and 0.855 is 85.5; each
      // is first rounded to a thousandth of a percent, so the two halves tie
      // and the point goes to Draw, as it does wherever the arithmetic
      // differs.
      expect(shown(0, 0.145, 0.855), (white: 0, draw: 15, black: 85));
      expect(shown(0.005, 0.035, 0.96), (white: 1, draw: 3, black: 96));
      // Ties go to White, then Draw, then Black.
      expect(shown(0.335, 0.335, 0.33), (white: 34, draw: 33, black: 33));
      expect(shown(0.3, 0.355, 0.345), (white: 30, draw: 36, black: 34));
      expect(shown(1 / 3, 1 / 3, 1 / 3), (white: 34, draw: 33, black: 33));
      for (var i = 0; i < 200; i++) {
        final w = (i * 37 % 101) / 100;
        final d = (1 - w) * ((i * 13 % 97) / 96);
        final total = shown(w, d, 1 - w - d);
        expect(total.white + total.draw + total.black, 100, reason: '$i');
      }
    });

    test('a half-valid reading is never shown', () {
      Map<String, dynamic> broken(void Function(Map<String, dynamic>) edit) {
        final json = _payload();
        edit(json);
        return json;
      }

      expect(
        TobyReading.fromJson(broken((json) => json['stage'] = 'maybe')),
        isNull,
      );
      expect(
        TobyReading.fromJson(
          broken((json) => (json['moves'] as List).first['probability'] = 1.5),
        ),
        isNull,
      );
      expect(
        TobyReading.fromJson(
          broken((json) => (json['moves'] as List).first['uci'] = 'P@e4'),
        ),
        isNull,
      );
      expect(
        TobyReading.fromJson(broken((json) => json['positionWdl'] = 'even')),
        isNull,
      );
      expect(
        TobyReading.fromJson(broken((json) => json.remove('sideToMove'))),
        isNull,
      );
    });

    test('answers map to what the loop does next', () {
      expect(
        interpretTobyReply(_reply(200, _payload())),
        isA<TobyReplyReading>().having(
          (outcome) => outcome.reading.isFinal,
          'final',
          isTrue,
        ),
      );
      expect(
        interpretTobyReply(_reply(202, _payload(stage: 'network'))),
        isA<TobyReplyReading>().having(
          (outcome) => outcome.reading.isFinal,
          'final',
          isFalse,
        ),
      );
      expect(
        interpretTobyReply(
          _reply(202, {'status': 'pending', 'reason': 'busy'}),
        ),
        isA<TobyReplyPending>().having(
          (outcome) => outcome.wait,
          'wait',
          const Duration(seconds: 2),
        ),
      );
      expect(
        interpretTobyReply(
          _reply(202, {
            'status': 'pending',
            'reason': 'queued',
          }, const Duration(seconds: 3)),
        ),
        isA<TobyReplyPending>().having(
          (outcome) => outcome.wait,
          'wait',
          const Duration(seconds: 3),
        ),
      );
      expect(
        interpretTobyReply(_reply(401, {'error': 'unauthorized'})),
        isA<TobyReplyDenied>().having((o) => o.signIn, 'signIn', isTrue),
      );
      expect(
        interpretTobyReply(_reply(403, {'error': 'premium_required'})),
        isA<TobyReplyDenied>().having((o) => o.signIn, 'signIn', isFalse),
      );
      expect(
        interpretTobyReply(_reply(403, {'error': 'unauthorized'})),
        isA<TobyReplyDenied>().having((o) => o.signIn, 'signIn', isTrue),
      );
      expect(
        interpretTobyReply(_reply(403)),
        isA<TobyReplyDenied>().having((o) => o.signIn, 'signIn', isFalse),
      );
      for (final status in [429, 502, 503, 504]) {
        expect(
          interpretTobyReply(_reply(status)),
          isA<TobyReplyFailed>().having((o) => o.retryable, 'retryable', true),
        );
      }
      expect(
        interpretTobyReply((statusCode: null, data: null, retryAfter: null)),
        isA<TobyReplyFailed>().having((o) => o.retryable, 'retryable', true),
      );
      for (final status in [204, 400, 404]) {
        expect(
          interpretTobyReply(_reply(status)),
          isA<TobyReplyFailed>().having((o) => o.retryable, 'retryable', false),
        );
      }
    });

    test('the memory keeps the 256 most recently used readings', () {
      final cache = TobyReadingCache(3);
      final reading = TobyReading.fromJson(_payload())!;
      for (final key in ['a', 'b', 'c']) {
        cache.store(key, reading);
      }
      expect(cache.lookup('a'), same(reading));
      cache.store('d', reading);
      expect(cache.lookup('b'), isNull);
      expect(cache.lookup('a'), same(reading));
      expect(cache.length, 3);
      expect(tobyReadingCache.capacity, 256);
    });
  });

  group('the repository call', () {
    late RequestOptions sent;

    GamebaseRepository repositoryAnswering(
      void Function(RequestOptions, RequestInterceptorHandler) answer,
    ) {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              sent = options;
              answer(options, handler);
            },
          ),
        );
      return GamebaseRepository(
        dio,
        baseUrl: 'http://example.test',
        apiKey: 'test-key',
      );
    }

    test('waits longer than a held poll on every platform', () async {
      final repository = repositoryAnswering(
        (options, handler) => handler.resolve(
          Response<Object?>(
            requestOptions: options,
            statusCode: 202,
            data: {'status': 'pending', 'reason': 'queued'},
            headers: Headers.fromMap({
              'retry-after': ['1'],
            }),
          ),
        ),
      );
      final reply = await repository.getTobyReading(
        TobyRequest(
          moves: const ['e2e4'],
        ).toBody(session: _session, have: TobyHave.none),
        CancelToken(),
      );

      expect(sent.path, 'http://example.test/api/next-move');
      expect(sent.method, 'POST');
      expect(sent.receiveTimeout, GamebaseRepository.tobyReceiveTimeout);
      expect(
        GamebaseRepository.tobyReceiveTimeout,
        greaterThanOrEqualTo(const Duration(seconds: 12)),
      );
      expect(sent.headers.containsKey('Cache-Control'), isFalse);
      expect(reply.statusCode, 202);
      expect(reply.retryAfter, const Duration(seconds: 1));
      expect(reply.data!['reason'], 'queued');
    });

    test(
      'a refusal comes back as its status, and a re-check skips caches',
      () async {
        final repository = repositoryAnswering(
          (options, handler) => handler.reject(
            DioException.badResponse(
              statusCode: 403,
              requestOptions: options,
              response: Response<Object?>(
                requestOptions: options,
                statusCode: 403,
                data: {'error': 'premium_required'},
              ),
            ),
          ),
        );
        final reply = await repository.getTobyReading(
          TobyRequest(
            moves: const [],
          ).toBody(session: _session, have: TobyHave.none),
          CancelToken(),
          recheckAccess: true,
        );
        expect(sent.headers['Cache-Control'], 'no-cache');
        expect(reply.statusCode, 403);
        expect(reply.data!['error'], 'premium_required');
        expect(interpretTobyReply(reply), isA<TobyReplyDenied>());
      },
    );
  });
}
