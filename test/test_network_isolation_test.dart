import 'package:chessever2/config/test_network_isolation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only exact test service HTTPS hosts may connect directly', () {
    for (final url in [
      'https://odmekzlfunfocvedqusl.supabase.co/rest/v1/games',
      'https://odmekzlfunfocvedqusl.supabase.co/storage/v1/object/public/photo',
      'https://chessever-chat-test.young-sun-69a8.workers.dev/v1/chat/quota',
    ]) {
      expect(testNetworkProxyFor(Uri.parse(url)), 'DIRECT', reason: url);
    }
  });

  test('production, shared, lookalike and insecure destinations stay local', () {
    for (final url in [
      'https://oelbsuggrzyqwzmvidju.supabase.co/storage/v1/object/public/photo',
      'https://chessever-chat.young-sun-69a8.workers.dev',
      'https://service.chessever.com',
      'https://chessever-analysis.young-sun-69a8.workers.dev',
      'https://chessever-cloudflare.young-sun-69a8.workers.dev',
      'https://odmekzlfunfocvedqusl.supabase.co.other.invalid',
      'https://odmekzlfunfocvedqusl.supabase.co@other.invalid',
      'https://user@odmekzlfunfocvedqusl.supabase.co',
      'http://odmekzlfunfocvedqusl.supabase.co',
      'ftp://odmekzlfunfocvedqusl.supabase.co',
      'https://localhost.other.invalid',
    ]) {
      expect(
        testNetworkProxyFor(Uri.parse(url)),
        'PROXY 127.0.0.1:9',
        reason: url,
      );
    }
  });

  test('loopback tools remain reachable', () {
    for (final url in [
      'http://localhost:8787',
      'http://127.0.0.1:8080',
      'https://127.0.0.1:8443',
      'http://[::1]:8080',
    ]) {
      expect(testNetworkProxyFor(Uri.parse(url)), 'DIRECT', reason: url);
    }
  });
}
