import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'dart:async';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// FIDE age groups, then Women and Playing now, as one row of plain text
/// tabs: the selected ones are white and bold, the rest sit at 70 %.
///
/// Everything but "All ages" is Premium, yet the tabs look the same for
/// every account: narrowing the wall goes through the app's premium guard
/// (which passes for subscribers and in debug builds). Widening it back
/// never asks.
class WallFilterTabs extends ConsumerStatefulWidget {
  const WallFilterTabs({super.key});

  @override
  ConsumerState<WallFilterTabs> createState() => _WallFilterTabsState();
}

class _WallFilterTabsState extends ConsumerState<WallFilterTabs> {
  final GlobalKey _selectedAge = GlobalKey();

  @override
  void initState() {
    super.initState();
    // A persisted "Seniors 65+" sits past the right edge; bring it in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _selectedAge.currentContext;
      if (!mounted || target == null) return;
      if (ref.read(streakWallFilterProvider).age == StreakAgeGroup.all) return;
      Scrollable.ensureVisible(target, alignment: 0.5);
    });
  }

  bool get _premium =>
      ref.read(featureAccessStateProvider.select((s) => s.isSubscribed));

  /// Runs [apply] once the viewer may narrow the wall.
  Future<void> _narrow(void Function() apply) async {
    HapticFeedbackService.selection();
    if (_premium) {
      apply();
      return;
    }
    // A confirmed purchase or restore resumes with the filter applied.
    await requirePremiumGuard(
      context,
      ref,
      featureId: 'streaks_filters',
      returnTo: 'streaks',
      onEntitled: () {
        if (mounted) apply();
      },
    );
  }

  void _update(StreakWallFilter Function(StreakWallFilter f) change) {
    final c = ref.read(streakWallFilterProvider.notifier);
    c.state = change(c.state);
  }

  void _onAge(StreakAgeGroup age) {
    final current = ref.read(streakWallFilterProvider).age;
    if (age == current) return;
    if (age == StreakAgeGroup.all) {
      HapticFeedbackService.selection();
      _update((f) => f.copyWith(age: age));
      return;
    }
    unawaited(_narrow(() => _update((f) => f.copyWith(age: age))));
  }

  void _onWomen() {
    final on = ref.read(streakWallFilterProvider).womenOnly;
    if (on) {
      HapticFeedbackService.selection();
      _update((f) => f.copyWith(womenOnly: false));
      return;
    }
    unawaited(_narrow(() => _update((f) => f.copyWith(womenOnly: true))));
  }

  void _onPlaying() {
    final on = ref.read(streakWallFilterProvider).playingNow;
    if (on) {
      HapticFeedbackService.selection();
      _update((f) => f.copyWith(playingNow: false));
      return;
    }
    unawaited(_narrow(() => _update((f) => f.copyWith(playingNow: true))));
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(streakWallFilterProvider);
    final gap = 18.w;

    final tabs = <Widget>[
      for (final age in StreakAgeGroup.values) ...[
        _TextTab(
          key: age == filter.age ? _selectedAge : null,
          label: age.label,
          selected: age == filter.age,
          onTap: () => _onAge(age),
        ),
        SizedBox(width: gap),
      ],
      // A wider pause marks the switch from "pick one age" to two toggles.
      SizedBox(width: 10.w),
      _TextTab(label: 'Women', selected: filter.womenOnly, onTap: _onWomen),
      SizedBox(width: gap),
      _TextTab(
        label: 'Playing now',
        selected: filter.playingNow,
        onTap: _onPlaying,
      ),
    ];

    return SizedBox(
      height: 44.w,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: Row(children: tabs),
      ),
    );
  }
}

/// One plain text tab. The bold weight is always laid out (invisibly) so a
/// selection never shifts its neighbours sideways.
class _TextTab extends StatelessWidget {
  const _TextTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.textPrimary;
    final bold = wallText(13, 17, FontWeight.w700, ink);
    final style = selected
        ? bold
        : wallText(13, 17, FontWeight.w500, ink.withValues(alpha: 0.7));
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 44.w,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Text(label, maxLines: 1, style: bold),
              ),
              Text(label, maxLines: 1, style: style),
            ],
          ),
        ),
      ),
    );
  }
}
