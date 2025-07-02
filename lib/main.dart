import 'package:chessever2/l10n/app_localizations.dart';
import 'package:chessever2/localization/locale_provider.dart';
import 'package:chessever2/screens/authentication/auth_screen.dart';
import 'package:chessever2/screens/chessboard/ChessBoardScreen.dart';
import 'package:chessever2/screens/authentication/home_screen/home_screen.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/players/player_screen.dart';
import 'package:chessever2/screens/players/providers/player_providers.dart'; // Added import for player providers
import 'package:chessever2/screens/favorites/favorite_screen.dart';
import 'package:chessever2/screens/countryman_screen.dart';
import 'package:chessever2/screens/splash/splash_screen.dart';
import 'package:chessever2/screens/standings_screen.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_view.dart';
import 'package:chessever2/screens/tournaments/tournament_screen.dart';
import 'package:chessever2/screens/calendar_screen.dart';
import 'package:chessever2/services/notification_service.dart';
import 'package:chessever2/services/settings_manager.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:device_preview_plus/device_preview_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Load environment variables
  await dotenv.load(fileName: ".env");
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();

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
      builder: DevicePreview.appBuilder,
      debugShowCheckedModeBanner: false,
      title: 'ChessEver',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/splash': (context) => const SplashScreen(),
        '/auth_screen': (context) => const AuthScreen(),
        '/home_screen': (context) => const HomeScreen(),
        '/tournament_screen': (context) => const TournamentScreen(),
        '/tournament_detail_screen': (context) => const TournamentDetailView(),
        '/calendar_screen': (context) => const CalendarScreen(),
        '/library_screen': (context) => const LibraryScreen(),
        'analysisBoard': (context) => const ChessScreen(),

        // New Screen
        '/playerList': (context) => const PlayerScreen(),
        // Updated to use the navigation component
        '/favorites': (context) => const FavoriteScreen(),
        // Updated to use the new FavoriteScreen
        '/countryman_screen': (context) => const CountrymanScreen(),
        '/standings': (context) => const StandingsScreen(),
        // New route for Tournament Details screen
      },
    );
  }
}
