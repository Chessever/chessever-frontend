
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesErrorWidget extends ConsumerWidget {
  final String errorMessage;

  const GamesErrorWidget({
    super.key,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const GenericErrorWidget(),
          SizedBox(height: 16.h),
          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: kWhiteColor70),
          ),
          SizedBox(height: 16.h),
          ElevatedButton(
            onPressed: () async {
              await ref.read(gamesAppBarProvider.notifier).refreshRounds();
              await ref.read(gamesTourScreenProvider.notifier).refreshGames();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
