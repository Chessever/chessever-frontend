import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';
import 'screens/input_design_screen.dart';
import 'screens/splash_auth_screen.dart';
import 'screens/tournament_list_screen.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ChessEver',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      initialRoute: '/',
      routes: {
        '/': (context) => const InputDesignScreen(),
        '/splash_auth': (context) => const SplashAuthScreen(),
        '/tournaments': (context) => const TournamentListScreen(),
      },
    );
  }
}
