import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:omni_home/common/widgets/navbar.dart';
import 'package:omni_home/views/setTimer/set_timer_omni.dart';
import 'package:omni_home/views/setup/setup_page.dart';
import 'package:provider/provider.dart';
import 'package:omni_home/services/services_omni.dart';



void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ESP32Service()),
      ],
      child: const RelayControlApp(),
    ),
  );
}

class RelayControlApp extends StatelessWidget {
  const RelayControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Relay Control',
      theme: ThemeData(
        primarySwatch: Colors.purple,
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(),  // Changed from roboto to poppins
      ),
      debugShowCheckedModeBanner: false,
      home: const RelayControlPage(),
    );
  }
}

class RelayControlPage extends StatefulWidget {
  const RelayControlPage({super.key});

  @override
  State<RelayControlPage> createState() => _RelayControlPageState();
}

class _RelayControlPageState extends State<RelayControlPage> {
  int _selectedIndex = 0;
  bool _isSending = false; // Debounce flag

  Future<void> _sendSettingsToESP(String ip, List<TimeOfDay> onTimes, List<TimeOfDay> offTimes) async {
    if (_isSending) return;
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: ESP32 IP not set')),
      );
      return;
    }
    _isSending = true;
    try {
      final success = await Provider.of<ESP32Service>(context, listen: false).setSchedule(onTimes, offTimes);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save settings')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving settings: $e')),
      );
    } finally {
      _isSending = false;
    }
  }

  Future<void> _toggleRelay(ESP32Service esp32Service, int index, bool value) async {
    try {
      await esp32Service.toggleRelay(index, value);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error toggling relay: $e')),
      );
    }
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _onNavBarTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _handleRefresh(ESP32Service esp32Service) async {
    await esp32Service.tryReconnect();
    if (esp32Service.isConnected) {
      await esp32Service.fetchStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ESP32Service>(
      builder: (context, esp32Service, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'OmniHome',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,  // Semi-bold weight
                color: Colors.white,
                fontSize: 24,  // Slightly larger size
                letterSpacing: 0.5,  // Subtle letter spacing
              ),
            ),
            centerTitle: true,
            backgroundColor: Colors.purple[600],
          ),
          body: RefreshIndicator(
            onRefresh: () => _handleRefresh(esp32Service),
            color: Colors.purple[600],
            backgroundColor: Colors.white,
            child: _selectedIndex == 0
                ? SetTimeRelays(
                    onTimes: esp32Service.onTimes,
                    offTimes: esp32Service.offTimes,
                    relayStates: esp32Service.relayStates,
                    selectTime: (context, relayIndex, isOnTime, {TimeOfDay? voiceSelectedTime}) async {
                      if (voiceSelectedTime != null) {
                        if (isOnTime) {
                          esp32Service.onTimes[relayIndex] = voiceSelectedTime;
                        } else {
                          esp32Service.offTimes[relayIndex] = voiceSelectedTime;
                        }
                        // Send immediately for voice commands
                        await esp32Service.setSingleRelaySchedule(relayIndex, isOnTime, voiceSelectedTime);
                        esp32Service.notifyListeners();
                      } else {
                        // Store previous times for potential revert
                        final previousOnTime = esp32Service.onTimes[relayIndex];
                        final previousOffTime = esp32Service.offTimes[relayIndex];
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: isOnTime
                              ? esp32Service.onTimes[relayIndex]
                              : esp32Service.offTimes[relayIndex],
                        );
                        if (picked != null) {
                          if (isOnTime) {
                            esp32Service.onTimes[relayIndex] = picked;
                          } else {
                            esp32Service.offTimes[relayIndex] = picked;
                          }
                          // Send immediately to ESP32
                          await esp32Service.setSingleRelaySchedule(relayIndex, isOnTime, picked);
                          esp32Service.notifyListeners();
                        } else {
                          // Revert to previous times if canceled
                          if (isOnTime) {
                            esp32Service.onTimes[relayIndex] = previousOnTime;
                          } else {
                            esp32Service.offTimes[relayIndex] = previousOffTime;
                          }
                          esp32Service.notifyListeners();
                        }
                      }
                    },
                    toggleRelay: (index, value) => _toggleRelay(esp32Service, index, value),
                    sendSettingsToESP: () => _sendSettingsToESP(
                        esp32Service.esp32IP ?? '',
                        esp32Service.onTimes,
                        esp32Service.offTimes),
                  )
                : const Setup(),
          ),
          bottomNavigationBar: NavBar(
            selectedIndex: _selectedIndex,
            onTap: _onNavBarTapped,
          ),
        );
      },
    );
  }
}