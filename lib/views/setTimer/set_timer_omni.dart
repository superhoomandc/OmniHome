import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class SetTimeRelays extends StatefulWidget {
  final List<TimeOfDay> onTimes;
  final List<TimeOfDay> offTimes;
  final List<bool> relayStates;
  final Function(BuildContext, int, bool, {TimeOfDay? voiceSelectedTime}) selectTime;
  final Function(int, bool) toggleRelay;
  final Function() sendSettingsToESP;

  const SetTimeRelays({
    super.key,
    required this.onTimes,
    required this.offTimes,
    required this.relayStates,
    required this.selectTime,
    required this.toggleRelay,
    required this.sendSettingsToESP,
  });

  @override
  _SetTimeRelaysState createState() => _SetTimeRelaysState();
}

class _SetTimeRelaysState extends State<SetTimeRelays> with SingleTickerProviderStateMixin {
  late stt.SpeechToText _speech;
  bool _speechRecognitionAvailable = false;
  bool _isListening = false;
  String _transcription = '';
  String _statusMessage = 'Initializing speech recognition...';
  late AnimationController _animationController;
  late Animation<double> _micAnimation;

  final List<String> relayNames = [
    'Porch', //porch
    'Bathroom', //bathroom
    'Kitchen', //kitchen
    'Closet', //closet
    'Bedroom', //bedroom
    'Living Room' //living room
  ];

  final List<IconData> relayIcons = [
    Icons.door_front_door_outlined,        
    Icons.bathroom_outlined,       
    Icons.kitchen_outlined,          
    Icons.door_sliding_outlined,     
    Icons.bed_outlined, 
    Icons.living_outlined,  
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initializeSpeech();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _micAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  void _initializeSpeech() async {
    try {
      bool available = await _speech.initialize(
        onStatus: (status) {
          print('Speech status: $status');
          setState(() {
            _isListening = status == 'listening';
            _statusMessage = _isListening ? 'Listening...' : 'Tap to speak';
            if (_isListening) {
              _animationController.repeat(reverse: true);
            } else {
              _animationController.stop();
              _animationController.value = 1.0;
            }
          });
        },
        onError: (error) {
          print('Speech error: $error');
          setState(() {
            _isListening = false;
            _statusMessage = 'Speech error: ${error.errorMsg}';
            _animationController.stop();
            _animationController.value = 1.0;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speech recognition error: ${error.errorMsg}')),
          );
        },
        debugLogging: true,
      );

      setState(() {
        _speechRecognitionAvailable = available;
        _statusMessage = available ? 'Tap to speak' : 'Speech recognition unavailable';
      });

      if (!available) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to initialize speech recognition. Please check device settings.'),
          ),
        );
      }

      print('Speech recognition available: $available');
    } catch (e) {
      print('Error initializing speech recognition: $e');
      setState(() {
        _speechRecognitionAvailable = false;
        _statusMessage = 'Failed to initialize speech recognition';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initialize speech recognition: $e')),
      );
    }
  }

