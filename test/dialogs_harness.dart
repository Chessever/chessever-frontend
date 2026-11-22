// Group G5 ("dialogs") of the popup sweep: the dialogs that bypass the alert
// modal, and the tooltips, bubbles, lightboxes and stages around them, each
// opened over a busy Today-like page of live boards.
//
// Shared by dialogs_open_perf_test.dart and dialogs_glass_preview_test.dart.
// Only public entry points that exist both before and after the sweep are
// used, so the same scenes run on a scratch export of HEAD for the "before"
// numbers and renders.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/utils/board_feature_teaching_tracker.dart';
import 'package:chessever2/screens/chessboard/widgets/board_feature_teaching_host.dart';
import 'package:chessever2/screens/feed/race/race_screen.dart';
import 'package:chessever2/services/attention_policy.dart';
import 'package:chessever2/services/discovery_dots/discovery_dot.dart';
import 'package:chessever2/services/discovery_dots/discovery_dots_provider.dart';
import 'package:chessever2/services/forced_update_policy.dart';
import 'package:chessever2/services/phone_store_upgrader.dart';
import 'package:chessever2/services/phone_update_reminder.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/custom_upgrade_alert.dart';
import 'package:chessever2/widgets/discovery_dot.dart';
import 'package:chessever2/widgets/discovery_nudge_tooltip.dart';
import 'package:chessever2/widgets/paywall/premium_celebration_overlay.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/rewarded_access_ui.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/rewarded_interstitial_intro.dart';
import 'package:chessever2/widgets/phone_update_route_observer.dart';
import 'package:chessever2/widgets/profile_avatar_editor.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgrader/upgrader.dart';

const dialogsCapture = ValueKey('dialogs_capture');
const dialogsOpener = ValueKey('dialogs_opener');
const dialogsAnchor = ValueKey('dialogs_anchor');
const dialogsScreen = Size(393, 852);

const _fens = [
  'r1bqkb1r/pp3ppp/2nppn2/8/3NP3/2N5/PPP1BPPP/R1BQK2R w KQkq - 0 7',
  'rnbqk2r/ppp1bppp/4pn2/3p4/2PP4/2N2N2/PP2PPPP/R1BQKB1R w KQkq - 2 5',
  'r2q1rk1/pp1nbppp/2p1pn2/3p4/2PP4/1PN1PN2/PB3PPP/R2QKB1R w KQ - 1 9',
  'rn1qkb1r/pp2pppp/2p2n2/5b2/P1pP4/2N2N2/1P2PPPP/R1BQKB1R w KQkq - 1 6',
];

const _pairings = [
  ('GM Firouzja, Alireza', 2759, 'GM Caruana, Fabiano', 2795),
  ('GM Nakamura, Hikaru', 2802, 'GM Gukesh, D', 2777),
  ('GM Abdusattorov, Nodirbek', 2766, 'GM Erigaisi, Arjun', 2778),
  ('GM So, Wesley', 2741, 'GM Praggnanandhaa, R', 2758),
];

/// A Today-like column of live boards: the busiest thing these open over.
class DialogsBusyPage extends StatelessWidget {
  const DialogsBusyPage({super.key, this.anchor});

  /// Put in the page's header row (the discovery dot's anchor).
  final Widget? anchor;

