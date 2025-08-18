import 'package:chessever2/l10n/app_localizations.dart';
import 'package:chessever2/localization/locale_provider.dart';
import 'package:chessever2/screens/authentication/auth_screen.dart';
import 'package:chessever2/screens/calendar_detail_screen.dart';
import 'package:chessever2/screens/authentication/home_screen/home_screen.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:chessever2/screens/countryman_games_screen.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/players/player_screen.dart';
import 'package:chessever2/screens/players/providers/player_providers.dart';
import 'package:chessever2/screens/favorites/favorite_screen.dart';
import 'package:chessever2/screens/score_card/pages/score_card_page.dart';
import 'package:chessever2/screens/splash/splash_screen.dart';
import 'package:chessever2/screens/standings/standings_screen.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_screen.dart';
import 'package:chessever2/screens/tournaments/group_event_screen.dart';
import 'package:chessever2/screens/calendar_screen.dart';
import 'package:chessever2/services/notification_service.dart';
import 'package:chessever2/services/settings_manager.dart';
import 'package:chessever2/utils/lifecycle_event_handler.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/board_color_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';

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
  await NotificationService.initialize();

  WidgetsBinding.instance.addObserver(
    LifecycleEventHandler(
      onAppExit: () async {
        StockfishSingleton().dispose();
      },
    ),
  );
  await _initRevenueCat();
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
      SettingsManager.initializeSettings(ref);
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
        '/playerList': (context) => const PlayerScreen(),
        // Updated to use the navigation component
        '/favorites': (context) => const FavoriteScreen(),
        // Updated to use the new FavoriteScreen
        '/countryman_games_screen': (context) => const CountrymanGamesScreen(),
        '/standings': (context) => const StandingsScreen(),
        '/calendar_detail_screen': (context) => CalendarDetailsScreen(),
        // New route for Score Card
        '/Score_card': (context) => ScoreCard(),
        '/Board_sheet': (context) => BoardColorDialog(),
      },
    );
  }
}
