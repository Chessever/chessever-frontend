import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/settings/widgets/engine_settings_body.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('evaluation bar settings expose board and grid controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engineSettingsProviderNew.overrideWith(
            () => _FakeEngineSettingsNotifier(const EngineSettings()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: SingleChildScrollView(
                  child: EngineSettingsBody(trackPersist: (_) {}),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Evaluation Bar'), findsOneWidget);
    expect(find.text('Board View'), findsOneWidget);
    expect(find.text('Grid View'), findsOneWidget);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches[0].value, isTrue);
    expect(switches[1].value, isTrue);
    expect(switches[2].value, isTrue);
  });

  testWidgets('master off keeps child choices on but disables their controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engineSettingsProviderNew.overrideWith(
            () => _FakeEngineSettingsNotifier(
              const EngineSettings(showEngineGauge: false),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: SingleChildScrollView(
                  child: EngineSettingsBody(trackPersist: (_) {}),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches[0].value, isFalse);
    expect(switches[1].value, isTrue);
    expect(switches[1].onChanged, isNull);
    expect(switches[2].value, isTrue);
    expect(switches[2].onChanged, isNull);
  });
}

class _FakeEngineSettingsNotifier extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  _FakeEngineSettingsNotifier(this.settings);

  final EngineSettings settings;

  @override
  Future<EngineSettings> build() async => settings;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
