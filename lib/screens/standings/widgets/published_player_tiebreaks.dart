import 'package:chessever2/repository/supabase/tour/published_tiebreak.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// The organizer's start number, club and tiebreaks, in Chess-Results' column
/// order (SNo, Club/City, TB1..n).
class PublishedPlayerTiebreaks extends StatelessWidget {
  const PublishedPlayerTiebreaks({
    super.key,
    required this.values,
    this.startNumber,
    this.club,
  });
  final List<PublishedTiebreak> values;
  final int? startNumber;
  final String? club;

  static bool hasAny({
    required List<PublishedTiebreak> values,
    int? startNumber,
    String? club,
  }) =>
      values.isNotEmpty ||
      (startNumber != null && startNumber > 0) ||
      (club != null && club.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: context.colors.textSecondary, fontSize: 12);
    final clubName = club?.trim();
    final sno = startNumber;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        if (sno != null && sno > 0) Text('SNo $sno', style: style),
        if (clubName != null && clubName.isNotEmpty)
          Text(
            clubName,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        for (final value in values)
          Text('${value.description}: ${value.formattedPoints}', style: style),
      ],
    );
  }
}
