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
  final VoidCallback? onDownloadTournament;
  final VoidCallback? onAddToLibrary;

  const CompletedEventCard({
    super.key,
    required this.tourEventCardModel,
    this.onTap,
    this.onDownloadTournament,
    this.onAddToLibrary,
  });

  @override
  Widget build(BuildContext context) {
    return EventCard(
      tourEventCardModel: tourEventCardModel,
      onTap: onTap,
      onMorePressed: () => _showMenu(context),
    );
  }

  void _showMenu(BuildContext context) {
    // showModalBottomSheet(
    //   context: context,
    //   backgroundColor: Colors.transparent,
    //   builder:
    //       (context) => Container(
    //         margin: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 10.sp),
    //
    //         decoration: BoxDecoration(
    //           color: kBackgroundColor,
    //           borderRadius: BorderRadius.circular(20.br),
    //         ),
    //         child: Column(
    //           mainAxisSize: MainAxisSize.min,
    //           children: [
    //             ListTile(
    //               leading: SvgWidget(
    //                 SvgAsset.tournamentPgnIcon,
    //                 semanticsLabel: 'Download Tournament PGN',
    //                 height: 20.ic,
    //                 width: 20.ic,
    //                 colorFilter: const ColorFilter.mode(
    //                   kWhiteColor,
    //                   BlendMode.srcIn,
    //                 ),
    //               ),
    //               title: Text(
    //                 'Download Tournament PGN',
    //                 style: AppTypography.textXsBold.copyWith(
    //                   color: kWhiteColor,
    //                 ),
    //               ),
    //               onTap: () {
    //                 Navigator.pop(context);
    //                 onDownloadTournament?.call();
    //               },
    //             ),
    //
    //             ListTile(
    //               leading: SvgWidget(
    //                 SvgAsset.addToLibraryIcon,
    //                 semanticsLabel: 'Add to Library',
    //                 height: 20.ic,
    //                 width: 20.ic,
    //                 colorFilter: const ColorFilter.mode(
    //                   kWhiteColor,
    //                   BlendMode.srcIn,
    //                 ),
    //               ),
    //               title: Text(
    //                 'Add to Library',
    //                 style: AppTypography.textXsBold.copyWith(
    //                   color: kWhiteColor,
    //                 ),
    //                 // style: TextStyle(color: kWhiteColor),
    //               ),
    //               onTap: () {
    //                 Navigator.pop(context);
    //                 onAddToLibrary?.call();
    //               },
    //             ),
    //           ],
    //         ),
    //       ),
    // );
  }
}
