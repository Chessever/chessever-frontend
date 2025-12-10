import 'dart:async';
import 'dart:io';
import 'package:chessever2/localization/locale_provider.dart';
import 'package:chessever2/screens/authentication/auth_screen.dart';
import 'package:chessever2/screens/calendar/calendar_detail_screen.dart';
import 'package:chessever2/screens/favorites/favorite_screen.dart';
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:worker_manager/worker_manager.dart';
import 'package:clarity_flutter/clarity_flutter.dart';
import 'package:heroine/heroine.dart';
import 'package:upgrader/upgrader.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
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
      WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

      // Set orientation (non-blocking - not critical to wait for)
      unawaited(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]),
      );

      // Load environment variables first (only in debug mode)
      if (kDebugMode) {
        await dotenv.load(fileName: ".env");
      }

      // Add lifecycle observer
      WidgetsBinding.instance.addObserver(
        LifecycleEventHandler(
          onAppExit: () async {
            StockfishSingleton().dispose();
          },
        ),
      );

      // Parallelize all critical initialization tasks
      await Future.wait([
        // Critical: Required before app starts
        Supabase.initialize(
          url: _getEnv('SUPABASE_URL'),
          anonKey: _getEnv('SUPABASE_ANON_KEY'),
        ),
        // Platform-specific worker manager initialization
        if (Platform.isAndroid)
          workerManager.init(isolatesCount: 3)
        else if (Platform.isIOS)
          workerManager.init(isolatesCount: 6)
        else
          Future.value(),
        // Clear evaluation cache
        _clearEvaluationCache(),
        // Reset favorites for Supabase migration (one-time for beta users)
        _resetFavoritesForMigration(),
        // Initialize Amplitude (with error handling)
        AnalyticsService.instance.initialize(
          apiKey: _resolveAmplitudeApiKey(),
        ),
        // Initialize RevenueCat for subscriptions
        _initializeRevenueCat(),
      ]);

      // Non-critical: Load audio assets in background (don't block app startup)
      unawaited(AudioPlayerService.instance.initializeAndLoadAllAssets());

      await SentryFlutter.init(
        (options) {
          options.dsn = _getEnv('SENTRY_FLUTTER');
          options.sendDefaultPii = true;
        },
        appRunner:
            () => runApp(SentryWidget(child: ProviderScope(child: MyApp()))),
      );
    },
    (error, stackTrace) {
      Sentry.captureException(error, stackTrace: stackTrace);
    },
  );
}

/// Clears evaluation cache when cache version is updated
/// Update CACHE_VERSION number to trigger cache clearing
Future<void> _clearEvaluationCache() async {
  try {
    const int cacheVersion = 8; // v8: Force clear for eval bar perspective fix
    const String versionKey = 'eval_cache_clear_version';
    const String evalPrefix = 'cloud_eval_';

    final prefs = await SharedPreferences.getInstance();
    final currentVersion = prefs.getInt(versionKey) ?? 0;

    if (currentVersion < cacheVersion) {
      print(
        '🧹 CLEARING EVALUATION CACHE: version $currentVersion -> $cacheVersion',
      );

      // Find and remove all evaluation cache entries
      final keys = prefs.getKeys().where((k) => k.startsWith(evalPrefix));
      int removedCount = 0;

      for (final key in keys) {
        await prefs.remove(key);
        removedCount++;
      }

      // Update version
      await prefs.setInt(versionKey, cacheVersion);

      print(
        '✅ Evaluation cache cleared: $removedCount entries removed, version updated to $cacheVersion',
      );
    } else {
      print('📁 Evaluation cache version $cacheVersion is up to date');
    }
  } catch (e, _) {}
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
  } catch (e, st) {
    debugPrint('❌ Error initializing RevenueCat: $e');
    if (kDebugMode) {
      debugPrintStack(stackTrace: st);
    }
  }
}

/// Resets favorites system to clean state for Supabase migration
/// This is a one-time reset for beta users to ensure clean transition
Future<void> _resetFavoritesForMigration() async {
  try {
    const int migrationVersion = 4; // v4: Clear non-user-specific cache keys
    const String versionKey = 'favorites_reset_version';

    final prefs = await SharedPreferences.getInstance();
    final currentVersion = prefs.getInt(versionKey) ?? 0;

    if (currentVersion < migrationVersion) {
      print(
        '🧹 RESETTING FAVORITES: Migrating to Supabase-backed system (v$migrationVersion)',
      );

      // Old SharedPreferences-only keys to clear
      const oldKeys = [
        'favorite_players', // Old player favorites
        'current', // Old event favorites (current category)
        'upcoming', // Old event favorites (upcoming category)
        'past', // Old event favorites (past category)
        'cached_favorite_players_full', // Old cache key
        'cached_favorite_events', // Old non-user-specific event cache (now user-specific)
        'cached_favorite_players', // Old player cache
        'favorites_migration_complete_v1', // Old migration flag
      ];

      int removedCount = 0;
      for (final key in oldKeys) {
        if (prefs.containsKey(key)) {
          await prefs.remove(key);
          removedCount++;
        }
      }

      // Update version to prevent re-running
      await prefs.setInt(versionKey, migrationVersion);

      print(
        '✅ Favorites reset complete: $removedCount keys cleared. Users will need to re-favorite players/events.',
      );
      print('   New system uses Supabase + SharedPreferences cache.');
    } else {
      print('📁 Favorites migration version $migrationVersion is up to date');
    }
  } catch (e, st) {
    print('❌ Error resetting favorites: $e');
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

    final upgrader = useMemoized(
      () => Upgrader(
        messages: CustomUpgraderMessages(),
        durationUntilAlertAgain: const Duration(days: 1),
        debugDisplayAlways: kDebugMode,
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
          '/favorites_screen': (context) => const FavoriteScreen(),
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
