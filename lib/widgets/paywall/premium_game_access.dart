import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Applies a collection's existing open check to nested player-name targets.
/// These targets handle their own gestures, independently of the game card.
class PremiumCollectionPlayerAccess extends InheritedWidget {
  const PremiumCollectionPlayerAccess({
    super.key,
    required this.ensureAccess,
    required super.child,
  });

  final Future<bool> Function(BuildContext context) ensureAccess;

  static Future<bool> Function(BuildContext context)? maybeOf(
    BuildContext context,
  ) => context
      .getInheritedWidgetOfExactType<PremiumCollectionPlayerAccess>()
      ?.ensureAccess;

  @override
  bool updateShouldNotify(PremiumCollectionPlayerAccess oldWidget) =>
      oldWidget.ensureAccess != ensureAccess;
}

/// Browse freely, but require paid/rewarded access before opening the game.
Future<bool> ensurePremiumGameAccess(
  BuildContext context, {
  required String featureId,
  required String returnTo,
}) async {
  if (!context.mounted) return false;
  if (ProviderScope.containerOf(
    context,
    listen: false,
  ).read(premiumAccessProvider)) {
    return true;
  }
  return showPremiumPaywallSheet(
    context: context,
    featureId: featureId,
    returnTo: returnTo,
  );
}

/// Every Countrymen game, live ones included, asks a viewer without Premium to
/// watch an ad or subscribe before it opens.
Future<bool> ensureCountrymenGameAccess(BuildContext context) =>
    ensurePremiumGameAccess(
      context,
      featureId: 'countrymen',
      returnTo: 'countrymen/games',
    );

/// Every Favorites game, live ones included, asks a viewer without Premium to
/// watch an ad or subscribe before it opens.
Future<bool> ensureFavoritesGameAccess(BuildContext context) =>
    ensurePremiumGameAccess(
      context,
      featureId: 'favorites_games',
      returnTo: 'favorites/games',
    );

/// Building and browsing a Smart Event is free; opening any of its games,
/// live ones included, asks a viewer without Premium to watch an ad or
/// subscribe.
Future<bool> ensureSmartEventGameAccess(BuildContext context) =>
    ensurePremiumGameAccess(
      context,
      featureId: 'smart_event_games',
      returnTo: 'smart_event/games',
    );
