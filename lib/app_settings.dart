import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<double> appFontScale = ValueNotifier<double>(1.0);

/// AI Insights (automatic photo analysis + category selection).
/// Stored on this device so the choice is remembered between launches.
class AiInsightsPreference {
  AiInsightsPreference._();

  static const String _key = 'citisense_ai_insights_enabled';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
