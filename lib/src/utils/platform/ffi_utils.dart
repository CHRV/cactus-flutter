import 'package:cactus/src/services/api/supabase.dart';
import 'package:cactus/src/utils/platform/device_info.dart';
import 'package:flutter/foundation.dart';

Future<String?> registerApp(String encString) async {
  try {
    final response = encString;
    return response.isNotEmpty ? response : null;
  } catch (e) {
    debugPrint('Error in registerApp: $e');
    return null;
  }
}

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

Future<String?> fetchDeviceId() async {
  String? deviceId = await getDeviceId();
  if (deviceId == null) {
    debugPrint('Failed to get device ID, registering device...');
    try {
      final deviceData = await getDeviceMetadata();
      return await Supabase.registerDevice(deviceData: deviceData);
    } catch (e) {
      return null;
    }
  }
  return deviceId;
}
