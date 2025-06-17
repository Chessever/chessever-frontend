// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'country_dropdown_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$countryDropdownNotifierHash() =>
    r'1e4cc6dda5dace10ffebe454e440a994b929373d';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

abstract class _$CountryDropdownNotifier
    extends BuildlessAutoDisposeNotifier<CountryDropdownState> {
  late final String? initialCountry;

  CountryDropdownState build({String? initialCountry});
}

/// See also [CountryDropdownNotifier].
@ProviderFor(CountryDropdownNotifier)
const countryDropdownNotifierProvider = CountryDropdownNotifierFamily();

/// See also [CountryDropdownNotifier].
class CountryDropdownNotifierFamily extends Family<CountryDropdownState> {
  /// See also [CountryDropdownNotifier].
  const CountryDropdownNotifierFamily();

  /// See also [CountryDropdownNotifier].
  CountryDropdownNotifierProvider call({String? initialCountry}) {
    return CountryDropdownNotifierProvider(initialCountry: initialCountry);
  }

  @override
  CountryDropdownNotifierProvider getProviderOverride(
    covariant CountryDropdownNotifierProvider provider,
  ) {
    return call(initialCountry: provider.initialCountry);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'countryDropdownNotifierProvider';
}

/// See also [CountryDropdownNotifier].
class CountryDropdownNotifierProvider
    extends
        AutoDisposeNotifierProviderImpl<
          CountryDropdownNotifier,
          CountryDropdownState
        > {
  /// See also [CountryDropdownNotifier].
  CountryDropdownNotifierProvider({String? initialCountry})
    : this._internal(
        () => CountryDropdownNotifier()..initialCountry = initialCountry,
        from: countryDropdownNotifierProvider,
        name: r'countryDropdownNotifierProvider',
        debugGetCreateSourceHash:
            const bool.fromEnvironment('dart.vm.product')
                ? null
                : _$countryDropdownNotifierHash,
        dependencies: CountryDropdownNotifierFamily._dependencies,
        allTransitiveDependencies:
            CountryDropdownNotifierFamily._allTransitiveDependencies,
        initialCountry: initialCountry,
      );

  CountryDropdownNotifierProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.initialCountry,
  }) : super.internal();

  final String? initialCountry;

  @override
  CountryDropdownState runNotifierBuild(
    covariant CountryDropdownNotifier notifier,
  ) {
    return notifier.build(initialCountry: initialCountry);
  }

  @override
  Override overrideWith(CountryDropdownNotifier Function() create) {
    return ProviderOverride(
      origin: this,
      override: CountryDropdownNotifierProvider._internal(
        () => create()..initialCountry = initialCountry,
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        initialCountry: initialCountry,
      ),
    );
  }

  @override
  AutoDisposeNotifierProviderElement<
    CountryDropdownNotifier,
    CountryDropdownState
  >
  createElement() {
    return _CountryDropdownNotifierProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is CountryDropdownNotifierProvider &&
        other.initialCountry == initialCountry;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, initialCountry.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin CountryDropdownNotifierRef
    on AutoDisposeNotifierProviderRef<CountryDropdownState> {
  /// The parameter `initialCountry` of this provider.
  String? get initialCountry;
}

class _CountryDropdownNotifierProviderElement
    extends
        AutoDisposeNotifierProviderElement<
          CountryDropdownNotifier,
          CountryDropdownState
        >
    with CountryDropdownNotifierRef {
  _CountryDropdownNotifierProviderElement(super.provider);

  @override
  String? get initialCountry =>
      (origin as CountryDropdownNotifierProvider).initialCountry;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
