import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Service to handle deep links for game sharing.
/// Handles URLs like: `https://chessever.com/games/{id}`
class DeepLinkService {
  static final DeepLinkService instance = DeepLinkService._();
  DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  bool _isInitialized = false;

  /// Initialize the deep link service
  /// Should be called once after app startup when auth state is ready
  Future<void> initialize(
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Handle initial link (app opened from link when cold started)
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        _handleDeepLink(initialLink, navigatorKey, ref);
      }
    } catch (e) {
      debugPrint('DeepLinkService: Error getting initial link: $e');
    }

    // Listen for links while app is running (warm start / already open)
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => _handleDeepLink(uri, navigatorKey, ref),
      onError: (e) => debugPrint('DeepLinkService: Error listening to links: $e'),
    );
  }

  /// Parse and handle incoming deep link
  void _handleDeepLink(
    Uri uri,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) {
    debugPrint('DeepLinkService: Received link: $uri');

    // Parse: chessever.com/games/<id>
    // Path segments: ['games', '<id>']
    if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'games') {
      final gameId = uri.pathSegments[1];
      if (gameId.isNotEmpty) {
        _navigateToGame(gameId, navigatorKey, ref);
      }
    }
  }

  /// Fetch game by ID and navigate to chess board screen
  Future<void> _navigateToGame(
    String gameId,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) async {
    // Check auth state - allow authenticated AND anonymous users
    final authState = ref.read(authStateProvider);
    final status = authState.value?.status;

    // Only block truly unauthenticated users (not logged in at all)
    if (status != AppAuthStatus.authenticated) {
      debugPrint('DeepLinkService: Ignoring link - user not authenticated');
      return; // Ignore deep link - user will see auth screen
    }

    try {
      debugPrint('DeepLinkService: Fetching game: $gameId');

      // Fetch game from Supabase
      final gameRepo = ref.read(gameRepositoryProvider);
      final game = await gameRepo.getGameById(gameId);
      final gameTourModel = GamesTourModel.fromGame(game);

      debugPrint('DeepLinkService: Game loaded, navigating to chess board');

      // Navigate to chess board
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ChessBoardScreenNew(
            games: [gameTourModel],
            currentIndex: 0,
          ),
        ),
      );
    } catch (e) {
      // On error, navigate to home screen silently
      debugPrint('DeepLinkService: Failed to load game: $e');
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/home_screen',
        (route) => false,
      );
    }
  }

  /// Dispose of resources
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _isInitialized = false;
  }
}
