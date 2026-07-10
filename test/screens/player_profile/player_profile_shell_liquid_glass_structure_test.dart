import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source =
      File(
        '${Directory.current.path}/lib/screens/player_profile/'
        'player_profile_screen.dart',
      ).readAsStringSync();

  test('profile tabs fill one opaque canvas behind floating controls', () {
    expect(source, contains('GlassFullScreenPage('));
    expect(
      source,
      contains("ValueKey<String>('player-profile-floating-controls')"),
    );
    expect(source, contains('includeContentSafeArea: false'));
    expect(source, contains('topOverlay: Center('));
    expect(source, contains('content: Center('));
    expect(source, contains('ColoredBox('));
    expect(source, contains('color: context.colors.background'));
    expect(source, isNot(contains('child: Column(\n            children: [')));
    expect(source, isNot(contains('SliverAppBar(')));
    expect(source, isNot(contains('SliverPersistentHeader(')));
  });

  test('preserves profile identity, tabs, actions, status, and E2E root', () {
    expect(source, contains('E2eIds.playerProfileRoot'));
    expect(source, contains('PlayerProfileTab.about'));
    expect(source, contains('PlayerProfileTab.games'));
    expect(source, contains('PlayerProfileTab.events'));
    expect(source, contains('PageView.builder('));
    expect(source, contains('onPageChanged: _handlePageChanged'));
    expect(source, contains('_shareProfile('));
    expect(source, contains('_toggleFavorite'));
    expect(source, contains("title: 'Build Tree'"));
    expect(source, contains("title: 'Save to Library'"));
    expect(source, contains('_buildIndicatorBar('));
    expect(source, contains('playerProfileDataKeyProvider(activePlayerKey)'));
    expect(source, contains('PlayerProfileDataSource.twic'));
  });

  test('keeps parent and games floating chrome from colliding', () {
    expect(source, contains('_profileContentTopInset('));
    expect(source, contains('required double contentTopInset'));
    expect(source, contains('EdgeInsets.only(top: contentTopInset)'));
    expect(source, contains('selectedTab == PlayerProfileTab.games'));
    expect(source, contains('_profileActionExtent(context)'));
    expect(source, contains('MediaQuery.viewPaddingOf(context).top'));
  });

  test('supports accessibility, Dynamic Type, themes, and Reduce Motion', () {
    expect(source, contains('MediaQuery.textScalerOf(context).scale(16)'));
    expect(source, contains('.clamp(48.0, 72.0)'));
    expect(source, contains("label: 'Player profile controls'"));
    expect(source, contains("label: 'Share profile'"));
    expect(source, contains("'Remove favorite' : 'Add favorite'"));
    expect(source, contains("label: 'Build opening tree'"));
    expect(source, contains('GlassMotion.reduceMotion(context)'));
    expect(source, contains('_pageController.jumpToPage(index)'));
    expect(source, contains('context.colors.background'));
    expect(source, contains('context.colors.textPrimary'));
  });
}
