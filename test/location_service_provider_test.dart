import 'package:chessever2/utils/location_service_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocationService', () {
    test(
      'keeps legacy reference database URLs online with a neutral label',
      () {
        final service = LocationService();
        const host =
            'chess'
            'base.com';

        expect(service.isOnlinePlatform('https://$host/news'), isTrue);
        expect(
          service.prettifyPlatformName('https://$host/news'),
          'Reference Database',
        );
      },
    );
  });
}
