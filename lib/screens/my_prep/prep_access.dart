import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How many profiles Prep holds without a paid subscription. The reader's
/// own profile and their opponents count alike, each with any number of
/// sources.
const kFreePrepProfiles = 2;

/// Whether [profile] counts towards [kFreePrepProfiles]. A player kept in
/// Players does not, and the reader's own profile counts from its first
/// source: Games shows it as empty until then.
bool prepCountsAsProfile(PrepProfile profile) => switch (profile.kind) {
  PrepKind.favorite => false,
  PrepKind.mine => profile.accounts.isNotEmpty,
  PrepKind.opponent => true,
};

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
/// downloading their games is free, within [kFreePrepProfiles]. [feature]
/// names what asked, for the paywall analytics.
Future<bool> ensurePrepAccess(
  BuildContext context, {
  required String feature,
}) async {
  if (!context.mounted) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(premiumAccessProvider)) return true;
  return _prompt(context, feature, rewarded: true);
}

/// Only a paid subscription lifts Prep's limits. A watched ad does not, as
/// with Favorites and saved games, so ten minutes of access never leaves
/// more behind than a free reader keeps.
final prepUnlimitedProvider = Provider<bool>(
  (ref) => ref.watch(subscriptionProvider.select((s) => s.isSubscribed)),
);

/// Whether one more profile may join Prep, the reader's own or an
/// opponent's. Past [kFreePrepProfiles] the subscription paywall asks.
Future<bool> prepMayAddProfile(BuildContext context) {
  final profiles = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(prepProfilesProvider).valueOrNull;
  final held = profiles?.where(prepCountsAsProfile).length ?? 0;
  return _withinLimit(
    context,
    total: held + 1,
    limit: kFreePrepProfiles,
    feature: 'prep_profiles',
  );
}

/// Whether sources may join [profile], or start a new one where it is
/// null. Only a profile that is not counted yet is asked about: one already
/// kept takes any number of sources.
Future<bool> prepMayAttach(BuildContext context, PrepProfile? profile) async =>
    profile != null &&
        (profile.kind != PrepKind.mine || profile.accounts.isNotEmpty) ||
    await prepMayAddProfile(context);

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
