import 'dart:convert';

import 'package:cactus/models/types.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelCache {
  static const String _modelKey = 'cactus_model';

  static Future<void> saveModel(CactusModel model) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(model.toJson());
      await prefs.setString("${_modelKey}_${model.slug}", jsonString);
    } catch (e) {
      debugPrint('Error saving model to cache: $e');
      rethrow;
    }
  }

  static Future<CactusModel?> loadModel(String slug) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString("${_modelKey}_$slug");
      if (jsonString == null || jsonString.isEmpty) {
        return null;
      }
      final Map<String, dynamic> json =
          jsonDecode(jsonString) as Map<String, dynamic>;
      return CactusModel.fromJson(json);
    } catch (e) {
      debugPrint('Error loading model from cache: $e');
      return null;
    }
  }
}
