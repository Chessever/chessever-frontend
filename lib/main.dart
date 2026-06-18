import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:logarte/logarte.dart';
import 'package:chessever2/e2e/e2e_config.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/localization/locale_provider.dart';
import 'package:chessever2/screens/authentication/auth_screen.dart';
import 'package:chessever2/screens/calendar/calendar_detail_screen.dart';
import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/home/home_screen.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:chessever2/screens/countryman_games_screen.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/players/player_screen.dart';
import 'package:chessever2/screens/players/providers/player_providers.dart';
import 'package:chessever2/screens/onboarding/onboarding_flow_screen.dart';
import 'package:chessever2/screens/onboarding/player_selection_screen.dart';
import 'package:chessever2/screens/splash/splash_screen.dart';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/tournament_detail_screen.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:chessever2/utils/lifecycle_event_handler.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/auth_state_listener.dart';
import 'package:chessever2/widgets/board_color_dialog.dart';
import 'package:chessever2/widgets/custom_upgrade_alert.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/local_storage/onboarding/onboarding_repository.dart';
import 'package:chessever2/repository/local_storage/sesions_manager/session_manager.dart';
import 'package:chessever2/repository/local_storage/supabase_safe_storage.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:terminate_restart/terminate_restart.dart';
import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:heroine/heroine.dart';
import 'package:upgrader/upgrader.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'revenue_cat_service/revenue_cat_service.dart';
import 'services/analytics/analytics_service.dart';
import 'services/appsflyer_service.dart';
import 'services/deep_link_service.dart';
import 'services/pgn_file_intake_service.dart';
import 'services/push_notifications_service.dart';
import 'theme/app_theme.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/providers/notification_permission_prompt_provider.dart';
import 'package:chessever2/providers/push_token_sync_provider.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

// Global navigator key for upgrader dialog
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Helper function to get environment variables.
///
/// * Prefer compile-time values provided via `--dart-define` or
///   `--dart-define-from-file`.
/// * In local debug runs we can still read an already-loaded `.env` via
///   `flutter_dotenv`, but `.env` must not be bundled as an app asset.
///   See [_releaseEnvValues] for the list of required keys.
String _getEnv(String key) {
  final releaseValue = _releaseEnvValues[key];
  if (releaseValue != null && releaseValue.isNotEmpty) {
    return releaseValue;
  }

  if (kDebugMode) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw Exception('Missing env variable in .env file: $key');
    }
    return value;
  }

  final value = releaseValue;
  if (value == null || value.isEmpty) {
    throw Exception(
      'Missing env variable "$key". '
      'Ensure you pass --dart-define=$key=... when building the app.',
    );
  }
  return value;
}

/// Compile-time environment values injected via `--dart-define`.
/// Codemagic example:
/// `flutter build apk --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY ...`
const Map<String, String> _releaseEnvValues = {
  'AMPLITUDE': String.fromEnvironment('AMPLITUDE', defaultValue: ''),
  'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL', defaultValue: ''),
  'SUPABASE_ANON_KEY': String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  ),
  'GOOGLE_WEB_CLIENT_ID': String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  ),
  'GOOGLE_IOS_CLIENT_ID': String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  ),
  'SENTRY_FLUTTER': String.fromEnvironment('SENTRY_FLUTTER', defaultValue: ''),
  'CLARITY_PROJECT_ID': String.fromEnvironment(
    'CLARITY_PROJECT_ID',
    defaultValue: '',
  ),
  'RevenueCatAPIKey': String.fromEnvironment(
    'RevenueCatAPIKey',
    defaultValue: '',
  ),
  'ONESIGNAL_APP_ID': String.fromEnvironment(
    'ONESIGNAL_APP_ID',
    defaultValue: '',
  ),
  'APPSFLYER_DEV_KEY': String.fromEnvironment(
    'APPSFLYER_DEV_KEY',
    defaultValue: '',
  ),
};

String _resolveAmplitudeApiKey() {
  try {
    final envApiKey = _getEnv('AMPLITUDE');
    if (envApiKey.isNotEmpty) return envApiKey;
  } catch (_) {}
  return AnalyticsService.fallbackApiKey;
}

