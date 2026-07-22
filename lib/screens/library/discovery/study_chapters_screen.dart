import 'package:chessever2/repository/gamebase/discovery/discovery_models.dart';
import 'package:chessever2/repository/gamebase/discovery/discovery_providers.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Chapter list for a single curated study. Tapping a chapter pulls its cached
/// PGN and opens it on the board, the same as any other game in the app.
class StudyChaptersScreen extends ConsumerStatefulWidget {
  const StudyChaptersScreen({super.key, required this.study});

  final LichessStudy study;

  @override
  ConsumerState<StudyChaptersScreen> createState() =>
      _StudyChaptersScreenState();
}

class _StudyChaptersScreenState extends ConsumerState<StudyChaptersScreen> {
  int? _loadingIndex;

  /// Opens the whole study as one indexed, swipeable set of games on the board,
  /// landing on the tapped chapter. Loading every chapter's PGN up front is what
  /// lets the reader flip through the study — annotations, variations and
  /// comments all render on our own board, entirely in-app.
  Future<void> _openStudyAt(
    List<LichessStudyChapter> chapters,
    int index,
  ) async {
    if (_loadingIndex != null) return;
    HapticFeedbackService.cardTap();
    setState(() => _loadingIndex = index);
    try {
      final repo = ref.read(gamebaseRepositoryProvider);
      final pgns = await Future.wait(
        chapters.map(
          (c) => repo.getStudyChapterPgn(widget.study.id, c.chapterId),
        ),
      );
      if (!mounted) return;

      // Keep loadable chapters in order; remember where the tapped one lands so
      // the board opens on it even if earlier chapters were skipped.
      final models = <GamesTourModel>[];
      var openAt = 0;
      for (var i = 0; i < chapters.length; i++) {
        final pgn = pgns[i];
        if (pgn == null || pgn.trim().isEmpty) continue;
        if (i == index) openAt = models.length;
        final chessGame = ChessGame.fromPgn(
          'study_${chapters[i].chapterId}',
          pgn,
        );
        models.add(chessGameToImportedGamesTourModel(chessGame));
      }

      if (models.isEmpty) {
        _toast("Couldn't load this study");
        return;
      }

      ref.read(chessboardViewFromProviderNew.notifier).state =
          ChessboardView.tour;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChessBoardScreenNew(
            currentIndex: openAt,
            games: models,
            showGamebaseButton: false,
            disableGamebaseOverlayByDefault: true,
          ),
        ),
      );
    } catch (_) {
      if (mounted) _toast("Couldn't open this study");
    } finally {
      if (mounted) setState(() => _loadingIndex = null);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTypography.textSmMedium.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
        backgroundColor: context.colors.surface.withValues(alpha: 0.95),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(studyDetailProvider(widget.study.id));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: context.colors.textPrimary,
            size: 20.sp,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.study.name,
              style: AppTypography.textMdBold.copyWith(
                color: context.colors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if ((widget.study.authorUsername ?? '').trim().isNotEmpty)
              Text(
                'Study by ${widget.study.authorUsername!.trim()}',
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textPrimary.withValues(alpha: 0.55),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: detailAsync.when(
          data: (detail) {
            final chapters = detail?.chapters ?? const <LichessStudyChapter>[];
            if (chapters.isEmpty) {
              return Center(
                child: Text(
                  'This study has no chapters',
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.6),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              itemCount: chapters.length,
              separatorBuilder: (_, __) => SizedBox(height: 8.h),
              itemBuilder: (context, i) {
                final chapter = chapters[i];
                final loading = _loadingIndex == i;
                return _ChapterCard(
                  index: i + 1,
                  chapter: chapter,
                  loading: loading,
                  onTap: () => _openStudyAt(chapters, i),
                );
              },
            );
          },
          loading: () => Center(
            child: CircularProgressIndicator(
              color: context.colors.textPrimary,
              strokeWidth: 2.5,
            ),
          ),
          error: (e, _) => Center(
            child: Text(
              'Could not load chapters',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.index,
    required this.chapter,
    required this.loading,
    required this.onTap,
  });

  final int index;
  final LichessStudyChapter chapter;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final moves = (chapter.plyCount / 2).ceil();
    return TappableScale(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Row(
          children: [
            Container(
              width: 32.h,
              height: 32.h,
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Center(
                child: Text(
                  '$index',
                  style: AppTypography.textSmBold.copyWith(color: kPrimaryColor),
                ),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    chapter.name?.trim().isNotEmpty == true
                        ? chapter.name!
                        : 'Chapter $index',
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    [
                      moves <= 0
                          ? 'Position'
                          : (moves == 1 ? '1 move' : '$moves moves'),
                      if ((chapter.eco ?? '').trim().isNotEmpty) chapter.eco!.trim(),
                    ].join('  ·  '),
                    style: AppTypography.textXsRegular.copyWith(
                      color: const Color(0xFFA1A1A1),
                    ),
                  ),
                  if (chapter.gameSubtitle != null) ...[
                    SizedBox(height: 2.h),
                    Text(
                      chapter.gameSubtitle!,
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.textPrimary.withValues(alpha: 0.45),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 8.w),
            if (loading)
              SizedBox(
                width: 18.w,
                height: 18.h,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
                ),
              )
            else
              Icon(
                Icons.play_arrow_rounded,
                size: 22.sp,
                color: kPrimaryColor,
              ),
          ],
        ),
      ),
    );
  }
}
