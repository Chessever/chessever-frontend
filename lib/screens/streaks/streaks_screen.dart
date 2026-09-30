import 'dart:async';

import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/streaks/widgets/wall_class_switch.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/screens/streaks/widgets/wall_filter_tabs.dart';
import 'package:chessever2/screens/streaks/widgets/wall_podium.dart';
import 'package:chessever2/screens/streaks/widgets/wall_row.dart';
import 'package:chessever2/screens/streaks/widgets/wall_runs_card.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

const String _kShareUrl = 'https://streaks.chessever.com';

/// Everyone on a run: the streak wall, per time control, with FIDE age
/// groups. Classical, rapid and blitz are three separate walls; the switch
/// picks one and everything below follows it.
class StreaksScreen extends ConsumerStatefulWidget {
  const StreaksScreen({super.key, this.initialClass});

  /// The wall to open on. Applied to [streakSelectedClassProvider] after the
  /// first frame; that frame already draws this class.
  final StreakTimeClass? initialClass;

  @override
  ConsumerState<StreaksScreen> createState() => _StreaksScreenState();
}

class _StreaksScreenState extends ConsumerState<StreaksScreen> {
  final ScrollController _scroll = ScrollController();

  /// Whether the podium is on screen; its embers and flames rest otherwise.
  final ValueNotifier<bool> _podiumLive = ValueNotifier<bool>(true);

  /// [StreaksScreen.initialClass] until the provider has taken it.
  StreakTimeClass? _pending;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _pending = widget.initialClass;
    if (_pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final tc = _pending;
        if (tc != null) {
          ref.read(streakSelectedClassProvider.notifier).state = tc;
        }
        setState(() => _pending = null);
      });
    }
    // A wall the app has held for a while re-reads on open; a fresh one (or
    // one still on its first load) is left alone.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(streakWallProvider).hasValue) return;
      unawaited(ref.read(streakWallProvider.notifier).refreshIfStale());
    });
  }

  void _onScroll() {
    // Switch + tabs + podium stage is ~330 design px; past it, rest.
    final live = _scroll.offset < 340.w;
    if (_podiumLive.value != live) _podiumLive.value = live;
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _podiumLive.dispose();
    super.dispose();
  }

  void _selectClass(StreakTimeClass tc) {
    _pending = null;
    ref.read(streakSelectedClassProvider.notifier).state = tc;
  }

  Future<void> _refresh() => ref.read(streakWallProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final wall = ref.watch(streakWallProvider);
    final pending = _pending;
    final StreakTimeClass chosen = ref.watch(streakSelectedClassProvider);
    final selected = pending ?? chosen;
    final filter = ref.watch(streakWallFilterProvider);
    final classRows = ref.watch(
      filter.looksPastFloor
          ? streakAllClassRowsProvider(selected)
          : streakClassRowsProvider(selected),
    );
    final visible = pending != null
        ? classRows.where(filter.matches).toList(growable: false)
        : ref.watch(streakVisibleRowsProvider);
    final counts = wall.hasValue ? ref.watch(streakClassCountsProvider) : null;

    final slivers = <Widget>[
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16.w, 4.w, 16.w, 0),
        sliver: SliverToBoxAdapter(
          child: WallClassSwitch(
            selected: selected,
            counts: counts,
            onChanged: _selectClass,
          ),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.only(top: 6.w),
        sliver: const SliverToBoxAdapter(child: WallFilterTabs()),
      ),
      ..._body(
        wall: wall,
        selected: selected,
        filter: filter,
        classRows: classRows,
        visible: visible,
      ),
    ];

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _WallHeader(),
                Expanded(
                  child: RefreshIndicator(
                    color: colors.accentText,
                    backgroundColor: colors.surface,
                    onRefresh: _refresh,
                    child: CustomScrollView(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: slivers,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body({
    required AsyncValue<List<StreakRow>> wall,
    required StreakTimeClass selected,
    required StreakWallFilter filter,
    required List<StreakRow> classRows,
    required List<StreakRow> visible,
  }) {
    final colors = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom + 32.w;

    if (!wall.hasValue) {
      if (wall.hasError) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: GenericErrorWidget(
              message: userFacingError(
                wall.error,
                fallback: "Couldn't load the streaks. Please try again.",
              ),
              onRetry: () => unawaited(_refresh()),
            ),
          ),
        ];
      }
      return [
        SliverPadding(
          padding: EdgeInsets.only(top: 12.w),
          sliver: const SliverToBoxAdapter(child: WallSkeletonRows()),
        ),
      ];
    }

    final label = selected.label.toLowerCase();
    final footnote = SliverPadding(
      padding: EdgeInsets.fromLTRB(16.w, 20.w, 16.w, bottom),
      sliver: SliverToBoxAdapter(
        child: Text(
          "A streak is every decisive win over the board since the player's "
          "last loss in that time control. Draws don't break it. Online "
          "games don't count.",
          style: wallText(12, 17, FontWeight.w400, colors.textSecondary),
        ),
      ),
    );

    if (visible.isEmpty) {
      final message = classRows.isEmpty
          ? 'No one has three $label wins in a row right now.'
          : 'No one matching these filters is on a $label run right now.';
      return [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16.w, 28.w, 16.w, 0),
          sliver: SliverToBoxAdapter(
            child: _CalmLine(
              message: message,
              action: classRows.isEmpty ? null : 'Show everyone',
              onAction: () {
                HapticFeedbackService.selection();
                ref.read(streakWallFilterProvider.notifier).state =
                    const StreakWallFilter();
              },
            ),
          ),
        ),
        footnote,
      ];
    }

    final rankWidth = wallRankWidth(visible.length);
    final index = <int, int>{
      for (var i = 0; i < visible.length; i++) visible[i].fideId: i,
    };

    return [
      SliverPadding(
        padding: EdgeInsets.only(top: 4.w),
        sliver: SliverToBoxAdapter(
          child: ValueListenableBuilder<bool>(
            valueListenable: _podiumLive,
            builder: (context, live, child) =>
                TickerMode(enabled: live, child: child!),
            child: WallPodium(rows: visible, timeClass: selected),
          ),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16.w, 28.w, 16.w, 0),
        sliver: SliverToBoxAdapter(child: WallRunsCard(rows: visible)),
      ),
      SliverPadding(
        padding: EdgeInsets.only(top: 28.w),
        sliver: SliverToBoxAdapter(
          child: _ListHeader(scope: _scope(selected, filter)),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.only(top: 6.w),
        sliver: SliverList.builder(
          itemCount: visible.length,
          findChildIndexCallback: (key) {
            if (key is! ValueKey<int>) return null;
            return index[key.value];
          },
          itemBuilder: (context, i) => WallRow(
            key: ValueKey<int>(visible[i].fideId),
            row: visible[i],
            rank: i + 1,
            rankWidth: rankWidth,
          ),
        ),
      ),
      footnote,
    ];
  }

  /// "Classical · Under 20 · Women": what the list below is showing.
  static String _scope(StreakTimeClass tc, StreakWallFilter f) {
    return [
      tc.label,
      f.age == StreakAgeGroup.all ? 'all ages' : f.age.label,
      if (f.womenOnly) 'women',
      if (f.playingNow) 'playing now',
      if (f.fed != null) f.fed!,
      if (f.title != null) f.title!,
      if (f.query.trim().isNotEmpty) '"${f.query.trim()}"',
    ].join(' · ');
  }
}

