# OmniHome - Smart Home Control System

A Flutter-based smart home control application that interfaces with an ESP32 microcontroller to manage home appliances and lighting through relays.

## Features

- **Room Control**: Manage up to 6 different rooms/appliances
- **Voice Control**: Hands-free operation using voice commands
- **Scheduling**: Set automatic ON/OFF timers for each relay
- **Real-time Status**: Monitor device states in real-time
- **Intuitive UI**: Modern, user-friendly interface
- **WiFi Management**: Easy WiFi setup and configuration
- **Secure Communication**: Protected API endpoints

## Technical Stack

- **Frontend**: Flutter/Dart
- **Backend**: ESP32 (Arduino Framework)
- **Communication**: RESTful API
- **Storage**: ESP32 Preferences, Flutter SharedPreferences
- **Additional Features**: 
  - NTP Time Synchronization
  - Voice Recognition
  - WiFi Manager
  - I2C LCD Display

## Prerequisites

- Flutter SDK (2.5.0 or higher)
- Arduino IDE or PlatformIO
- ESP32 Development Board
- 6-Channel Relay Module
- 20x4 I2C LCD Display
- Push Buttons (x4)

## Getting Started

1. **Clone the Repository**
   ```bash
   git clone https://github.com/yourusername/omni_home.git
   cd omni_home
   ```

2. **Install Dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure ESP32**
   - Upload the ESP32 firmware using Arduino IDE or PlatformIO
   - Configure your WiFi credentials
   - Note the ESP32's IP address

4. **Hardware Setup**
   - Connect relays to ESP32 pins: 16, 17, 18, 19, 21, 22
   - Connect switches to pins: 23, 25, 26, 32
   - Connect I2C LCD: SDA to pin 21, SCL to pin 22

5. **Run the Application**
   ```bash
   flutter run
   ```

## Usage

1. **Initial Setup**
   - Launch the app
   - Connect to ESP32's WiFi network (ESP32_Relay)
   - Enter your network credentials

2. **Room Control**
   - Tap room cards to access detailed controls
   - Use switches to toggle power
   - Set schedules using the time picker

3. **Voice Control**
   - Tap the microphone button
   - Speak commands like "turn on living room"
   - Wait for confirmation feedback

## Project Structure

```
omni_home/
├── lib/
│   ├── main.dart
│   ├── services/
│   ├── views/
│   └── common/
├── esp32/
│   └── omnihome.ino
└── README.md
```

## API Endpoints

- `GET /` - Get system status
- `POST /toggle` - Toggle relay state
- `POST /set` - Update schedules
- `GET /reset` - Reset WiFi settings

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.


