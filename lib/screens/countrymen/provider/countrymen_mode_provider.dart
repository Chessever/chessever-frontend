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

/// True while the Games tab's floating search is expanded — the parent screen
/// watches this to hide the floating bottom country selector while searching.
final countrymenSearchActiveProvider = StateProvider<bool>((ref) => false);
