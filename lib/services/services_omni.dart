import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ESP32Service with ChangeNotifier {
  String? _esp32IP;
  bool _isConnected = false;
  bool _isReconnecting = false;
  String? _ssid;
  final List<bool> _relayStates = [false, false, false, false, false, false]; //Change this to match your relay count
  final List<TimeOfDay> _onTimes = [ // Default on times for 6 relays
    const TimeOfDay(hour: 8, minute: 0),
    const TimeOfDay(hour: 9, minute: 0),
    const TimeOfDay(hour: 10, minute: 0),
    const TimeOfDay(hour: 11, minute: 0),
    const TimeOfDay(hour: 12, minute: 0),
    const TimeOfDay(hour: 13, minute: 0),
  ];
  final List<TimeOfDay> _offTimes = [ // Default off times for 6 relays
    const TimeOfDay(hour: 16, minute: 0),
    const TimeOfDay(hour: 17, minute: 0),
    const TimeOfDay(hour: 18, minute: 0),
    const TimeOfDay(hour: 19, minute: 0),
    const TimeOfDay(hour: 20, minute: 0),
    const TimeOfDay(hour: 21, minute: 0),
  ];
  Timer? _pollingTimer;

  String? get esp32IP => _esp32IP;
  bool get isConnected => _isConnected;
  bool get isReconnecting => _isReconnecting;
  String? get ssid => _ssid;
  List<bool> get relayStates => _relayStates;
  List<TimeOfDay> get onTimes => _onTimes;
  List<TimeOfDay> get offTimes => _offTimes;

  ESP32Service() {
    _loadSavedIP();
  }

  Future<void> _loadSavedIP() async {
    final prefs = await SharedPreferences.getInstance();
    _esp32IP = prefs.getString('esp32IP');
    _ssid = prefs.getString('lastSSID');
    if (_esp32IP != null) {
      await tryReconnect();
      _startPolling();
    }
    notifyListeners();
  }

  Future<void> setESP32IP(String ip) async {
    _esp32IP = ip;
    _isConnected = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp32IP', ip);
    _startPolling();
    notifyListeners();
  }

  Future<void> tryReconnect() async {
    if (_esp32IP == null) return;
    _isReconnecting = true;
    notifyListeners();
    try {
      final response = await http
          .get(Uri.parse('http://$_esp32IP/'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _isConnected = true;
          _ssid = data['ssid'];
          await _fetchStatus();
        } else {
          _isConnected = false;
        }
      } else {
        _isConnected = false;
      }
    } catch (e) {
      print('Error reconnecting: $e');
      _isConnected = false;
    }
    _isReconnecting = false;
    notifyListeners();
  }

  Future<void> _fetchStatus() async {
    if (_esp32IP == null || !_isConnected) return;
    try {
      final response = await http
          .get(Uri.parse('http://$_esp32IP/getStatus'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          List<dynamic> relays = data['relays'];
          for (var relay in relays) {
            int index = relay['relay'] - 1;
            _relayStates[index] = relay['state'] == 1;
            _onTimes[index] = _parseTime(relay['onTime']);
            _offTimes[index] = _parseTime(relay['offTime']);
          }
          notifyListeners();
        }
      }
    } catch (e) {
      print('Error fetching status: $e');
    }
  }

  Future<void> fetchStatus() async {
    await _fetchStatus();
  }

  Future<bool> setSchedule(List<TimeOfDay> onTimes, List<TimeOfDay> offTimes) async {
    if (_esp32IP == null || !_isConnected) {
      print('Cannot set schedule: Not connected to ESP32');
      return false;
    }

    try {
      final Map<String, String> data = { // Prepare data for all 6 relays
        'onTime1': _formatTime(onTimes[0]),
        'offTime1': _formatTime(offTimes[0]),
        'onTime2': _formatTime(onTimes[1]),
        'offTime2': _formatTime(offTimes[1]),
        'onTime3': _formatTime(onTimes[2]),
        'offTime3': _formatTime(offTimes[2]),
        'onTime4': _formatTime(onTimes[3]),
        'offTime4': _formatTime(offTimes[3]),
        'onTime5': _formatTime(onTimes[4]),
        'offTime5': _formatTime(offTimes[4]),
        'onTime6': _formatTime(onTimes[5]),
        'offTime6': _formatTime(offTimes[5]),
      };
      print('Sending schedule to ESP32: $data');
      final response = await http
          .post(
            Uri.parse('http://$_esp32IP/set'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 10));
      print('ESP32 response: status=${response.statusCode}, body=${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          await _fetchStatus(); // Sync state after setting
          return true;
        } else {
          print('Failed to set schedule: ${responseData['error']}');
          return false;
        }
      } else {
        print('Failed to set schedule: HTTP ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Error setting schedule: $e');
      return false;
    }
  }

  Future<bool> setSingleRelaySchedule(int relayIndex, bool isOnTime, TimeOfDay time) async {
    if (_esp32IP == null || !_isConnected) {
      print('Cannot set single relay schedule: Not connected to ESP32');
      return false;
    }

    try {
      final Map<String, String> data = {
        'relay': (relayIndex + 1).toString(),
        'type': isOnTime ? 'onTime' : 'offTime',
        'time': _formatTime(time),
      };
      print('Sending single relay schedule to ESP32: $data');
      final response = await http
          .post(
            Uri.parse('http://$_esp32IP/setSingle'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 5));
      print('ESP32 response: status=${response.statusCode}, body=${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          await _fetchStatus(); // Sync state after setting
          return true;
        } else {
          print('Failed to set single relay schedule: ${responseData['error']}');
          return false;
        }
      } else {
        print('Failed to set single relay schedule: HTTP ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Error setting single relay schedule: $e');
      return false;
    }
  }

  Future<void> toggleRelay(int index, bool value) async {
    if (_esp32IP == null || !_isConnected) {
      print('Cannot toggle relay: Not connected to ESP32');
      return;
    }

    final previousState = _relayStates[index];
    _relayStates[index] = value;
    notifyListeners();

    try {
      final response = await http
          .post(
            Uri.parse('http://$_esp32IP/toggle'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'relay': (index + 1).toString(),
              'state': value ? '1' : '0',
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] != true) {
          _relayStates[index] = previousState;
          notifyListeners();
          print('Failed to toggle relay: ${responseData['error']}');
        }
      } else {
        _relayStates[index] = previousState;
        notifyListeners();
        print('Failed to toggle relay: HTTP ${response.statusCode}');
      }
    } catch (e) {
      _relayStates[index] = previousState;
      notifyListeners();
      print('Error toggling relay: $e');
    }
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isConnected) {
        _fetchStatus();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> disconnect() async {
    _pollingTimer?.cancel();
    try {
      if (_esp32IP != null) {
        await http
            .post(Uri.parse('http://$_esp32IP/disconnect'))
            .timeout(const Duration(seconds: 5));
      }
    } catch (e) {
      // Ignore errors during disconnect
    }
    _esp32IP = null;
    _isConnected = false;
    _ssid = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('esp32IP');
    await prefs.remove('lastSSID');
    await prefs.remove('lastPassword');
    notifyListeners();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}