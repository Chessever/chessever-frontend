import 'package:chessever2/widgets/game_date_header.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Dates identify the UTC calendar day displayed by Reports.
Uri reportsShareUri(ReportGameType? type, {String? date}) {
  if (date != null) {
    final parsed = DateTime.tryParse(date);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        !parsed.toIso8601String().startsWith('${date}T')) {
      throw ArgumentError.value(date, 'date', 'Expected a report calendar day');
    }
  }
  return Uri.https(
    'chessever.com',
    '/app/reports/${type?.key ?? 'all'}',
    date == null ? null : {'date': date},
  );
}

Future<void> showReportsShareMenu(
  BuildContext context,
  ReportGameType? type, {
  String? date,
}) async {
  final box = context.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;
  final origin = box.localToGlobal(Offset.zero) & box.size;
  HapticFeedbackService.medium();
  final selected = await showMenu<bool>(
    context: context,
    position: RelativeRect.fromRect(origin, Offset.zero & overlay.size),
    items: const [PopupMenuItem(value: true, child: Text('Share'))],
  );
  if (selected != true || !context.mounted) return;
  try {
    await Share.share(
      reportsShareUri(type, date: date).toString(),
      subject:
          'ChessEver Reports · ${type?.label ?? 'All'}${date == null ? '' : ' · $date'}',
      sharePositionOrigin: origin,
    );
  } catch (error) {
    if (context.mounted) {
      showAppSnack(context, userFacingError(error), tone: AppSnackTone.danger);
    }
  }
}

/// The date heading keeps its collapse tap and exposes sharing on hold.
class ReportsDateShareHeader extends StatelessWidget {
  const ReportsDateShareHeader({
    super.key,
    required this.date,
    required this.type,
    required this.dateLabel,
    required this.isExpanded,
    this.onToggle,
  });
  final String? date;
  final ReportGameType? type;
  final String dateLabel;
  final bool isExpanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) => GameDateHeader(
    dateLabel: dateLabel,
    isExpanded: isExpanded,
    onToggle: onToggle,
    onLongPress: date == null
        ? null
        : () => showReportsShareMenu(context, type, date: date),
  );
}
