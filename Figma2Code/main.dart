import 'package:flutter/material.dart';
import 'screens/input_design_screen.dart';
import 'screens/splash_auth_screen.dart';
import 'screens/tournament_list_screen.dart'; // <-- Import the list screen

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ChessEver',
      theme: ThemeData.dark(),
      initialRoute: '/',
      routes: {
        '/': (context) => const InputDesignScreen(),
        '/splash_auth': (context) => const SplashAuthScreen(),
        '/tournaments': (context) => const TournamentListScreen(), // <-- Show list, not details
      },
    );
  }
}
