import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/book_preview_screen.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/services/live_updates_service.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

List<GamesTourModel> _buildSortedRoundGameModels(List<Games> roundGames) {
  final gameList = roundGames
      .map(GamesTourModel.fromGame)
      .toList(growable: false);
  gameList.sort((a, b) {
    final aBoard = a.boardNr ?? 1 << 30;
    final bBoard = b.boardNr ?? 1 << 30;
    if (aBoard != bBoard) return aBoard.compareTo(bBoard);
    return a.gameId.compareTo(b.gameId);
  });
  return gameList;
}

/// Service to handle deep links and notification tap routing.
/// Handles URLs like: `https://chessever.com/games/{id}`
/// Handles URLs like: `https://chessever.com/databases/{id}`
/// Handles notification data routing for games, events, rounds, and databases.
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

  /// Public access to the splash-complete gate so other services that need to
  /// push routes from a cold-start intent (e.g. PGN file-open handler) can
  /// wait instead of racing the navigator.
  static Future<void> awaitAppReady() => _appReadyCompleter.future;

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
        handleDeepLink(initialLink, navigatorKey, ref);
      }
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Error getting initial link: $e');
      _captureDeepLinkException(e, stackTrace, stage: 'get_initial_link');
    }

    // Listen for links while app is running (warm start / already open)
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _addBreadcrumb(
          'warm-start link received',
          data: _sanitizedUriData(uri),
        );
        handleDeepLink(uri, navigatorKey, ref);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('DeepLinkService: Error listening to links: $error');
        _captureDeepLinkException(error, stackTrace, stage: 'uri_link_stream');
      },
    );
  }

  /// Parse and handle incoming deep link
  void handleDeepLink(
    Uri uri,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) {
    debugPrint('DeepLinkService: Received link: $uri');

    // iOS "Open in ChessEver" delivers `.pgn` as a file:// URI through
    // app_links (SceneDelegate forwards the URL). With
    // LSSupportsOpeningDocumentsInPlace disabled in Info.plist, iOS copies
    // the file into Documents/Inbox/ first, so the path is freely readable.
    // On Android, ACTION_VIEW for .pgn is handled by receive_sharing_intent
    // (which also resolves content:// URIs to real file paths), so we skip
    // this branch on Android to avoid double-handling the same file.
    if (Platform.isIOS && uri.scheme == 'file') {
      _addBreadcrumb(
        'file uri received',
        data: {'scheme': uri.scheme, 'path': _maskedValue(uri.path)},
      );
      try {
        final path = uri.toFilePath();
        unawaited(
          PgnFileIntakeService.instance.handlePgnFilePath(
            path,
            navigatorKey,
            waitAppReady: true,
          ),
        );
      } catch (e, stackTrace) {
        debugPrint('DeepLinkService: Failed routing file uri: $e');
        _captureDeepLinkException(
          e,
          stackTrace,
          stage: 'route_file_uri',
          extras: {'path': _maskedValue(uri.path)},
        );
      }
      return;
    }

    try {
      String? gameId;
      String? bookShareToken;
      String? folderId;
      String? broadcastId;

      // Universal link: https://chessever.com/games/<id>
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'games') {
        gameId = uri.pathSegments[1];
      }

      // Universal link: https://chessever.com/books/<shareToken>
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'books') {
        bookShareToken = uri.pathSegments[1];
      }

      // Universal link: https://chessever.com/databases/<folderId>
      if (uri.pathSegments.length >= 2 &&
          (uri.pathSegments[0] == 'databases' ||
              uri.pathSegments[0] == 'folders')) {
        folderId = uri.pathSegments[1];
      }

      // Universal link: https://chessever.com/broadcast/<slug>/<id>
      // Also accept /broadcast/<id> for links without a slug.
      if (uri.pathSegments.isNotEmpty && uri.pathSegments[0] == 'broadcast') {
        if (uri.pathSegments.length >= 3) {
          broadcastId = uri.pathSegments[2];
        } else if (uri.pathSegments.length == 2) {
          broadcastId = uri.pathSegments[1];
        }
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

      // Custom scheme: com.chessever.app://databases/<folderId>
      if (folderId == null &&
          (uri.host == 'databases' || uri.host == 'folders') &&
          uri.pathSegments.isNotEmpty) {
        folderId = uri.pathSegments[0];
      }

      // Custom scheme: com.chessever.app://broadcast/<slug>/<id>
      // Also accept com.chessever.app://broadcast/<id>.
      if (broadcastId == null &&
          uri.host == 'broadcast' &&
          uri.pathSegments.isNotEmpty) {
        broadcastId = uri.pathSegments.last;
      }

      _addBreadcrumb(
        'deep link parsed',
        data: {
          ..._sanitizedUriData(uri),
          'gameId': _maskedValue(gameId),
          'bookShareToken': _maskedValue(bookShareToken),
          'folderId': _maskedValue(folderId),
          'broadcastId': _maskedValue(broadcastId),
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
      } else if (folderId != null && folderId.isNotEmpty) {
        _addBreadcrumb(
          'routing to database folder',
          data: {'folderId': _maskedValue(folderId)},
        );
        _navigateToFolder(folderId, navigatorKey, ref);
      } else if (broadcastId != null && broadcastId.isNotEmpty) {
        _addBreadcrumb(
          'routing to broadcast event',
          data: {'broadcastId': _maskedValue(broadcastId)},
        );
        _navigateToEvent(broadcastId, navigatorKey, ref);
      } else {
        _addBreadcrumb(
          'deep link ignored',
          data: {'reason': 'unsupported path', ..._sanitizedUriData(uri)},
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

      final isAuthenticated = _isFullyAuthenticated(resolvedState);
      if (!isAuthenticated) {
        debugPrint(
          'DeepLinkService: User not authenticated, routing to auth screen',
        );
        _captureDeepLinkException(
          Exception('Deep link ignored because user is not authenticated'),
          StackTrace.current,
          stage: 'book_preview_requires_auth',
          extras: {'shareToken': _maskedValue(shareToken)},
          captureAsException: false,
        );
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/auth_screen',
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

  /// Navigate to a specific library folder for push notifications (e.g. game added/updated in a database).
  Future<void> _navigateToFolder(
    String folderId,
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

      final isAuthenticated = _isFullyAuthenticated(resolvedState);
      if (!isAuthenticated) {
        debugPrint(
          'DeepLinkService: User not authenticated, routing to auth screen',
        );
        _captureDeepLinkException(
          Exception(
            'Folder deep link ignored because user is not authenticated',
          ),
          StackTrace.current,
          stage: 'folder_requires_auth',
          extras: {'folderId': _maskedValue(folderId)},
          captureAsException: false,
        );
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/auth_screen',
          (route) => false,
        );
        return;
      }

      debugPrint('DeepLinkService: Opening library folder: $folderId');

      final repo = ref.read(libraryRepositoryProvider);

      LibraryFolder? targetFolder;
      try {
        targetFolder = await repo.getFolder(folderId);
      } catch (_) {
        // Might fail if not owner, ignore
      }

      // Fallback: Check subscriptions
      if (targetFolder == null) {
        try {
          final subscribedBooks = await repo.getSubscribedBooks();
          targetFolder =
              subscribedBooks.where((f) => f.id == folderId).firstOrNull;
        } catch (_) {
          // Ignore
        }
      }

      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        if (targetFolder != null) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => FolderContentsScreen(folder: targetFolder!),
            ),
          );
        } else {
          debugPrint(
            'DeepLinkService: Folder not found or access denied: $folderId',
          );
          navigator.pushNamedAndRemoveUntil('/home_screen', (route) => false);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('DeepLinkService: Failed to open folder: $e');
      _captureDeepLinkException(
        e,
        stackTrace,
        stage: 'navigate_to_folder',
        extras: {'folderId': _maskedValue(folderId)},
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
      // Keep only auth restore and splash completion on the critical path.
      // Round-game context is useful for swiping, but it should never delay
      // opening the tapped game from a shared link.
      debugPrint('DeepLinkService: Fetching game: $gameId');
      _addBreadcrumb('fetching game', data: {'gameId': gameId});

      final authFuture = _waitForAuthenticatedSession(ref);
      final appReadyFuture = _appReadyCompleter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint(
            'DeepLinkService: Timed out waiting for app ready, proceeding',
          );
        },
      );

      // Auth is required before we can proceed.
      final isAuthenticated = await authFuture;
      if (!isAuthenticated) {
        debugPrint(
          'DeepLinkService: No authenticated session, routing to auth screen',
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
        await appReadyFuture;
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/auth_screen',
          (route) => false,
        );
        return;
      }

      final gameRepo = ref.read(gameRepositoryProvider);
      final game = await gameRepo.getGameByAnyId(gameId).timeout(_fetchTimeout);
      final resolvedGameId = game.id;
      final gameTourModel = GamesTourModel.fromGame(game);

      await appReadyFuture;

      // Resolve tournament context so swiping and tournament button works.
      final roundRepo = ref.read(roundRepositoryProvider);
      final tourRepo = ref.read(tourRepositoryProvider);
      final broadcastRepo = ref.read(groupBroadcastRepositoryProvider);

      try {
        final round = await roundRepo
            .getRoundById(game.roundId)
            .timeout(_fetchTimeout);
        final tour = await tourRepo
            .getToursByIds([round.tourId])
            .timeout(_fetchTimeout);

        if (tour.isNotEmpty) {
          final broadcastId = tour.first.groupBroadcastId;
          if (broadcastId != null) {
            final broadcast = await broadcastRepo
                .getGroupBroadcastById(broadcastId)
                .timeout(_fetchTimeout);

            // Pre-select tour and round so the tournament button in board screen works
            await _preselectTourAndRound(
              ref,
              groupBroadcastId: broadcast.id,
              tourId: tour.first.id,
              roundId: round.id,
            );

            ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
            ref.read(chessboardViewFromProviderNew.notifier).state =
                ChessboardView.tour;
          } else {
            ref.read(chessboardViewFromProviderNew.notifier).state =
                ChessboardView.forYou;
          }
        } else {
          ref.read(chessboardViewFromProviderNew.notifier).state =
              ChessboardView.forYou;
        }
      } catch (e) {
        debugPrint('DeepLinkService: Failed to resolve full context: $e');
        ref.read(chessboardViewFromProviderNew.notifier).state =
            ChessboardView.forYou;
      }

      final roundGamesFuture = gameRepo
          .getGamesByRoundId(game.roundId)
          .timeout(_fetchTimeout);

      debugPrint('DeepLinkService: Game loaded, navigating to chess board');
      _addBreadcrumb(
        'navigating to chess board',
        data: {
          'gameId': gameId,
          'resolvedGameId': resolvedGameId,
          'roundId': game.roundId,
          'openIndex': 0,
          'gameListLength': 1,
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
            'openIndex': 0,
            'gameListLength': 1,
          },
        ),
      );
      ref.read(shouldStreamProvider.notifier).state = false;

      final navigator = navigatorKey.currentState;
      if (navigator != null) {
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(
            builder:
                (_) => _DeepLinkedChessBoardRoute(
                  initialGame: gameTourModel,
                  initialGameId: resolvedGameId,
                  roundGamesFuture: roundGamesFuture,
                  onRoundGamesError: (error, stackTrace) {
                    debugPrint(
                      'DeepLinkService: Failed to load round games for swipe context: $error',
                    );
                    _captureDeepLinkException(
                      error,
                      stackTrace,
                      stage: 'load_round_games_for_swipe_context',
                      extras: {'gameId': gameId, 'roundId': game.roundId},
                      captureAsException: false,
                    );
                  },
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
      if (_isFullyAuthenticated(ref.read(authStateProvider).valueOrNull)) {
        return true;
      }

      final session = Supabase.instance.client.auth.currentSession;
      final user = Supabase.instance.client.auth.currentUser;
      if (session != null &&
          user != null &&
          !session.isExpired &&
          user.isAnonymous != true) {
        return true;
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    if (_isFullyAuthenticated(ref.read(authStateProvider).valueOrNull)) {
      return true;
    }

    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;
    return session != null &&
        user != null &&
        !session.isExpired &&
        user.isAnonymous != true;
  }

  /// Anonymous sessions are no longer treated as authenticated.
  bool _isFullyAuthenticated(AppAuthState? state) {
    if (state?.status != AppAuthStatus.authenticated) return false;
    return state?.user?.isAnonymous != true;
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
    final folderId = _firstNonEmptyString([
      data['folder_id'],
      data['folderId'],
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
      case 'book_game_added':
      case 'book_game_updated':
      case 'book_game_removed':
        if (folderId != null && folderId.isNotEmpty) {
          _navigateToFolder(folderId, navigatorKey, ref);
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

        if (folderId != null) {
          _navigateToFolder(folderId, navigatorKey, ref);
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

      final isAuthenticated = _isFullyAuthenticated(resolvedState);
      if (!isAuthenticated) {
        debugPrint(
          'DeepLinkService: User not authenticated, routing to auth screen',
        );
        _captureDeepLinkException(
          Exception(
            'Event deep link ignored because user is not authenticated',
          ),
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
          '/auth_screen',
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

    // Shared event URLs `chessever.com/broadcast/<slug>/<id>` mirror Lichess,
    // where `<id>` is a tour's short id (e.g. `QXavbhIZ`). When that's the
    // case, treat the path-tail value as the shared tour so the destination
    // category is preselected — matching Lichess's behavior for the same URL
    // shape. If `<id>` is actually a group_broadcasts.id (legacy shares) the
    // lookup misses and we fall through with the original value.
    final probeId =
        resolvedTourId == null && resolvedGroupBroadcastId != null
            ? resolvedGroupBroadcastId
            : null;

    // Resolve/validate group_broadcast_id from tour. Combines the tour-by-id
    // lookup for both an explicit `tourId` and the Lichess-style probe above
    // into a single Supabase round-trip.
    final lookupId = resolvedTourId ?? probeId;
    if (lookupId != null) {
      try {
        final tours = await ref
            .read(tourRepositoryProvider)
            .getToursByIds([lookupId])
            .timeout(_fetchTimeout);
        if (tours.isNotEmpty) {
          if (resolvedTourId == null) {
            resolvedTourId = tours.first.id;
          }
          final tourGroupId = _asNonEmptyString(tours.first.groupBroadcastId);
          if (tourGroupId != null) {
            resolvedGroupBroadcastId = tourGroupId;
          }
        }
      } catch (e) {
        debugPrint(
          'DeepLinkService: Failed to resolve tour/group broadcast: $e',
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

class _DeepLinkedChessBoardRoute extends StatefulWidget {
  const _DeepLinkedChessBoardRoute({
    required this.initialGame,
    required this.initialGameId,
    required this.roundGamesFuture,
    required this.onRoundGamesError,
  });

  final GamesTourModel initialGame;
  final String initialGameId;
  final Future<List<Games>> roundGamesFuture;
  final void Function(Object error, StackTrace stackTrace) onRoundGamesError;

  @override
  State<_DeepLinkedChessBoardRoute> createState() =>
      _DeepLinkedChessBoardRouteState();
}

class _DeepLinkedChessBoardRouteState
    extends State<_DeepLinkedChessBoardRoute> {
  late List<GamesTourModel> _games;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _games = <GamesTourModel>[widget.initialGame];
    _currentIndex = 0;
    _hydrateRoundGames();
  }

  Future<void> _hydrateRoundGames() async {
    try {
      final roundGames = await widget.roundGamesFuture;
      if (!mounted || roundGames.isEmpty) return;

      final gameList = _buildSortedRoundGameModels(roundGames);
      final index = gameList.indexWhere(
        (g) => g.gameId == widget.initialGameId,
      );
      if (index < 0) return;

      setState(() {
        _games = gameList;
        _currentIndex = index;
      });
    } catch (error, stackTrace) {
      widget.onRoundGamesError(error, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChessBoardScreenNew(
      key: ValueKey('deep-link-${widget.initialGameId}-${_games.length}'),
      games: _games,
      currentIndex: _currentIndex,
    );
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
