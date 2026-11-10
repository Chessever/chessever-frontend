import 'dart:async';
import 'dart:convert';

import 'package:chessever2/config/app_environment.dart';
import 'package:chessever2/services/webview_link.dart';
import 'package:chessever2/services/webview_session.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

final webViewSessionProvider = Provider<Future<Session?> Function()>((ref) {
  return () async {
    if (AppEnvironment.isTest) return null;
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;
    if (session == null || session.user.isAnonymous) return null;
    if (session.isExpired) return (await auth.refreshSession()).session;
    return session;
  };
});

class AppWebViewScreen extends ConsumerStatefulWidget {
  const AppWebViewScreen({super.key, required this.url});
  final Uri url;

  @override
  ConsumerState<AppWebViewScreen> createState() => _AppWebViewScreenState();
}

class _AppWebViewScreenState extends ConsumerState<AppWebViewScreen> {
  late final WebViewController _controller;
  final _syncedOrigins = <String>{};
  Uri? _pendingTarget;
  bool _syncing = false;
  bool _loading = true;
  bool _failed = false;
  bool _canGoBack = false;
  String _host = '';

  @override
  void initState() {
    super.initState();
    _host = widget.url.host;
    _controller = WebViewController();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = webViewUrl(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (request.isMainFrame) {
              if (_pendingTarget != null &&
                  uri.origin != _pendingTarget!.origin) {
                _showFailure();
                return NavigationDecision.prevent;
              }
              if (canShareWebViewSession(uri) &&
                  !_syncedOrigins.contains(uri.origin) &&
                  !(_pendingTarget?.origin == uri.origin &&
                      uri.path == '/favicon.ico')) {
                unawaited(_load(uri));
                return NavigationDecision.prevent;
              }
              if (mounted) {
                setState(() {
                  _host = uri.host;
                });
              }
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) => unawaited(_pageFinished(url)),
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && error.errorCode != -999) {
              _showFailure();
            }
          },
        ),
      );
      await _load(widget.url);
    } catch (_) {
      _showFailure();
    }
  }

  Future<void> _load(Uri uri) async {
    if (webViewUrl(uri.toString()) == null) {
      _showFailure();
      return;
    }
    if (canShareWebViewSession(uri) && !_syncedOrigins.contains(uri.origin)) {
      _pendingTarget = uri;
    }
    if (mounted) {
      setState(() {
        _failed = false;
        _loading = true;
      });
    }
    // An inert same-origin document lets us seed storage before any web app
    // JavaScript executes, including when another account used this WebView.
    await _controller.loadRequest(
      _pendingTarget != null ? uri.resolve('/favicon.ico') : uri,
    );
  }

  Future<void> _pageFinished(String url) async {
    if (!mounted || _syncing) return;
    try {
      final uri = webViewUrl(url);
      if (uri == null) return;
      if (canShareWebViewSession(uri) && !_syncedOrigins.contains(uri.origin)) {
        _syncing = true;
        final session = await ref.read(webViewSessionProvider)();
        if (!mounted) return;
        final written = await _controller.runJavaScriptReturningResult(
          webViewSessionScript(uri, session),
        );
        if (!mounted) return;
        if (written != true && written != 'true') {
          _showFailure();
          return;
        }
        _syncedOrigins.add(uri.origin);
        final target = _pendingTarget;
        _pendingTarget = null;
        _syncing = false;
        // Replace the inert bootstrap document so Back skips it and the web
        // client reads the session before starting its first real page.
        final destination = target != null && target.origin == uri.origin
            ? target
            : uri;
        await _controller.runJavaScript(
          'window.location.replace(${jsonEncode(destination.toString())});',
        );
        return;
      }
      _pendingTarget = null;
      final canGoBack = await _controller.canGoBack();
      if (mounted) {
        setState(() {
          _loading = false;
          _canGoBack = canGoBack;
        });
      }
    } catch (_) {
      _showFailure();
    } finally {
      _syncing = false;
    }
  }

  void _showFailure() {
    if (mounted) {
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_canGoBack,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_controller.goBack());
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(_host, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Offstage(
            offstage: _loading || _failed,
            child: WebViewWidget(controller: _controller),
          ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_failed)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Couldn't open this page."),
                  TextButton(
                    onPressed: () => unawaited(_load(widget.url)),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