String _resolveOneSignalAppId() {
  try {
    final envAppId = _getEnv('ONESIGNAL_APP_ID');
    if (envAppId.isNotEmpty) return envAppId;
  } catch (_) {}
  return '';
}

void _e2eStartupLog(String message) {
  if (!E2eConfig.isEnabled) {
    return;
  }

  final line = '[E2E][main] $message';
  try {
    final traceFile = File(
      '${Directory.systemTemp.path}/chessever_e2e_trace.log',
    );
    traceFile.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } catch (_) {}

  debugPrint(line);
}

Future<void> main() async {
  await runZonedGuarded(
    () async {
      _e2eStartupLog('runZonedGuarded entered');
      WidgetsBinding widgetsBinding;
      if (kDebugMode && !E2eConfig.isEnabled) {
        widgetsBinding = MarionetteBinding.ensureInitialized();
      } else if (E2eConfig.isEnabled) {
        widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
      } else {
        widgetsBinding = SentryWidgetsFlutterBinding.ensureInitialized();
      }
      _e2eStartupLog('binding initialized: ${widgetsBinding.runtimeType}');
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
      _e2eStartupLog('native splash preserved');

      FlutterError.onError = (details) {
        // Verbose, colorful, full-stacktrace console log (copy-paste ready).
        talker.handle(details.exception, details.stack, 'FlutterError.onError');
        // Keep feeding the in-app logarte overlay too.
        logarte.log(
          'FLUTTER ERROR: ${details.exception}',
          stackTrace: details.stack,
          source: 'FlutterError.onError',
        );
        FlutterError.presentError(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        talker.handle(error, stack, 'PlatformDispatcher.onError');
        logarte.log(
          'PLATFORM ERROR: $error',
          stackTrace: stack,
          source: 'PlatformDispatcher.onError',
        );
        return false; // Return false so the error continues to Sentry / runZonedGuarded
      };

      // Local debug builds may provide values through --dart-define-from-file.
      // If a developer still has a dotenv asset in a private local workflow,
      // load it opportunistically, but never require bundling .env.
      if (kDebugMode && !E2eConfig.isEnabled) {
        try {
          _e2eStartupLog('loading .env');
          await dotenv.load(fileName: ".env");
          _e2eStartupLog('.env loaded');
        } catch (_) {
          _e2eStartupLog('.env not bundled; using dart-define values only');
        }
      }

      // Sentry init with timeout - don't let it block app startup indefinitely
      try {
        _e2eStartupLog('starting SentryFlutter.init');
        await SentryFlutter.init(
          (options) {
            options.dsn = _getEnv('SENTRY_FLUTTER');
            options.sendDefaultPii = true;

            // ========== PERFORMANCE OPTIMIZATIONS ==========
            // Disable performance tracing - causes frame drops
            options.tracesSampleRate = 0.0;
            // ignore: experimental_member_use
            options.profilesSampleRate = 0.0;
            options.enableAutoPerformanceTracing = false;
            options.enableUserInteractionTracing = false;

            // Disable expensive features that can block UI
            options.attachScreenshot = false;
            // ignore: experimental_member_use
            options.attachViewHierarchy = false;

            // Limit breadcrumbs to reduce memory/processing overhead
            options.maxBreadcrumbs = 50;
            options.enableAutoNativeBreadcrumbs = false;
            options.enableUserInteractionBreadcrumbs = false;

            // Disable app lifecycle tracking overhead
            options.enableAutoSessionTracking = false;
            options.anrEnabled = false; // ANR detection can cause overhead

            // Sample rate for errors (1.0 = 100% of errors sent)
            options.sampleRate = 1.0;

            // ========== BUG FIXES ==========
            // Disable LoadContextsIntegration to avoid "type 'int' is not a subtype of type 'double?'"
            // error on Android when native layer returns int instead of double for device properties
            for (final integration in List.of(options.integrations)) {
              if (integration.runtimeType.toString() ==
                  'LoadContextsIntegration') {
                options.removeIntegration(integration);
              }
            }

            // Add beforeSend to catch any remaining errors and ensure non-blocking
            options.beforeSend = (event, hint) {
              // Let the event through - errors during processing are handled internally
              return event;
            };
          },
          // Don't use SentryWidget - it adds performance monitoring overhead
          // Just run the app directly
          appRunner: () => runApp(ProviderScope(child: StartupGate())),
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            _e2eStartupLog(
              'SentryFlutter.init timed out, running app directly',
            );
            debugPrint(
              '⚠️ SentryFlutter.init() timed out - starting app anyway',
            );
            runApp(ProviderScope(child: StartupGate()));
          },
        );
        _e2eStartupLog('SentryFlutter.init completed');
      } catch (e) {
        _e2eStartupLog('Sentry init failed: $e');
        debugPrint('⚠️ Sentry init failed: $e - starting app anyway');
        runApp(ProviderScope(child: StartupGate()));
      }
    },
    (error, stackTrace) {
      logarte.log(
        'GLOBAL ERROR: $error',
        stackTrace: stackTrace,
        source: 'runZonedGuarded',
      );
      // Wrap in try-catch to prevent recursive errors if Sentry itself fails
      try {
        // Use unawaited to make error capture non-blocking
        unawaited(
          Sentry.captureException(
            error,
            stackTrace: stackTrace,
          ).catchError((_) => SentryId.empty()),
        );
      } catch (_) {
        // Silently ignore Sentry errors - don't let monitoring break the app
      }
    },
  );
}

