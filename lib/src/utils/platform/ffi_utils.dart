import 'package:cactus/src/utils/platform/device_info.dart';
import 'package:flutter/foundation.dart';

Future<String?> getDeviceId() async {
  try {
    final deviceData = await getDeviceMetadata();
    final deviceId = deviceData['device_id'] as String?;
    return deviceId;
  } catch (e) {
    debugPrint('Error getting device ID: $e');
    return null;
  }
}
