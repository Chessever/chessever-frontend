import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final locationRepositoryProvider = AutoDisposeProvider<LocationRepository>((
  ref,
) {
  return LocationRepository();
});

// Location Model
class LocationData {
  final double latitude;
  final double longitude;
  final String country;
  final String countryCode;
  final String city;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.country,
    required this.countryCode,
    required this.city,
  });

  @override
  String toString() {
    return 'LocationData(lat: $latitude, lng: $longitude, country: $country, city: $city)';
  }
}

// Location Repository
class LocationRepository {
  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied');
    }
    return true;
  }

  Future<LocationData> getCurrentLocation() async {
    try {
      await _handleLocationPermission();

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        return LocationData(
          latitude: position.latitude,
          longitude: position.longitude,
          country: place.country ?? 'Unknown',
          countryCode: place.isoCountryCode ?? 'Unknown',
          city: place.locality ?? 'Unknown',
        );
      } else {
        throw Exception('Unable to get location details');
      }
    } catch (e) {
      throw Exception('Failed to get location: $e');
    }
  }

  Future<String> getCountryOnly() async {
    final locationData = await getCurrentLocation();
    return locationData.country;
  }

  Future<String> getCountryCode() async {
    final locationData = await getCurrentLocation();
    return locationData.countryCode;
  }
}
