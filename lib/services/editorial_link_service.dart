import 'dart:async';

import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/for_you/discovery/likes_screen.dart';
import 'package:chessever2/screens/for_you/discovery/reports_screen.dart';
import 'package:chessever2/screens/inbox/inbox_screen.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_prep/my_prep_home_screen.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

enum EditorialPage {
  feed,
  likes,
  miniatures,
  reports,
  myPrep,
  library,
  myLikes,
  collections,
  inbox,
}

/// Public hub pages stay browsable; their existing guards protect individual
/// games and actions. Reports themselves are Premium, including cached ones.
String? editorialPremiumFeature(EditorialPage page) =>
    page == EditorialPage.reports ? 'game_reports' : null;

bool _isInternal(Uri uri) =>
    uri.scheme == 'https' &&
    (uri.host == 'chessever.com' || uri.host == 'www.chessever.com') &&
    uri.userInfo.isEmpty &&
    uri.port == 443;

EditorialPage? editorialPageForUri(Uri uri) {
  if (!_isInternal(uri)) return null;
  final path = uri.path.replaceFirst(RegExp(r'/$'), '');
  return switch (path) {
    '/feed' || '/app/feed' => EditorialPage.feed,
    '/likes' || '/app/likes' => EditorialPage.likes,
    '/miniatures' || '/app/miniatures' => EditorialPage.miniatures,
    '/reports' || '/app/reports' => EditorialPage.reports,
    '/my-prep' || '/app/my-prep' => EditorialPage.myPrep,
    '/library' || '/app/library' => EditorialPage.library,
    '/my-likes' || '/app/my-likes' => EditorialPage.myLikes,
    '/collections' || '/app/collections' => EditorialPage.collections,
    '/inbox' || '/app/inbox' => EditorialPage.inbox,
    _ => null,
  };
}

typedef EditorialLinkOpener =
    Future<void> Function(BuildContext context, Uri uri);
typedef EditorialAccessRequest =
    Future<bool> Function(BuildContext context, String featureId);
typedef EditorialPageNavigation =
    void Function(BuildContext context, EditorialPage page);

final editorialAccessRequestProvider = Provider<EditorialAccessRequest>(
  (ref) =>
      (context, featureId) => ensurePremiumGameAccess(
        context,
        featureId: featureId,
        returnTo: 'editorial_link',
      ),
);

final editorialPageNavigationProvider = Provider<EditorialPageNavigation>(
  (ref) => (context, page) {
    final screen = switch (page) {
      EditorialPage.feed => const FeedScreen(),
      EditorialPage.likes => const LikesScreen(),
      EditorialPage.miniatures => const MiniaturesScreen(),
      EditorialPage.reports => const ReportsScreen(),
      EditorialPage.myPrep => const MyPrepHomeScreen(),
      EditorialPage.library => const LibraryScreen(),
      EditorialPage.myLikes => const MyLikesScreen(),
      EditorialPage.collections => const CollectionsScreen(),
      EditorialPage.inbox => const InboxScreen(),
    };
    unawaited(
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => screen)),
    );
  },
);

/// Both Inbox buttons/Markdown links and Nudge See actions enter here. A
/// canceled paywall consumes the link without falling through to the browser.
/// Keep one pending request per provider scope so repeated taps cannot stack
/// purchase dialogs or navigate twice after an unlock.
final editorialLinkOpenerProvider = Provider<EditorialLinkOpener>((ref) {
  var opening = false;
  return (context, uri) async {
    if (opening || !context.mounted) return;
    opening = true;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final page = editorialPageForUri(uri);
      if (page != null) {
        final feature = editorialPremiumFeature(page);
        if (feature != null &&
            !await container.read(editorialAccessRequestProvider)(
              context,
              feature,
            )) {
          return;
        }
        if (!context.mounted) return;
        container.read(editorialPageNavigationProvider)(context, page);
        return;
      }

      if (_isInternal(uri) &&
          uri.pathSegments.length == 2 &&
          uri.pathSegments.first == 'collections') {
        final repository = container.read(collectionsRepositoryProvider);
        final release = repository.holdFreshAccess(uri.pathSegments.last);
        try {
          var collection = await repository.fetchCollection(
            uri.pathSegments.last,
          );
          if (!context.mounted) return;
          if (collection.isPremium && collection.contentLocked != false) {
            if (!await container.read(editorialAccessRequestProvider)(
              context,
              collectionPaywallFeatureId(collection.kind),
            )) {
              return;
            }
            if (!context.mounted) return;
            collection = await repository.fetchCollection(
              uri.pathSegments.last,
            );
            if (!context.mounted) return;
            if (collection.contentLocked == true) {
              if (messenger?.mounted ?? false) {
                showAppSnackOn(
                  messenger!,
                  'This collection is still locked. Please try again.',
                  tone: AppSnackTone.danger,
                );
              }
              return;
            }
          }
          unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CollectionScreen(collection: collection),
              ),
            ),
          );
        } finally {
          release();
        }
        return;
      }

      final route = newsInAppRoute(uri);
      if (route != null) {
        if (!DeepLinkService.instance.openLinkFromApp(route)) {
          if (messenger?.mounted ?? false) {
            showAppSnackOn(messenger!, 'Please try again in a moment.');
          }
        }
        return;
      }
      if (uri.scheme != 'https' && uri.scheme != 'http') return;
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && (messenger?.mounted ?? false)) {
        showAppSnackOn(
          messenger!,
          "Couldn't open the link.",
          tone: AppSnackTone.danger,
        );
      }
    } catch (error) {
      debugPrint(
        '[EditorialLink] Could not open destination: ${error.runtimeType}',
      );
      if (messenger?.mounted ?? false) {
        showAppSnackOn(
          messenger!,
          "Couldn't open the link. Try again.",
          tone: AppSnackTone.danger,
        );
      }
    } finally {
      opening = false;
    }
  };
});
