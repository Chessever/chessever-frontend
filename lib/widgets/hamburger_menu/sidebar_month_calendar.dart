import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/calendar/provider/calendar_detail_screen_provider.dart';
import 'package:chessever2/screens/calendar/provider/calendar_month_events_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:motor/motor.dart';

/// The calendar as it lives in the sidebar: one compact month, days with
/// events lifted onto a tonal cell, today edged in its own ink, and a small
/// king leaning on the day a major event starts.
///
/// Only the month on screen is loaded, through the calendar's shared month
/// provider, so paging back to a month just seen costs nothing. Months step
/// within the years the full calendar offers.
class SidebarMonthCalendar extends ConsumerStatefulWidget {
  const SidebarMonthCalendar({
    super.key,
    required this.onDaySelected,
    required this.onOpenFullCalendar,
    this.today,
  });

  /// A day was tapped. It is a local date with no time part.
  final ValueChanged<DateTime> onDaySelected;

  /// The "Full calendar" action.
  final VoidCallback onOpenFullCalendar;

  /// Clock seam for tests. Defaults to now.
  final DateTime? today;

  @override
  ConsumerState<SidebarMonthCalendar> createState() =>
      _SidebarMonthCalendarState();
}

/// Months are counted as `year * 12 + (month - 1)` so stepping and sliding
/// are plain integer and double arithmetic.
int _monthIndex(DateTime date) => date.year * 12 + date.month - 1;
int _yearOfIndex(int index) => index ~/ 12;
int _monthOfIndex(int index) => index % 12 + 1;

/// Days of [year]/[month] on which a major event starts, by the web
/// calendar's rule (`chessever_web_frontend` `broadcast-seo.ts`): rows that
/// share a FIDE event id are one event, which is major when any of its rows
/// carries [CalendarEvent.isMajorEvent] or [CalendarEvent.isMajorUpcoming].
/// Its dates come from the regular FIDE row when there is one, since the
/// major-events scrape can only date an event to its month.
///
/// Only [events] are read, so an event whose rows fall outside the fetched
/// month is judged on the rows that did arrive.
Set<int> majorEventStartDays(
  Iterable<CalendarEvent> events, {
  required int year,
  required int month,
}) {
  final groups = <String, List<CalendarEvent>>{};
  for (final event in events) {
    final fideId = event.fideEventId?.trim() ?? '';
    final key =
        fideId.isNotEmpty
            ? 'fide:$fideId'
            : 'name:${_eventTitleKey(event.name)}:'
                '${event.startDate?.toIso8601String() ?? 'undated'}';
    (groups[key] ??= []).add(event);
  }

  final days = <int>{};
  for (final rows in groups.values) {
    if (!rows.any((r) => r.isMajorEvent || r.isMajorUpcoming)) continue;
    final canonical = rows.firstWhere(
      (r) => !r.isMajorEvent,
      orElse: () => rows.first,
    );
    DateTime? start = canonical.startDate ?? canonical.endDate;
    for (final row in rows) {
      start ??= row.startDate ?? row.endDate;
    }
    if (start == null) continue;
    final day = calendarLocalDay(start);
    if (day.year == year && day.month == month) days.add(day.day);
  }
  return days;
}

