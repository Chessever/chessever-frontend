// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tournament_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$tournamentControllerHash() =>
    r'219d75ba49a20ccd0e0818a980c1711679713e4a';

/// See also [tournamentController].
@ProviderFor(tournamentController)
final tournamentControllerProvider =
    AutoDisposeProvider<TournamentController>.internal(
      tournamentController,
      name: r'tournamentControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$tournamentControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TournamentControllerRef = AutoDisposeProviderRef<TournamentController>;
String _$tournamentNotifierHash() =>
    r'f3289f09e859dd5da5c4bbfd00e0cb345f520e5e';

/// See also [TournamentNotifier].
@ProviderFor(TournamentNotifier)
final tournamentNotifierProvider = AutoDisposeAsyncNotifierProvider<
  TournamentNotifier,
  Map<String, List<Map<String, dynamic>>>
>.internal(
  TournamentNotifier.new,
  name: r'tournamentNotifierProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$tournamentNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$TournamentNotifier =
    AutoDisposeAsyncNotifier<Map<String, List<Map<String, dynamic>>>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
