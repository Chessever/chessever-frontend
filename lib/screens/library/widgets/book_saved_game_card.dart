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
    final whiteElo = md['WhiteElo']?.toString();
    final blackElo = md['BlackElo']?.toString();
    final result = md['Result'] as String? ?? '*';
    final eco = md['ECO'] as String? ?? '';
    final event = md['Event'] as String? ?? md['Site'] as String? ?? '';
    final date = _formatDate(md['Date'] as String?);

    final status = _parseResult(result);
    final timeControlIcon = _getTimeControlIcon(md);

    return GestureDetector(
      onTap: () async {
        HapticFeedbackService.cardTap();
        await loadSavedAnalysis(context, analysis);
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 10.sp),
        decoration: BoxDecoration(
          color: const Color(0xFF252525), // Dark grey background
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: kWhiteColor.withValues(alpha: 0.05),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 12.sp),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _PlayerInfo(
                      name: whiteName,
                      rating: whiteElo,
                      isWinner: status == _BookResult.white,
                      alignment: CrossAxisAlignment.start,
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.sp),
                    child: _ResultBadge(status: status),
                  ),
                  Expanded(
                    child: _PlayerInfo(
                      name: blackName,
                      rating: blackElo,
                      isWinner: status == _BookResult.black,
                      alignment: CrossAxisAlignment.end,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
              decoration: BoxDecoration(
                color: kBlackColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(12.br),
                ),
                border: Border(
                  top: BorderSide(color: kWhiteColor.withValues(alpha: 0.05)),
                ),
              ),
              child: Row(
                children: [
                  // Time Control Icon
                  Image.asset(timeControlIcon, width: 14.sp, height: 14.sp),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      event.isNotEmpty ? event : 'Unknown event',
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (eco.isNotEmpty) ...[
                    SizedBox(width: 8.w),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 4.w,
                        vertical: 2.h,
                      ),
                      decoration: BoxDecoration(
                        color: kWhiteColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4.br),
                      ),
                      child: Text(
                        eco,
                        style: AppTypography.textXsBold.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.7),
                          fontSize: 10.sp,
                        ),
                      ),
                    ),
                  ],
                  if (date.isNotEmpty) ...[
                    SizedBox(width: 10.w),
                    Text(
                      date,
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
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
    switch (result.trim()) {
      case '1-0':
        return _BookResult.white;
      case '0-1':
        return _BookResult.black;
      case '1/2-1/2':
      case '½-½':
        return _BookResult.draw;
      default:
        return _BookResult.unknown;
    }
  }
}

enum _BookResult { white, black, draw, unknown }

class _PlayerInfo extends StatelessWidget {
  const _PlayerInfo({
    required this.name,
    required this.rating,
    required this.isWinner,
    required this.alignment,
  });

  final String name;
  final String? rating;
  final bool isWinner;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          name,
          style: AppTypography.textSmMedium.copyWith(
            color: kWhiteColor,
            fontWeight: isWinner ? FontWeight.w700 : FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 2.sp),
        Text(
          rating != null && rating!.isNotEmpty ? rating! : '',
          style: AppTypography.textXsRegular.copyWith(
            color: kWhiteColor.withValues(alpha: 0.5),
            fontSize: 12.sp,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
    Color backgroundColor;
    Color textColor;
    String text;

    switch (status) {
      case _BookResult.white:
        backgroundColor = kWhiteColor.withValues(alpha: 0.1);
        textColor = kWhiteColor;
        text = '1-0';
        break;
      case _BookResult.black:
        backgroundColor = kWhiteColor.withValues(alpha: 0.1);
        textColor = kWhiteColor;
        text = '0-1';
        break;
      case _BookResult.draw:
        backgroundColor = kWhiteColor.withValues(alpha: 0.05);
        textColor = kWhiteColor.withValues(alpha: 0.7);
        text = '½-½';
        break;
      case _BookResult.unknown:
        backgroundColor = kWhiteColor.withValues(alpha: 0.05);
        textColor = kWhiteColor.withValues(alpha: 0.5);
        text = '-';
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 4.sp),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6.br),
        border: Border.all(
          color: kWhiteColor.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: AppTypography.textSmMedium.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 12.sp,
        ),
      ),
    );
  }
}
