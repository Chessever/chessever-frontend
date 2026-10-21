import 'dart:async';

import 'package:chessever2/providers/board_engine_lines_visibility_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/settings/widgets/engine_settings_body.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerFor(BoardEngineLinesVisibilityStore store) {
    final container = ProviderContainer(
      overrides: [
        boardEngineLinesVisibilityStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'missing preference preserves legacy Cards/List indices and defaults',
    () async {
      final container = containerFor(_Store());
      expect(
        await container.read(boardEngineLinesVisibleProvider.future),
        isTrue,
      );
      expect(engineLinesViewFromIndex(0), EngineLinesView.cards);
      expect(engineLinesViewFromIndex(1), EngineLinesView.list);
      for (final value in <int?>[null, -1, 2, 999]) {
        expect(engineLinesViewFromIndex(value), EngineLinesView.list);
      }
      expect(const EngineSettings().engineLinesView, EngineLinesView.list);
    },
  );

  for (final saved in [false, true]) {
    test(
      'device preference $saved survives a new provider container',
      () async {
        final store = _Store();
        final first = containerFor(store);
        await first.read(boardEngineLinesVisibleProvider.future);
        await first
            .read(boardEngineLinesVisibleProvider.notifier)
            .setVisible(saved);
        expect(store.value, saved);
        final reopened = containerFor(store);
        expect(
          await reopened.read(boardEngineLinesVisibleProvider.future),
          saved,
        );
      },
    );
  }

  test('a choice made during initial load wins over the late read', () async {
    final load = Completer<bool?>();
    final store = _Store()..loadResult = load.future;
    final container = containerFor(store);
    final notifier = container.read(boardEngineLinesVisibleProvider.notifier);
    final choice = notifier.setVisible(false);
    load.complete(true);
    await choice;
    expect(
      container.read(boardEngineLinesVisibleProvider).requireValue,
      isFalse,
    );
    expect(store.value, isFalse);
  });

  test('rapid choices serialize writes and persist the last tap', () async {
    final firstWrite = Completer<void>();
    final store = _Store()..firstWrite = firstWrite.future;
    final container = containerFor(store);
    await container.read(boardEngineLinesVisibleProvider.future);
    final notifier = container.read(boardEngineLinesVisibleProvider.notifier);
    final off = notifier.setVisible(false);
    final on = notifier.setVisible(true);
    final offAgain = notifier.setVisible(false);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, [false]);
    expect(
      container.read(boardEngineLinesVisibleProvider).requireValue,
      isFalse,
    );
    firstWrite.complete();
    await Future.wait([off, on, offAgain]);
    expect(store.writes, [false, true, false]);
    expect(store.value, isFalse);
  });

  test(
    'load failure preserves legacy visibility and a failed save can retry',
    () async {
      final store = _Store()..failLoad = true;
      final container = containerFor(store);
      expect(
        await container.read(boardEngineLinesVisibleProvider.future),
        isTrue,
      );
      store.failSave = true;
      final notifier = container.read(boardEngineLinesVisibleProvider.notifier);
      await notifier.setVisible(false);
      expect(
        container.read(boardEngineLinesVisibleProvider).requireValue,
        isFalse,
      );
      expect(store.value, isNull); // Session-only when disk fails, not durable.
      store.failSave = false;
      await notifier.setVisible(false);
      expect(store.value, isFalse);
    },
  );

  test(
    'production store reads/writes only the new SQLite device key',
    () async {
      const channel = MethodChannel('com.tekartik.sqflite');
      final values = <String, String>{
        'cached_engine_settings': 'legacy-style-snapshot',
      };
      final writtenKeys = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = call.arguments as Map?;
            switch (call.method) {
              case 'getDatabasesPath':
                return '/board-engine-lines-test';
              case 'openDatabase':
                return <String, Object>{'id': 1};
              case 'query':
                if ((args!['sql'] as String).contains('user_version')) {
                  return [
                    {'user_version': 1},
                  ];
                }
                final key = (args['arguments'] as List).first as String;
                return [
                  if (values[key] case final value?) {'value': value},
                ];
              case 'insert':
                final arguments = args!['arguments'] as List;
                final key = arguments[0] as String;
                expect(arguments[2], 'bool');
                writtenKeys.add(key);
                values[key] = arguments[1] as String;
                return 1;
              default:
                return null;
            }
          });
      SqflitePlugin.registerWith();
      addTearDown(() async {
        await AppDatabase.instance.close();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final store = BoardEngineLinesVisibilityStore();
      expect(await store.load(), isNull);
      await store.save(false);
      expect(await store.load(), isFalse);
      await store.save(true);
      expect(await store.load(), isTrue);
      expect(writtenKeys, [
        BoardEngineLinesVisibilityStore.preferenceKey,
        BoardEngineLinesVisibilityStore.preferenceKey,
      ]);
      expect(values['cached_engine_settings'], 'legacy-style-snapshot');
    },
  );

  for (final style in EngineLinesView.values) {
    testWidgets(
      'Off retains $style and Cards/List restores only visibility/style',
      (tester) async {
        final store = _Store();
        final container = ProviderContainer(
          overrides: [
            boardEngineLinesVisibilityStoreProvider.overrideWithValue(store),
            engineSettingsProviderNew.overrideWith(() => _Settings(style)),
          ],
        );
        addTearDown(container.dispose);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final persists = <Future<void>>[];
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                extensions: const [AppColors.dark],
              ),
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return Scaffold(
                    body: SingleChildScrollView(
                      child: EngineSettingsBody(trackPersist: persists.add),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = container.read(engineSettingsProviderNew).requireValue;
        final depth = EngineSearchProgress(depth: 22, kiloNodes: 100);
        container
            .read(engineDepthTrackerProvider.notifier)
            .update(
              component: EngineComponent.principalVariation,
              progress: depth,
            );
        expect(find.text('Off'), findsOneWidget);
        await tester.ensureVisible(find.text('Off'));
        await tester.tap(find.text('Off'));
        await tester.pumpAndSettle();
        await Future.wait(persists);
        expect(
          container.read(boardEngineLinesVisibleProvider).requireValue,
          isFalse,
        );
        expect(store.value, isFalse);
        expect(
          container.read(engineSettingsProviderNew).requireValue,
          same(before),
        );
        expect(
          container.read(
            engineDepthTrackerProvider,
          )[EngineComponent.principalVariation],
          same(depth),
        );
        expect(before.showEngineAnalysis, isTrue);
        expect(
          before.shouldShowEngineGaugeOnBoard,
          style == EngineLinesView.cards,
        );
        expect(
          before.shouldShowEngineGaugeInGrid,
          style == EngineLinesView.cards,
        );
        expect(before.showPvArrows, style == EngineLinesView.cards);
        for (final target in EngineLinesView.values) {
          await tester.tap(
            find.text(target == EngineLinesView.cards ? 'Cards' : 'List'),
          );
          await tester.pumpAndSettle();
          await Future.wait(persists);
          final settings = container
              .read(engineSettingsProviderNew)
              .requireValue;
          expect(
            container.read(boardEngineLinesVisibleProvider).requireValue,
            isTrue,
          );
          expect(store.value, isTrue);
          expect(settings.engineLinesView, target);
          expect(settings.showEngineAnalysis, before.showEngineAnalysis);
          expect(settings.showEngineGauge, before.showEngineGauge);
          expect(
            settings.showEngineGaugeOnBoard,
            before.showEngineGaugeOnBoard,
          );
          expect(settings.showEngineGaugeInGrid, before.showEngineGaugeInGrid);
          expect(settings.showPvArrows, before.showPvArrows);
          expect(settings.showDepthOverlay, before.showDepthOverlay);
          expect(settings.searchTimeIndex, before.searchTimeIndex);
          expect(
            settings.principalVariationIndex,
            before.principalVariationIndex,
          );
          expect(settings.maxArrowsOnBoard, before.maxArrowsOnBoard);
          expect(
            container.read(
              engineDepthTrackerProvider,
            )[EngineComponent.principalVariation],
            same(depth),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _Store extends BoardEngineLinesVisibilityStore {
  bool? value;
  Future<bool?>? loadResult;
  Future<void>? firstWrite;
  bool failLoad = false;
  bool failSave = false;
  final writes = <bool>[];

  @override
  Future<bool?> load() async {
    if (failLoad) throw StateError('fixture read failure');
    return loadResult ?? value;
  }

  @override
  Future<void> save(bool visible) async {
    writes.add(visible);
    if (writes.length == 1) await firstWrite;
    if (failSave) throw StateError('fixture write failure');
    value = visible;
  }
}

class _Settings extends EngineSettingsNotifierNew {
  _Settings(this.style);
  final EngineLinesView style;

  @override
  Future<EngineSettings> build() async => EngineSettings(
    engineLinesView: style,
    showEngineGauge: style == EngineLinesView.cards,
    showPvArrows: style == EngineLinesView.cards,
    showDepthOverlay: style == EngineLinesView.cards,
    searchTimeIndex: 2,
    principalVariationIndex: 2,
    maxArrowsOnBoard: 1,
  );

  @override
  Future<void> setEngineLinesView(EngineLinesView view) async {
    state = AsyncData(state.requireValue.copyWith(engineLinesView: view));
  }
}
