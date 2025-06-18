// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$playerControllerHash() => r'da585ac700e3f95313c532c28a35779f18944e0c';

/// See also [playerController].
@ProviderFor(playerController)
final playerControllerProvider = AutoDisposeProvider<PlayerController>.internal(
  playerController,
  name: r'playerControllerProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$playerControllerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PlayerControllerRef = AutoDisposeProviderRef<PlayerController>;
String _$playerNotifierHash() => r'166fb5a78b950fb4e063239cc77ac377340eea77';

/// See also [PlayerNotifier].
@ProviderFor(PlayerNotifier)
final playerNotifierProvider = AutoDisposeAsyncNotifierProvider<
  PlayerNotifier,
  List<Map<String, dynamic>>
>.internal(
  PlayerNotifier.new,
  name: r'playerNotifierProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$playerNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$PlayerNotifier = AutoDisposeAsyncNotifier<List<Map<String, dynamic>>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
