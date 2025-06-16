import 'package:chessever2/l10n/app_localizations.dart';
import 'package:chessever2/localization/locale_provider.dart';
import 'package:chessever2/screens/chessever_screen.dart';
import 'package:chessever2/screens/settings_screen.dart';
import 'package:chessever2/services/settings_manager.dart';
import 'package:device_preview_plus/device_preview_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';
import 'screens/input_design_screen.dart';
import 'screens/splash_auth_screen.dart';
import 'screens/tournament_list_screen.dart';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(
    DevicePreview(
      enabled: kDebugMode, // Changed to use kDebugMode
      builder: (context) => const ProviderScope(child: MyApp()),
    ),
  );
  FlutterNativeSplash.remove();
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

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
        '/': (context) => const ChesseverScreen(),
        '/input_screen': (context) => const InputDesignScreen(),
        '/splash_auth': (context) => const SplashAuthScreen(),
        '/tournaments': (context) => const TournamentListScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