/// One-time migration: Clear all SharedPreferences except Supabase auth token
/// SQLite takes over all app storage from this version onwards
/// Has a timeout to prevent blocking if SharedPreferences is corrupted
Future<void> _migrateToSqliteStorage(String supabaseAuthKey) async {
  try {
    final db = AppDatabase.instance;
    const migrationKey = 'sqlite_migration_complete_v1';

    // Check if already migrated (stored in SQLite)
    final alreadyMigrated = await db.getBool(migrationKey) ?? false;
    if (alreadyMigrated) return;

    debugPrint('🔄 SQLite Migration: Cleaning up old SharedPreferences...');

    // Get SharedPreferences with timeout to prevent hang on corrupted prefs
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          throw TimeoutException('SharedPreferences.getInstance() timed out');
        },
      );
    } catch (e) {
      debugPrint(
        '⚠️ SQLite Migration: SharedPreferences timed out, skipping cleanup',
      );
      // Mark as migrated anyway - SQLite will be used going forward
      // Old corrupted prefs will just be ignored
      await db.setBool(migrationKey, true);
      return;
    }

    final allKeys = prefs.getKeys().toList();

    // Keys to preserve (Supabase auth related)
    final keysToPreserve = <String>{
      supabaseAuthKey,
      'flutter.$supabaseAuthKey', // Flutter prefix variant
    };

    int removedCount = 0;
    for (final key in allKeys) {
      // Preserve Supabase auth keys
      if (keysToPreserve.any((preserve) => key.contains(preserve))) {
        continue;
      }
      // Preserve any key containing 'auth-token' or 'supabase' for safety
      if (key.contains('auth-token') || key.contains('supabase')) {
        continue;
      }

      // Remove everything else
      try {
        await prefs.remove(key).timeout(const Duration(milliseconds: 500));
        removedCount++;
      } catch (_) {
        // Skip keys that timeout
      }
    }

    // Mark migration as complete in SQLite
    await db.setBool(migrationKey, true);

    debugPrint(
      '✅ SQLite Migration complete: Removed $removedCount old SharedPreferences keys',
    );
  } catch (e, st) {
    debugPrint('❌ SQLite Migration error: $e');
    if (kDebugMode) {
      debugPrintStack(stackTrace: st);
    }
    // Don't block app startup on migration errors
  }
}

