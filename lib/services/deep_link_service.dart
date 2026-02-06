import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/live_updates_service.dart';
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

  // Guards to prevent duplicate/concurrent navigation
  bool _isNavigating = false;
  String? _lastHandledGameId;
  DateTime? _lastHandledTime;

  // Debounce duration to prevent duplicate link events
  static const _debounceDuration = Duration(milliseconds: 500);

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

    String? gameId;

    // Universal link: https://chessever.com/games/<id>
    if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'games') {
      gameId = uri.pathSegments[1];
    }

    // Custom scheme: com.chessever.app://games/<id>
    if (gameId == null &&
        uri.host == 'games' &&
        uri.pathSegments.isNotEmpty) {
      gameId = uri.pathSegments[0];
    }

    if (gameId != null && gameId.isNotEmpty) {
      if (uri.queryParameters['stop_live'] == '1') {
        _stopLiveUpdates(gameId, ref);
      }
      _navigateToGame(gameId, navigatorKey, ref);
    }
  }

  void _stopLiveUpdates(String gameId, WidgetRef ref) {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    unawaited(LiveUpdatesService.instance.stopForGame(gameId, user.id));
  }

  /// Fetch game by ID and navigate to chess board screen
  Future<void> _navigateToGame(
    String gameId,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) async {
    // Guard: Prevent concurrent navigation
    if (_isNavigating) {
      debugPrint('DeepLinkService: Navigation already in progress, ignoring');
      return;
    }

    // Guard: Debounce duplicate links (same game within short time)
    final now = DateTime.now();
    if (_lastHandledGameId == gameId && _lastHandledTime != null) {
      final timeSinceLastHandle = now.difference(_lastHandledTime!);
      if (timeSinceLastHandle < _debounceDuration) {
        debugPrint('DeepLinkService: Duplicate link ignored (debounce)');
        return;
      }
    }

    // Update tracking
    _lastHandledGameId = gameId;
    _lastHandledTime = now;
    _isNavigating = true;

    // Check auth state - wait for loading to resolve so Universal Links stay in-app.
    AppAuthState? resolvedState = ref.read(authStateProvider).value;
    if (resolvedState == null) {
      try {
        resolvedState = await ref.read(authStateProvider.future);
      } catch (_) {
        resolvedState = null;
      }
    }

    if (resolvedState?.status != AppAuthStatus.authenticated) {
      debugPrint('DeepLinkService: User not authenticated yet, routing to home');
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/home_screen',
        (route) => false,
      );
      _isNavigating = false;
      return;
    }

    try {
      debugPrint('DeepLinkService: Fetching game: $gameId');

      // Fetch game from Supabase
      final gameRepo = ref.read(gameRepositoryProvider);
      final game = await gameRepo.getGameById(gameId);
      final gameTourModel = GamesTourModel.fromGame(game);

      debugPrint('DeepLinkService: Game loaded, navigating to chess board');

      // Navigate to chess board - pop all existing routes first to prevent stacking
      // This ensures we don't stack multiple game screens
      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        // Pop until we reach a route that's not a ChessBoardScreenNew
        // Then push the new game screen
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => ChessBoardScreenNew(
              games: [gameTourModel],
              currentIndex: 0,
            ),
          ),
          (route) {
            // Keep the home screen (first route) or any non-game screen
            // Remove any existing game screens to prevent stacking
            return route.isFirst;
          },
        );
      }
    } catch (e) {
      // On error, navigate to home screen silently
      debugPrint('DeepLinkService: Failed to load game: $e');
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/home_screen',
        (route) => false,
      );
    } finally {
      _isNavigating = false;
    }
  }

  /// Dispose of resources
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _isInitialized = false;
    _isNavigating = false;
    _lastHandledGameId = null;
    _lastHandledTime = null;
  }
}
