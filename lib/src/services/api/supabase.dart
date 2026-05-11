import 'dart:io';
import 'dart:convert';

import 'package:cactus/models/types.dart';
import 'package:flutter/foundation.dart';

class Supabase {
  static const String _supabaseUrl = 'https://vlqqczxwyaodtcdmdmlw.supabase.co';
  static const String _supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZscXFjenh3eWFvZHRjZG1kbWx3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTE1MTg2MzIsImV4cCI6MjA2NzA5NDYzMn0.nBzqGuK9j6RZ6mOPWU2boAC_5H9XDs-fPpo5P3WZYbI';

  static Future<List<VoiceModel>> fetchVoiceModels({String? provider}) async {
    final client = HttpClient();

    try {
      String url = '$_supabaseUrl/rest/v1/whisper?select=*';
      if (provider != null) {
        url += '&provider=eq.$provider';
      }
      
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('apikey', _supabaseKey);
      request.headers.set('Authorization', 'Bearer $_supabaseKey');
      request.headers.set('Accept-Profile', 'cactus');

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        debugPrint('Fetched voice models for provider $provider: $responseBody');
        final List<dynamic> data = json.decode(responseBody);
        return data.map((json) => VoiceModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to fetch voice models: ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }
}
