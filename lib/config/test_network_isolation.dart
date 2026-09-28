import 'dart:io';

import 'package:chessever2/config/app_environment.dart';
import 'package:flutter/foundation.dart';

const _enabled = bool.fromEnvironment('CHESSEVER_TEST_NETWORK_ISOLATION');

/// Installs an opt-in boundary for local test-app verification. Native SDKs
/// have their own configuration; this limits Dart HTTP clients.
void installTestNetworkIsolation() {
  if (!_enabled || !kDebugMode || !AppEnvironment.isTest) return;
  HttpOverrides.global = TestNetworkIsolationHttpOverrides();
}

/// Every destination outside the verified test services and local machine
/// goes through a closed local port, without contacting its remote host.
String testNetworkProxyFor(Uri uri) {
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return 'PROXY 127.0.0.1:9';
  }
  if (uri.userInfo.isNotEmpty) return 'PROXY 127.0.0.1:9';
  final host = uri.host.toLowerCase();
  if (host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '[::1]') {
    return 'DIRECT';
  }
  if (uri.scheme == 'https' &&
      (host == '${AppEnvironment.testSupabaseProjectRef}.supabase.co' ||
          host == 'chessever-chat-test.young-sun-69a8.workers.dev')) {
    return 'DIRECT';
  }
  return 'PROXY 127.0.0.1:9';
}

class TestNetworkIsolationHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)..findProxy = testNetworkProxyFor;
  }
}
