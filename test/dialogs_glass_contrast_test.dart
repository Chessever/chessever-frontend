// Group G5 ("dialogs") of the popup sweep: every ink each converted surface
// draws reads at 4.5:1 or better on its glass, over the busiest page it can
// open on (live boards: white squares and pieces under a light plate, black
// ones under a dark plate), with the scrim it really opens with.
//
// Each surface is drawn empty at its size over the boards, so every pixel
// inside it is plate; the 0.5th and 99.5th percentile pixels (single grain
// specks are not what a glyph sits on) decide.
import 'dart:ui' as ui;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/glass_dialog_route.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessever2/widgets/profile_avatar_editor.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dialogs_harness.dart';

class _Case {
  const _Case(
    this.name, {
    required this.size,
    required this.radius,
    required this.tone,
    required this.inks,
    this.scrim,
    this.dark = false,
    this.cover,
    this.page,
    this.noFrost = false,
  });

  final String name;
  final Size size;
  final double radius;
  final Color Function(BuildContext context) tone;

  /// The scrim it opens with; null: the glass route's own.
  final Color Function(BuildContext context)? scrim;

  /// Dark in both themes ([FixedDarkPopupGlass]).
  final bool dark;

  /// The plate's coverage the surface asks for (null: the theme's).
  final double? Function(BuildContext context)? cover;
  final Map<String, Color> Function(BuildContext context) inks;

  /// What the glass is solved over, when the surface names it.
  final Color Function(BuildContext context)? page;

  /// Drawn under [PopupGlassNoFrost], as the surface is.
  final bool noFrost;
}

final _cases = <_Case>[
  _Case(
    'race stop',
    size: const Size(345, 150),
    radius: 4,
    tone: (c) => c.colors.surface,
    cover: (c) => c.isLightTheme ? null : 0.92,
    inks: (c) => {
      'title': c.colors.textPrimary,
      'body': c.colors.textSecondary,
    },
  ),
  _Case(
    'board teaching',
    size: const Size(345, 330),
    radius: 12,
    tone: (c) => c.colors.surfaceElevated,
    inks: (c) => {'copy': c.colors.textPrimary, 'Got it': c.colors.accentText},
  ),
  _Case(
    'rewarded choice',
    size: const Size(352, 300),
    radius: 20,
    dark: true,
    tone: (_) => const Color(0xFF242A30),
    scrim: (_) => Colors.black.withValues(alpha: 0.56),
    inks: (_) => {
      'title': const Color(0xFFF5F7FA),
      'body': const Color(0xFFC5CDD6),
    },
  ),
  _Case(
    'interstitial intro',
    size: const Size(313, 230),
    radius: 28,
    tone: (c) => DialogTheme.of(c).backgroundColor ?? c.colors.popup,
    inks: (c) => {
      'title': Theme.of(c).colorScheme.onSurface,
      'body': Theme.of(c).colorScheme.onSurfaceVariant,
      'Skip': Theme.of(c).colorScheme.primary,
    },
  ),
  _Case(
    'update prompt',
    size: const Size(313, 300),
    radius: 20,
    tone: (c) => c.colors.popup,
    inks: (c) => {
      'title': c.colors.textPrimary,
      'body': c.colors.textPrimaryMuted,
    },
  ),
  // Anchored, with no scrim at all: the page under them is at full
  // strength.
  _Case(
    'nudge tooltip',
    size: const Size(320, 190),
    radius: 14,
    tone: (c) => c.colors.popup,
    scrim: (_) => Colors.transparent,
    inks: (c) => {'copy': c.colors.textPrimary},
  ),
  _Case(
    'discovery bubble',
    size: const Size(300, 70),
    radius: 14,
    tone: (c) => c.isLightTheme ? c.colors.popup : const Color(0xFF08080A),
    scrim: (_) => Colors.transparent,
    inks: (c) => {
      'copy': c.isLightTheme
          ? c.colors.textPrimary
          : Colors.white.withValues(alpha: 0.94),
    },
  ),
  // The lightbox's controls: dark glass a step over its dark stage in both
  // themes, without a live blur (the stage is flat). White type well over
  // 7:1, and the error line in the dark theme's red.
  _Case(
    'avatar controls',
    size: const Size(369, 150),
    radius: 20,
    dark: true,
    noFrost: true,
    tone: ProfileAvatarLightbox.controlsToneOf,
    page: ProfileAvatarLightbox.stageOf,
    scrim: ProfileAvatarLightbox.scrimOf,
    inks: (_) => {
      'name and actions': Colors.white,
      'error line': ProfileAvatarLightbox.errorInk,
    },
  ),
];

void main() {
  setUpAll(() async {
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
  });

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';
    for (final c in _cases) {
      testWidgets('${c.name}: inks clear 4.5:1 on the glass, $theme', (
        tester,
      ) async {
        final context = await pumpDialogsHost(tester, light: light);
        final panel = SizedBox.fromSize(
          size: c.size,
          child: const SizedBox.expand(),
        );
        final radius = BorderRadius.circular(c.radius);
        final Widget glass = c.dark
            ? FixedDarkPopupGlass(
                borderRadius: radius,
                tone: c.tone(context),
                cover: c.cover?.call(context),
                page: c.page?.call(context),
                child: panel,
              )
            : PopupGlass(
                borderRadius: radius,
                tone: c.tone(context),
                cover: c.cover?.call(context),
                page: c.page?.call(context),
                child: panel,
              );
        showGlassDialog<void>(
          context: context,
          scrim: c.scrim?.call(context),
          builder: (_) => Center(
            child: c.noFrost ? PopupGlassNoFrost(child: glass) : glass,
          ),
        );
        await tester.pump();
        await settleDialogs(tester);
        final rect = tester.getRect(find.byType(PopupGlass));
        final pixels = <Color>[];
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(dialogsCapture),
          );
          final image = await boundary.toImage(pixelRatio: 3);
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final inside = rect.deflate(4);
          for (var y = (inside.top * 3).ceil(); y < inside.bottom * 3; y++) {
            for (var x = (inside.left * 3).ceil(); x < inside.right * 3; x++) {
              final i = (y * image.width + x) * 4;
              pixels.add(
                Color.fromARGB(
                  255,
                  data.getUint8(i),
                  data.getUint8(i + 1),
                  data.getUint8(i + 2),
                ),
              );
            }
          }
          image.dispose();
        });
        pixels.sort(
          (a, b) => a.computeLuminance().compareTo(b.computeLuminance()),
        );
        final darkest = pixels[pixels.length ~/ 200];
        final lightest = pixels[pixels.length - 1 - pixels.length ~/ 200];
        String hex(Color c) =>
            '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
        final report = <String>[];
        final worst = <String, double>{};
        final inks = c.inks(context);
        for (final MapEntry(key: name, value: ink) in inks.entries) {
          // An ink with alpha is drawn over the plate it sits on.
          double on(Color ground) =>
              wcagContrast(Color.alphaBlend(ink, ground), ground);
          final ratio = [
            on(darkest),
            on(lightest),
          ].reduce((a, b) => a < b ? a : b);
          worst[name] = ratio;
          report.add('$name ${ratio.toStringAsFixed(2)}:1');
        }
        // ignore: avoid_print
        print(
          'CONTRAST $theme ${c.name}: plate ${hex(darkest)}..${hex(lightest)} '
          '| ${report.join(' | ')}',
        );
        for (final MapEntry(key: name, value: ratio) in worst.entries) {
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '${c.name} $name');
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
