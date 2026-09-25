import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/my_space/library/space_library_bridge.dart';
import 'package:chessever2/screens/my_space/models/space_auto_item.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryFolder _folder(
  String id,
  String name, {
  String? parentId,
  bool liked = false,
  bool subscribed = false,
  String nodeType = LibraryFolder.nodeTypeDatabase,
}) => LibraryFolder(
  id: id,
  userId: 'u',
  name: name,
  color: '#000000',
  icon: 'db',
  orderIndex: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  parentId: parentId,
  isLikedGames: liked,
  isSubscribed: subscribed,
  nodeType: nodeType,
);

SpaceAutoItem _suggested(SpaceShortcut s) =>
    SpaceAutoItem(shortcut: s, origin: SpaceAutoOrigin.suggested);

final _carlsen = spacePlayerDraft(
  playerName: 'Carlsen, Magnus',
  fideId: 1503014,
  rating: 2830,
);
final _nakamura = spacePlayerDraft(
  playerName: 'Nakamura, Hikaru',
  fideId: 2016192,
  rating: 2800,
);

void main() {
  group('composeSpaceAutoRow', () {
    test('suggestions skip pinned, hidden, mirrored and repeated keys', () {
      final ding = spacePlayerDraft(playerName: 'Ding, Liren', fideId: 8603677);
      final row = composeSpaceAutoRow(
        trailing: [
          _suggested(_carlsen),
          _suggested(_nakamura),
          _suggested(_nakamura),
          _suggested(ding),
        ],
        pinned: {_carlsen.key},
        hidden: {ding.key},
        trailingCap: 5,
      );
      expect(row.trailing.map((a) => a.key), [_nakamura.key]);
    });

    test('suggestions stop at the cap', () {
      final many = [
        for (var i = 1; i <= 20; i++)
          _suggested(spacePlayerDraft(playerName: 'P$i', fideId: i)),
      ];
      expect(
        composeSpaceAutoRow(trailing: many, trailingCap: 12).trailing,
        hasLength(12),
      );
    });

    test('a mirrored tile stands in for its pin', () {
      final twic = spaceLibraryFolderDraft(kTwicFolder);
      final row = composeSpaceAutoRow(
        leading: [
          SpaceAutoItem(
            shortcut: twic,
            origin: SpaceAutoOrigin.library,
            folder: kTwicFolder,
          ),
        ],
        pinned: {twic.key},
      );
      expect(row.leading, hasLength(1));
      expect(row.hiddenPinKeys, contains(twic.key));
    });
  });

  test('the Library order is the Library tab\'s', () {
    final liked = _folder('liked', 'Liked Games', liked: true);
    final mine = _folder('mine', 'Najdorf prep');
    final shared = _folder('shared', 'Club book', subscribed: true);
    final order = spaceLibraryDisplayOrder([mine, liked, shared]);
    expect(order.map((f) => f.id), [
      'liked',
      kTwicBookId,
      kMiniaturesBookId,
      'mine',
      'shared',
    ]);
    expect(spaceLibraryDisplayOrder([]).map((f) => f.id), [
      kTwicBookId,
      kMiniaturesBookId,
    ]);
    // A liked-games destination pins as My Likes, the rest as themselves.
    expect(spaceLibraryFolderDraft(liked).key, 'likes:me');
    expect(spaceLibraryFolderDraft(mine).key, 'folder:mine');
    expect(
      spaceLibraryFolderDraft(kMiniaturesFolder).kind,
      SpaceShortcutKind.miniatures,
    );
    final folderNode = _folder(
      'f',
      'Prep',
      nodeType: LibraryFolder.nodeTypeFolder,
    );
    expect(spaceLibraryFolderDraft(folderNode).params['nodeType'], 'folder');
  });

  test('streaks have no row of their own; a pinned one lives in Players', () {
    expect(SpaceSection.values.map((s) => s.title), isNot(contains('Streaks')));
    expect(SpaceShortcutKind.streak.section, SpaceSection.players);
  });

  test('current events: live and upcoming, followed first', () {
    GroupEventCardModel event(String id, TourEventCategory c) =>
        GroupEventCardModel(
          id: id,
          title: 'Event $id',
          dates: 'Sep 20 - 28',
          maxAvgElo: 2700,
          timeUntilStart: '',
          tourEventCategory: c,
          timeControl: 'standard',
          endDate: null,
          startDate: null,
        );
    final drafts = spaceCurrentEventDrafts(
      [
        event('a', TourEventCategory.live),
        event('b', TourEventCategory.completed),
        event('c', TourEventCategory.upcoming),
        event('gamebase::x', TourEventCategory.live),
        event('d', TourEventCategory.ongoing),
      ],
      {'d'},
    );
    expect(drafts.map((d) => d.targetId), ['d', 'a', 'c']);
  });
}
