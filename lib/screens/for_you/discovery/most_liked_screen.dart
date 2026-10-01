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
/// and day ([mostLikedActiveQuery]), picked on either of them. Picking a
/// player narrows Games to their ranked games and turns to it.
class MostLikedScreen extends StatefulWidget {
  const MostLikedScreen({super.key, this.now, this.embedded = false});

  final bool embedded;

  /// Pins "now" in tests.
  final DateTime? now;

  static Future<void> open(BuildContext context) {
    HapticFeedbackService.cardTap();
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MostLikedScreen()));
  }

  @override
  State<MostLikedScreen> createState() => _MostLikedScreenState();
}

class _MostLikedScreenState extends State<MostLikedScreen> {
  final _tabs = EventViewController();
  MostLikedPlayer? _player;

  void _pickPlayer(MostLikedPlayer player) {
    setState(() => _player = player);
    _tabs.showTab(0, scrollToTop: true);
  }

  @override
  Widget build(BuildContext context) {
    return EventViewShell(
      title: 'Most liked',
      embedded: widget.embedded,
      tabs: const ['Games', 'Players'],
      controller: _tabs,
      pageBuilder: (context, index) => MostLikedPage(
        key: ValueKey('most_liked_page_$index'),
        view: index == 0 ? MostLikedView.games : MostLikedView.players,
        now: widget.now,
        playerFilter: _player,
        onPickPlayer: _pickPlayer,
        onClearPlayerFilter: () => setState(() => _player = null),
      ),
    );
  }
}

/// Shared ranking page for standalone rankings and the Likes destination.
class MostLikedPage extends ConsumerWidget {
  const MostLikedPage({
    super.key,
    required this.view,
    this.now,
    this.playerFilter,
    this.onPickPlayer,
    this.onClearPlayerFilter,
  });

  final MostLikedView view;
  final DateTime? now;
  final MostLikedPlayer? playerFilter;
  final ValueChanged<MostLikedPlayer>? onPickPlayer;
  final VoidCallback? onClearPlayerFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = mostLikedActiveQuery(ref, now: now);
    // The period bar sits above the scrolling list, not in it, so Games (a
    // long list of boards) keeps its period tabs and arrows in view exactly
    // as the short Players list does.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 8.sp),
        MostLikedPeriodBar(now: now),
        Expanded(
          child: RefreshIndicator(
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
                bottom: 24.sp + MediaQuery.viewPaddingOf(context).bottom,
              ),
              children: [
                MostLikedSection(
                  view: view,
                  now: now,
                  playerFilter: playerFilter,
                  onPickPlayer: onPickPlayer,
                  onClearPlayerFilter: onClearPlayerFilter,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
