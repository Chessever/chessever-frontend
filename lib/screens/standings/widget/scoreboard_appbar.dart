import 'package:chessever2/screens/standings/widget/player_dropdown.dart';
import 'package:chessever2/screens/tournaments/widget/round_drop_down.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ScoreboardAppbar extends ConsumerStatefulWidget {
  const ScoreboardAppbar({super.key});

  @override
  ConsumerState<ScoreboardAppbar> createState() => _ScoreboardAppbarState();
}

class _ScoreboardAppbarState extends ConsumerState<ScoreboardAppbar> {
  late final GlobalKey _menuKey;

  @override
  void initState() {
    _menuKey = GlobalKey();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 16.w),
        IconButton(
          iconSize: 24.ic,
          padding: EdgeInsets.zero,
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: Icon(
            Icons.arrow_back_ios_new_outlined,
            size: 24.ic,
          ),
        ),
        const Spacer(),
        const PlayerDropDown(),
        const Spacer(),
        IconButton(onPressed: () {}, icon: Icon(Icons.favorite_outline)),

        SizedBox(width: 20.w),
      ],
    );
  }
}
