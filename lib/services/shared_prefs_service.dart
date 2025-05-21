import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefsService {
  static Future<String?> getEsp32Ip() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('esp32_ip');
  }
}