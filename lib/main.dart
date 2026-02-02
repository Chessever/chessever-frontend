import 'dart:async';
import 'dart:io';
import 'package:chessever2/localization/locale_provider.dart';
import 'package:chessever2/screens/authentication/auth_screen.dart';
import 'package:chessever2/screens/calendar/calendar_detail_screen.dart';
import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/home/home_screen.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
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
import 'package:chessever2/utils/lifecycle_event_handler.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/auth_state_listener.dart';
import 'package:chessever2/widgets/board_color_dialog.dart';
import 'package:chessever2/widgets/custom_upgrade_alert.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
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
import 'services/deep_link_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

// Global navigator key for upgrader dialog
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Helper function to get environment variables.
///
/// * In debug mode we load the `.env` file using `flutter_dotenv`.
/// * In CI/production we expect the values to be provided via `--dart-define`
///   flags (e.g. Codemagic build arguments).
///   See [_releaseEnvValues] for the list of required keys.
String _getEnv(String key) {
  if (kDebugMode) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw Exception('Missing env variable in .env file: $key');
    }
    return value;
  }

  final value = _releaseEnvValues[key];
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
};

String _resolveAmplitudeApiKey() {
  try {
    final envApiKey = _getEnv('AMPLITUDE');
    if (envApiKey.isNotEmpty) return envApiKey;
  } catch (_) {}
  return AnalyticsService.fallbackApiKey;
}

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsBinding widgetsBinding = SentryWidgetsFlutterBinding.ensureInitialized();
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

      // CRITICAL: Initialize SQLite database FIRST (replaces SharedPreferences for all app storage)
      // SQLite is now the primary storage for everything except Supabase auth token
      await AppDatabase.instance.database;

      // Load environment variables (only in debug mode)
      if (kDebugMode) {
        await dotenv.load(fileName: ".env");
      }

      // Get Supabase auth key name for cleanup exclusion
      final supabaseUrl = _getEnv('SUPABASE_URL');
      final supabaseHost = Uri.parse(supabaseUrl).host.split('.').first;
      final persistSessionKey = 'sb-$supabaseHost-auth-token';

      // ONE-TIME MIGRATION: Clean up all SharedPreferences except Supabase auth token
      // SQLite takes over from this version onwards (non-blocking with timeout)
      unawaited(_migrateToSqliteStorage(persistSessionKey));

      // Initialize SharedPreferences for Supabase auth only (with timeout, non-blocking)
      // If this fails, Supabase safe storage will fall back to memory
      unawaited(
        SharedPreferencesService.instance.initialize().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint('⚠️ SharedPreferences init timed out - using memory fallback for auth');
            return Future.value(null);
          },
        ).catchError((e) {
          debugPrint('⚠️ SharedPreferences init failed: $e');
          return null;
        }),
      );

      // Add lifecycle observer
      WidgetsBinding.instance.addObserver(
        LifecycleEventHandler(
          onAppExit: () async {
            StockfishSingleton().dispose();
          },
          onAppResume: () async {
            // Sync purchases when app comes to foreground
            final revenueCat = RevenueCatService();
            if (revenueCat.onAppResumeCallback != null) {
              unawaited(revenueCat.onAppResumeCallback!());
            } else {
              unawaited(revenueCat.syncPurchases());
            }
          },
        ),
      );

      // Initialize Supabase FIRST - this is critical and must complete
      // The SafeSupabaseLocalStorage has built-in 3s timeout for SharedPreferences
      final supabaseAnonKey = _getEnv('SUPABASE_ANON_KEY');
      final authOptions = FlutterAuthClientOptions(
        localStorage: SafeSupabaseLocalStorage(
          persistSessionKey: persistSessionKey,
        ),
        pkceAsyncStorage: SafeGotrueAsyncStorage(),
      );

      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        authOptions: authOptions,
      );

      // Non-critical initializers - run in parallel, don't block app startup
      unawaited(Future.wait([
        // Initialize Amplitude (with error handling)
        () async {
          try {
            await AnalyticsService.instance.initialize(
              apiKey: _resolveAmplitudeApiKey(),
            ).timeout(const Duration(seconds: 5));
          } catch (e) {
            debugPrint('⚠️ Analytics init failed: $e');
          }
        }(),
        // Initialize RevenueCat for subscriptions
        _initializeRevenueCat(),
      ]));

      // Initialize TerminateRestart (for user-triggered Shorebird updates only)
      TerminateRestart.instance.initialize();

      // Non-critical: Load audio assets in background (don't block app startup)
      unawaited(AudioPlayerService.instance.initializeAndLoadAllAssets());

      // Sentry init with timeout - don't let it block app startup indefinitely
      try {
        await SentryFlutter.init(
          (options) {
            options.dsn = _getEnv('SENTRY_FLUTTER');
            options.sendDefaultPii = true;

            // ========== PERFORMANCE OPTIMIZATIONS ==========
            // Disable performance tracing - causes frame drops
            options.tracesSampleRate = 0.0;
            options.profilesSampleRate = 0.0;
            options.enableAutoPerformanceTracing = false;
            options.enableUserInteractionTracing = false;

            // Disable expensive features that can block UI
            options.attachScreenshot = false;
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
          appRunner: () => runApp(ProviderScope(child: MyApp())),
        ).timeout(const Duration(seconds: 5), onTimeout: () {
          debugPrint('⚠️ SentryFlutter.init() timed out - starting app anyway');
          runApp(ProviderScope(child: MyApp()));
        });
      } catch (e) {
        debugPrint('⚠️ Sentry init failed: $e - starting app anyway');
        runApp(ProviderScope(child: MyApp()));
      }
    },
    (error, stackTrace) {
      // Wrap in try-catch to prevent recursive errors if Sentry itself fails
      try {
        // Use unawaited to make error capture non-blocking
        unawaited(
          Sentry.captureException(error, stackTrace: stackTrace).catchError((_) => SentryId.empty()),
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
      debugPrint('⚠️ SQLite Migration: SharedPreferences timed out, skipping cleanup');
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

    debugPrint('✅ SQLite Migration complete: Removed $removedCount old SharedPreferences keys');
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
    final apiKey = Platform.isIOS
        ? 'appl_hggBdZrNsqmMHEorxxxLYjyHTzz'
        : 'goog_ZmINjxirbMFvSsVMUfviZwrpfBY';

    await Purchases.configure(
      PurchasesConfiguration(apiKey)..appUserID = null,
    );
    debugPrint('✅ RevenueCat initialized successfully for ${Platform.isIOS ? 'iOS' : 'Android'}');

    // Sync purchases at app startup (non-blocking)
    unawaited(RevenueCatService().syncPurchases());
  } catch (e, st) {
    debugPrint('❌ Error initializing RevenueCat: $e');
    if (kDebugMode) {
      debugPrintStack(stackTrace: st);
    }
  }
}

class MyApp extends HookConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    /// Initializing Responsive Unit
    ResponsiveHelper.init(context);

    // Set orientation based on device type - tablets get landscape, phones stay portrait
    useEffect(() {
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
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) {
          return;
        }

        if (!kDebugMode) {
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
        }

        try {
          await _initializeFavoritesService(ref);
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('Failed to initialize favorites service: $e');
            debugPrintStack(stackTrace: st);
          }
        }

        // Initialize deep link handling for game sharing URLs
        try {
          await DeepLinkService.instance.initialize(navigatorKey, ref);
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint('Failed to initialize deep link service: $e');
            debugPrintStack(stackTrace: st);
          }
        }
      });

      return () => DeepLinkService.instance.dispose();
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
          '/player_selection_screen': (context) => const PlayerSelectionScreen(),
        },
      ),
    );
  }
}

Future<void> _initializeFavoritesService(WidgetRef ref) async {
  final playerViewModel = ref.read(playerViewModelProvider);
  await playerViewModel.initialize();
}
