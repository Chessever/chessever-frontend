import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'event_card.dart';

class CompletedEventCard extends StatelessWidget {
  final GroupEventCardModel tourEventCardModel;
  final VoidCallback? onTap;

  const CompletedEventCard({
    super.key,
    required this.tourEventCardModel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return EventCard(
      tourEventCardModel: tourEventCardModel,
      onTap: onTap,
    );
  }
}
