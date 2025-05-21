import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:omni_home/views/setup/setup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _isSetupComplete = false;

  @override
  void initState() {
    super.initState();
    _checkSetupStatus();
  }

  Future<void> _checkSetupStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('esp32_ip');
    setState(() {
      _isSetupComplete = savedIp != null && savedIp.isNotEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _isSetupComplete
        ? LightControlPage(title: widget.title)
        : SetupPage(title: widget.title);
  }
}

class LightControlPage extends StatefulWidget {
  const LightControlPage({super.key, required String title});
  @override
  State<LightControlPage> createState() => _LightControlPageState();
}

class _LightControlPageState extends State<LightControlPage> {
  // ignore: non_constant_identifier_names
  String esp32_ip = ""; // Placeholder for ESP32 IP (Predefined)
  String ssid = "Loading..."; // Placeholder for SSID (Predefined)
  bool isLoading = false;
  List<bool> relayStates = [false, false, false, false, false, false];
  List<TimeOfDay> onTimes = [
    const TimeOfDay(hour: 6, minute: 0),
    const TimeOfDay(hour: 8, minute: 0),
    const TimeOfDay(hour: 12, minute: 0),
    const TimeOfDay(hour: 15, minute: 0),
    const TimeOfDay(hour: 18, minute: 0),
    const TimeOfDay(hour: 21, minute: 0),
  ];
  List<TimeOfDay> offTimes = [
    const TimeOfDay(hour: 7, minute: 0),
    const TimeOfDay(hour: 9, minute: 0),
    const TimeOfDay(hour: 13, minute: 0),
    const TimeOfDay(hour: 16, minute: 0),
    const TimeOfDay(hour: 19, minute: 0),
    const TimeOfDay(hour: 22, minute: 0),
  ];

  @override
  void initState() {
    super.initState();
    _loadIp();
  }

  Future<void> _loadIp() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      esp32_ip = prefs.getString('esp32_ip') ?? esp32_ip;
    });
    _fetchInitialData();
  }

  Future<void> _saveIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp32_ip', ip);
    setState(() {
      esp32_ip = ip;
    });
    await _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('http://$esp32_ip/')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          ssid = data['ssid'] ?? 'Unknown';
          isLoading = false;
        });
      } else {
        throw Exception('Failed to fetch data: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        ssid = "Error connecting";
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error connecting to ESP32: $e'),
          action: SnackBarAction(label: 'Retry', onPressed: _fetchInitialData),
        ),
      );
    }
  }

  Future<void> _selectTime(BuildContext context, int relayIndex, bool isOnTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isOnTime ? onTimes[relayIndex] : offTimes[relayIndex],
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.teal,
              onPrimary: Colors.white,
              surface: Colors.teal.shade50,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isOnTime) {
          onTimes[relayIndex] = picked;
        } else {
          offTimes[relayIndex] = picked;
        }
      });
    }
  }

  Future<void> _sendSettingsToESP() async {
    setState(() => isLoading = true);
    try {
      final Map<String, String> data = {};
      for (int i = 0; i < relayStates.length; i++) {
        data['onTime${i + 1}'] = _formatTime(onTimes[i]);
        data['offTime${i + 1}'] = _formatTime(offTimes[i]);
      }

      final response = await http.post(
        Uri.parse('http://$esp32_ip/set'),
        body: jsonEncode(data),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Settings saved successfully!')),
          );
        } else {
          throw Exception('Failed to save settings: ${data['error']}');
        }
      } else {
        throw Exception('Failed to save settings: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          action: SnackBarAction(label: 'Retry', onPressed: _sendSettingsToESP),
        ),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _toggleRelay(int index, bool value) async {
    setState(() => isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('http://$esp32_ip/toggle'),
        body: jsonEncode({
          'relay': (index + 1).toString(),
          'state': value ? '1' : '0',
        }),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          setState(() {
            relayStates[index] = value;
          });
        } else {
          throw Exception('Failed to toggle relay: ${data['error']}');
        }
      } else {
        throw Exception('Failed to toggle relay: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error toggling relay: $e'),
          action: SnackBarAction(label: 'Retry', onPressed: () => _toggleRelay(index, value)),
        ),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _resetWiFi() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(Uri.parse('http://$esp32_ip/reset')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('esp32_ip');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('WiFi reset. Returning to setup screen.')),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const SetupPage(title: 'OmniHome')),
          );
        } else {
          throw Exception('Failed to reset WiFi: ${data['error']}');
        }
      } else {
        throw Exception('Failed to reset WiFi: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error resetting WiFi: $e'),
          action: SnackBarAction(label: 'Retry', onPressed: _resetWiFi),
        ),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _updateIpDialog() async {
    final controller = TextEditingController(text: esp32_ip);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update ESP32 IP'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter ESP32 IP'),
          keyboardType: TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(controller.text)) {
                _saveIp(controller.text);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('IP updated. Connecting to ESP32...')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid IP address format')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relay Control'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _updateIpDialog,
            tooltip: 'Change ESP32 IP',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Control Relays',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ...List.generate(relayStates.length, (index) => _buildRelayControl(index)),
                  const SizedBox(height: 24),
                  Center(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Save All Settings'),
                      onPressed: _sendSettingsToESP,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Network Info',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text('IP: $esp32_ip'),
                          Text('SSID: $ssid'),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            icon: const Icon(Icons.wifi_off),
                            label: const Text('Reset WiFi'),
                            onPressed: _resetWiFi,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRelayControl(int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Relay ${index + 1}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('ON Time:'),
                OutlinedButton(
                  onPressed: () => _selectTime(context, index, true),
                  child: Text(_formatTime(onTimes[index])),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('OFF Time:'),
                OutlinedButton(
                  onPressed: () => _selectTime(context, index, false),
                  child: Text(_formatTime(offTimes[index])),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: Text('Relay ${index + 1} State'),
              value: relayStates[index],
              onChanged: (value) => _toggleRelay(index, value),
              activeColor: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}