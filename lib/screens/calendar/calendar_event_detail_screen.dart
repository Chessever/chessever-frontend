import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';

class CalendarEventDetailScreen extends StatelessWidget {
  const CalendarEventDetailScreen({super.key, required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          event.name,
          style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
        ),
        backgroundColor: kBlack2Color,
        iconTheme: const IconThemeData(color: kWhiteColor),
      ),
      backgroundColor: kBlackColor,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(label: 'Location', value: event.location ?? 'TBA'),
            _DetailRow(
              label: 'Time Control',
              value: event.timeControl ?? 'Standard',
            ),
            _DetailRow(
              label: 'Start Date',
              value: event.startDate?.toIso8601String().split('T').first ?? 'TBA',
            ),
            _DetailRow(
              label: 'End Date',
              value: event.endDate?.toIso8601String().split('T').first ?? 'TBA',
            ),
            const SizedBox(height: 16),
            Text(
              'About',
              style: AppTypography.textMdBold.copyWith(color: kWhiteColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Community event',
              style: AppTypography.textSmRegular.copyWith(color: kWhiteColor70),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: AppTypography.textSmRegular.copyWith(color: kWhiteColor70),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
          ),
        ],
      ),
    );
  }
}
