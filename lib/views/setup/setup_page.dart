import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:omni_home/views/home/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_scan/wifi_scan.dart';

class SetupPage extends StatefulWidget {
  final String title;
  const SetupPage({super.key, required this.title});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  List<String> _wifiList = [];
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _loadWifiList();
  }

  Future<void> _loadWifiList() async {
    try {
      final canScan = await WiFiScan.instance.canStartScan(askPermissions: true);
      if (canScan != CanStartScan.yes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot start WiFi scan. Check permissions.')),
        );
        return;
      }
      final isScanning = await WiFiScan.instance.startScan();
      if (!isScanning) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start WiFi scan.')),
        );
        return;
      }
      final canGetResults = await WiFiScan.instance.canGetScannedResults(askPermissions: true);
      if (canGetResults == CanGetScannedResults.yes) {
        final accessPoints = await WiFiScan.instance.getScannedResults();
        setState(() {
          _wifiList = accessPoints.map((ap) => ap.ssid).where((ssid) => ssid.isNotEmpty).toSet().toList();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot get WiFi scan results. Check permissions.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading WiFi list: $e')),
      );
    }
  }

  Future<void> _saveCredentials() async {
    final ip = _ipController.text;
    final ssid = _ssidController.text;
    final password = _passwordController.text;

    if (!RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(ip)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid IP address format')),
      );
      return;
    }

    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SSID cannot be empty')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('http://$ip/setWiFi'),
        body: jsonEncode({
          'ssid': ssid,
          'password': password,
        }),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          final newIp = data['ip'];
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('esp32_ip', newIp); // <-- FIXED KEY
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LightControlPage(title: 'OmniHome')),
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('WiFi credentials saved. Connected to ESP32.')),
          );
        } else {
          throw Exception('Failed to set WiFi: ${data['error']}');
        }
      } else {
        throw Exception('Failed to set WiFi: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error connecting to ESP32: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 WiFi Setup'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Configure ESP32 WiFi',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'ESP32 AP IP Address',
                  hintText: 'e.g., 192.168.4.1',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'WiFi SSID',
                  border: OutlineInputBorder(),
                ),
                items: [
                  ..._wifiList.map((ssid) => DropdownMenuItem<String>(
                        value: ssid,
                        child: Text(ssid.isEmpty ? 'Unknown' : ssid),
                      )),
                  const DropdownMenuItem<String>(
                    value: 'manual',
                    child: Text('Enter manually'),
                  ),
                ],
                onChanged: (value) {
                  if (value == 'manual') {
                    _ssidController.clear();
                  } else {
                    _ssidController.text = value ?? '';
                  }
                },
                hint: const Text('Select WiFi Network'),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _ssidController,
                decoration: const InputDecoration(
                  labelText: 'WiFi SSID (if manual)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'WiFi Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                ),
                obscureText: !_isPasswordVisible,
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _saveCredentials,
                      child: const Text('Save and Connect'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
