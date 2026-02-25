import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Tab mode for Countrymen screen
enum CountrymenScreenMode {
  events, // Events/tournaments in country
  games, // Games from country with date tabs
  players, // Players from country
}

final selectedCountrymenModeProvider =
    AutoDisposeStateProvider<CountrymenScreenMode>(
      (ref) => CountrymenScreenMode.games,
    );

const countrymenModeNames = {
  CountrymenScreenMode.events: 'Events',
  CountrymenScreenMode.games: 'Games',
  CountrymenScreenMode.players: 'Players',
};
