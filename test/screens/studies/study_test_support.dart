import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:dio/dio.dart';

typedef StudiesPageHandler =
    Future<GamebaseStudiesPage> Function({
      required GamebaseStudiesFilter filter,
      required int limit,
      required int offset,
    });

typedef StudyDetailHandler = Future<GamebaseStudyDetail> Function(String id);

class WidgetTestGamebaseRepository extends GamebaseRepository {
  WidgetTestGamebaseRepository({
    required this.studiesHandler,
    required this.detailHandler,
  }) : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  final StudiesPageHandler studiesHandler;
  final StudyDetailHandler detailHandler;

  @override
  Future<GamebaseStudiesPage> getStudies({
    GamebaseStudiesFilter filter = GamebaseStudiesFilter.defaultFilter,
    int limit = 50,
    int offset = 0,
  }) {
    return studiesHandler(filter: filter, limit: limit, offset: offset);
  }

  @override
  Future<GamebaseStudyDetail> getStudy(String lichessStudyId) {
    return detailHandler(lichessStudyId);
  }
}

GamebaseStudySummary testStudy({
  String id = 'AbCd1234',
  String name = 'Annotated Sicilian Model Games',
  String? author = 'example_author',
  int views = 840,
  int chapterCount = 2,
  double credibilityScore = 76.4,
}) {
  return GamebaseStudySummary(
    lichessStudyId: id,
    authorUsername: author,
    name: name,
    views: views,
    lichessCreatedAt: DateTime.utc(2026, 1, 15),
    lichessUpdatedAt: DateTime.utc(2026, 7, 1),
    chapterCount: chapterCount,
    plyTotal: 112,
    hasAnnotations: true,
    ecos: const <String>['B90', 'B91'],
    ecoCategories: const <String>['B'],
    openings: const <String>['Sicilian Defense'],
    variants: const <String>['Standard'],
    chapterModes: const <String>['normal', 'gamebook'],
    players: const <String>['Example White', 'Example Black'],
    isGamebook: true,
    hasCustomPositions: false,
    credibilityScore: credibilityScore,
    passedGate: true,
    status: GamebaseStudyStatus.active,
    syncedAt: DateTime.utc(2026, 7, 10),
  );
}

GamebaseStudiesPage testStudiesPage({
  required List<GamebaseStudySummary> items,
  int? total,
  int limit = 30,
  int offset = 0,
}) {
  return GamebaseStudiesPage(
    items: items,
    total: total ?? items.length,
    limit: limit,
    offset: offset,
  );
}

GamebaseStudyChapterMetadata testChapter({
  required String chapterId,
  required int orderIndex,
  String studyId = 'AbCd1234',
  String? name,
}) {
  return GamebaseStudyChapterMetadata(
    lichessStudyId: studyId,
    lichessChapterId: chapterId,
    name: name ?? 'Chapter ${orderIndex + 1}',
    plyCount: 56,
    orderIndex: orderIndex,
    eco: 'B90',
    opening: 'Sicilian Defense',
    variant: 'Standard',
    result: '1-0',
    chapterMode: 'normal',
    isSetup: false,
    whiteName: 'Example White',
    blackName: 'Example Black',
    whiteElo: 2500,
    blackElo: 2450,
    hasAnnotations: true,
  );
}

GamebaseStudyDetail testStudyDetail({
  GamebaseStudySummary? study,
  List<GamebaseStudyChapterMetadata>? chapters,
}) {
  return GamebaseStudyDetail(
    study: study ?? testStudy(),
    chapters:
        chapters ??
        <GamebaseStudyChapterMetadata>[
          testChapter(
            chapterId: 'Chapter2',
            orderIndex: 1,
            name: 'Dragon endgame',
          ),
          testChapter(chapterId: 'Chapter1', orderIndex: 0, name: 'Main line'),
        ],
  );
}
