import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/stories/story_row_prefs.dart';
import 'package:chessever2/widgets/paywall/home_customization_access.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The subscription flow a reader without Premium goes through before
/// Collection stories turn Off; true once they hold Premium. [returnTo]
/// names where they asked ('settings', or 'home' for the row on Today).
typedef StoryRowPaywall =
    Future<bool> Function(
      BuildContext context,
      WidgetRef ref, {
      required String returnTo,
    });

/// The app's flow: Home customization's, a paid subscription only, never a
/// rewarded session. Tests pass their own.
final storyRowPaywallProvider = Provider<StoryRowPaywall>(
  (ref) =>
      (context, ref, {required returnTo}) => ensureHomeCustomizationAccess(
        context,
        ref,
        featureId: 'hide_collection_stories',
        returnTo: returnTo,
      ),
);

/// Whether the reader may set Collection stories to [mode], however they
/// asked (Settings, a pull past the row's end, the row's accessibility
/// action). On is always free. Off belongs to Premium: a reader without it
/// goes through the subscription flow first, and backing out of it leaves
/// the choice as it was.
Future<bool> mayChooseStoryRowMode(
  BuildContext context,
  WidgetRef ref,
  StoryRowMode mode, {
  required String returnTo,
}) async {
  if (mode != StoryRowMode.off) return true;
  if (ref.read(subscriptionProvider).isSubscribed) return true;
  final entitled = await ref.read(storyRowPaywallProvider)(
    context,
    ref,
    returnTo: returnTo,
  );
  return entitled && context.mounted;
}
