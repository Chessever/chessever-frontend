import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/group_event/group_event_screen.dart',
      ).readAsStringSync();

  test(
    'Events and For You use one full-screen canvas with floating chrome',
    () {
      expect(source, contains('return GlassFullScreenPage('));
      expect(source, contains("'group-event-floating-controls'"));
      expect(source, contains('topOverlay: Align('));
      expect(source, contains('content: Align('));
      expect(source, contains('GlassIslandTopBar('));
      expect(source, contains('GlassIslandSearch('));
      expect(source, contains('GlassFloatingSegments('));
      expect(source, contains('PageView.builder('));

      expect(source, isNot(contains('return Material(')));
      expect(source, isNot(contains('child: Column(')));
      expect(source, isNot(contains('Expanded(')));
      expect(source, isNot(contains('SliverAppBar(')));
      expect(source, isNot(contains('SliverPersistentHeader(')));
    },
  );

  test('For You stays search-free while Events owns destination search', () {
    expect(source, contains('mode == GroupEventScreenMode.forYou'));
    expect(source, contains('? null'));
    expect(source, contains('mode != GroupEventScreenMode.forYou'));
    expect(source, contains('homeBottomSearchTextProvider'));
    expect(source, contains('searchTabQueryProvider'));
    expect(source, contains('GroupEventCategory.search'));
  });

  test('floating controls retain accessibility and motion safeguards', () {
    expect(source, contains('clamp(48.0, 96.0)'));
    expect(source, contains('MediaQuery.textScalerOf(context)'));
    expect(source, contains("label: 'Filter events'"));
    expect(source, contains("label: 'Event categories'"));
    expect(source, contains('GlassMotion.reduceMotion(context)'));
    expect(source, contains('pageController.jumpToPage(newIndex)'));
    expect(source, contains('target.jumpTo(target.position.minScrollExtent)'));
  });

  test('existing event behavior contracts remain connected', () {
    expect(source, contains('bottomNavBarReTapRequestProvider'));
    expect(source, contains('eventAppliedFilterProvider'));
    expect(source, contains('FilterPopup('));
    expect(source, contains('RefreshIndicator('));
    expect(source, contains('loadMorePast()'));
    expect(source, contains('E2eIds.eventsRoot'));
    expect(source, contains('E2eIds.eventsFilterButton'));
  });
}
