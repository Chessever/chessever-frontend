import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/utils/explorer_access_depth.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_ads.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether this reader reads and walks the Opening Explorer at any depth:
/// Premium, paid or from a watched ad. Debug builds without rewarded ads skip
/// the gate, as `requirePremiumGuard` does, so engineers can work on deep
/// positions without a live subscription.
final explorerDepthUnlockedProvider = Provider<bool>(
  (ref) =>
      ref.watch(premiumAccessProvider) ||
      (kDebugMode && !RewardedAdsConfig.available),
);

/// Whether playing one more ply in the explorer under [ref] asks for Premium
/// first. Reads the nearest explorer scope, so the standalone Explorer's
/// isolated notifier is the one measured there.
bool explorerNextStepNeedsPremium(WidgetRef ref) =>
    !ref.read(explorerDepthUnlockedProvider) &&
    explorerNextStepLocked(
      ref.read(gamebaseExplorerProvider.notifier).accessPly,
    );
