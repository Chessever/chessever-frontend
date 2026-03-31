import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/book_preview_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/services/live_updates_service.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to handle deep links and notification tap routing.
/// Handles URLs like: `https://chessever.com/games/{id}`
/// Handles notification data routing for games, events, and rounds.
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

  /// Timeout for individual network fetches (game, event).
  static const _fetchTimeout = Duration(seconds: 10);

  /// Completer that resolves when the app navigates past the splash screen.
  /// Prevents deep link navigation from racing with splash screen navigation.
  static Completer<void> _appReadyCompleter = Completer<void>();

  /// Call after the splash screen has completed navigation.
  static void notifyAppReady() {
    if (!_appReadyCompleter.isCompleted) {
      _appReadyCompleter.complete();
    }
  }

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
        _addBreadcrumb(
          'cold-start link received',
          data: _sanitizedUriData(initialLink),
        );
        _handleDeepLink(initialLink, navigatorKey, ref);
      }
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Error getting initial link: $e');
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'get_initial_link',
      );
    }

    // Listen for links while app is running (warm start / already open)
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _addBreadcrumb(
          'warm-start link received',
          data: _sanitizedUriData(uri),
        );
        _handleDeepLink(uri, navigatorKey, ref);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('DeepLinkService: Error listening to links: $error');
        _captureDeepLinkException(
          error,
          stackTrace,
          stage: 'uri_link_stream',
        );
      },
    );
  }

  /// Parse and handle incoming deep link
  void _handleDeepLink(
    Uri uri,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) {
    debugPrint('DeepLinkService: Received link: $uri');

    try {
      String? gameId;
      String? bookShareToken;

      // Universal link: https://chessever.com/games/<id>
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'games') {
        gameId = uri.pathSegments[1];
      }

      // Universal link: https://chessever.com/books/<shareToken>
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'books') {
        bookShareToken = uri.pathSegments[1];
      }

      // Custom scheme: com.chessever.app://games/<id>
      if (gameId == null &&
          uri.host == 'games' &&
          uri.pathSegments.isNotEmpty) {
        gameId = uri.pathSegments[0];
      }

      // Custom scheme: com.chessever.app://books/<shareToken>
      if (bookShareToken == null &&
          uri.host == 'books' &&
          uri.pathSegments.isNotEmpty) {
        bookShareToken = uri.pathSegments[0];
      }

      _addBreadcrumb(
        'deep link parsed',
        data: {
          ..._sanitizedUriData(uri),
          'gameId': _maskedValue(gameId),
          'bookShareToken': _maskedValue(bookShareToken),
        },
      );

      if (gameId != null && gameId.isNotEmpty) {
        if (uri.queryParameters['stop_live'] == '1') {
          _stopLiveUpdates(gameId, ref);
        }
        _addBreadcrumb('routing to game', data: {'gameId': gameId});
        unawaited(
          _captureDeepLinkMessage(
            'deep link routing to game',
            stage: 'route_to_game',
            extras: {'gameId': gameId},
          ),
        );
        _navigateToGame(gameId, navigatorKey, ref);
      } else if (bookShareToken != null && bookShareToken.isNotEmpty) {
        _addBreadcrumb(
          'routing to shared book',
          data: {'shareToken': _maskedValue(bookShareToken)},
        );
        _navigateToBookPreview(bookShareToken, navigatorKey, ref);
      } else {
        _addBreadcrumb(
          'deep link ignored',
          data: {
            'reason': 'unsupported path',
            ..._sanitizedUriData(uri),
          },
        );
      }
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Failed parsing deep link: $e');
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'parse_handle_deep_link',
        extras: _sanitizedUriData(uri),
      );
    }
  }

  void _stopLiveUpdates(String gameId, WidgetRef ref) {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    unawaited(LiveUpdatesService.instance.stopForGame(gameId, user.id));
  }

  /// Navigate to the book preview screen for a shared book deep link.
  Future<void> _navigateToBookPreview(
    String shareToken,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) async {
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      try {
        await _appReadyCompleter.future.timeout(const Duration(seconds: 30));
      } catch (_) {
        debugPrint(
          'DeepLinkService: Timed out waiting for app ready, proceeding',
        );
      }

      AppAuthState? resolvedState = ref.read(authStateProvider).value;
      if (resolvedState == null) {
        try {
          resolvedState = await ref.read(authStateProvider.future);
        } catch (_) {
          resolvedState = null;
        }
      }

      if (resolvedState?.status != AppAuthStatus.authenticated) {
        debugPrint('DeepLinkService: User not authenticated, routing to home');
        _captureDeepLinkException(
          Exception('Deep link ignored because user is not authenticated'),
          StackTrace.current,
          stage: 'book_preview_requires_auth',
          extras: {'shareToken': _maskedValue(shareToken)},
          captureAsException: false,
        );
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/home_screen',
          (route) => false,
        );
        return;
      }

      debugPrint('DeepLinkService: Opening book preview: $shareToken');

      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => BookPreviewScreen(shareToken: shareToken),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Failed to open book preview: $e');
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'navigate_to_book_preview',
        extras: {'shareToken': _maskedValue(shareToken)},
      );
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/home_screen',
        (route) => false,
      );
    } finally {
      _isNavigating = false;
    }
  }

  /// Fetch game by ID, load full tournament context for swiping,
  /// and navigate to chess board screen.
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

    try {
      // Wait for the app to be past the splash screen before navigating.
      // On warm start this resolves immediately since splash already completed.
      try {
        await _appReadyCompleter.future.timeout(const Duration(seconds: 30));
      } catch (_) {
        debugPrint(
          'DeepLinkService: Timed out waiting for app ready, proceeding',
        );
      }

      final isAuthenticated = await _waitForAuthenticatedSession(ref);
      if (!isAuthenticated) {
        debugPrint(
          'DeepLinkService: No authenticated session available for game link, routing to home',
        );
        _captureDeepLinkException(
          Exception(
            'Deep link ignored because no authenticated session was available',
          ),
          StackTrace.current,
          stage: 'game_link_requires_auth',
          extras: {'gameId': gameId},
          captureAsException: false,
        );
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/home_screen',
          (route) => false,
        );
        return;
      }

      debugPrint('DeepLinkService: Fetching game: $gameId');
      _addBreadcrumb('fetching game', data: {'gameId': gameId});

      // Fetch the tapped game from Supabase.
      // getGameByAnyId handles both Supabase UUIDs and Lichess short IDs.
      final gameRepo = ref.read(gameRepositoryProvider);
      final game = await gameRepo.getGameByAnyId(gameId).timeout(_fetchTimeout);
      // Normalize to Supabase UUID so round-game index lookup works regardless
      // of whether the deep link contained a Lichess short ID or a UUID.
      final resolvedGameId = game.id;
      final gameTourModel = GamesTourModel.fromGame(game);
      List<GamesTourModel> gameList = <GamesTourModel>[gameTourModel];
      var openIndex = 0;
      try {
        final roundGames = await gameRepo
            .getGamesByRoundId(game.roundId)
            .timeout(_fetchTimeout);
        if (roundGames.isNotEmpty) {
          gameList = roundGames
              .map(GamesTourModel.fromGame)
              .toList(growable: false);
          // Keep board order stable for swipe navigation.
          gameList.sort((a, b) {
            final aBoard = a.boardNr ?? 1 << 30;
            final bBoard = b.boardNr ?? 1 << 30;
            if (aBoard != bBoard) return aBoard.compareTo(bBoard);
            return a.gameId.compareTo(b.gameId);
          });
          final idx = gameList.indexWhere((g) => g.gameId == resolvedGameId);
          openIndex = idx >= 0 ? idx : 0;
        }
      } catch (e, stackTrace) {
        debugPrint(
          'DeepLinkService: Failed to load round games for swipe context: $e',
        );
        _captureDeepLinkException(
          e,
          stackTrace,
          stage: 'load_round_games_for_swipe_context',
          extras: {'gameId': gameId, 'roundId': game.roundId},
          captureAsException: false,
        );
      }

      debugPrint('DeepLinkService: Game loaded, navigating to chess board');
      _addBreadcrumb(
        'navigating to chess board',
        data: {
          'gameId': gameId,
          'resolvedGameId': resolvedGameId,
          'roundId': game.roundId,
          'openIndex': openIndex,
          'gameListLength': gameList.length,
        },
      );
      unawaited(
        _captureDeepLinkMessage(
          'deep link game loaded',
          stage: 'navigate_to_game_success',
          extras: {
            'gameId': gameId,
            'resolvedGameId': resolvedGameId,
            'roundId': game.roundId,
            'openIndex': openIndex,
            'gameListLength': gameList.length,
          },
        ),
      );
      ref.read(chessboardViewFromProviderNew.notifier).state =
          ChessboardView.forYou;
      ref.read(shouldStreamProvider.notifier).state = false;

      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(
            builder:
                (_) => ChessBoardScreenNew(
                  games: gameList,
                  currentIndex: openIndex,
                ),
          ),
          (route) => route.isFirst,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Failed to load game: $e');
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'navigate_to_game',
        extras: {'gameId': gameId},
      );
      _addBreadcrumb(
        'game deep link failed; routing home',
        data: {'gameId': gameId},
      );
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/home_screen',
        (route) => false,
      );
    } finally {
      _isNavigating = false;
    }
  }

  Future<bool> _waitForAuthenticatedSession(WidgetRef ref) async {
    final deadline = DateTime.now().add(kAuthRestoreTimeout);

    while (DateTime.now().isBefore(deadline)) {
      final state = ref.read(authStateProvider).valueOrNull;
      if (state?.status == AppAuthStatus.authenticated) {
        return true;
      }

      final session = Supabase.instance.client.auth.currentSession;
      final user = Supabase.instance.client.auth.currentUser;
      if (session != null && user != null && !session.isExpired) {
        return true;
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    final state = ref.read(authStateProvider).valueOrNull;
    if (state?.status == AppAuthStatus.authenticated) {
      return true;
    }

    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;
    return session != null && user != null && !session.isExpired;
  }

  /// Route based on OneSignal notification data payload.
  /// Called from the OneSignal click listener.
  void handleNotificationData(
    Map<String, dynamic> data,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) {
    final type = _asNonEmptyString(data['type'])?.toLowerCase();

    debugPrint('DeepLinkService: Handling notification data: type=$type');

    final gameId = _firstNonEmptyString([data['game_id'], data['gameId']]);
    final broadcastId = _firstNonEmptyString([
      data['group_broadcast_id'],
      data['groupBroadcastId'],
      data['group_id'],
      data['event_id'],
    ]);
    final roundId = _firstNonEmptyString([data['round_id'], data['roundId']]);
    final tourId = _firstNonEmptyString([
      data['tour_id'],
      data['tourId'],
      data['category_id'],
    ]);

    switch (type) {
      case 'game_started':
      case 'game_finished':
      case 'live_game_update':
      case 'live_game_alert':
        if (gameId != null && gameId.isNotEmpty) {
          _navigateToGame(gameId, navigatorKey, ref);
        } else {
          _navigateToHome(navigatorKey);
        }
        return;
      case 'round_started':
      case 'round_heads_up':
      case 'round_finished':
        if (broadcastId != null || roundId != null || tourId != null) {
          _navigateToEvent(
            broadcastId,
            navigatorKey,
            ref,
            roundId: roundId,
            tourId: tourId,
          );
        } else {
          _navigateToHome(navigatorKey);
        }
        return;
      default:
        // Best-effort fallback for payloads with routing hints.
        if (gameId != null) {
          _navigateToGame(gameId, navigatorKey, ref);
          return;
        }

        if (broadcastId != null || roundId != null || tourId != null) {
          _navigateToEvent(
            broadcastId,
            navigatorKey,
            ref,
            roundId: roundId,
            tourId: tourId,
          );
          return;
        }

        // call_to_action and any unknown types — open the app to home
        _navigateToHome(navigatorKey);
        return;
    }
  }

  /// Navigate to home screen — fallback for notifications without routing data
  void _navigateToHome(GlobalKey<NavigatorState> navigatorKey) {
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/home_screen',
      (route) => false,
    );
  }

  /// Fetch event by group_broadcast_id and navigate to tournament detail screen
  Future<void> _navigateToEvent(
    String? groupBroadcastId,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref, {
    String? roundId,
    String? tourId,
  }) async {
    if (_isNavigating) {
      debugPrint('DeepLinkService: Navigation already in progress, ignoring');
      return;
    }
    _isNavigating = true;

    try {
      try {
        await _appReadyCompleter.future.timeout(const Duration(seconds: 30));
      } catch (_) {
        debugPrint(
          'DeepLinkService: Timed out waiting for app ready, proceeding',
        );
      }

      AppAuthState? resolvedState = ref.read(authStateProvider).value;
      if (resolvedState == null) {
        try {
          resolvedState = await ref.read(authStateProvider.future);
        } catch (_) {
          resolvedState = null;
        }
      }

      if (resolvedState?.status != AppAuthStatus.authenticated) {
        debugPrint('DeepLinkService: User not authenticated, routing to home');
        _captureDeepLinkException(
          Exception('Event deep link ignored because user is not authenticated'),
          StackTrace.current,
          stage: 'event_link_requires_auth',
          extras: {
            'groupBroadcastId': groupBroadcastId,
            'roundId': roundId,
            'tourId': tourId,
          },
          captureAsException: false,
        );
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/home_screen',
          (route) => false,
        );
        return;
      }

      final routeContext = await _resolveEventRouteContext(
        ref,
        groupBroadcastId: groupBroadcastId,
        roundId: roundId,
        tourId: tourId,
      );
      if (routeContext == null) {
        debugPrint(
          'DeepLinkService: Could not resolve event route context from '
          'group_broadcast_id=$groupBroadcastId, round_id=$roundId, tour_id=$tourId',
        );
        _captureDeepLinkException(
          Exception('Failed to resolve event route context for deep link'),
          StackTrace.current,
          stage: 'resolve_event_route_context',
          extras: {
            'groupBroadcastId': groupBroadcastId,
            'roundId': roundId,
            'tourId': tourId,
          },
        );
        _navigateToHome(navigatorKey);
        return;
      }

      debugPrint(
        'DeepLinkService: Fetching event: ${routeContext.groupBroadcastId}',
      );

      final broadcastRepo = ref.read(groupBroadcastRepositoryProvider);
      final broadcast = await broadcastRepo
          .getGroupBroadcastById(routeContext.groupBroadcastId)
          .timeout(_fetchTimeout);

      await _preselectTourAndRound(
        ref,
        groupBroadcastId: broadcast.id,
        tourId: routeContext.tourId,
        roundId: routeContext.roundId,
      );

      ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
      ref.read(selectedTourModeProvider.notifier).state =
          TournamentDetailScreenMode.games;

      debugPrint(
        'DeepLinkService: Event loaded, navigating to tournament detail',
      );

      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/tournament_detail_screen',
        (route) => route.isFirst,
      );
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Failed to load event: $e');
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'navigate_to_event',
        extras: {
          'groupBroadcastId': groupBroadcastId,
          'roundId': roundId,
          'tourId': tourId,
        },
      );
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/home_screen',
        (route) => false,
      );
    } finally {
      _isNavigating = false;
    }
  }

  String? _asNonEmptyString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  String? _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final text = _asNonEmptyString(value);
      if (text != null) return text;
    }
    return null;
  }

  Future<void> _preselectTourAndRound(
    WidgetRef ref, {
    required String groupBroadcastId,
    String? tourId,
    String? roundId,
  }) async {
    final cleanTourId = _asNonEmptyString(tourId);
    final cleanRoundId = _asNonEmptyString(roundId);

    if (cleanTourId != null) {
      try {
        final db = AppDatabase.instance;
        await db.setString('selected_tour_$groupBroadcastId', cleanTourId);
      } catch (e) {
        debugPrint('DeepLinkService: Failed to persist selected tour: $e');
      }
    }

    if (cleanRoundId != null) {
      ref.read(userSelectedRoundProvider.notifier).state = (
        id: cleanRoundId,
        userSelected: true,
      );
    }
  }

  Future<_EventRouteContext?> _resolveEventRouteContext(
    WidgetRef ref, {
    String? groupBroadcastId,
    String? roundId,
    String? tourId,
  }) async {
    var resolvedGroupBroadcastId = _asNonEmptyString(groupBroadcastId);
    var resolvedRoundId = _asNonEmptyString(roundId);
    var resolvedTourId = _asNonEmptyString(tourId);

    // If only round_id is available, resolve its tour first.
    if (resolvedTourId == null && resolvedRoundId != null) {
      try {
        final round = await ref
            .read(roundRepositoryProvider)
            .getRoundById(resolvedRoundId)
            .timeout(_fetchTimeout);
        resolvedTourId = round.tourId;
      } catch (e) {
        debugPrint('DeepLinkService: Failed to resolve tour from round: $e');
      }
    }

    // Resolve/validate group_broadcast_id from tour if possible.
    if (resolvedTourId != null) {
      try {
        final tours = await ref
            .read(tourRepositoryProvider)
            .getToursByIds([resolvedTourId])
            .timeout(_fetchTimeout);
        if (tours.isNotEmpty) {
          final tourGroupId = _asNonEmptyString(tours.first.groupBroadcastId);
          if (tourGroupId != null) {
            resolvedGroupBroadcastId = tourGroupId;
          }
        }
      } catch (e) {
        debugPrint(
          'DeepLinkService: Failed to resolve group broadcast from tour: $e',
        );
      }
    }

    if (resolvedGroupBroadcastId == null) {
      return null;
    }

    return _EventRouteContext(
      groupBroadcastId: resolvedGroupBroadcastId,
      tourId: resolvedTourId,
      roundId: resolvedRoundId,
    );
  }

  /// Dispose of resources
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _isInitialized = false;
    _isNavigating = false;
    _lastHandledGameId = null;
    _lastHandledTime = null;
    _appReadyCompleter = Completer<void>();
  }

  void _addBreadcrumb(String message, {Map<String, dynamic>? data}) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'deep_link',
        message: message,
        type: 'navigation',
        data: data,
        level: SentryLevel.info,
      ),
    );
  }

  Map<String, dynamic> _sanitizedUriData(Uri uri) {
    return {
      'scheme': uri.scheme,
      'host': uri.host,
      'path': uri.path,
      'routeKind': _routeKindFromUri(uri),
      if (uri.queryParameters.isNotEmpty)
        'queryParameters': _whitelistedQueryParameters(uri),
    };
  }

  String _routeKindFromUri(Uri uri) {
    if (uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    return uri.host;
  }

  Map<String, String> _whitelistedQueryParameters(Uri uri) {
    final allowed = <String>{'stop_live'};
    final safe = <String, String>{};
    for (final entry in uri.queryParameters.entries) {
      if (allowed.contains(entry.key)) {
        safe[entry.key] = entry.value;
      }
    }
    return safe;
  }

  String? _maskedValue(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.length <= 6) return '***';
    return '${value.substring(0, 3)}***${value.substring(value.length - 2)}';
  }

  Future<void> _captureDeepLinkException(
    dynamic error,
    StackTrace stackTrace, {
    required String stage,
    Map<String, dynamic>? extras,
    bool captureAsException = true,
  }) async {
    try {
      final mergedExtras = <String, dynamic>{'stage': stage, ...?extras};
      final sentryExtras = mergedExtras.map(
        (key, value) => MapEntry(key, value?.toString()),
      );
      if (!captureAsException) {
        _addBreadcrumb(
          'deep link warning',
          data: {'stage': stage, ...?extras, 'error': error.toString()},
        );
        return;
      }

      await Sentry.captureException(
        error,
        stackTrace: stackTrace,
        withScope: (scope) {
          scope.setTag('area', 'deep_link');
          scope.setTag('stage', stage);
          scope.setContexts('deep_link', sentryExtras);
        },
      ).timeout(const Duration(seconds: 2));
    } catch (telemetryError, telemetryStackTrace) {
      debugPrint(
        'DeepLinkService: Sentry logging failed at $stage: $telemetryError',
      );
      debugPrint('$telemetryStackTrace');
    }
  }

  Future<void> _captureDeepLinkMessage(
    String message, {
    required String stage,
    Map<String, dynamic>? extras,
    SentryLevel level = SentryLevel.info,
  }) async {
    try {
      final mergedExtras = <String, dynamic>{'stage': stage, ...?extras};
      final sentryExtras = mergedExtras.map(
        (key, value) => MapEntry(key, value?.toString()),
      );
      await Sentry.captureMessage(
        message,
        level: level,
        withScope: (scope) {
          scope.setTag('area', 'deep_link');
          scope.setTag('stage', stage);
          scope.setContexts('deep_link', sentryExtras);
        },
      ).timeout(const Duration(seconds: 2));
    } catch (telemetryError, telemetryStackTrace) {
      debugPrint(
        'DeepLinkService: Sentry message logging failed at $stage: $telemetryError',
      );
      debugPrint('$telemetryStackTrace');
    }
  }
}

class _EventRouteContext {
  const _EventRouteContext({
    required this.groupBroadcastId,
    this.tourId,
    this.roundId,
  });

  final String groupBroadcastId;
  final String? tourId;
  final String? roundId;
}
