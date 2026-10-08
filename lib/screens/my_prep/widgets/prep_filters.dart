import 'dart:math' as math;
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:flutter/material.dart';

/// Which side the prepared player had.
enum PrepSide { both, white, black }

/// Desktop's date windows anchor to the latest downloaded game, so historical
/// players can be studied without an empty window relative to today's date.
enum PrepStatsWindow {
  all('All dates', null),
  year('1 year', 365),
  sixMonths('6 months', 180),
  ninetyDays('90 days', 90),
  thirtyDays('30 days', 30);

  const PrepStatsWindow(this.label, this.days);
  final String label;
  final int? days;
}

/// The slice of games every tab of a profile shows.
@immutable
class PrepFilter {
  const PrepFilter({
    this.source,
    this.speed,
    this.side = PrepSide.both,
    this.accountKey,
    this.accountFile,
    this.outcome,
    this.year,
    this.eco,
    this.opening,
    this.opponent,
    this.window = PrepStatsWindow.all,
  });

  final PrepSource? source;
  final PrepTimeControl? speed;
  final PrepSide side;
  final String? accountKey;
  final String? accountFile;
  final PrepOutcome? outcome;
  final int? year;
  final String? eco;
  final String? opening;
  final String? opponent;
  final PrepStatsWindow window;

  bool get hasFacets =>
      outcome != null ||
      year != null ||
      eco != null ||
      opening != null ||
      opponent != null;

  PrepFilter copyWith({
    Object? source = _keep,
    Object? speed = _keep,
    PrepSide? side,
    Object? accountKey = _keep,
    Object? accountFile = _keep,
    Object? outcome = _keep,
    Object? year = _keep,
    Object? eco = _keep,
    Object? opening = _keep,
    Object? opponent = _keep,
    PrepStatsWindow? window,
  }) => PrepFilter(
    source: identical(source, _keep) ? this.source : source as PrepSource?,
    speed: identical(speed, _keep) ? this.speed : speed as PrepTimeControl?,
    side: side ?? this.side,
    accountKey: identical(accountKey, _keep)
        ? this.accountKey
        : accountKey as String?,
    accountFile: identical(accountFile, _keep)
        ? this.accountFile
        : accountFile as String?,
    outcome: identical(outcome, _keep) ? this.outcome : outcome as PrepOutcome?,
    year: identical(year, _keep) ? this.year : year as int?,
    eco: identical(eco, _keep) ? this.eco : eco as String?,
    opening: identical(opening, _keep) ? this.opening : opening as String?,
    opponent: identical(opponent, _keep) ? this.opponent : opponent as String?,
    window: window ?? this.window,
  );

  bool matches(PrepGame g, {DateTime? since}) =>
      (source == null || g.source == source) &&
      (speed == null || g.speed == speed) &&
      (accountFile == null || g.sourcePath.endsWith(accountFile!)) &&
      (outcome == null || g.outcome == outcome) &&
      (year == null || g.date?.year == year) &&
      (eco == null || g.eco == eco) &&
      (opening == null || g.openingFamily == opening) &&
      (since == null || (g.date != null && !g.date!.isBefore(since))) &&
      (opponent == null ||
          g.opponent.toLowerCase() == opponent!.toLowerCase()) &&
      switch (side) {
        PrepSide.both => true,
        PrepSide.white => g.playerIsWhite == true,
        PrepSide.black => g.playerIsWhite == false,
      };

  List<PrepGame> apply(List<PrepGame> games) {
    if (source == null &&
        accountFile == null &&
        speed == null &&
        side == PrepSide.both &&
        !hasFacets &&
        window == PrepStatsWindow.all) {
      return games;
    }
    DateTime? latest;
    if (window.days != null) {
      for (final game in games) {
        if (source != null && game.source != source) continue;
        if (accountFile != null && !game.sourcePath.endsWith(accountFile!)) {
          continue;
        }
        final date = game.date;
        if (date != null && (latest == null || date.isAfter(latest))) {
          latest = date;
        }
      }
    }
    final since = latest?.subtract(Duration(days: window.days!));
    return [
      for (final game in games)
        if (matches(game, since: since)) game,
    ];
  }
}

const Object _keep = Object();

/// Source and clock chips, showing only what the downloaded games contain.
class PrepFilterBar extends StatelessWidget {
  const PrepFilterBar({
    super.key,
    required this.games,
    required this.profile,
    required this.filter,
    required this.onChanged,
  });

