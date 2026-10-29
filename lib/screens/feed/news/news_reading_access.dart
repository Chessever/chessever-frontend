import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const kFreeNewsArticles = 3;

/// Shared across reader routes and grid refreshes for this app session.
final newsReadingAccessProvider = Provider((ref) => NewsReadingAccess());

final newsPremiumPromptProvider = Provider<Future<bool> Function(BuildContext)>(
  (ref) =>
      (context) => ensurePremiumGameAccess(
        context,
        featureId: 'news_reading',
        returnTo: 'news/reader',
      ),
);

/// Three new articles are free. Going back to an already read article does
/// not spend another read. A dismissed prompt leaves the next article gated.
class NewsReadingAccess {
  final _read = <String>{};
  int _freeReads = 0;
  bool _promptOpen = false;

  bool canRead(String key, {required bool hasPremium}) =>
      hasPremium || _read.contains(key) || _freeReads < kFreeNewsArticles;

  Future<bool> open(
    String key, {
    required bool Function() hasPremium,
    required Future<bool> Function() requestPremium,
  }) async {
    if (_promptOpen) return false;
    if (hasPremium()) {
      _freeReads = 0;
      _read.add(key);
      return true;
    }
    if (_read.contains(key)) return true;
    if (_freeReads >= kFreeNewsArticles) {
      _promptOpen = true;
      try {
        if (!await requestPremium()) return false;
        _freeReads = 0;
      } finally {
        _promptOpen = false;
      }
    }
    _read.add(key);
    if (!hasPremium()) _freeReads++;
    return true;
  }
}

Future<bool> requestNewsArticleAccess(BuildContext context, String key) async {
  if (!context.mounted) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  return container
      .read(newsReadingAccessProvider)
      .open(
        key,
        hasPremium: () => container.read(premiumAccessProvider),
        requestPremium: () async {
          final allowed = await container.read(newsPremiumPromptProvider)(
            context,
          );
          return context.mounted && allowed;
        },
      );
}