/// Initialize RevenueCat for subscription management
Future<void> _initializeRevenueCat() async {
  try {
    // Platform-specific API keys
    final apiKey =
        Platform.isIOS
            ? 'appl_hggBdZrNsqmMHEorxxxLYjyHTzz'
            : 'goog_ZmINjxirbMFvSsVMUfviZwrpfBY';

    // If a Supabase session is already restored at boot, configure RC with
    // that UID directly. Without this, RC starts anonymous ($RCAnonymousID:…)
    // and any webhook fired before the auth-listener calls Purchases.logIn(uid)
    // arrives with the anonymous id — the affiliate webhook then can't match
    // it back to affiliate_referrals.referred_user_id and silently drops it.
    String? bootUserId;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final user = Supabase.instance.client.auth.currentUser;
      if (session != null && user != null && !session.isExpired) {
        bootUserId = user.id;
      }
    } catch (_) {}

    await Purchases.configure(
      PurchasesConfiguration(apiKey)..appUserID = bootUserId,
    );
    debugPrint(
      '✅ RevenueCat initialized for ${Platform.isIOS ? 'iOS' : 'Android'} '
      '(appUserID=${bootUserId ?? 'anonymous'})',
    );

    // Sync purchases at app startup (non-blocking)
    unawaited(RevenueCatService().syncPurchases());
  } catch (e, st) {
    debugPrint('❌ Error initializing RevenueCat: $e');
    if (kDebugMode) {
      debugPrintStack(stackTrace: st);
    }
  }
}

String _buildPersistSessionKey(String supabaseUrl) {
  final supabaseHost = Uri.parse(supabaseUrl).host.split('.').first;
  return 'sb-$supabaseHost-auth-token';
}

Future<void> _initializeSqliteWithRecovery() async {
  try {
    await AppDatabase.instance.database;
  } catch (e) {
    debugPrint('⚠️ SQLite init failed: $e');
    await AppDatabase.instance.reset();
    await AppDatabase.instance.database;
  }
}

Future<void> _sanitizeSupabasePersistedSession(String persistSessionKey) async {
  final prefs = await SharedPreferencesService.instance.ensureInitialized();
  if (prefs == null) return;

  final keys = <String>[persistSessionKey, 'flutter.$persistSessionKey'];

  for (final key in keys) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) continue;
    try {
      jsonDecode(raw);
    } catch (_) {
      await prefs.remove(key);
      debugPrint('🧹 Cleared corrupted Supabase session token: $key');
    }
  }
}

Future<void> _clearSupabasePersistedSession(String persistSessionKey) async {
  final prefs = await SharedPreferencesService.instance.ensureInitialized();
  if (prefs == null) return;
  await prefs.remove(persistSessionKey);
  await prefs.remove('flutter.$persistSessionKey');
}

