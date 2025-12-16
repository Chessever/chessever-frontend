import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:flutter/material.dart';

class BookSavedGameCard extends StatelessWidget {
  const BookSavedGameCard({super.key, required this.analysis});

  final SavedAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final md = analysis.chessGame.metadata;
    final whiteName = md['White'] as String? ?? 'White';
    final blackName = md['Black'] as String? ?? 'Black';
    final whiteTitle = (md['WhiteTitle'] ?? '').toString().trim();
    final blackTitle = (md['BlackTitle'] ?? '').toString().trim();
    final whiteElo = (md['WhiteElo'] ?? '').toString().trim();
    final blackElo = (md['BlackElo'] ?? '').toString().trim();

    final result = (md['Result'] as String? ?? '*').trim();
    final status = _parseResult(result);

    final eventRaw = md['Event'] as String? ?? md['Site'] as String? ?? '';
    final eventName = _formatEventName(eventRaw);
    final eco = (md['ECO'] as String? ?? '').trim();
    final date = _formatDate(md['Date'] as String?);
    final timeControlIcon = _getTimeControlIcon(md);

    return GestureDetector(
      onTap: () async {
        HapticFeedbackService.cardTap();
        await loadSavedAnalysis(context, analysis);
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF18181B), // Zinc 900
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: const Color(0xFF27272A)), // Zinc 800
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 10.h),
              decoration: BoxDecoration(
                color: const Color(0xFFE4E4E7), // Zinc 200
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(12.br),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _PlayerInfo(
                      name: whiteName,
                      title: whiteTitle,
                      rating: whiteElo,
                      alignment: CrossAxisAlignment.start,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10.w),
                    child: _ResultBadge(status: status),
                  ),
                  Expanded(
                    child: _PlayerInfo(
                      name: blackName,
                      title: blackTitle,
                      rating: blackElo,
                      alignment: CrossAxisAlignment.end,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: const Color(0xFF09090B), // Zinc 950
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(12.br),
                ),
                border: Border(
                  top: BorderSide(color: kWhiteColor.withValues(alpha: 0.06)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: Row(
                      children: [
                        Image.asset(timeControlIcon, width: 14.sp, height: 14.sp),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            eventName,
                            style: AppTypography.textXsRegular.copyWith(
                              color: const Color(0xFFA1A1AA), // Zinc 400
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(
                        eco,
                        style: AppTypography.textXsMedium.copyWith(
                          color: const Color(0xFFA1A1AA), // Zinc 400
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        date,
                        style: AppTypography.textXsRegular.copyWith(
                          color: const Color(0xFF71717A), // Zinc 500
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTimeControlIcon(Map<String, dynamic> md) {
    final event = (md['Event'] as String? ?? '').toLowerCase();
    final timeControl = (md['TimeControl'] as String? ?? '').toLowerCase();

    // Check for Blitz
    if (event.contains('blitz') || timeControl.contains('blitz')) {
      return PngAsset.blitzIcon;
    }
    // Check for Rapid
    if (event.contains('rapid') || timeControl.contains('rapid')) {
      return PngAsset.rapidIcon;
    }

    return PngAsset.classicalIcon;
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty || raw.startsWith('????')) return '';
    final parts = raw.split('.');
    if (parts.length != 3) return raw;
    final y = parts[0];
    final m = parts[1];
    final d = parts[2];
    if (y == '????' || m == '??' || d == '??') return '';
    return '$d/$m/$y';
  }

  _BookResult _parseResult(String result) {
    final trimmed = result.trim();
    switch (trimmed) {
      case '1-0':
        return _BookResult.white;
      case '0-1':
        return _BookResult.black;
      case '1/2-1/2':
      case '½-½':
        return _BookResult.draw;
      case 'W':
        return _BookResult.white;
      case 'B':
        return _BookResult.black;
      case 'D':
        return _BookResult.draw;
      default:
        return _BookResult.unknown;
    }
  }

  String _formatEventName(String raw) {
    final cleaned = raw.replaceAll('-', ' ').replaceAll('_', ' ').trim();
    if (cleaned.isEmpty) return 'Unknown event';
    return cleaned;
  }
}

enum _BookResult { white, black, draw, unknown }

class _PlayerInfo extends StatelessWidget {
  const _PlayerInfo({
    required this.name,
    required this.title,
    required this.rating,
    required this.alignment,
  });

  final String name;
  final String title;
  final String rating;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final rank = [
      if (title.isNotEmpty) title,
      if (rating.isNotEmpty) rating,
    ].join(' ');

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          name,
          style: AppTypography.textSmMedium.copyWith(
            color: kBlackColor,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign:
              alignment == CrossAxisAlignment.end
                  ? TextAlign.right
                  : TextAlign.left,
        ),
        SizedBox(height: 2.sp),
        Text(
          rank,
          style: AppTypography.textXsRegular.copyWith(
            color: kBlack2Color.withValues(alpha: 0.7),
            fontSize: 12.sp,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign:
              alignment == CrossAxisAlignment.end
                  ? TextAlign.right
                  : TextAlign.left,
        ),
      ],
    );
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.status});

  final _BookResult status;

  @override
  Widget build(BuildContext context) {
    String text;

    switch (status) {
      case _BookResult.white:
        text = '1 - 0';
        break;
      case _BookResult.black:
        text = '0 - 1';
        break;
      case _BookResult.draw:
        text = '½ - ½';
        break;
      case _BookResult.unknown:
        text = '*';
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 4.sp),
      decoration: BoxDecoration(
        color: kBlackColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6.br),
        border: Border.all(color: kBlackColor.withValues(alpha: 0.06)),
      ),
      child: Text(
        text,
        style: AppTypography.textSmMedium.copyWith(
          color: kBlackColor,
          fontWeight: FontWeight.w700,
          fontSize: 12.sp,
        ),
      ),
    );
  }
}
