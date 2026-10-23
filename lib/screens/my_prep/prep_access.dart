import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How many of their own accounts My Games holds without a paid
/// subscription: a ChessEver record, a username or an imported PGN each.
const kFreePrepOwnAccounts = 3;

/// How many opponents Profiles holds without a paid subscription.
const kFreePrepOpponents = 1;

bool _promptOpen = false;

/// Asks for Premium for [feature]: the paywall sheet, with the watch-an-ad
/// unlock beside the subscription where [rewarded] allows it. Resolves to
/// whether the reader may go on.
typedef PrepPremiumPrompt =
    Future<bool> Function(
      BuildContext context,
      String feature, {
      required bool rewarded,
    });

/// The sheet Prep asks with, a provider so tests can stand in for it.
final prepPremiumPromptProvider = Provider<PrepPremiumPrompt>(
  (ref) =>
      (context, feature, {required rewarded}) => showPremiumPaywallSheet(
        context: context,
        featureId: feature,
        returnTo: 'my_space/my_prep',
        allowRewarded: rewarded,
      ),
);

/// Whether the reader may open Prep's statistics, games and trees right now,
/// without asking.
bool hasPrepAccess(WidgetRef ref) => ref.read(premiumAccessProvider);

/// A profile's statistics, its games and its trees are Premium, with the
/// watch-an-ad unlock every Premium surface offers. Adding players and
/// downloading their games is free, within [kFreePrepOwnAccounts] and
/// [kFreePrepOpponents]. [feature] names what asked, for the paywall
/// analytics.
Future<bool> ensurePrepAccess(
  BuildContext context, {
  required String feature,
}) async {
  if (!context.mounted) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(premiumAccessProvider)) return true;
  return _prompt(context, feature, rewarded: true);
}

/// Importing a PGN as a source is Premium, with the same watch-an-ad unlock.
/// Files imported earlier stay attached; their games open behind
/// [ensurePrepAccess] like every other source's.
Future<bool> ensurePrepPgnAccess(BuildContext context) =>
    ensurePrepAccess(context, feature: 'prep_pgn_import');

/// Only a paid subscription lifts Prep's limits. A watched ad does not, as
/// with Favorites and saved games, so ten minutes of access never leaves
/// more behind than a free reader keeps.
final prepUnlimitedProvider = Provider<bool>(
  (ref) => ref.watch(subscriptionProvider.select((s) => s.isSubscribed)),
);

/// Whether My Games may hold [total] of the reader's own accounts. Past
/// [kFreePrepOwnAccounts] the subscription paywall asks.
Future<bool> prepMayHoldOwnAccounts(BuildContext context, int total) =>
    _withinLimit(
      context,
      total: total,
      limit: kFreePrepOwnAccounts,
      feature: 'prep_own_accounts',
    );

/// Whether one more opponent may join Profiles. Past [kFreePrepOpponents]
/// the subscription paywall asks.
Future<bool> prepMayAddOpponent(BuildContext context) {
  final profiles = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(prepProfilesProvider).valueOrNull;
  final opponents =
      profiles?.where((p) => p.kind == PrepKind.opponent).length ?? 0;
  return _withinLimit(
    context,
    total: opponents + 1,
    limit: kFreePrepOpponents,
    feature: 'prep_opponents',
  );
}

Future<bool> _withinLimit(
  BuildContext context, {
  required int total,
  required int limit,
  required String feature,
}) async {
  if (total <= limit) return true;
  if (!context.mounted) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(prepUnlimitedProvider)) return true;
  return _prompt(context, feature, rewarded: false);
}

/// One prompt at a time: a second tap while one is open is a no.
Future<bool> _prompt(
  BuildContext context,
  String feature, {
  required bool rewarded,
}) async {
  if (_promptOpen) return false;
  _promptOpen = true;
  try {
    final prompt = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(prepPremiumPromptProvider);
    return await prompt(context, feature, rewarded: rewarded);
  } finally {
    _promptOpen = false;
  }
}