  @override
  Widget build(BuildContext context) {
    const settings = BoardSettingsNew();
    final colors = context.colors;
    Widget player(String name, int rating, String clock) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$name  $rating',
              style: AppTypography.textSmMedium.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            clock,
            style: AppTypography.textSmMedium.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 12,
        16,
        120,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Today',
                style: AppTypography.textXlBold.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            ?anchor,
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _fens.length; i++) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                player(_pairings[i].$1, _pairings[i].$2, '1:42:10'),
                StaticChessboard(
                  size: 341,
                  orientation: Side.white,
                  fen: _fens[i],
                  settings: StaticChessboardSettings(
                    colorScheme: settings.colorScheme,
                    pieceAssets: settings.pieceAssets,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                player(_pairings[i].$3, _pairings[i].$4, '1:38:55'),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

/// One popup of the group: how its page is hosted, how it is opened, and
/// what shows once it is open.
class DialogScene {
  const DialogScene(
    this.name, {
    required this.open,
    required this.shown,
    this.close,
    this.firstPump = Duration.zero,
  });

  final String name;

  /// Pumps the host page (light or dark) and returns the opener. The
  /// opener starts the open synchronously, without pumping a frame.
  final Future<void Function()> Function(
    WidgetTester tester, {
    required bool light,
  })
  open;

  /// What is on screen once the popup is open.
  final Finder Function() shown;

  /// Takes the popup away (when leaving it open would hold state over to
  /// the next run), after the measurements.
  final Future<void> Function(WidgetTester tester)? close;

  /// How far the clock moves with the frame that opens it (a timer that
  /// opens it).
  final Duration firstPump;
}

void _view(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = dialogsScreen * 3;
  tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

/// Pumps [home] in the app's theme over the busy page; [home] gets the
/// page's context. Returns the opener's context once built.
Future<BuildContext> pumpDialogsHost(
  WidgetTester tester, {
  required bool light,
  List<Override> overrides = const [],
  Widget Function(Widget page)? wrapPage,
  Widget? anchor,
}) async {
  _view(tester);
  late BuildContext opener;
  await tester.pumpWidget(
    RepaintBoundary(
      key: dialogsCapture,
      child: ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              final page = Scaffold(
                body: Stack(
                  children: [
                    DialogsBusyPage(anchor: anchor),
                    Offstage(
                      child: Builder(
                        builder: (context) {
                          opener = context;
                          return const SizedBox(key: dialogsOpener);
                        },
                      ),
                    ),
                  ],
                ),
              );
              return wrapPage?.call(page) ?? page;
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await precacheDialogsPage(tester);
  return opener;
}

/// Decodes every picture on screen for real, so the page drawn is the
/// finished, busiest one.
Future<void> precacheDialogsPage(WidgetTester tester) async {
  await tester.runAsync(() async {
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
    final context = tester.element(find.byType(Scaffold).first);
    for (final widget in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(widget.image, context);
    }
    for (final box in tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    )) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration && decoration.image != null) {
        await precacheImage(decoration.image!.image, context);
      }
    }
  });
  await tester.pump();
  await tester.pump();
}

class _TeachingStore implements BoardFeatureTeachingStore {
  Map<String, Object?> value = {
    'visits': 2,
    'features': {
      'like': {'nextVisit': 3},
      'notationSwipe': {'nextVisit': 3},
    },
  };
  @override
  Future<Map<String, Object?>?> read() async => value;
  @override
  Future<void> write(Map<String, Object?> value) async => this.value = value;
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription()
    : super(SubscriptionState(isSubscribed: false, isLoading: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Reward extends RewardedAccessNotifier {
  @override
  Future<bool> unlock(BuildContext context) => Completer<bool>().future;
}

class _Upgrader extends PhoneStoreUpgrader {
  _Upgrader() : super(messages: CustomUpgraderMessages()) {
    updateState(
      state.copyWith(
        packageInfo: PackageInfo(
          appName: 'ChessEver',
          packageName: 'test.phone',
          version: '35.25.3',
          buildNumber: '3504',
        ),
      ),
    );
  }

  @override
  Future<bool> initialize() async {
    await updateVersionInfo();
    WidgetsBinding.instance.addObserver(this);
    return true;
  }

  @override
  Future<UpgraderVersionInfo?> updateVersionInfo() async {
    final info = UpgraderVersionInfo(
      appStoreVersion: Upgrader.parseVersion('35.25.4', 'test', false),
      releaseNotes: 'Faster popups, steadier boards.',
    );
    updateState(state.copyWith(versionInfo: info));
    return info;
  }

  @override
  String body(UpgraderMessages messages) => messages.body;

  @override
  bool alreadyIgnoredThisVersion() => false;

  @override
  Future<void> sendUserToAppStore() async {}
}

class _Policy implements ForcedUpdatePolicySource {
  @override
  Future<ForcedUpdatePolicy> load() async => ForcedUpdatePolicy.fallback;
  @override
  Stream<void> get changes => const Stream.empty();
}

class _DotsSource implements DiscoveryDotsSource {
  @override
  Future<String> initialize() async => _config;
  @override
  Future<String> fetch() async => _config;
  @override
  Stream<String> get updates => const Stream.empty();

  static const _config =
      '{"dots":[{"id":"sweep","rev":1,"target":"sweep.anchor",'
      '"message":"New: share any board as a picture from its menu."}]}';
}

class _SeenStore implements DiscoveryDotsSeenStore {
  Map<String, int> seen = {};
  @override
  Map<String, int> read() => seen;
  @override
  Future<void> write(Map<String, int> value) async => seen = value;
}

final _user = AppUser(
  id: 'sweep-user',
  displayName: 'Magnus Carlsen',
  avatarUrl: null,
  createdAt: DateTime(2026),
);

Future<Uint8List> _photo() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFF2E5E4E), BlendMode.src);
  canvas.drawCircle(
    const Offset(320, 260),
    150,
    Paint()..color = const Color(0xFFE8C9A0),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(640, 640);
  picture.dispose();
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

/// Every popup of the group.
final List<DialogScene> dialogScenes = [
  DialogScene(
    'race_stop',
    shown: () => find.text('End this run?'),
    open: (tester, {required light}) async {
      final context = await pumpDialogsHost(tester, light: light);
      return () => unawaited(confirmRaceStop(context, others: true));
    },
  ),
  DialogScene(
    'teaching',
    shown: () => find.text('Keep a game you like'),
    firstPump: const Duration(seconds: 5),
    open: (tester, {required light}) async {
      final store = _TeachingStore();
      final tracker = BoardFeatureTeachingTracker(store);
      var elapsed = Duration.zero;
      await pumpDialogsHost(
        tester,
        light: light,
        overrides: [
          boardFeatureTeachingTrackerProvider.overrideWithValue(tracker),
        ],
        wrapPage: (page) => BoardFeatureTeachingHost(
          elapsed: () => elapsed,
          isEligibleVisit: () => true,
          eligibleFeatures: () => {BoardTeachingFeature.like},
          child: page,
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.tapAt(const Offset(200, 400));
      }
      await tester.pump();
      return () => elapsed = const Duration(seconds: 30);
    },
  ),
  for (final expired in [false, true])
    DialogScene(
      expired ? 'rewarded_expired' : 'rewarded_choice',
      shown: () =>
          find.text(expired ? 'Your Premium time is up' : 'Unlock Premium'),
      open: (tester, {required light}) async {
        debugResetRewardedAccessChoice();
        final context = await pumpDialogsHost(
          tester,
          light: light,
          overrides: [
            subscriptionProvider.overrideWith((ref) => _Subscription()),
            rewardedAccessProvider.overrideWith((ref) => _Reward()),
          ],
        );
        return () => unawaited(
          showRewardedAccessChoice(
            context,
            expired: expired,
            upgrade: (_) async => false,
          ),
        );
      },
      close: (tester) async => debugResetRewardedAccessChoice(),
    ),
  DialogScene(
    'interstitial_intro',
    shown: () => find.text('Try another ad?'),
    open: (tester, {required light}) async {
      final context = await pumpDialogsHost(tester, light: light);
      return () => unawaited(showRewardedInterstitialIntro(context));
    },
  ),
  DialogScene(
    'update_prompt',
    shown: () => find.text('Update Available'),
    open: (tester, {required light}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final reminder = PhoneUpdateReminder(
        now: () => DateTime.utc(2026, 11, 20),
        preferences: () async => prefs,
      );
      final observer = PhoneUpdateRouteObserver();
      addTearDown(observer.dispose);
      final navigator = GlobalKey<NavigatorState>();
      final upgrader = _Upgrader();
      _view(tester);
      // Away from the app until the open: the check waits for a resume.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpWidget(
        RepaintBoundary(
          key: dialogsCapture,
          child: ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              navigatorKey: navigator,
              navigatorObservers: [observer],
              theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
              initialRoute: PhoneUpdateRouteObserver.homeRoute,
              routes: {
                PhoneUpdateRouteObserver.homeRoute: (_) =>
                    const Scaffold(body: DialogsBusyPage()),
              },
              builder: (context, child) {
                ResponsiveHelper.init(context);
                return CustomUpgradeAlert(
                  upgrader: upgrader,
                  navigatorKey: navigator,
                  routeObserver: observer,
                  reminder: reminder,
                  enabled: true,
                  policySource: _Policy(),
                  child: child!,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await precacheDialogsPage(tester);
      return () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
    },
  ),
  DialogScene(
    'nudge_tooltip',
    shown: () => find.text('1/2'),
    open: (tester, {required light}) async {
      final context = await pumpDialogsHost(
        tester,
        light: light,
        anchor: const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Icon(Icons.auto_awesome, key: dialogsAnchor, size: 24),
        ),
      );
      final box = tester.renderObject<RenderBox>(find.byKey(dialogsAnchor));
      final target = box.localToGlobal(Offset.zero) & box.size;
      return () => unawaited(
        showDiscoveryNudgeTooltip(
          context,
          target: target,
          messages: [
            DiscoveryNudgeMessage(
              body:
                  'Game Reports now mark the moment a game turned, with the '
                  'engine line that would have held.',
              actionUrl: Uri.parse('https://chessever.com/reports'),
            ),
            const DiscoveryNudgeMessage(body: 'Likes sync to the desktop app.'),
          ],
        ),
      );
    },
  ),
  DialogScene(
    'discovery_bubble',
    shown: () => find.text('New: share any board as a picture from its menu.'),
    open: (tester, {required light}) async {
      await pumpDialogsHost(
        tester,
        light: light,
        overrides: [
          discoveryDotsSourceProvider.overrideWithValue(_DotsSource()),
          discoveryDotsSeenStoreProvider.overrideWithValue(_SeenStore()),
          discoveryDotsDeliveryStoreProvider.overrideWithValue(_SeenStore()),
          accountCreatedAtProvider.overrideWithValue(DateTime.utc(2020)),
        ],
        anchor: DiscoveryDotAnchor(
          id: 'sweep.anchor',
          child: TextButton(
            key: dialogsAnchor,
            onPressed: () {},
            child: const Text('Share'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final at = tester.getCenter(find.byKey(dialogsAnchor));
      // A tap, delivered at once: the bubble opens on the pointer's up.
      return () {
        tester.binding.handlePointerEvent(
          PointerDownEvent(pointer: 91, position: at),
        );
        tester.binding.handlePointerEvent(
          PointerUpEvent(pointer: 91, position: at),
        );
      };
    },
  ),
  DialogScene(
    'avatar_lightbox',
    shown: () => find.text('Upload'),
    open: (tester, {required light}) async {
      final photo = await tester.runAsync(
        () async => prepareProfileAvatar(await _photo()),
      );
      final context = await pumpDialogsHost(
        tester,
        light: light,
        overrides: [
          currentUserProvider.overrideWithValue(_user),
          profileAvatarUrlProvider.overrideWithValue(null),
          subscriptionProvider.overrideWith((ref) => _Subscription()),
          profileAvatarPickerProvider.overrideWithValue(() async => photo),
        ],
      );
      return () => unawaited(showProfileAvatarEditor(context));
    },
  ),
  DialogScene(
    'celebration',
    shown: () => find.text('Welcome to Premium!'),
    open: (tester, {required light}) async {
      final context = await pumpDialogsHost(tester, light: light);
      return () => unawaited(showPremiumCelebration(context));
    },
    // Its own 3.5 s auto-dismiss: let it run out with the page gone, so no
    // review prompt follows.
    close: (tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
    },
  ),
];

/// Pumps until the springs and fades of the open have come to rest, at most
/// [limit] frames of 16 ms. Returns the frames pumped.
Future<int> settleDialogs(WidgetTester tester, {int limit = 240}) async {
  var frames = 0;
  while (tester.binding.hasScheduledFrame && frames < limit) {
    await tester.pump(const Duration(milliseconds: 16));
    frames++;
  }
  return frames;
}

/// The backdrop filters on screen that cover (nearly) the whole screen.
int fullScreenBlurs(WidgetTester tester) =>
    find.byType(BackdropFilter).evaluate().where((e) {
      final box = e.renderObject;
      if (box is! RenderBox || !box.hasSize) return false;
      return box.size.width >= dialogsScreen.width * 0.9 &&
          box.size.height >= dialogsScreen.height * 0.9;
    }).length;

/// Every system-channel call the scenes make (haptics, sounds) answered.
void muteDialogsPlatform(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (_) async => null,
  );
}