/// The web's title cleanup: a trailing ` *` marks nothing about identity.
String _eventTitleKey(String name) => name
    .trim()
    .replaceAll(RegExp(r'\s+\*+\s*$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .toLowerCase();

class _SidebarMonthCalendarState extends ConsumerState<SidebarMonthCalendar> {
  /// No overshoot: a bounce would flash a sliver of the month beyond.
  static const _slide = CupertinoMotion.smooth(
    duration: Duration(milliseconds: 420),
    snapToEnd: true,
  );

  late final DateTime _today = DateUtils.dateOnly(
    widget.today ?? DateTime.now(),
  );
  late int _month = _monthIndex(_today);

  /// Event days of months already loaded, so a month sliding out keeps its
  /// marks. Only the month being moved to is ever watched.
  final Map<int, Set<int>> _seenDays = {};

  /// Major-event start days, kept beside [_seenDays] for the same reason.
  final Map<int, Set<int>> _seenMajor = {};

  /// Start days worked out once per fetched month, not on every build.
  final Expando<Set<int>> _majorOf = Expando('sidebarMajorStartDays');

  void _step(int delta, int first, int last) {
    final next = (_month + delta).clamp(first, last);
    if (next == _month) return;
    HapticFeedbackService.selection();
    setState(() => _month = next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final years = ref.watch(availableYearsProvider);
    final firstIndex = years.reduce(math.min) * 12;
    final lastIndex = years.reduce(math.max) * 12 + 11;
    final month = _month.clamp(firstIndex, lastIndex);

    final monthArgs = CalendarFilterArgs(
      month: _monthOfIndex(month),
      year: _yearOfIndex(month),
    );
    final monthAsync = ref.watch(calendarMonthEventsProvider(monthArgs));
    final monthData = monthAsync.valueOrNull;
    final loaded = monthData?.eventDays;
    if (loaded != null) _seenDays[month] = loaded;
    final majorLoaded =
        monthData == null
            ? null
            : _majorOf[monthData] ??= majorEventStartDays(
              monthData.calendarEvents,
              year: monthData.year,
              month: monthData.month,
            );
    if (majorLoaded != null) _seenMajor[month] = majorLoaded;
    // A failed month would otherwise read exactly like a month with no
    // events, so it says so under the grid and offers another try.
    final failed = monthAsync.hasError && !monthAsync.hasValue;

    final localizations = MaterialLocalizations.of(context);
    final firstWeekday = localizations.firstDayOfWeekIndex;
    final animate = !MediaQuery.disableAnimationsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = 16.sp;
        final gridWidth = constraints.maxWidth - gutter * 2;
        final column = gridWidth / 7;
        final cell = (column - 4).clamp(24.0, 36.0);
        final rowHeight = cell + 4;
        final gridHeight = rowHeight * 6;
        // Title and action start where the first cell's edge does.
        final inset = (column - cell) / 2;
        // Pull the chevrons right until the last glyph centres on the last
        // column, without letting the 44pt box leave the drawer.
        final chevronRight = math.max(0.0, gutter - (22 - column / 2));

        Widget grid(int index) {
          return _MonthGrid(
            year: _yearOfIndex(index),
            month: _monthOfIndex(index),
            eventDays: index == month ? loaded : _seenDays[index],
            majorDays: index == month ? majorLoaded : _seenMajor[index],
            today: _today,
            firstWeekday: firstWeekday,
            cell: cell,
            rowHeight: rowHeight,
            onDayTap: (date) {
              HapticFeedbackService.navigation();
              widget.onDaySelected(date);
            },
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: gutter + inset,
                right: chevronRight,
              ),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        header: true,
                        // Scaled down rather than cut: at a large text scale
                        // "September 2026" is wider than the space the two
                        // 44pt chevrons leave on a 360dp phone's drawer.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            DateFormat('MMMM y').format(
                              DateTime(
                                _yearOfIndex(month),
                                _monthOfIndex(month),
                              ),
                            ),
                            key: const ValueKey('sidebar_calendar_title'),
                            maxLines: 1,
                            softWrap: false,
                            style: AppTypography.textSmSemiBold.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _MonthStepButton(
                      icon: Icons.chevron_left_rounded,
                      label: 'Previous month',
                      onTap: month > firstIndex
                          ? () => _step(-1, firstIndex, lastIndex)
                          : null,
                    ),
                    _MonthStepButton(
                      icon: Icons.chevron_right_rounded,
                      label: 'Next month',
                      onTap: month < lastIndex
                          ? () => _step(1, firstIndex, lastIndex)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 24,
                  child: Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: Center(
                            child: Text(
                              localizations.narrowWeekdays[(firstWeekday + i) %
                                  7],
                              textScaler: MediaQuery.textScalerOf(
                                context,
                              ).clamp(maxScaleFactor: 1.2),
                              style: AppTypography.textXxsMedium.copyWith(
                                color: colors.textSecondary,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: SizedBox(
                height: gridHeight,
                child: ClipRect(
                  clipper: const _GridClipper(),
                  child: SingleMotionBuilder(
                    motion: _slide,
                    active: animate,
                    value: month.toDouble(),
                    builder: (context, position, _) {
                      return _SlidingMonths(
                        position: position,
                        width: gridWidth,
                        height: gridHeight,
                        builder: grid,
                      );
                    },
                  ),
                ),
              ),
            ),
            if (failed)
              Padding(
                padding: EdgeInsets.only(left: gutter + inset, top: 4),
                child: _MonthLoadNotice(
                  retrying: monthAsync.isLoading,
                  onRetry: () {
                    HapticFeedbackService.buttonPress();
                    ref.invalidate(calendarMonthEventsProvider(monthArgs));
                  },
                ),
              ),
            Padding(
              padding: EdgeInsets.only(left: gutter + inset - 10, top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  key: e2eKey(E2eIds.drawerFullCalendar),
                  onTap: () {
                    HapticFeedbackService.navigation();
                    widget.onOpenFullCalendar();
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          'Full calendar',
                          style: AppTypography.textSmMedium.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Room the grid's clip leaves above its first week, where a king standing
/// on a top-row day rises past the grid's edge.
const double _kingHeadroom = 8;

/// Clips the sliding months to the grid's width, plus [_kingHeadroom] above
/// and 2 to the right, so a king on a top-row or last-column day is never
/// shaved. The right margin is half the gap between days: during a slide it
/// shows nothing of the next month, whose first day starts past it.
class _GridClipper extends CustomClipper<Rect> {
  const _GridClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -_kingHeadroom, size.width + 2, size.height);

  @override
  bool shouldReclip(_GridClipper oldClipper) => false;
}

/// Lays the month at [position] side by side with its neighbour, offset by
/// the fractional part, so a month change is one continuous slide with both
/// months fully drawn. At rest only one month is built.
class _SlidingMonths extends StatelessWidget {
  const _SlidingMonths({
    required this.position,
    required this.width,
    required this.height,
    required this.builder,
  });

  final double position;
  final double width;
  final double height;
  final Widget Function(int index) builder;

  @override
  Widget build(BuildContext context) {
    final base = position.floor();
    final t = position - base;
    final visible = <(int, double)>[
      if (t < 0.999) (base, -t * width),
      if (t > 0.001) (base + 1, (1 - t) * width),
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final (index, left) in visible)
          Positioned(
            key: ValueKey(index),
            left: left,
            top: 0,
            width: width,
            height: height,
            child: builder(index),
          ),
      ],
    );
  }
}

/// Six weeks of one month, so the block keeps one height from month to
/// month. Weeks are completed with the neighbouring months' dates, a step
/// fainter than a quiet day and inert; the chevrons move months.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.year,
    required this.month,
    required this.eventDays,
    this.majorDays,
    required this.today,
    required this.firstWeekday,
    required this.cell,
    required this.rowHeight,
    required this.onDayTap,
  });

  final int year;
  final int month;

  /// Null until the month has loaded.
  final Set<int>? eventDays;

  /// Days a major event starts on. Null until the month has loaded.
  final Set<int>? majorDays;
  final DateTime today;
  final int firstWeekday;
  final double cell;
  final double rowHeight;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    // DateTime.weekday runs Monday 1 .. Sunday 7; `% 7` gives the Sunday-0
    // index MaterialLocalizations uses.
    final leading = (DateTime(year, month).weekday % 7 - firstWeekday) % 7;
    final days = DateUtils.getDaysInMonth(year, month);
    final known = eventDays;

    // Marks settle in once the month arrives instead of snapping on.
    return SingleMotionBuilder(
      motion: const CupertinoMotion.smooth(
        duration: Duration(milliseconds: 280),
        snapToEnd: true,
      ),
      active: !MediaQuery.disableAnimationsOf(context),
      value: known == null ? 0.0 : 1.0,
      builder: (context, marks, _) {
        return Column(
          children: [
            for (var week = 0; week < 6; week++)
              SizedBox(
                height: rowHeight,
                child: Row(
                  children: [
                    for (var weekday = 0; weekday < 7; weekday++)
                      Expanded(
                        child: Center(
                          child: Builder(
                            builder: (context) {
                              final day = week * 7 + weekday - leading + 1;
                              final date = DateTime(year, month, day);
                              if (day < 1 || day > days) {
                                return _SpillDay(day: date.day, side: cell);
                              }
                              return _DayCell(
                                key: ValueKey('sidebar_day_$year-$month-$day'),
                                date: date,
                                side: cell,
                                hasEvents: known?.contains(day),
                                majorStart: majorDays?.contains(day) == true,
                                marks: marks.clamp(0.0, 1.0),
                                isToday: date == today,
                                onTap: () => onDayTap(date),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A date from the month before or after, completing a week. Carries no
/// marks and takes no taps; the chevrons move months.
class _SpillDay extends StatelessWidget {
  const _SpillDay({required this.day, required this.side});

  final int day;
  final double side;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: side,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$day',
              textAlign: TextAlign.center,
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.3),
              // The faintest of the three steps, and still 4.5:1.
              style: _dayNumberStyle(
                weight: FontWeight.w400,
                color: context.colors.textPrimary.withValues(
                  alpha: _spillDayAlpha(context.isLightTheme),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Day numbers step down in three clear steps of primary ink: a day with
/// events (full ink, bold, on its lifted cell), a quiet day, and a date from
/// a neighbouring month. Each step clears 4.5:1 on the drawer in both
/// themes, so the faintest date still reads; paper needs more ink than
/// black for the same contrast.
double _quietDayAlpha(bool isLight) => isLight ? 0.8 : 0.65;
double _spillDayAlpha(bool isLight) => isLight ? 0.63 : 0.47;

TextStyle _dayNumberStyle({required FontWeight weight, required Color color}) {
  return AppTypography.textXsMedium.copyWith(
    fontSize: 13.f,
    height: 1.0,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: weight,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: color,
  );
}

class _DayCell extends StatefulWidget {
  const _DayCell({
    super.key,
    required this.date,
    required this.side,
    required this.hasEvents,
    this.majorStart = false,
    required this.marks,
    required this.isToday,
    required this.onTap,
  });

  final DateTime date;
  final double side;

  /// Null while the month is loading.
  final bool? hasEvents;

  /// A major event starts on this day.
  final bool majorStart;

  /// 0..1 as the month's marks settle in.
  final double marks;
  final bool isToday;
  final VoidCallback onTap;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lit = widget.hasEvents == true ? widget.marks : 0.0;
    var fill = colors.surface.withValues(alpha: colors.surface.a * lit);
    if (_pressed) {
      fill = Color.alphaBlend(colors.textPrimary.withValues(alpha: 0.08), fill);
    }
    final isLight = context.isLightTheme;
    final quiet = _quietDayAlpha(isLight);
    final ink = colors.textPrimary.withValues(
      alpha: quiet + (1 - quiet) * lit,
    );

    final label = StringBuffer(DateFormat('EEEE d MMMM').format(widget.date));
    if (widget.isToday) label.write(', today');
    if (widget.hasEvents == true) label.write(', has events');
    if (widget.hasEvents == false) label.write(', no events');
    if (widget.majorStart) label.write(', major event starts');

    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final numberStyle = _dayNumberStyle(
      weight: lit > 0.5 ? FontWeight.w600 : FontWeight.w400,
      color: ink,
    );

    final cell = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(4),
        // Today carries an edge in its own ink rather than a new colour,
        // strong enough to hold 3:1 on paper as well as on black.
        border: widget.isToday
            ? Border.all(
                color: colors.textPrimary.withValues(
                  alpha: isLight ? 0.6 : 0.45,
                ),
              )
            : null,
      ),
      child: SizedBox.square(
        dimension: widget.side,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${widget.date.day}',
              textAlign: TextAlign.center,
              textScaler: scaler,
              style: numberStyle,
            ),
          ),
        ),
      ),
    );

    final kingBox = widget.majorStart
        ? majorKingBox(
            side: widget.side,
            digitSize: scaler.scale(numberStyle.fontSize!),
          )
        : null;

    return Semantics(
      button: true,
      label: label.toString(),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: kingBox == null
            ? cell
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  cell,
                  Positioned.fromRect(
                    rect: kingBox,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: MajorKingPainter(
                          ink: colors.accentText,
                          // The drawer's own colour: where the king crosses
                          // the day's lifted cell or today's edge it cuts a
                          // clean notch, like a badge, and elsewhere the
                          // edge is invisible.
                          knockout: colors.background,
                          lean: _kingLean * widget.marks,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// How far the king leans into its day once the month's marks settle: it
/// arrives upright and tips over onto the cell.
const double _kingLean = -12 * math.pi / 180;

/// Gap the king's cut-out edge keeps from the top of the day's figures.
const double _kingDigitClearance = 1.2;

/// The box [MajorKingPainter] draws in on a day cell of [side] whose number
/// is set at [digitSize], in the cell's own coordinates.
///
/// The king stands on the cell's top-right corner like a badge: its base sits
/// in the band above the figures and it rises past the cell's top edge into
/// the gap between weeks. Its lowest point, cut-out edge and lean included,
/// stops [_kingDigitClearance] short of the figures, which stand 0.73em tall
/// and centred in the cell as the number is set (Inter, line height 1.0). On
/// the right it reaches 2 past the cell, half the gap to the next day.
///
/// The bounds were measured on the rotated glyph: the cut-out edge reaches
/// 0.33 of the box right of the base's middle and 0.09 of it below the base
/// once leaning.
@visibleForTesting
Rect majorKingBox({required double side, required double digitSize}) {
  final k = (side * 0.40).clamp(10.0, 12.5);
  final figuresTop = side / 2 - 0.37 * digitSize;
  final baseMiddle = Offset(
    side + 2 - 0.33 * k,
    figuresTop - _kingDigitClearance - 0.09 * k,
  );
  return Rect.fromLTWH(baseMiddle.dx - k / 2, baseMiddle.dy - k, k, k);
}

/// A Staunton king in a 24-unit square, standing on its bottom edge. Drawn,
/// not an asset: it has to lean, and carry a cut-out edge in the colour
/// under it.
final Path _kingGlyph = Path()
  // Cross.
  ..addRRect(
    RRect.fromLTRBR(11.0, 0.4, 13.0, 5.2, const Radius.circular(1.0)),
  )
  ..addRRect(
    RRect.fromLTRBR(9.2, 2.2, 14.8, 4.2, const Radius.circular(1.0)),
  )
  // Crown.
  ..moveTo(5.6, 6.9)
  ..cubicTo(5.4, 6.2, 5.9, 5.6, 6.6, 5.6)
  ..lineTo(17.4, 5.6)
  ..cubicTo(18.1, 5.6, 18.6, 6.2, 18.4, 6.9)
  ..lineTo(17.1, 10.6)
  ..lineTo(6.9, 10.6)
  ..close()
  // Collar.
  ..addRRect(
    RRect.fromLTRBR(7.4, 11.4, 16.6, 13.0, const Radius.circular(0.8)),
  )
  // Body.
  ..moveTo(9.3, 13.8)
  ..lineTo(14.7, 13.8)
  ..lineTo(16.2, 19.0)
  ..lineTo(7.8, 19.0)
  ..close()
  // Base.
  ..addRRect(
    RRect.fromLTRBR(5.4, 19.8, 18.6, 23.2, const Radius.circular(1.2)),
  );

/// Paints the major-event king: a cut-out edge in [knockout] (the drawer's
/// colour, so a lifted cell or today's edge stops cleanly short of the king),
/// then the king in [ink], leaning by [lean] radians about the middle of its
/// base.
@visibleForTesting
class MajorKingPainter extends CustomPainter {
  const MajorKingPainter({
    required this.ink,
    required this.knockout,
    required this.lean,
  });

  final Color ink;
  final Color knockout;
  final double lean;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(size.width / 2, size.height)
      ..rotate(lean)
      ..scale(size.width / 24)
      ..translate(-12, -24);
    canvas.drawPath(
      _kingGlyph,
      Paint()
        ..color = knockout
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(_kingGlyph, Paint()..color = ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(MajorKingPainter oldDelegate) =>
      oldDelegate.ink != ink ||
      oldDelegate.knockout != knockout ||
      oldDelegate.lean != lean;
}

/// One quiet line under the grid when the month on screen failed to load,
/// with a retry that asks for that month again. The day cells stay as they
/// are; this line is what tells a failure apart from an empty month.
class _MonthLoadNotice extends StatelessWidget {
  const _MonthLoadNotice({required this.retrying, required this.onRetry});

  /// A retry is in flight; the action rests until it answers.
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Flexible(
          child: Semantics(
            liveRegion: true,
            child: Text(
              "Couldn't load events",
              key: const ValueKey('sidebar_calendar_error'),
              style: AppTypography.textSmRegular.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
        InkWell(
          key: const ValueKey('sidebar_calendar_retry'),
          onTap: retrying ? null : onRetry,
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                widthFactor: 1,
                child: Text(
                  'Retry',
                  style: AppTypography.textSmMedium.copyWith(
                    color: colors.textPrimary.withValues(
                      alpha: retrying ? 0.4 : 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MonthStepButton extends StatelessWidget {
  const _MonthStepButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.iconPrimary;
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: label,
        padding: EdgeInsets.zero,
        onPressed: onTap,
        color: ink,
        disabledColor: ink.withValues(alpha: 0.25),
        icon: Icon(icon, size: 22.ic),
      ),
    );
  }
}
