// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$favoriteControllerHash() =>
    r'd62824e56cd404d4d0b0e6371c43e9e840c3a514';

/// See also [favoriteController].
@ProviderFor(favoriteController)
final favoriteControllerProvider =
    AutoDisposeProvider<FavoriteController>.internal(
      favoriteController,
      name: r'favoriteControllerProvider',
      debugGetCreateSourceHash:
          const bool.fromEnvironment('dart.vm.product')
              ? null
              : _$favoriteControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef FavoriteControllerRef = AutoDisposeProviderRef<FavoriteController>;
String _$favoriteNotifierHash() => r'166715e7e54b0b5e56db2c1a419f8e51245c2f0b';

/// See also [FavoriteNotifier].
@ProviderFor(FavoriteNotifier)
final favoriteNotifierProvider = AutoDisposeAsyncNotifierProvider<
  FavoriteNotifier,
  List<Map<String, dynamic>>
>.internal(
  FavoriteNotifier.new,
  name: r'favoriteNotifierProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$favoriteNotifierHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$FavoriteNotifier =
    AutoDisposeAsyncNotifier<List<Map<String, dynamic>>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