  final List<PrepGame> games;
  final PrepProfile profile;
  final PrepFilter filter;
  final ValueChanged<PrepFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final speeds = <PrepTimeControl, int>{};
    final sources = <PrepSource>{};
    for (final g in games) {
      if (g.speed != null) speeds[g.speed!] = (speeds[g.speed!] ?? 0) + 1;
      sources.add(g.source);
    }
    final orderedSpeeds = PrepTimeControl.values.where(speeds.containsKey);
    final single = sources.length == 1 ? sources.first : null;
    if (games.isEmpty && profile.accounts.length < 2) {
      return SizedBox(height: 8.h);
    }
    final gutter = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
    return SizedBox(
      height:
          math.max(44, MediaQuery.textScalerOf(context).scale(14) * 1.3 + 20) +
          16,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 8),
        children: [
          if (profile.accounts.length > 1)
            _SourcePicker(
              profile: profile,
              filter: filter,
              onChanged: onChanged,
            ),
          _WindowPicker(filter: filter, onChanged: onChanged),
          PrepChip(
            label: 'All games',
            selected: filter.speed == null,
            onTap: () => onChanged(filter.copyWith(speed: null)),
          ),
          for (final speed in orderedSpeeds)
            PrepChip(
              label: speed.labelFor(filter.source ?? single),
              count: speeds[speed],
              selected: filter.speed == speed,
              onTap: () => onChanged(
                filter.copyWith(speed: filter.speed == speed ? null : speed),
              ),
            ),
        ],
      ),
    );
  }
}

class _WindowPicker extends StatelessWidget {
  const _WindowPicker({required this.filter, required this.onChanged});
  final PrepFilter filter;
  final ValueChanged<PrepFilter> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<PrepStatsWindow>(
    tooltip: 'Choose dates relative to the latest game',
    initialValue: filter.window,
    onSelected: (window) => onChanged(filter.copyWith(window: window)),
    itemBuilder: (_) => [
      for (final window in PrepStatsWindow.values)
        PopupMenuItem(value: window, child: Text(window.label)),
    ],
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      child: Row(
        children: [
          Text(
            filter.window.label,
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          Icon(
            Icons.expand_more_rounded,
            color: context.colors.textSecondary,
            size: 18,
          ),
        ],
      ),
    ),
  );
}

class _SourcePicker extends StatelessWidget {
  const _SourcePicker({
    required this.profile,
    required this.filter,
    required this.onChanged,
  });
  final PrepProfile profile;
  final PrepFilter filter;
  final ValueChanged<PrepFilter> onChanged;
  @override
  Widget build(BuildContext context) {
    final selected = profile.accounts
        .where((a) => a.key == filter.accountKey)
        .firstOrNull;
    return PopupMenuButton<String>(
      tooltip: 'Choose source database',
      initialValue: selected?.key ?? 'combined',
      onSelected: (key) {
        final account = profile.accounts.where((a) => a.key == key).firstOrNull;
        onChanged(
          filter.copyWith(
            source: account?.source,
            accountKey: account?.key,
            accountFile: account == null
                ? null
                : PrepRepository.gamesFileName(account),
          ),
        );
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'combined', child: Text('Combined')),
        for (final account in profile.accounts)
          PopupMenuItem(
            value: account.key,
            child: Row(
              children: [
                PrepSourceMark(source: account.source, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${account.source.label} · ${account.displayName ?? account.username}',
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.w),
        child: Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 210),
              child: Text(
                selected == null
                    ? filter.source?.label ?? 'Combined'
                    : '${selected.source.label} · ${selected.displayName ?? selected.username}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            Icon(
              Icons.expand_more_rounded,
              color: context.colors.textSecondary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact toggle chip; filled ink when on.
class PrepChip extends StatelessWidget {
  const PrepChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = selected ? colors.textInverse : colors.textPrimary;
    return Padding(
      padding: EdgeInsets.only(right: 6.w),
      child: Semantics(
        button: true,
        selected: selected,
        child: TappableScale(
          scaleDown: 0.97,
          onTap: () {
            HapticFeedbackService.selection();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 44),
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.textPrimary : colors.surface,
              borderRadius: BorderRadius.circular(10.br),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[leading!, SizedBox(width: 6.w)],
                Text(
                  label,
                  style: AppTypography.textXsMedium.copyWith(color: ink),
                ),
                if (count != null) ...[
                  SizedBox(width: 5.w),
                  Text(
                    prepCount(count!),
                    style: AppTypography.textXsRegular.copyWith(
                      color: ink.withValues(alpha: 0.6),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// White / Black / Both, as one segmented row.
class PrepSidePicker extends StatelessWidget {
  const PrepSidePicker({
    super.key,
    required this.side,
    required this.onChanged,
    this.mine = false,
  });

  final PrepSide side;
  final ValueChanged<PrepSide> onChanged;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    String label(PrepSide s) => switch (s) {
      PrepSide.both => 'Both colours',
      PrepSide.white => mine ? 'As White' : 'Their White',
      PrepSide.black => mine ? 'As Black' : 'Their Black',
    };
    return Row(
      children: [
        for (final s in [PrepSide.white, PrepSide.black, PrepSide.both])
          PrepChip(
            label: label(s),
            selected: side == s,
            onTap: () => onChanged(s),
          ),
      ],
    );
  }
}