/// Back, the title, and share.
class _WallHeader extends StatelessWidget {
  const _WallHeader();

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.textPrimary;
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 0, 16.w, 0),
      child: SizedBox(
        height: 44.w,
        child: Row(
          children: [
            SizedBox.square(
              dimension: 44.w,
              child: IconButton(
                tooltip: 'Back',
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: ink,
                  size: 20.w,
                ),
              ),
            ),
            SizedBox(width: 4.w),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'Streaks',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: wallText(22, 28, FontWeight.w700, ink),
                ),
              ),
            ),
            Builder(
              builder: (button) {
                return SizedBox.square(
                  dimension: 44.w,
                  child: IconButton(
                    tooltip: 'Share',
                    padding: EdgeInsets.zero,
                    onPressed: () => _share(button),
                    icon: Icon(Icons.ios_share, color: ink, size: 20.w),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static void _share(BuildContext button) {
    HapticFeedbackService.light();
    final box = button.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);
    unawaited(Share.share(_kShareUrl, sharePositionOrigin: origin));
  }
}

/// "Everyone on a run" with the scope it is showing.
class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.scope});

  final String scope;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 28.w),
        child: Row(
          children: [
            Semantics(
              header: true,
              child: Text(
                'Everyone on a run',
                maxLines: 1,
                style: wallText(16, 24, FontWeight.w700, colors.textPrimary),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                scope,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: wallText(12, 16, FontWeight.w500, colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The empty wall: one calm sentence, and a way back to everyone.
class _CalmLine extends StatelessWidget {
  const _CalmLine({required this.message, this.action, this.onAction});

  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: wallText(14, 20, FontWeight.w500, colors.textPrimaryMuted),
        ),
        if (action != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12.w),
              child: Text(
                action!,
                style: wallText(14, 20, FontWeight.w700, colors.textPrimary),
              ),
            ),
          ),
      ],
    );
  }
}
