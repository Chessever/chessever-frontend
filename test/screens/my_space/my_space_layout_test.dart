import 'package:chessever2/screens/my_space/domain/my_space_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MySpaceShelfType', () {
    test('covers every version 1 wire type', () {
      expect(
        MySpaceShelfType.supportedValues.map((type) => type.rawType),
        const [
          'continue',
          'my_likes',
          'saved_events',
          'databases',
          'saved_studies',
          'favorite_players',
          'library_recents',
          'miniatures',
          'study_discovery',
          'pinned_event',
          'pinned_database',
          'pinned_folder',
          'pinned_study',
          'pinned_study_chapter',
          'pinned_player',
          'pinned_game',
        ],
      );

      for (final type in MySpaceShelfType.supportedValues) {
        expect(MySpaceShelfType.fromJson(type.rawType), same(type));
        expect(type.toJson(), type.rawType);
      }
    });

    test('keeps future types explicit and preserves their raw value', () {
      final type = MySpaceShelfType.fromJson('future_personal_rail');

      expect(type, isA<MySpaceUnsupportedShelfType>());
      expect(type.rawType, 'future_personal_rail');
      expect(type.toString(), 'future_personal_rail');
      expect(type.isSupported, isFalse);
      expect(type.isDynamic, isFalse);
      expect(type.isPinned, isFalse);
      expect(type.supportedSizes, isEmpty);
      expect(type, MySpaceUnsupportedShelfType('future_personal_rail'));
      expect(type.toJson, throwsFormatException);
    });

    test('does not allow a supported value to masquerade as unsupported', () {
      expect(
        () => MySpaceUnsupportedShelfType('continue'),
        throwsFormatException,
      );
    });
  });

  group('MySpaceLayout curated default', () {
    test('uses schema v1 and the approved shelf order', () {
      final layout = MySpaceLayout.curatedDefault;

      expect(layout.schemaVersion, 1);
      expect(layout.shelves.map((shelf) => shelf.type), const [
        MySpaceShelfType.continueShelf,
        MySpaceShelfType.myLikes,
        MySpaceShelfType.savedEvents,
        MySpaceShelfType.databases,
        MySpaceShelfType.savedStudies,
        MySpaceShelfType.favoritePlayers,
      ]);
      expect(layout.shelves.map((shelf) => shelf.id).toSet(), hasLength(6));
      expect(
        layout.shelves.every(
          (shelf) =>
              shelf.targetId == null &&
              shelf.size == MySpaceShelfSize.standard &&
              shelf.visible,
        ),
        isTrue,
      );
      expect(layout.isSaveable, isTrue);
    });

    test('exposes an unmodifiable shelf list', () {
      final shelves = MySpaceLayout.curatedDefault.shelves;

      expect(() => shelves.clear(), throwsUnsupportedError);
    });
  });

  group('MySpaceLayout JSON contract', () {
    test('round-trips supported layouts without normalization', () {
      final layout = MySpaceLayout(
        shelves: [
          MySpaceShelfDescriptor(
            id: 'likes',
            type: MySpaceShelfType.myLikes,
            size: MySpaceShelfSize.compact,
            visible: false,
          ),
          MySpaceShelfDescriptor(
            id: 'study',
            type: MySpaceShelfType.pinnedStudy,
            targetId: 'study-42',
            size: MySpaceShelfSize.featured,
          ),
        ],
      );

      final json = layout.toJson();

      expect(json, {
        'schema_version': 1,
        'shelves': [
          {
            'id': 'likes',
            'type': 'my_likes',
            'targetId': null,
            'size': 'compact',
            'visible': false,
          },
          {
            'id': 'study',
            'type': 'pinned_study',
            'targetId': 'study-42',
            'size': 'featured',
            'visible': true,
          },
        ],
      });

      final decoded = MySpaceLayout.fromJson(json);
      expect(decoded, layout);
      expect(decoded.hashCode, layout.hashCode);
    });

    test('rejects missing and unknown layout keys', () {
      expect(
        () => MySpaceLayout.fromJson({'schema_version': 1}),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('missing required key(s): shelves'),
          ),
        ),
      );
      expect(
        () => MySpaceLayout.fromJson({
          'schema_version': 1,
          'shelves': <Object?>[],
          'payload': 'not allowed',
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('unknown key(s): payload'),
          ),
        ),
      );
    });

    test('rejects invalid schema and shelf container shapes', () {
      expect(
        () => MySpaceLayout.fromJson({
          'schema_version': '1',
          'shelves': <Object?>[],
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('schema_version must be an integer'),
          ),
        ),
      );
      expect(
        () => MySpaceLayout.fromJson({
          'schema_version': 2,
          'shelves': <Object?>[],
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('unsupported version 2'),
          ),
        ),
      );
      expect(
        () => MySpaceLayout.fromJson({
          'schema_version': 1,
          'shelves': <String, Object?>{},
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('shelves must be a JSON array'),
          ),
        ),
      );
      expect(
        () => MySpaceLayout.fromJson({
          'schema_version': 1,
          'shelves': ['not an object'],
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('shelves[0] must be a JSON object'),
          ),
        ),
      );
    });

    test('rejects missing and unknown descriptor keys', () {
      final missingVisible = _descriptorJson()..remove('visible');
      final unknownKey = _descriptorJson()..['title'] = 'hidden payload';

      expect(
        () => MySpaceLayout.fromJson(_layoutJson([missingVisible])),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('missing required key(s): visible'),
          ),
        ),
      );
      expect(
        () => MySpaceLayout.fromJson(_layoutJson([unknownKey])),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('unknown key(s): title'),
          ),
        ),
      );
    });

    test('rejects malformed descriptor field values', () {
      final invalidDescriptors = <Map<String, dynamic>>[
        {..._descriptorJson(), 'id': 7},
        {..._descriptorJson(), 'id': ''},
        {..._descriptorJson(), 'type': null},
        {..._descriptorJson(), 'type': ' future_type '},
        {..._descriptorJson(), 'targetId': 42},
        {..._descriptorJson(), 'size': 'wide'},
        {..._descriptorJson(), 'visible': 'true'},
      ];

      for (final descriptor in invalidDescriptors) {
        expect(
          () => MySpaceLayout.fromJson(_layoutJson([descriptor])),
          throwsFormatException,
          reason: 'Descriptor should be rejected: $descriptor',
        );
      }
    });

    test('keeps unknown descriptors readable but never saveable', () {
      final layout = MySpaceLayout.fromJson(
        _layoutJson([
          _descriptorJson(
            id: 'future',
            type: 'future_personal_rail',
            targetId: 'future-target-shape',
          ),
        ]),
      );
      final descriptor = layout.shelves.single;

      expect(descriptor.type, isA<MySpaceUnsupportedShelfType>());
      expect(descriptor.type.rawType, 'future_personal_rail');
      expect(descriptor.targetId, 'future-target-shape');
      expect(descriptor.isSaveable, isFalse);
      expect(layout.isSaveable, isFalse);
      expect(descriptor.validateForSave, throwsFormatException);
      expect(descriptor.toJson, throwsFormatException);
      expect(layout.validateForSave, throwsFormatException);
      expect(layout.toJson, throwsFormatException);
    });
  });

  group('MySpaceLayout validation', () {
    test('rejects duplicate descriptor ids', () {
      expect(
        () => MySpaceLayout(
          shelves: [
            _descriptor(id: 'same', type: MySpaceShelfType.myLikes),
            _descriptor(id: 'same', type: MySpaceShelfType.savedEvents),
          ],
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('duplicates shelf id "same"'),
          ),
        ),
      );
    });

    test('rejects repeated singleton dynamic types', () {
      expect(
        () => MySpaceLayout(
          shelves: [
            _descriptor(id: 'likes-1', type: MySpaceShelfType.myLikes),
            _descriptor(id: 'likes-2', type: MySpaceShelfType.myLikes),
          ],
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('singleton dynamic shelf'),
          ),
        ),
      );
    });

    test('allows pinned types to repeat only for distinct targets', () {
      expect(
        () => MySpaceLayout(
          shelves: [
            _descriptor(
              id: 'study-1',
              type: MySpaceShelfType.pinnedStudy,
              targetId: 'same-study',
            ),
            _descriptor(
              id: 'study-2',
              type: MySpaceShelfType.pinnedStudy,
              targetId: 'same-study',
            ),
          ],
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('duplicates pinned target'),
          ),
        ),
      );

      expect(
        () => MySpaceLayout(
          shelves: [
            _descriptor(
              id: 'study-1',
              type: MySpaceShelfType.pinnedStudy,
              targetId: 'study-a',
            ),
            _descriptor(
              id: 'study-2',
              type: MySpaceShelfType.pinnedStudy,
              targetId: 'study-b',
            ),
          ],
        ),
        returnsNormally,
      );
    });

    test('requires targets for pinned types and forbids them for dynamics', () {
      expect(
        () => _descriptor(id: 'pinned', type: MySpaceShelfType.pinnedEvent),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('targetId is required for pinned type'),
          ),
        ),
      );
      expect(
        () => _descriptor(
          id: 'dynamic',
          type: MySpaceShelfType.savedEvents,
          targetId: 'event-id',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('targetId must be null for dynamic type'),
          ),
        ),
      );
      expect(
        () => MySpaceShelfDescriptor.fromJson(
          _descriptorJson(
            id: 'blank-target',
            type: 'pinned_event',
            targetId: '',
          ),
        ),
        throwsFormatException,
      );
    });

    test('enforces the explicit type and size matrix', () {
      expect(
        () => _descriptor(
          id: 'compact-continue',
          type: MySpaceShelfType.continueShelf,
          size: MySpaceShelfSize.compact,
        ),
        throwsFormatException,
      );
      expect(
        () => _descriptor(
          id: 'featured-likes',
          type: MySpaceShelfType.myLikes,
          size: MySpaceShelfSize.featured,
        ),
        throwsFormatException,
      );
      expect(
        () => _descriptor(
          id: 'compact-pin',
          type: MySpaceShelfType.pinnedPlayer,
          targetId: 'player-id',
          size: MySpaceShelfSize.compact,
        ),
        throwsFormatException,
      );

      expect(
        () => _descriptor(
          id: 'featured-continue',
          type: MySpaceShelfType.continueShelf,
          size: MySpaceShelfSize.featured,
        ),
        returnsNormally,
      );
      expect(
        () => _descriptor(
          id: 'compact-likes',
          type: MySpaceShelfType.myLikes,
          size: MySpaceShelfSize.compact,
        ),
        returnsNormally,
      );
      expect(
        () => _descriptor(
          id: 'featured-pin',
          type: MySpaceShelfType.pinnedPlayer,
          targetId: 'player-id',
          size: MySpaceShelfSize.featured,
        ),
        returnsNormally,
      );
    });

    test('rejects layouts over the maximum shelf count', () {
      final shelves = List.generate(
        MySpaceLayout.maxShelfCount + 1,
        (index) => _descriptor(
          id: 'game-$index',
          type: MySpaceShelfType.pinnedGame,
          targetId: 'game-target-$index',
        ),
      );

      expect(
        () => MySpaceLayout(shelves: shelves),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('maximum is ${MySpaceLayout.maxShelfCount}'),
          ),
        ),
      );
    });
  });
}

MySpaceShelfDescriptor _descriptor({
  required String id,
  required MySpaceShelfType type,
  String? targetId,
  MySpaceShelfSize size = MySpaceShelfSize.standard,
}) {
  return MySpaceShelfDescriptor(
    id: id,
    type: type,
    targetId: targetId,
    size: size,
  );
}

Map<String, dynamic> _layoutJson(List<Object?> shelves) {
  return {'schema_version': 1, 'shelves': shelves};
}

Map<String, dynamic> _descriptorJson({
  String id = 'shelf-id',
  String type = 'saved_studies',
  Object? targetId,
  String size = 'standard',
  bool visible = true,
}) {
  return {
    'id': id,
    'type': type,
    'targetId': targetId,
    'size': size,
    'visible': visible,
  };
}
