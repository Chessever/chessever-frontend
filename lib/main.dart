import 'package:chessever2/l10n/app_localizations.dart';
import 'package:chessever2/localization/locale_provider.dart';
import 'package:chessever2/screens/authentication/auth_screen.dart';
import 'package:chessever2/screens/calendar/calendar_detail_screen.dart';
import 'package:chessever2/screens/home/home_screen.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/countryman_games_screen.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/players/player_screen.dart';
import 'package:chessever2/screens/players/providers/player_providers.dart';
import 'package:chessever2/screens/favorites/favorite_screen.dart';
import 'package:chessever2/screens/splash/splash_screen.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/tournament_detail_screen.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:chessever2/utils/notification_service.dart';
import 'package:chessever2/utils/lifecycle_event_handler.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/board_color_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:worker_manager/worker_manager.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load environment variables
  await dotenv.load(fileName: ".env");
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize worker manager with 75 isolates for parallel move evaluation
  await workerManager.init(isolatesCount: 75);

  await NotificationService.initialize();

  WidgetsBinding.instance.addObserver(
    LifecycleEventHandler(
      onAppExit: () async {
        StockfishSingleton().dispose();
      },
    ),
  );
  await AudioPlayerService.instance.initializeAndLoadAllAssets();
  await _initRevenueCat();

  // Clear evaluation cache to start fresh (remove all wrong evaluations)
  await _clearEvaluationCache();

  // Initialize Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(
    ProviderScope(child: MyApp()),
    // DevicePreview(
    //   enabled: kDebugMode, // Changed to use kDebugMode
    //   builder: (context) => const ProviderScope(child: MyApp()),
    // ),
  );
}

Future<void> _initRevenueCat() async {
  await Purchases.setDebugLogsEnabled(true); // Enable debug logs
  // final SupabaseClient = Supabase.instance.client;
  // final user = SupabaseClient.auth.currentUser;
  // await Purchases.setDebugLogsEnabled(true);
  await Purchases.configure(
    PurchasesConfiguration(dotenv.env['RevenueCatAPIKey'] ?? ''),
    // dotenv.env['RevenueCatAPIKey'] ?? '',
    // appUserId: '',
  );
}

/// Clears evaluation cache when cache version is updated
/// Update CACHE_VERSION number to trigger cache clearing
Future<void> _clearEvaluationCache() async {
  const int CACHE_VERSION = 3; // Update this number to clear cache
  const String versionKey = 'eval_cache_clear_version';
  const String evalPrefix = 'cloud_eval_';

  final prefs = await SharedPreferences.getInstance();
  final currentVersion = prefs.getInt(versionKey) ?? 0;

  if (currentVersion < CACHE_VERSION) {
    print('🧹 CLEARING EVALUATION CACHE: version $currentVersion -> $CACHE_VERSION');

    // Find and remove all evaluation cache entries
    final keys = prefs.getKeys().where((k) => k.startsWith(evalPrefix));
    int removedCount = 0;

    for (final key in keys) {
      await prefs.remove(key);
      removedCount++;
    }

    // Update version
    await prefs.setInt(versionKey, CACHE_VERSION);

    print('✅ Evaluation cache cleared: $removedCount entries removed, version updated to $CACHE_VERSION');
  } else {
    print('📁 Evaluation cache version $CACHE_VERSION is up to date');
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    // Initialize settings from persistent storage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialize the favorites service
      _initializeFavoritesService();
    });
  }

  // Initialize the favorites service
  Future<void> _initializeFavoritesService() async {
    // Initialize player favorites
    final playerViewModel = ref.read(playerViewModelProvider);
    await playerViewModel.initialize();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    ///Initializing  Responsive Unit
    ResponsiveHelper.init(context);

    return MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // builder: DevicePreview.appBuilder,
      debugShowCheckedModeBanner: false,
      title: 'ChessEver',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      navigatorObservers: [routeObserver],
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/auth_screen': (context) => const AuthScreen(),
        '/home_screen': (context) => const HomeScreen(),
        '/group_event_screen': (context) => const GroupEventScreen(),
        '/tournament_detail_screen':
            (context) => const TournamentDetailScreen(),
        '/calendar_screen': (context) => const CalendarScreen(),
        '/library_screen': (context) => const LibraryScreen(),
        // '/chess_screen': (context) => const ChessScreen(),

        // New Screen
        '/player_list_screen': (context) => const PlayerListScreen(),
        // Updated to use the navigation component
        '/favorites_screen': (context) => const FavoriteScreen(),
        // Updated to use the new FavoriteScreen
        '/countryman_games_screen': (context) => const CountrymanGamesScreen(),
        '/standings': (context) => const PlayerTourScreen(),
        '/calendar_detail_screen': (context) => CalendarDetailsScreen(),
        '/Board_sheet': (context) => BoardColorDialog(),
      },
    );
  }
}
