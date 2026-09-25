import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_section.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Discovery › Most liked › See all: the whole ranking, laid out as an event
/// is (back, the centred title, Games | Players, pages that swipe), the same
/// frame Collection and the Favorites and Countrymen screens open into.
///
/// Games lists the ranking the way an event's Games tab lists its games;
/// Players lists everyone with a game in it. Both tabs rank the same period
/// and day ([mostLikedActiveQuery]), picked on either of them.
class MostLikedScreen extends StatelessWidget {
  const MostLikedScreen({super.key, this.now});

  /// Pins "now" in tests.
  final DateTime? now;

  static Future<void> open(BuildContext context) {
    HapticFeedbackService.cardTap();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MostLikedScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return EventViewShell(
      title: 'Most liked',
      tabs: const ['Games', 'Players'],
      pageBuilder: (context, index) => _MostLikedPage(
        key: ValueKey('most_liked_page_$index'),
        view: index == 0 ? MostLikedView.games : MostLikedView.players,
        now: now,
      ),
    );
  }
}

class _MostLikedPage extends ConsumerWidget {
  const _MostLikedPage({super.key, required this.view, this.now});

  final MostLikedView view;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = mostLikedActiveQuery(ref, now: now);
    return RefreshIndicator(
      color: context.colors.textPrimary,
      backgroundColor: context.colors.surface,
      onRefresh: () async {
        ref.invalidate(mostLikedProvider);
        try {
          await ref.read(mostLikedProvider(query).future);
        } catch (_) {
          // The section shows the failure and its retry.
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.only(
          top: 8.sp,
          bottom: 24.sp + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [MostLikedSection(view: view, now: now)],
      ),
    );
  }
}
