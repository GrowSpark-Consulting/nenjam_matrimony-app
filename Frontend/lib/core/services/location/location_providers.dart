import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_location_service.dart';

/// Device location gateway. Overridable in tests with a fake
/// [DeviceLocationService] — an OS permission dialog cannot be granted or
/// denied from a widget test, so overriding this is the only way to drive the
/// Near Me screen through its permission states.
final deviceLocationServiceProvider = Provider<DeviceLocationService>(
  (ref) => const DeviceLocationServiceImpl(),
);
