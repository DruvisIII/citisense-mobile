import 'package:shared_preferences/shared_preferences.dart';

/// Controls CitiSense foreground notification alerts.
/// This preference is stored on this device.
class NotificationPreference {
  static const String _key = 'citisense_notifications_enabled';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
