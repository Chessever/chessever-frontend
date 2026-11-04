import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/library/models/shared_book_preview.dart';
import 'package:chessever2/screens/library/book_preview_screen.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'fixtures/duo_window_matrix.dart';

const _bookName = 'World championship preparation and annotated training games';
const _preview = SharedBookPreview(
  id: 'shared-book',
  name: _bookName,
  color: '#0FB4E5',
  icon: 'folder',
  ownerDisplayName: 'A player with a long display name',
  gameCount: 1200,
);

void _window(WidgetTester tester) {
  addTearDown(tester.view.reset);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1.6;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  for (final light in [false, true]) {
    for (final previewState in ['loading', 'loaded', 'missing', 'error']) {
      testWidgets(
        '${light ? 'light' : 'dark'} shared book $previewState survives all Duo cold starts and transitions',
        (tester) async {
          _window(tester);
          final matrix = [
            for (final window in duoWindowCases) (from: window, to: window),
            ...duoWindowTransitions,
          ];
          for (final transition in matrix) {
            applyDuoWindow(tester, transition.from);
            final pending = Completer<SharedBookPreview?>();
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  currentUserProvider.overrideWithValue(null),
                  sharedBookPreviewProvider('token').overrideWith((ref) async {
                    return switch (previewState) {
                      'loading' => pending.future,
                      'loaded' => _preview,
                      'missing' => null,
                      _ => throw StateError(
                        'Preview is temporarily unavailable',
                      ),
                    };
                  }),
                ],
                child: MaterialApp(
                  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
                  builder: (_, child) => AdaptiveWindowScope(child: child!),
                  home: const BookPreviewScreen(shareToken: 'token'),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 500));
            final state = tester.state(find.byType(BookPreviewScreen));
            final route = ModalRoute.of(
              tester.element(find.byType(BookPreviewScreen)),
            );
            for (final window in [transition.from, transition.to]) {
              applyDuoWindow(
                tester,
                window,
                mirrorInsets: window == transition.to,
              );
              await tester.pump(const Duration(milliseconds: 500));
              expect(tester.takeException(), isNull, reason: window.name);
              expect(tester.state(find.byType(BookPreviewScreen)), same(state));
              expect(
                ModalRoute.of(tester.element(find.byType(BookPreviewScreen))),
                same(route),
              );
              if (previewState == 'loading') {
                expect(find.byType(CircularProgressIndicator), findsOneWidget);
              } else {
                expect(
                  find.byIcon(Icons.arrow_back_ios_new_rounded).hitTestable(),
                  findsOneWidget,
                );
                final label = switch (previewState) {
                  'loaded' => 'Add to Library',
                  'missing' => 'Folder not found',
                  _ => 'Something went wrong',
                };
                await tester.ensureVisible(find.text(label));
                await tester.pump(const Duration(milliseconds: 100));
                expect(find.text(label).hitTestable(), findsOneWidget);
                expect(tester.takeException(), isNull, reason: window.name);
              }
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          }
        },
      );
    }

    testWidgets(
      '${light ? 'light' : 'dark'} Library rename preserves focused input and result across every Duo transition with the keyboard',
      (tester) async {
        _window(tester);
        for (final transition in duoWindowTransitions) {
          tester.view.viewInsets = const FakeViewPadding();
          applyDuoWindow(tester, transition.from);
          String? result;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                combinedLibraryFoldersProvider.overrideWith((ref) async => []),
              ],
              child: MaterialApp(
                theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
                builder: (_, child) => AdaptiveWindowScope(child: child!),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () async {
                        result = await showRenameFolderDialog(
                          context,
                          currentName: 'Openings',
                        );
                      },
                      child: const Text('Rename folder'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Rename folder'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'My Duo preparation');
          final editable = tester.state<EditableTextState>(
            find.byType(EditableText),
          );
          final route = ModalRoute.of(tester.element(find.byType(TextField)));
          for (final window in [transition.from, transition.to]) {
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            applyDuoWindow(
              tester,
              window,
              mirrorInsets: window == transition.to,
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: window.name);
            expect(
              tester.state<EditableTextState>(find.byType(EditableText)),
              same(editable),
            );
            expect(
              ModalRoute.of(tester.element(find.byType(TextField))),
              same(route),
            );
            expect(editable.widget.controller.text, 'My Duo preparation');
            expect(editable.widget.focusNode.hasFocus, isTrue);
            await tester.ensureVisible(find.text('Save'));
            await tester.pumpAndSettle();
            expect(find.text('Save').hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull, reason: window.name);
          }
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(result, 'My Duo preparation');
          expect(find.byType(TextField), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  }
}
