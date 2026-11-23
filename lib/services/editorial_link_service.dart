import 'dart:async';

import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/for_you/discovery/likes_screen.dart';
import 'package:chessever2/screens/for_you/discovery/news_screen.dart';
import 'package:chessever2/screens/for_you/discovery/reports_screen.dart';
import 'package:chessever2/screens/inbox/inbox_screen.dart';
import 'package:chessever2/screens/library/library_screen.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_prep/my_prep_home_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart'
    show BottomNavBarItem, openHomeSection;
import 'package:chessever2/services/app_destination.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/services/webview_link.dart';
import 'package:chessever2/utils/own_web_page.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

enum EditorialPage {
  feed,
  news,
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
    '/news' || '/app/news' => EditorialPage.news,
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
    // Feed is a dock section: open the dock's slot, as a tap on it would,
    // rather than push a second copy over the shell. A page reached with no
    // Home under it pushes its own. Collections has no slot: its page is
    // pushed over the message, so Back returns to it. (`/app/events` is no
    // hub page: it lands on the dock's Events through the app's links.)
    if (page == EditorialPage.feed &&
        openHomeSection(
          context,
          BottomNavBarItem.feed,
          navigationType: 'editorial',
        )) {
      return;
    }
    final screen = switch (page) {
      EditorialPage.feed => const FeedScreen(),
      EditorialPage.news => const NewsScreen(),
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

      // Everything else the app can open opens over the message, so Back
      // returns to it: `/webview?url=` (ChessEver's own message may open any
      // page in the app's WebView), every route of the app catalog
      // (/app/events, My Space's pages, Likes, Reports, a player's games,
      // settings, the calendar...) and every content path (a game, an event,
      // a scorecard, a profile, a book, the share-image shapes). Never the
      // browser, never a reset of Home; dock sections open on the dock.
      final route = webViewLinkTarget(uri) != null
          ? uri
          : newsInAppRoute(uri) ??
                (_isInternal(uri) && parseAppDestination(uri.toString()) != null
                    ? uri
                    : null);
      if (route != null) {
        if (!DeepLinkService.instance.openLinkInPlace(route) &&
            (messenger?.mounted ?? false)) {
          showAppSnackOn(messenger!, 'Please try again in a moment.');
        }
        return;
      }
      if (uri.scheme != 'https' && uri.scheme != 'http') return;
      // A chessever.com page with no screen in the app (account, legal)
      // opens over the app: on Android the plain browser intent used to
      // resolve to ChessEver itself and do nothing.
      final opened = isOwnWebHost(uri)
          ? await openOwnWebPage(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
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
