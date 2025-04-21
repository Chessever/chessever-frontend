// lib/app.dart
import 'package:flutter/material.dart';
import 'views/tournament_list_view.dart';
import 'theme/app_theme.dart'; // Assuming theme data is here

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chess Event Tracker',
      theme: AppTheme.lightTheme, // Define a default light theme
      darkTheme: AppTheme.darkTheme, // Define the dark theme
      themeMode: ThemeMode.dark, // Force dark mode as requested
      home: const TournamentListView(), // Start with View A
      debugShowCheckedModeBanner: false, // Optional: remove debug banner
    );
  }
}