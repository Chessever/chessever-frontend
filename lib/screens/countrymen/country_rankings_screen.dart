import 'package:chessever2/screens/countrymen/tabs/countrymen_players_tab.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Reuses the country ranking list with route-local filters and an exact
/// federation code. No pinned or temporary country selection is changed.
class CountryRankingsScreen extends StatelessWidget {
  const CountryRankingsScreen({super.key, required this.federation});

  final String federation;

  @override
  Widget build(BuildContext context) {
    final name = CountryUtils.getCountryName(federation);
    return ProviderScope(
      overrides: [
        countrymenPlayersProvider.overrideWith(
          (ref) => CountrymenPlayersNotifier(ref, federation: federation),
        ),
      ],
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          backgroundColor: context.colors.background,
          foregroundColor: context.colors.textPrimary,
          title: Row(
            children: [
              FederationFlag(federation: federation, width: 28, height: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${name.isEmpty ? federation : name} rankings',
                  style: AppTypography.textLgMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        body: const SafeArea(top: false, child: CountrymenPlayersTab()),
      ),
    );
  }
}
