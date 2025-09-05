import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;

final locationRepositoryProvider = AutoDisposeProvider<LocationRepository>((
  ref,
) {
  return LocationRepository();
});

// Location Repository
class LocationRepository {
  Future<String> getCountryCode() async {
  try {
    final response = await http.get(Uri.parse('https://ipapi.co/country/'));
    return response.body.trim();
  } catch (e) {
    return 'US';
  }
  }
}