bool _isSupabaseInitialized() {
  try {
    Supabase.instance.client;
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _initializeSupabaseWithRecovery({
  required String supabaseUrl,
  required String supabaseAnonKey,
  required String persistSessionKey,
}) async {
  if (_isSupabaseInitialized()) {
    return;
  }

  // Clean corrupted persisted sessions before init to avoid hard crashes.
  await _sanitizeSupabasePersistedSession(persistSessionKey);

  final authOptions = FlutterAuthClientOptions(
    localStorage: SafeSupabaseLocalStorage(
      persistSessionKey: persistSessionKey,
    ),
    pkceAsyncStorage: SafeGotrueAsyncStorage(),
  );

  Future<void> initialize() {
    return Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: authOptions,
    ).timeout(
      const Duration(seconds: 6),
      onTimeout: () {
        throw TimeoutException('Supabase.initialize timed out');
      },
    );
  }

  try {
    await initialize();
  } catch (e) {
    debugPrint('⚠️ Supabase init failed: $e');
    if (_isSupabaseInitialized()) {
      return;
    }
    // Retry once, but never clear auth storage here. A slow network or a
    // refresh race must not turn a valid persisted session into a logout.
    await initialize();
  }
}

Future<void> _initializeCoreServices() async {
  await _initializeSqliteWithRecovery();

  final supabaseUrl = _getEnv('SUPABASE_URL');
  final supabaseAnonKey = _getEnv('SUPABASE_ANON_KEY');
  final persistSessionKey = _buildPersistSessionKey(supabaseUrl);

  await _initializeSupabaseWithRecovery(
    supabaseUrl: supabaseUrl,
    supabaseAnonKey: supabaseAnonKey,
    persistSessionKey: persistSessionKey,
  );
}

Future<void> _bootstrapE2eSession(WidgetRef ref) async {
  if (!E2eConfig.isEnabled) {
    return;
  }

  if (!E2eConfig.hasCredentials) {
    throw StateError(
      'E2E mode requires E2E_TEST_EMAIL and E2E_TEST_PASSWORD dart defines.',
    );
  }

  final auth = Supabase.instance.client.auth;
  final sessionManager = ref.read(sessionManagerProvider);
  final onboardingRepository = ref.read(onboardingRepositoryProvider);

  try {
    await auth.signOut(scope: SignOutScope.local);
  } catch (_) {}

  await sessionManager.clearLocalStorage();

  final response = await auth.signInWithPassword(
    email: E2eConfig.testEmail.trim(),
    password: E2eConfig.testPassword,
  );

  final session = response.session;
  final user = response.user;
  if (session == null || user == null) {
    throw StateError('Supabase did not return an authenticated E2E session.');
  }

  await sessionManager.saveSession(session, user);

  if (E2eConfig.resetOnboarding) {
    await onboardingRepository.resetOnboarding(userId: user.id);
  } else {
    await onboardingRepository.markAsSeen(userId: user.id);
  }
}

void _initializePostStartupServices() {
  final supabaseUrl = _getEnv('SUPABASE_URL');
  final persistSessionKey = _buildPersistSessionKey(supabaseUrl);

  // ONE-TIME MIGRATION: Clean up all SharedPreferences except Supabase auth token
  unawaited(_migrateToSqliteStorage(persistSessionKey));

  // Add lifecycle observer
  WidgetsBinding.instance.addObserver(
    LifecycleEventHandler(
      onAppExit: () async {
        // Fully dispose the engine on background to free native resources.
        // On Android this prevents the OS from aggressively killing the app
        // due to background native thread activity. The engine will lazily
        // reinitialize on the next evaluatePosition() call after resume.
        //
        // IMPORTANT: Skip this in debug mode to prevent hot-restarts from
        // triggering native FFI teardowns that crash the VM (Service disappeared).
        if (!kDebugMode) {
          await StockfishSingleton().disposeAsync();
        }
      },
      onAppResume: () async {
        if (kDebugMode) {
          unawaited(
            Sentry.captureMessage(
              'app resumed while debugging share/deep link flow',
              level: SentryLevel.info,
              withScope: (scope) {
                scope.setTag('area', 'deep_link');
                scope.setTag('stage', 'app_resume');
                scope.setContexts('deep_link', {
                  'source': 'lifecycle_event_handler',
                });
              },
            ),
          );
        }
        // Engine was disposed on background — it will lazily reinitialize
        // on the next evaluatePosition() call. Only force recovery if a
        // stale engine reference remains in a broken state.
        ForegroundTaskScheduler.schedule(
          key: 'root_stockfish_recovery',
          delay: kForegroundHeavyRefreshDelay,
          task: () {
            final stockfish = StockfishSingleton();
            if (stockfish.requiresRecovery) {
              unawaited(stockfish.forceRecovery());
            } else if (!Platform.isAndroid) {
              unawaited(stockfish.warmUp());
            }
          },
        );

        // NOTE: We intentionally do NOT refresh the auth token on resume here.
        // The Supabase SDK already owns this: its lifecycle observer calls
        // startAutoRefresh() on AppLifecycleState.resumed, which fires an
        // immediate refresh tick (see supabase_flutter SupabaseAuth /
        // gotrue startAutoRefresh). A second manual auth.refreshSession() races
        // the SDK's refresh and can replay an already-rotated refresh token,
        // tripping GoTrue reuse-detection → whole-session-family revocation →
        // a forced "signedOut" the next time the SDK refreshes. Let the SDK be
        // the single refresh authority.

        ForegroundTaskScheduler.schedule(
          key: 'root_revenuecat_resume_sync',
          delay: kForegroundHeavyRefreshDelay,
          task: () {
            // Sync purchases when app comes to foreground.
            final revenueCat = RevenueCatService();
            if (revenueCat.onAppResumeCallback != null) {
              unawaited(revenueCat.onAppResumeCallback!());
            } else {
              unawaited(revenueCat.syncPurchases());
            }
          },
        );
      },
    ),
  );

  // Initialize OneSignal (non-blocking)
  if (!E2eConfig.suppressInterruptivePrompts) {
    unawaited(
      PushNotificationsService.instance.initialize(
        appId: _resolveOneSignalAppId(),
      ),
    );
  }

  // Non-critical initializers - run in parallel, don't block app startup
  unawaited(
    Future.wait([
      // Initialize Amplitude (with error handling)
      () async {
        try {
          await AnalyticsService.instance
              .initialize(apiKey: _resolveAmplitudeApiKey())
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint('⚠️ Analytics init failed: $e');
        }
      }(),
      // Initialize RevenueCat for subscriptions
      _initializeRevenueCat(),
    ]),
  );

  // Initialize TerminateRestart (for user-triggered Shorebird updates only)
  TerminateRestart.instance.initialize();

  ForegroundTaskScheduler.schedule(
    key: 'startup_audio_assets',
    // Past the splash→auth brand-logo assemble so SoLoud's native init stall
    // can't make the wall-clock logo controller skip frames. See
    // [kAudioWarmupDelay].
    delay: kAudioWarmupDelay,
    task: () => AudioPlayerService.instance.initializeAndLoadAllAssets(),
  );

  if (!Platform.isAndroid) {
    ForegroundTaskScheduler.schedule(
      key: 'startup_stockfish_warmup',
      delay: kStartupWarmupDelay + const Duration(seconds: 1),
      task: () => StockfishSingleton().warmUp(),
    );
  }
}

class StartupGate extends ConsumerStatefulWidget {
  const StartupGate({super.key});

  @override
  ConsumerState<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<StartupGate> {
  bool _ready = false;
  bool _inFlight = false;
  bool _postStartupInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startInitialization();
  }

  /// Tear down native resources before hot restart to prevent orphaned
  /// isolates/threads from blocking Flutter's reassemble mechanism.
  ///
  /// Any open Supabase Realtime WebSocket keeps a native socket + its Dart
  /// stream callback alive across the isolate swap — which is exactly what
  /// hangs "Performing hot restart…". Tear everything down synchronously
  /// before super.reassemble().
  /// Runs on both hot reload and hot restart (Flutter framework doesn't
  /// distinguish here). Must be safe for hot reload — any aggressive cleanup
  /// (provider invalidation, refresh cancellation flags, etc.) will visibly
  /// reset state that hot reload is supposed to preserve.
  ///
  /// Hot restart on mobile is a known Flutter limitation (issue #69949):
  /// widgets are NOT disposed, so native resources (Supabase WebSockets,
  /// Stockfish FFI, etc.) leak. We disconnect Supabase's realtime socket as
  /// a best-effort mitigation — Supabase Flutter itself does this on web via
  /// `hot_restart_cleanup_web.dart` but has a no-op stub on mobile.
  @override
  void reassemble() {
    StockfishSingleton().prepareForHotRestart();
    try {
      // Terminates the realtime WebSocket. On hot reload, a new socket gets
      // opened lazily when any `from().stream()` call fires again. On hot
      // restart, this prevents the old socket from lingering and causing
      // duplicate realtime events.
      Supabase.instance.client.realtime.disconnect();
    } catch (_) {}
    super.reassemble();
  }

  Future<void> _startInitialization() async {
    if (!mounted || _inFlight) return;
    _inFlight = true;
    setState(() {
      _errorMessage = null;
    });

    try {
      _e2eStartupLog('StartupGate: initializeCoreServices start');
      await _initializeCoreServices();
      _e2eStartupLog('StartupGate: initializeCoreServices done');
      _e2eStartupLog('StartupGate: bootstrapE2eSession start');
      await _bootstrapE2eSession(ref);
      _e2eStartupLog('StartupGate: bootstrapE2eSession done');
      if (!_postStartupInitialized) {
        _e2eStartupLog('StartupGate: initializePostStartupServices start');
        _initializePostStartupServices();
        _postStartupInitialized = true;
        _e2eStartupLog('StartupGate: initializePostStartupServices done');
      }
      if (!mounted) return;
      FlutterNativeSplash.remove();
      _e2eStartupLog('StartupGate: splash removed, app ready');
      setState(() {
        _ready = true;
      });
    } catch (e, st) {
      _e2eStartupLog('StartupGate: failed with $e');
      debugPrint('❌ Startup failed: $e');
      if (kDebugMode) {
        debugPrintStack(stackTrace: st);
      }
      FlutterNativeSplash.remove();
      if (!mounted) return;
      setState(() {
        _ready = false;
        _errorMessage = _friendlyStartupError(e);
      });
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _resetAndRetry() async {
    try {
      final supabaseUrl = _getEnv('SUPABASE_URL');
      final persistSessionKey = _buildPersistSessionKey(supabaseUrl);
      await AppDatabase.instance.reset();
      await _clearSupabasePersistedSession(persistSessionKey);
    } catch (e) {
      debugPrint('⚠️ Failed to reset local state: $e');
    }
    await _startInitialization();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return const MyApp();
    }

    if (_errorMessage != null) {
      return _StartupFailureApp(
        message: _errorMessage!,
        onRetry: _startInitialization,
        onResetAndRetry: _resetAndRetry,
      );
    }

    return const _StartupLoadingApp();
  }
}

String _friendlyStartupError(Object error) {
  if (error is TimeoutException) {
    return 'Startup timed out. Please check your connection and try again.';
  }
  return 'Startup failed. Please retry.';
}

class _StartupLoadingApp extends StatelessWidget {
  const _StartupLoadingApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        key: e2eKey(E2eIds.splashRoot),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/launch.webp',
              fit: BoxFit.cover,
              cacheWidth:
                  (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .toInt(),
              cacheHeight:
                  (MediaQuery.sizeOf(context).height *
                          MediaQuery.devicePixelRatioOf(context))
                      .toInt(),
            ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 64),
                child: CircularProgressIndicator(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({
    required this.message,
    required this.onRetry,
    required this.onResetAndRetry,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onResetAndRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/launch.webp',
              fit: BoxFit.cover,
              cacheWidth:
                  (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .toInt(),
              cacheHeight:
                  (MediaQuery.sizeOf(context).height *
                          MediaQuery.devicePixelRatioOf(context))
                      .toInt(),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 64,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white70,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 180,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: onRetry,
                        child: const Text('Retry'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 220,
                      height: 44,
                      child: OutlinedButton(
                        onPressed: onResetAndRetry,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white54),
                        ),
                        child: const Text('Reset Local Data & Retry'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Initialize logarte globally
// Console logs disabled — Talker owns the console so errors print once,
// verbose with full stacktrace. Logarte keeps the in-app overlay + network logs.
final logarte = Logarte(password: 'devr0ll', disableDebugConsoleLogs: true);

class MyApp extends HookConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Light theme is shelved — force dark mode app-wide regardless of any
    // previously persisted user preference. The themeModeProvider still
    // exists so the saved preference isn't wiped, but it's not consulted
    // here. Re-enable by restoring `ref.watch(themeModeProvider)`.
    // final themeMode = ref.watch(themeModeProvider);
    const themeMode = ThemeMode.dark;
    final locale = ref.watch(localeProvider);
    ref.watch(pushTokenSyncProvider);
    ref.watch(notificationPermissionPromptProvider);

    // Listen to auth state changes to set AppsFlyer Customer User ID and
    // ensure the install/launch event fires. startSdk is idempotent — for
    // new users who completed the onboarding ATT pre-prompt this is a no-op.
    // For users who skip onboarding by signing in directly from the welcome
    // page, this is the trigger that gets startSDK to fire so their install
    // is reported (without IDFA, since they bypassed the ATT prompt).
    ref.listen(authStateProvider, (previous, next) {
      final user = next.value?.user;
      if (user != null) {
        AppsflyerService.instance.setCustomerUserId(user.id);
        AppsflyerService.instance.startSdkIfNotYetStarted();
      }
    });

    /// Initializing Responsive Unit
    ResponsiveHelper.init(context);

    // Set orientation based on device type - tablets get landscape, phones stay portrait
    // Also ensure status bar is visible and UI is edge-to-edge
    useEffect(() {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
      );

      if (ResponsiveHelper.isTablet) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
      return null;
    }, const []);

    final upgrader = useMemoized(
      () => Upgrader(
        messages: CustomUpgraderMessages(),
        durationUntilAlertAgain: const Duration(days: 1),
        debugDisplayAlways: false,
        debugLogging: false,
      ),
      const [],
    );

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) {
          return;
        }

        // Handle OneSignal notification taps — route to correct screen.
        // Registered BEFORE DeepLinkService.initialize() so that clicks
        // queued during async I/O are not missed.
        OneSignal.Notifications.addClickListener((event) {
          final data = event.notification.additionalData;
          if (data != null) {
            DeepLinkService.instance.handleNotificationData(
              data,
              navigatorKey,
              ref,
            );
          }
        });

        ForegroundTaskScheduler.schedule(
          key: 'startup_deep_link_services',
          delay: const Duration(milliseconds: 250),
          task: () async {
            try {
              await DeepLinkService.instance.initialize(navigatorKey, ref);
              // Handle PGN files opened from Files / file managers / share sheet.
              await PgnFileIntakeService.instance.initialize(navigatorKey, ref);
              // Initialize AppsFlyer for marketing attribution and OneLink.
              await AppsflyerService.instance.initialize(navigatorKey, ref);
            } catch (e, st) {
              if (kDebugMode) {
                debugPrint(
                  'Failed to initialize deep link or appsflyer service: $e',
                );
                debugPrintStack(stackTrace: st);
              }
            }
          },
        );

        ForegroundTaskScheduler.schedule(
          key: 'startup_favorites_service',
          delay: kForegroundHeavyRefreshDelay,
          task: () async {
            try {
              await _initializeFavoritesService(ref);
            } catch (e, st) {
              if (kDebugMode) {
                debugPrint('Failed to initialize favorites service: $e');
                debugPrintStack(stackTrace: st);
              }
            }
          },
        );

        if (!kDebugMode) {
          ForegroundTaskScheduler.schedule(
            key: 'startup_clarity',
            delay: kStartupWarmupDelay,
            task: () {
              if (!context.mounted) return;
              try {
                final clarityConfig = ClarityConfig(
                  projectId: _getEnv('CLARITY_PROJECT_ID'),
                );

                final initialized = Clarity.initialize(context, clarityConfig);
                debugPrint('Clarity initialized: $initialized');
              } catch (e, st) {
                debugPrint('Failed to initialize Clarity: $e');
                debugPrintStack(stackTrace: st);
              }
            },
          );
        }
      });

      return () {
        DeepLinkService.instance.dispose();
        PgnFileIntakeService.instance.dispose();
      };
    }, const []);

    return AuthStateListener(
      navigatorKey: navigatorKey,
      child: MaterialApp(
        locale: locale,
        // supportedLocales: AppLocalizations.supportedLocales,
        // localizationsDelegates: AppLocalizations.localizationsDelegates,
        // builder: DevicePreview.appBuilder,
        debugShowCheckedModeBanner: false,
        title: 'ChessEver',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        navigatorKey: navigatorKey,
        navigatorObservers: [
          routeObserver,
          HeroineController(),
          AnalyticsService.instance.routeObserver,
        ],
        initialRoute: '/',
        builder:
            (context, child) => CustomUpgradeAlert(
              upgrader: upgrader,
              navigatorKey: navigatorKey,
              child: child ?? const SizedBox.shrink(),
            ),
        routes: {
          '/': (context) => const SplashScreen(),
          '/auth_screen': (context) => const AuthScreen(),
          '/home_screen': (context) => const HomeScreen(),
          '/group_event_screen': (context) => const GroupEventScreen(),
          '/tournament_detail_screen':
              (context) => const TournamentDetailScreen(),
          '/calendar_screen': (context) => const CalendarScreen(),
          '/library_screen': (context) => const LibraryScreen(),
          '/favorites_screen': (context) => const FavoritesTabScreen(),
          '/scorecard_screen': (context) => const ScoreCardScreen(),
          '/player_list_screen': (context) => const PlayerListScreen(),
          '/countryman_games_screen':
              (context) => const CountrymanGamesScreen(),
          '/standings': (context) => const PlayerTourScreen(),
          '/calendar_detail_screen': (context) => CalendarDetailsScreen(),
          '/Board_sheet': (context) => BoardColorDialog(),
          '/onboarding': (context) => const OnboardingFlowScreen(),
          '/player_selection_screen':
              (context) => const PlayerSelectionScreen(),
        },
      ),
    );
  }
}

Future<void> _initializeFavoritesService(WidgetRef ref) async {
  final playerViewModel = ref.read(playerViewModelProvider);
  await playerViewModel.initialize();
}
