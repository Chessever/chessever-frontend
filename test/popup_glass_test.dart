// Centred popups: the modal dims the page with a plain scrim (no animated
// full-screen blur), and every popup's surface is the frosted PopupGlass
// panel, its one backdrop filter clipped to the panel and visible from the
// first frame (never under an opacity).
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/collections/collection_search_filters.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup.dart';
import 'package:chessever2/screens/group_event/widget/notice_dialogs.dart';
import 'package:chessever2/screens/library/providers/book_games_search_provider.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/library/miniatures/widgets/miniature_players_filter_dialog.dart';
import 'package:chessever2/screens/library/widgets/book_games_filter_dialog.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/screens/library/widgets/library_gamebase_filter_dialog.dart';
import 'package:chessever2/screens/library/widgets/miniatures_filter_dialog.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_dialogs.dart';
import 'package:chessever2/screens/premium_games/providers/premium_games_provider.dart';
import 'package:chessever2/screens/premium_games/widgets/premium_games_filter.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/game_filter/game_filter_dialog.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu.dart';
import 'package:chessever2/widgets/hamburger_menu/hamburger_menu_dialogs.dart';
import 'package:chessever2/widgets/popup_glass.dart';
import 'package:chessever2/widgets/review_prompt/direct_feedback_dialog.dart';
import 'package:chessever2/widgets/review_prompt/review_prompt_dialogs.dart';
import 'package:chessever2/widgets/shorebird_update_dialog.dart';
import 'package:chessever2/widgets/smooth_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _open = ValueKey('popup_open');
const _screen = Size(393, 852);

typedef _Opener = void Function(BuildContext context);

/// Every popup opener the test drives, by name.
final Map<String, _Opener> _popups = {
  'confirm': (context) => showSmoothConfirmDialog(
    context: context,
    title: 'Remove Smart Event?',
    message: 'You can restore it with Undo.',
    confirmText: 'Remove',
    isDangerous: true,
  ),
  'notice': (context) =>
      showSimpleDialog(context: context, message: 'Saved to your library.'),
  'Today / Events filter': (context) => showAlertModal<void>(
    context: context,
    horizontalPadding: 0,
    child: FilterPopup(onApplyFilters: (_) {}, onResetFilters: () {}),
  ),
  'games filter': (context) =>
      showGameFilterDialog(context: context, currentFilter: GameFilter()),
  'collection search filters': (context) =>
      showCollectionSearchFilters(context, const CollectionSearchQuery()),
  'book games filter': (context) => showBookGamesFilterDialog(
    context: context,
    currentFilter: const BookGamesFilter(),
  ),
  'miniatures filter': (context) => showMiniaturesFilterDialog(
    context: context,
    currentFilter: const MiniatureGamesFilter(),
  ),
  'miniature players filter': (context) => showMiniaturePlayersFilterDialog(
    context: context,
    currentQuery: const MiniaturePlayersQuery(),
  ),
  'database filter': (context) => showLibraryGamebaseFilterDialog(
    context: context,
    currentFilter: GamebaseFilter(),
  ),
  'premium games filter': (context) => showPremiumGamesFilterDialog(
    context: context,
    type: PremiumGamesType.values.first,
    currentFilter: const PremiumGamesFilter(),
  ),
  'rename folder': (context) =>
      showRenameFolderDialog(context, currentName: 'Najdorf prep'),
  'prep rename': (context) => showPrepRenameDialog(context, 'Carlsen'),
  // Popups whose glass is cut from another tone than the surface.
  'review prompt': showReviewFlowDialog,
  'direct feedback': showDirectFeedbackDialog,
  'about': (context) => showChessEverAbout(context, '39.0.1'),
  'delete account': showDeleteAccountDialog,
  'update prompt': (context) => showAlertModal<void>(
    context: context,
    child: const ShorebirdUpdateDialog(),
  ),
};

