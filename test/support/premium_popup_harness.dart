// The stage the Premium popups' preview tests render on: the app's Inter,
// a busy page of live boards in the app's theme at a real phone or tablet
// view, 3x, and readings of what is drawn (a label's contrast on the pixels
// round it, a choice's mark and label found by their ink, not their boxes).
//
// Shared by test/rewarded_access_popup_preview_test.dart (the Unlock
// Premium chooser) and test/rewarded_interstitial_intro_preview_test.dart
// (Try another ad?), so both popups are measured the same way.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../dialogs_harness.dart';

const premiumPopupCapture = ValueKey('premium_popup_capture');

const premiumPopupPhone = Size(393, 852);
const premiumPopupTablet = Size(834, 1194);

/// Loads the app's Inter under every family a popup can ask for, and the
/// Material icons, so renders show real type.
Future<void> loadPremiumPopupFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  final inter = [
    for (final weight in ['Regular', 'Medium', 'Bold'])
      'assets/fonts/Inter-$weight.otf',
  ];
  await family('InterDisplay', inter);
  await family('Inter', inter);
  await family('Roboto', inter);
  await family('FlutterTest', inter);
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) await family('MaterialIcons', [icons.path]);
}

/// Pumps the busy page in the app's theme at [screen] and returns the
/// context a popup opens from.
Future<BuildContext> pumpPremiumPopupHost(
  WidgetTester tester, {
  required bool light,
  required Size screen,
  List<Override> overrides = const [],
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = screen * 3;
  tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  late BuildContext opener;
  await tester.pumpWidget(
    RepaintBoundary(
      key: premiumPopupCapture,
      child: ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Stack(
                  children: [
                    const DialogsBusyPage(),
                    Offstage(
                      child: Builder(
                        builder: (context) {
                          opener = context;
                          return const SizedBox();
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await precacheDialogsPage(tester);
  return opener;
}

/// The whole stage, as drawn, at 3x.
Future<ui.Image> premiumPopupImage(WidgetTester tester) async {
  late ui.Image image;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(premiumPopupCapture),
    );
    image = await boundary.toImage(pixelRatio: 3);
  });
  return image;
}

/// Writes the stage to [dir]/[name].png; with no [dir], only checks that
/// nothing threw.
Future<void> premiumPopupShot(
  WidgetTester tester,
  String dir,
  String name,
) async {
  expect(tester.takeException(), isNull);
  if (dir.isEmpty) return;
  final image = await premiumPopupImage(tester);
  await tester.runAsync(() async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
  image.dispose();
}

/// The worst contrast of [label]'s ink against the pixels around it: a
/// ring 2-5 px outside its text box, inside the control it labels. The
/// darkest and lightest 2% of the ring (grain specks, an antialiased edge)
/// are left out.
Future<double> premiumPopupLabelContrast(
  WidgetTester tester,
  String label,
) async {
  final text = find.text(label).last;
  final ink = tester.widget<RichText>(
    find.descendant(of: text, matching: find.byType(RichText)).first,
  );
  final color = ink.text.style!.color!;
  final rect = tester.getRect(text);
  final image = await premiumPopupImage(tester);
  final pixels = <Color>[];
  await tester.runAsync(() async {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final outer = rect.inflate(5);
    final inner = rect.inflate(2);
    for (var y = (outer.top * 3).floor(); y < outer.bottom * 3; y++) {
      for (var x = (outer.left * 3).floor(); x < outer.right * 3; x++) {
        if (inner.contains(Offset(x / 3, y / 3))) continue;
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
  });
  image.dispose();
  pixels.sort((a, b) => a.computeLuminance().compareTo(b.computeLuminance()));
  final trim = pixels.length ~/ 50;
  final darkest = pixels[trim];
  final lightest = pixels[pixels.length - 1 - trim];
  double on(Color ground) =>
      wcagContrast(Color.alphaBlend(color, ground), ground);
  return [on(darkest), on(lightest)].reduce((a, b) => a < b ? a : b);
}

/// What is drawn on the plate that holds [label], in points: its mark's ink
/// and its label's ink, found from the pixels (not the widget boxes). A
/// column is ink where some pixel of the plate's middle band stands off the
/// plate's own fill (read per row, so the sheen does not count) by half the
/// strongest ink of its group or more.
Future<({Rect plate, Rect mark, Rect label})> premiumPopupInk(
  WidgetTester tester,
  String label,
) async {
  final plate = tester.getRect(
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
  );
  final textLeft = tester.getRect(find.text(label)).left;
  final image = await premiumPopupImage(tester);
  late ByteData data;
  await tester.runAsync(() async {
    data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  final width = image.width;
  image.dispose();
  int px(double points) => (points * 3).round();
  final top = px(plate.center.dy - 12);
  final bottom = px(plate.center.dy + 12);
  final left = px(plate.left + 6);
  final right = px(plate.right - 6);
  int diff(int x, int y) {
    final i = (y * width + x) * 4;
    final r = (y * width + left) * 4;
    var sum = 0;
    for (var c = 0; c < 3; c++) {
      sum += (data.getUint8(i + c) - data.getUint8(r + c)).abs();
    }
    return sum;
  }

  // The strongest ink in each column, and where it is.
  final column = <int, int>{};
  for (var x = left + 1; x < right; x++) {
    var most = 0;
    for (var y = top; y < bottom; y++) {
      final d = diff(x, y);
      if (d > most) most = d;
    }
    column[x] = most;
  }
  final split = px(textLeft) - 1;
  Rect extent(int from, int to) {
    var strongest = 0;
    for (var x = from; x < to; x++) {
      if (column[x]! > strongest) strongest = column[x]!;
    }
    final cut = strongest / 2;
    int? first, last, high, low;
    for (var x = from; x < to; x++) {
      if (column[x]! < cut) continue;
      first ??= x;
      last = x;
      for (var y = top; y < bottom; y++) {
        if (diff(x, y) < cut) continue;
        if (high == null || y < high) high = y;
        if (low == null || y > low) low = y;
      }
    }
    return Rect.fromLTRB(
      first! / 3,
      high! / 3,
      (last! + 1) / 3,
      (low! + 1) / 3,
    );
  }

  return (
    plate: plate,
    mark: extent(left + 1, split),
    label: extent(split, right),
  );
}
