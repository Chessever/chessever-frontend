import 'package:chessever2/repository/supabase/tour/published_tiebreak.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// The organizer's labels and values, in their published priority order.
class PublishedPlayerTiebreaks extends StatelessWidget {
  const PublishedPlayerTiebreaks({super.key, required this.values});
  final List<PublishedTiebreak> values;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 4,
    children: [
      for (final value in values)
        Text(
          '${value.description}: ${value.formattedPoints}',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
        ),
    ],
  );
}
