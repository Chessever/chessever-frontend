import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/studies/study_detail_screen.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../screens/studies/study_test_support.dart';

void main() {
  const version =
      'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  testWidgets('waits for readiness then opens an HTTPS Study without auth', (
    tester,
  ) async {
    final service = DeepLinkService.instance;
    service.dispose();
    final harness = await _pumpHarness(tester);
    addTearDown(service.dispose);

    service.handleDeepLink(
      Uri.parse(
        'https://chessever.com/studies/AbCd1234/chapters/Chapter1?ply=12&v=$version',
      ),
      harness.navigatorKey,
      harness.ref,
    );
    await tester.pump();

    expect(find.byType(StudyDetailScreen), findsNothing);
    expect(harness.repository.detailRequests, isEmpty);

    DeepLinkService.notifyAppReady();
    await tester.pumpAndSettle();

    final screen = tester.widget<StudyDetailScreen>(
      find.byType(StudyDetailScreen),
    );
    expect(screen.lichessStudyId, 'AbCd1234');
    expect(screen.chapterId, 'Chapter1');
    expect(screen.ply, 12);
    expect(screen.contentVersion, version);
    expect(harness.repository.detailRequests, <String>['AbCd1234']);
    expect(find.textContaining('Shared chapter 1'), findsOneWidget);
    expect(find.textContaining('sign in', findRichText: true), findsNothing);
  });

  testWidgets('recognizes the registered custom-scheme Study equivalent', (
    tester,
  ) async {
    final service = DeepLinkService.instance;
    service.dispose();
    final harness = await _pumpHarness(tester);
    addTearDown(service.dispose);
    DeepLinkService.notifyAppReady();

    service.handleDeepLink(
      Uri.parse(
        'com.chessever.app://studies/AbCd1234/chapters/Chapter1?ply=0&v=$version',
      ),
      harness.navigatorKey,
      harness.ref,
    );
    await tester.pumpAndSettle();

    expect(find.byType(StudyDetailScreen), findsOneWidget);
    expect(harness.repository.detailRequests, <String>['AbCd1234']);
    expect(find.textContaining('highlighted at ply 0'), findsOneWidget);
  });
}

class _Harness {
  const _Harness({
    required this.navigatorKey,
    required this.ref,
    required this.repository,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final WidgetRef ref;
  final _TrackingRepository repository;
}

class _TrackingRepository extends WidgetTestGamebaseRepository {
  _TrackingRepository()
    : super(
        studiesHandler:
            ({required filter, required limit, required offset}) =>
                Future<GamebaseStudiesPage>.error(
                  StateError('Studies list should not be requested'),
                ),
        detailHandler: (id) async => testStudyDetail(),
      );

  final List<String> detailRequests = <String>[];

  @override
  Future<GamebaseStudyDetail> getStudy(String lichessStudyId) {
    detailRequests.add(lichessStudyId);
    return super.getStudy(lichessStudyId);
  }
}

Future<_Harness> _pumpHarness(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 1100);
  addTearDown(tester.view.reset);

  final navigatorKey = GlobalKey<NavigatorState>();
  final repository = _TrackingRepository();
  late WidgetRef capturedRef;

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        gamebaseRepositoryProvider.overrideWithValue(repository),
      ],
      child: LiquidGlassWidgets.wrap(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              ResponsiveHelper.init(context);
              return const Scaffold(body: Text('Home'));
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  return _Harness(
    navigatorKey: navigatorKey,
    ref: capturedRef,
    repository: repository,
  );
}