Future<void> _pumpHost(
  WidgetTester tester,
  _Opener opener, {
  bool light = false,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = _screen * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => TextButton(
                    key: _open,
                    onPressed: () => opener(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _tapOpen(WidgetTester tester) async {
  tester.widget<TextButton>(find.byKey(_open)).onPressed!();
  await tester.pump();
}

/// The backdrop filters on screen, with their sizes.
Iterable<(BackdropFilter, Size)> _backdrops(WidgetTester tester) => find
    .byType(BackdropFilter)
    .evaluate()
    .map(
      (e) => (e.widget as BackdropFilter, (e.renderObject! as RenderBox).size),
    );

/// Whether any render object between [finder]'s and the root fades it.
bool _underOpacity(WidgetTester tester, Finder finder) {
  RenderObject? node = tester.renderObject(finder).parent;
  while (node != null) {
    if (node is RenderOpacity && node.opacity < 1) return true;
    if (node is RenderAnimatedOpacity && node.opacity.value < 1) return true;
    node = node.parent;
  }
  return false;
}

void main() {
  testWidgets('the modal dims with a plain scrim and never blurs the screen', (
    tester,
  ) async {
    await _pumpHost(tester, _popups['confirm']!);
    await _tapOpen(tester);
    // Every frame of the open, including the first: no backdrop filter
    // covers the screen, the panel is the only one, and nothing fades it.
    final scrimAlphas = <double>[];
    for (var frame = 0; frame < 30; frame++) {
      final backdrops = _backdrops(tester).toList();
      expect(backdrops, hasLength(1), reason: 'frame $frame');
      final (filter, size) = backdrops.single;
      expect(size.width, lessThan(_screen.width), reason: 'frame $frame');
      expect(size.height, lessThan(_screen.height), reason: 'frame $frame');
      // The panel's frost is at full strength from the first frame.
      expect(
        filter.filter.toString(),
        contains(
          'blur(${PopupGlassStyle.blurSigma}, ${PopupGlassStyle.blurSigma}',
        ),
      );
      expect(_underOpacity(tester, find.byType(PopupGlass)), isFalse);
      expect(find.text('Remove Smart Event?'), findsOneWidget);
      // The scrim: the topmost screen-sized tint.
      final scrim = find
          .byType(ColoredBox)
          .evaluate()
          .where((e) => (e.renderObject! as RenderBox).size == _screen)
          .last;
      scrimAlphas.add((scrim.widget as ColoredBox).color.a);
      await tester.pump(const Duration(milliseconds: 16));
    }
    // The scrim fades in, then holds.
    expect(scrimAlphas.first, 0);
    expect(scrimAlphas.last, greaterThan(0.2));
    for (var i = 1; i < scrimAlphas.length; i++) {
      expect(scrimAlphas[i], greaterThanOrEqualTo(scrimAlphas[i - 1]));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final entry in _popups.entries) {
    testWidgets('${entry.key} sits on the glass panel', (tester) async {
      await _pumpHost(tester, entry.value);
      await _tapOpen(tester);
      await tester.pumpAndSettle();

      final glass = find.byType(PopupGlass);
      expect(glass, findsOneWidget);
      // One backdrop filter, the panel's, clipped to the panel.
      final panel = tester.getRect(glass);
      final filters = find.descendant(
        of: glass,
        matching: find.byType(BackdropFilter),
      );
      expect(filters, findsOneWidget);
      expect(_backdrops(tester), hasLength(1));
      expect(
        find.ancestor(of: filters, matching: find.byType(ClipRRect)),
        findsWidgets,
      );
      expect(tester.getRect(filters).width, lessThanOrEqualTo(panel.width));
      expect(_underOpacity(tester, glass), isFalse);
      expect(tester.takeException(), isNull);

      // A tap outside still dismisses it.
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(glass, findsNothing);
    });
  }

  for (final light in [false, true]) {
    testWidgets(
      'the glass averages to the popup\'s own tone over the dimmed page, '
      '${light ? 'light' : 'dark'}',
      (tester) async {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        );
        final colors = context.colors;
        for (final tone in [
          colors.surface,
          colors.background,
          colors.surfaceElevated,
          colors.popup,
        ]) {
          final style = PopupGlassStyle.of(context, tone: tone);
          // What the scrim leaves of the page under the popup.
          final page = Color.alphaBlend(
            colors.scrim.withValues(alpha: style.scrim),
            colors.background,
          );
          final seen = Color.alphaBlend(style.plate, page);
          // Within one 8-bit step, unless the tone is brighter than any
          // plate can reach over that page (then the plate is white).
          for (final (got, want) in [
            (seen.r, tone.r),
            (seen.g, tone.g),
            (seen.b, tone.b),
          ]) {
            if (style.plate.r >= 1 ||
                style.plate.g >= 1 ||
                style.plate.b >= 1) {
              expect(got, closeTo(want, 0.03), reason: '$tone');
            } else {
              expect(got, closeTo(want, 1 / 255), reason: '$tone');
            }
          }
          // Dense enough to carry text, translucent enough to be glass.
          expect(style.plate.a, inInclusiveRange(0.8, 0.92));
        }
      },
    );
  }

  testWidgets('light theme: the panel is the same glass', (tester) async {
    await _pumpHost(tester, _popups['Today / Events filter']!, light: true);
    await _tapOpen(tester);
    await tester.pumpAndSettle();
    expect(find.byType(PopupGlass), findsOneWidget);
    expect(_backdrops(tester), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('showSmoothDialog shows its popup from the first frame', (
    tester,
  ) async {
    await _pumpHost(
      tester,
      (context) => showSmoothDialog<void>(
        context: context,
        anchorToBottom: false,
        builder: (context) => PopupGlass(
          borderRadius: BorderRadius.circular(16),
          padding: const EdgeInsets.all(24),
          child: const Text('Smooth'),
        ),
      ),
    );
    await _tapOpen(tester);
    expect(find.text('Smooth'), findsOneWidget);
    expect(_underOpacity(tester, find.byType(PopupGlass)), isFalse);
    await tester.pumpAndSettle();
    expect(_underOpacity(tester, find.byType(PopupGlass)), isFalse);
  });
}
