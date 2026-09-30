import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The fire palette the streak designs share: the flame, the embers, the
/// level word and the share card's squares. The player card's result squares
/// do not burn; they take [streakResultTone] instead.
abstract final class StreakFire {
  /// Outer flame; every win on the share card.
  static const Color outer = Color(0xFFE4552A);

  /// Mid flame; also the level word ("On fire").
  static const Color mid = Color(0xFFF59A3C);

  /// The latest win on the share card.
  static const Color light = Color(0xFFFFB454);

  static const Color core = Color(0xFFFFE08A);

  /// The anchor loss on the share card.
  static const Color loss = Color(0xFFF5453A);

  static const List<Color> embers = [outer, mid, light, core];

  /// The level word in the page's own theme. On the light surface the design's
  /// orange sits under 2:1, so it steps down to a burnt tone of the same hue.
  static Color warmInk(BuildContext context) =>
      context.isLightTheme ? const Color(0xFFA8481A) : mid;
}

/// A result square's fill and the ink of its 1 or 0.
typedef StreakTone = ({Color fill, Color ink});

/// How a result square reads on the player card: a quiet step off the page,
/// never a wash. A win is a low tint of the app's win green with the 1 in
/// that green, the latest win one step deeper; the anchor loss is a plain
/// tile with only its 0 in the loss red. Fills are pre-blended, so a square
/// is opaque, and every ink clears 4.5:1 on its fill in both themes.
StreakTone streakResultToneFor(
  AppColors c, {
  required bool light,
  required bool win,
  bool latest = false,
}) {
  if (!win) return (fill: c.surface, ink: c.danger);
  final ink = light ? c.successStrong : c.success;
  // Past 0.28 on dark (0.22 on light) the 1 drops under 4.5:1.
  final alpha = latest ? (light ? 0.20 : 0.26) : 0.14;
  return (
    fill: Color.alphaBlend(ink.withValues(alpha: alpha), c.surface),
    ink: ink,
  );
}

/// [streakResultToneFor] in the page's own theme.
StreakTone streakResultTone(
  BuildContext context, {
  required bool win,
  bool latest = false,
}) => streakResultToneFor(
  context.colors,
  light: context.isLightTheme,
  win: win,
  latest: latest,
);

const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

/// Page text at the design's point size, line height and weight.
///
/// Words stay proportional. Inter's tabular set also re-spaces the space,
/// the hyphen and the full stop, so a whole line set tabular reads
/// "Vachier - Lagrave". Pass [tabular] for a bare figure that must hold its
/// width (a count, a result mark, a rating). A line that mixes words and
/// figures goes through [streakFigures] instead, so only its digits are
/// tabular.
TextStyle streakText(
  BuildContext context, {
  required double size,
  required double line,
  FontWeight weight = FontWeight.w500,
  Color? color,
  bool tabular = false,
}) {
  return AppTypography.textXsMedium.copyWith(
    fontSize: size.f,
    height: line / size,
    fontWeight: weight,
    color: color ?? context.colors.textPrimary,
    fontFeatures: tabular ? _tabular : null,
  );
}

final RegExp _figureRun = RegExp(r'\d+');

/// [text] with tabular figures on its digit runs only. `GM · 2733 · China ·
/// 33 y` keeps its rating and age at a fixed width, and the words, spaces
/// and separators keep their natural spacing. [style] covers the whole span;
/// a figure inherits it and adds only the tabular feature. Set it with
/// `Text.rich`, which reads the same plain text as `Text`.
TextSpan streakFigures(String text, {TextStyle? style}) {
  final runs = _figureRun.allMatches(text);
  if (runs.isEmpty) return TextSpan(text: text, style: style);
  final children = <InlineSpan>[];
  var at = 0;
  for (final m in runs) {
    if (m.start > at) {
      children.add(TextSpan(text: text.substring(at, m.start)));
    }
    children.add(
      TextSpan(text: m[0], style: const TextStyle(fontFeatures: _tabular)),
    );
    at = m.end;
  }
  if (at < text.length) children.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: style, children: children);
}

/// Display numerals. `.f` caps type at 40, so display sizes scale with the
/// layout (`.w`) instead, and the leading is split evenly like CSS so a tight
/// line height trims the box without lifting the digits out of it.
TextStyle streakDisplay(
  BuildContext context, {
  required double size,
  double line = 1,
  double letterSpacing = 0,
  Color? color,
}) {
  return AppTypography.textXsMedium.copyWith(
    fontSize: size.w,
    height: line,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: FontWeight.w700,
    letterSpacing: letterSpacing.w,
    color: color ?? context.colors.textPrimary,
    fontFeatures: _tabular,
  );
}

/// `2026-09-13…` as a UTC calendar day; anything else is null.
DateTime? streakDay(String? day) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(day?.trim() ?? '');
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime.utc(y, mo, d);
}

/// `Sep 13`, in the app's locale.
String? streakShortDay(String? day) {
  final t = streakDay(day);
  return t == null ? null : DateFormat.MMMd().format(t);
}

/// `Sep 13` this year, `Sep 13, 2025` otherwise.
String? streakListDay(String? day, {DateTime? now}) {
  final t = streakDay(day);
  if (t == null) return null;
  final year = (now ?? DateTime.now()).year;
  return t.year == year
      ? DateFormat.MMMd().format(t)
      : DateFormat.yMMMd().format(t);
}

/// `Mar 2025`.
String streakMonthYear(DateTime t) => DateFormat.yMMM().format(t);

/// The day [g] was played, as the `yyyy-mm-dd…` string [streakDay] reads:
/// its ledger day, else its sort timestamp. A zoned timestamp is read on the
/// viewer's calendar, not by its UTC date, so a late game is not labelled
/// with the next day.
String? streakGameDayOf(StreakGame g) {
  if (streakDay(g.gameDay) != null) return g.gameDay;
  final at = DateTime.tryParse(g.sortAt?.trim() ?? '');
  if (at == null || !at.isUtc) return g.sortAt;
  final t = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}';
}

/// The label under a run square: the day the game was played, `Feb 17`.
/// No year, even for last season: the square has no room for one, and the
/// run's head ('since Dec 18, 2025') and the square's spoken label carry it.
String streakSquareLabel(StreakGame g) =>
    streakShortDay(streakGameDayOf(g)) ?? '';

/// FIDE federation code → country name, falling back to the code itself.
String? streakCountry(String? fed) {
  final f = fed?.trim() ?? '';
  if (f.isEmpty) return null;
  final name = CountryUtils.getCountryName(f);
  return name.isNotEmpty ? name : f.toUpperCase();
}

/// `GM · 2733 · China · 33 y`, with the rating of [tc].
String streakPlayerMeta(PlayerStreaks p, StreakTimeClass tc) {
  final rating = p.ratings[tc];
  final country = streakCountry(p.fed);
  return [
    if (p.title != null) p.title!,
    if (rating != null && rating > 0) '$rating',
    ?country,
    if (p.age != null) '${p.age} y',
  ].join(' · ');
}

/// "classical win" / "classical wins".
String streakWinsWord(StreakTimeClass tc, int n) =>
    '${tc.label.toLowerCase()} ${n == 1 ? 'win' : 'wins'}';

/// Two-letter initials from a stored or display name.
String streakInitials(String name) {
  final display = streakDisplayName(name);
  final parts = display
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) {
    final p = parts.first;
    return p.substring(0, p.length < 2 ? p.length : 2).toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

/// The public link for one player's streak in one class.
String streakShareUrl(int fideId, StreakTimeClass tc) =>
    'https://streaks.chessever.com/p/$fideId?tc=${tc.wire}';
