import 'dart:io';

import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:dio/dio.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/feed/providers/board_feed_client.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _gamebaseUrl = String.fromEnvironment('BOARD_SMOKE_GAMEBASE_URL');
const _gamebaseKey = 'board-smoke-gamebase';
const _email = String.fromEnvironment('BOARD_SMOKE_EMAIL');
const _password = String.fromEnvironment('BOARD_SMOKE_PASSWORD');
const _loopback = {'127.0.0.1', 'localhost', '10.0.2.2', '::1'};

bool _isLocal(String value, int port) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'http' &&
      _loopback.contains(uri.host) &&
      uri.port == port &&
      uri.userInfo.isEmpty &&
      uri.path.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

Future<void> main() async {
  if (!kDebugMode ||
      !BoardFeedClient.enabled ||
      !_isLocal(_supabaseUrl, 55321) ||
      !_isLocal(BoardFeedClient.endpoint, 8789) ||
      !_isLocal(_gamebaseUrl, 8790) ||
      _supabaseKey.isEmpty ||
      _email.isEmpty ||
      _password.isEmpty) {
    throw StateError('Use the local board smoke-test Dart defines in debug.');
  }

  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _BoardSmokeHttp();
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabaseKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: SharedPreferencesLocalStorage(
        persistSessionKey: 'board-smoke-supabase-session',
      ),
      detectSessionInUri: false,
    ),
  );
  await Supabase.instance.client.auth.signInWithPassword(
    email: _email,
    password: _password,
  );

  final feed = BoardFeedClient.forCurrentUser()!;
  await feed.start(feed.newRequestId());

  runApp(
    ProviderScope(
      overrides: [
        gamebaseRepositoryProvider.overrideWithValue(
          GamebaseRepository(
            Dio(),
            baseUrl: _gamebaseUrl,
            apiKey: _gamebaseKey,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'ChessEver board smoke test',
        theme: AppTheme.lightTheme,
        navigatorObservers: [routeObserver],
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              appBar: AppBar(title: const Text('Board feed smoke test')),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Signed in locally as $_email'),
                    FilledButton(
                      onPressed: () => FeedScreen.open(context),
                      child: const Text('Open ChessEver Feed'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _BoardSmokeHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..findProxy = (uri) =>
          _loopback.contains(uri.host) &&
              const {55321, 8789, 8790}.contains(uri.port)
          ? 'DIRECT'
          : 'PROXY 127.0.0.1:9';
  }
}