  void _showVoiceModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: Text(
                'Voice Command',
                style: GoogleFonts.roboto(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple[900],
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _micAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _isListening ? _micAnimation.value : 1.0,
                        child: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          size: 48,
                          color: _isListening ? Colors.red[600] : Colors.purple[600],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _statusMessage,
                    style: GoogleFonts.roboto(
                      fontSize: 16,
                      color: Colors.purple[700],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _transcription.isEmpty
                        ? 'Say "Turn on Relay 1" or "Set Relay 1 off time to 08:30"'
                        : _transcription,
                    style: GoogleFonts.roboto(
                      fontSize: 14,
                      color: _transcription.isEmpty ? Colors.grey[800] : Colors.grey[600],
                      fontStyle: _transcription.isEmpty ? FontStyle.italic : FontStyle.normal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (_isListening) {
                      _stopListening();
                    }
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(
                    _isListening ? 'Stop' : 'Close',
                    style: GoogleFonts.roboto(
                      fontSize: 16,
                      color: Colors.purple[600],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _speechRecognitionAvailable
                      ? () {
                          setModalState(() {
                            _transcription = '';
                            _statusMessage = 'Tap to speak';
                          });
                          _startListening(setModalState);
                        }
                      : null,
                  child: Text(
                    _isListening ? 'Listening...' : 'Speak',
                    style: GoogleFonts.roboto(
                      fontSize: 16,
                      color: _speechRecognitionAvailable ? Colors.purple[600] : Colors.grey,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      _stopListening();
      _animationController.stop();
      _animationController.value = 1.0;
      setState(() {
        _transcription = '';
        _statusMessage = _speechRecognitionAvailable ? 'Tap to speak' : 'Speech recognition unavailable';
      });
    });
  }

  void _startListening(StateSetter setModalState) async {
    if (!_speechRecognitionAvailable) {
      setState(() {
        _statusMessage = 'Speech recognition not available';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available')),
      );
      return;
    }

    if (_isListening) {
      print('Already listening');
      return;
    }

    var status = await Permission.microphone.request();
    if (status.isGranted) {
      try {
        setState(() {
          _isListening = true;
          _statusMessage = 'Listening...';
          _animationController.repeat(reverse: true);
        });
        await _speech.listen(
          onResult: (result) {
            print('Recognition result: ${result.recognizedWords}, final: ${result.finalResult}');
            setModalState(() {
              _transcription = result.recognizedWords;
            });
            if (result.finalResult) {
              setState(() {
                _isListening = false;
                _statusMessage = 'Processing command...';
                _animationController.stop();
                _animationController.value = 1.0;
                _processVoiceCommand(result.recognizedWords);
              });
            }
          },
          localeId: 'en_US',
          cancelOnError: true,
          partialResults: true,
        );
      } catch (e) {
        print('Error starting speech recognition: $e');
        setState(() {
          _isListening = false;
          _statusMessage = 'Error: $e';
          _animationController.stop();
          _animationController.value = 1.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start speech recognition: $e')),
        );
      }
    } else {
      setState(() {
        _isListening = false;
        _statusMessage = 'Microphone permission denied';
        _animationController.stop();
        _animationController.value = 1.0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied. Please enable in settings.')),
      );
      await openAppSettings();
    }
  }

  void _stopListening() async {
    if (_isListening) {
      try {
        await _speech.stop();
        setState(() {
          _isListening = false;
          _statusMessage = _speechRecognitionAvailable ? 'Tap to speak' : 'Speech recognition unavailable';
          _animationController.stop();
          _animationController.value = 1.0;
        });
      } catch (e) {
        print('Error stopping speech recognition: $e');
        setState(() {
          _isListening = false;
          _statusMessage = 'Error stopping: $e';
          _animationController.stop();
          _animationController.value = 1.0;
        });
      }
    }
  }

  void _processVoiceCommand(String command) {
    print('Processing command: $command');
    // Normalize command: convert to lowercase, handle common mis-transcriptions
    command = command.toLowerCase().trim();
    command = command
        .replaceAll('one', '1')
        .replaceAll('two', '2')
        .replaceAll('three', '3')
        .replaceAll('tree', '3') // Handle "three" mis-transcribed as "tree"
        .replaceAll('four', '4')
        .replaceAll('for', '4'); // Handle "four" mis-transcribed as "for"


    // Regex for scheduling command: "set relay X on/off time to HH:MM"
    final scheduleRegex = RegExp(
      r'set relay (\d+) (on|off) time to (\d{1,2})(\d{2})',
      caseSensitive: false,
    );
    final scheduleMatch = scheduleRegex.firstMatch(command);

    // Regex for toggle command: "turn on/off relay X"
    final toggleRegex = RegExp(
      r'turn (on|off) relay (\d+)',
      caseSensitive: false,
    );
    final toggleMatch = toggleRegex.firstMatch(command);

    if (toggleMatch != null) {
      final state = toggleMatch.group(1)! == 'on';
      final relayNumber = int.parse(toggleMatch.group(2)!) - 1;
      print('Toggle match: state=$state, relayNumber=$relayNumber');

      if (relayNumber >= 0 && relayNumber < widget.relayStates.length) {
        widget.toggleRelay(relayNumber, state);
        setState(() {
          _statusMessage = 'Command processed successfully';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Turned Relay ${relayNumber + 1} ${state ? "ON" : "OFF"}'),
          ),
        );
      } else {
        setState(() {
          _statusMessage = 'Invalid relay number';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid relay number')),
        );
      }
    } else if (scheduleMatch != null) {
      final relayNumber = int.parse(scheduleMatch.group(1)!) - 1;
      final isOnTime = scheduleMatch.group(2)! == 'on';
      final hour = int.parse(scheduleMatch.group(3)!);
      final minute = int.parse(scheduleMatch.group(4)!);
      print('Schedule match: relayNumber=$relayNumber, isOnTime=$isOnTime, time=$hour:$minute');

      if (relayNumber >= 0 &&
          relayNumber < widget.onTimes.length &&
          hour >= 0 &&
          hour <= 23 &&
          minute >= 0 &&
          minute <= 59) {
        final time = TimeOfDay(hour: hour, minute: minute);
        widget.selectTime(context, relayNumber, isOnTime, voiceSelectedTime: time);
        setState(() {
          _statusMessage = 'Command processed successfully';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Set Relay ${relayNumber + 1} ${isOnTime ? "ON" : "OFF"} time to ${_formatTime(time)}',
            ),
          ),
        );
      } else {
        setState(() {
          _statusMessage = 'Invalid relay number or time';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid relay number or time')),
        );
      }
    } else {
      setState(() {
        _statusMessage = 'Could not understand the command';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Heard: $command')),
      );
      print('No regex match for command: $command');
    }
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Widget _buildRelayControl(int index, BuildContext context) {
    return Card(
      elevation: 4,
      shadowColor: Colors.purple.withOpacity(0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.purple.shade100, width: 1),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white,
              Colors.purple.shade50.withOpacity(0.5),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Room Header with Icon
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      relayIcons[index],
                      size: 22,
                      color: Colors.purple[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        relayNames[index],
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple[900],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Timer Controls
              Column(
                children: [
                  _buildTimeSelector(
                    'ON',
                    widget.onTimes[index],
                    () => widget.selectTime(context, index, true),
                    Colors.green.shade100,
                    Icons.alarm_on_rounded,
                  ),
                  const SizedBox(height: 8),
                  _buildTimeSelector(
                    'OFF',
                    widget.offTimes[index],
                    () => widget.selectTime(context, index, false),
                    Colors.red.shade100,
                    Icons.alarm_off_rounded,
                  ),
                ],
              ),

              // State Switch
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: widget.relayStates[index] 
                      ? Colors.purple.shade100 
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.relayStates[index] ? 'ON' : 'OFF',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: widget.relayStates[index] 
                            ? Colors.purple[800] 
                            : Colors.grey[700],
                      ),
                    ),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: widget.relayStates[index],
                        onChanged: (value) => widget.toggleRelay(index, value),
                        activeColor: Colors.purple[600],
                        inactiveThumbColor: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeSelector(
    String label, 
    TimeOfDay time, 
    VoidCallback onTap, 
    Color backgroundColor,
    IconData icon,
  ) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: Colors.purple[700]),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.purple[800],
                    ),
                  ),
                ],
              ),
              Text(
                _formatTime(time),
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.purple[900],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomCard(int index, BuildContext context) {
    return InkWell(
      onTap: () => _showRoomControlDialog(context, index),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            if (widget.relayStates[index])
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [
                      Colors.purple.shade50,
                      Colors.purple.shade100.withOpacity(0.5),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icon container
                    Container(
                      padding: const EdgeInsets.all(12), // Increased padding
                      decoration: BoxDecoration(
                        color: widget.relayStates[index] 
                            ? Colors.purple.shade100 
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        relayIcons[index],
                        size: 32, // Increased from 20
                        color: widget.relayStates[index] 
                            ? Colors.purple[700] 
                            : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Room name
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        relayNames[index],
                        style: GoogleFonts.poppins(
                          fontSize: 16, // Increased from 14
                          fontWeight: FontWeight.w600,
                          color: widget.relayStates[index] 
                              ? Colors.purple[900] 
                              : Colors.grey[800],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    
                    const SizedBox(height: 8), // Increased from 4
                    
                    // Status indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16, // Increased from 12
                        vertical: 8,   // Increased from 6
                      ),
                      decoration: BoxDecoration(
                        color: widget.relayStates[index]
                            ? Colors.purple.shade50
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: widget.relayStates[index]
                              ? Colors.purple.shade200
                              : Colors.grey.shade300,
                          width: 1, // Increased from 0.5
                        ),
                      ),
                      child: Text(
                        widget.relayStates[index] ? 'ON' : 'OFF',
                        style: GoogleFonts.poppins(
                          fontSize: 14, // Increased from 12
                          fontWeight: FontWeight.w500,
                          color: widget.relayStates[index]
                              ? Colors.purple[700]
                              : Colors.grey[600],
                        ),
                      ),
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

  void _showRoomControlDialog(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Room Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: widget.relayStates[index]
                            ? Colors.purple.shade100
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        relayIcons[index],
                        size: 28,
                        color: widget.relayStates[index]
                            ? Colors.purple[700]
                            : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            relayNames[index],
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple[900],
                            ),
                          ),
                          Text(
                            'Control settings',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: Colors.grey[400]),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Power Control
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: widget.relayStates[index]
                        ? Colors.purple.shade50
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: widget.relayStates[index]
                          ? Colors.purple.shade200
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Power',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.purple[900],
                            ),
                          ),
                          Transform.scale(
                            scale: 1.2,
                            child: Switch(
                              value: widget.relayStates[index],
                              onChanged: (value) {
                                widget.toggleRelay(index, value);
                                Navigator.pop(context);
                              },
                              activeColor: Colors.purple[600],
                              inactiveThumbColor: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.relayStates[index] ? 'Device is ON' : 'Device is OFF',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Timer Settings
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Schedule',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple[900],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildTimeSelector(
                        'Turn ON at',
                        widget.onTimes[index],
                        () {
                          widget.selectTime(context, index, true);
                          Navigator.pop(context);
                        },
                        Colors.green.shade100,
                        Icons.alarm_on_rounded,
                      ),
                      const SizedBox(height: 12),
                      _buildTimeSelector(
                        'Turn OFF at',
                        widget.offTimes[index],
                        () {
                          widget.selectTime(context, index, false);
                          Navigator.pop(context);
                        },
                        Colors.red.shade100,
                        Icons.alarm_off_rounded,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Stack(  // Wrap with Stack
        children: [
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Home',
                          style: GoogleFonts.poppins(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple[900],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Control your rooms',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12, // Reduced from 16
                      crossAxisSpacing: 12, // Reduced from 16
                      childAspectRatio: 0.95, // Increased from 0.85 to make cards more square
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildRoomCard(index, context),
                      childCount: 6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Voice control button positioned at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: FloatingActionButton.extended(
                  elevation: 0,
                  backgroundColor: Colors.purple[600],
                  onPressed: _speechRecognitionAvailable
                      ? () {
                          _showVoiceModal(context);
                          Future.delayed(const Duration(milliseconds: 300), () {
                            _startListening((_) {});
                          });
                        }
                      : null,
                  icon: const Icon(Icons.mic, color: Colors.white),
                  label: Text(
                    'Voice Control',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
