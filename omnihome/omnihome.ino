#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include <LiquidCrystal_I2C.h>
#include <NTPClient.h>
#include <WiFiUdp.h>
#include <ArduinoJson.h>
#include <ESP.h>

// Define relay pins (active LOW)
#define RELAY1_PIN 16
#define RELAY2_PIN 17
#define RELAY3_PIN 18
#define RELAY4_PIN 19
#define RELAY5_PIN 14
#define RELAY6_PIN 15

// Define switch pins (active-high)
#define SWITCH1_PIN 23
#define SWITCH2_PIN 25
#define SWITCH3_PIN 26
#define SWITCH4_PIN 32

// Arrays for easier management
const int switchPins[] = {SWITCH1_PIN, SWITCH2_PIN, SWITCH3_PIN, SWITCH4_PIN};
const int relayPins[] = {RELAY1_PIN, RELAY2_PIN, RELAY3_PIN, RELAY4_PIN, RELAY5_PIN, RELAY6_PIN};
const int numSwitches = 4;
const int numRelays = 6;

// Debounce and timing settings
const unsigned long DEBOUNCE_DELAY = 100;
const unsigned long EXIT_DURATION = 3000;
const unsigned long CURSOR_BLINK_INTERVAL = 500;
const unsigned long BLINK_INTERVAL = 1000;
const unsigned long TIMER_UPDATE_INTERVAL = 1000;
const unsigned long LCD_UPDATE_INTERVAL = 1000;
const unsigned long DISPLAY_SWITCH_INTERVAL = 3000;
const unsigned long STARTUP_AP_DISPLAY_DURATION = 2000;
const unsigned long NO_NETWORK_MESSAGE_DURATION = 3000;

// Initialize I2C LCD (16x4)
LiquidCrystal_I2C lcd(0x27, 16, 4);

// Initialize NTP client (UTC+8 for Philippines)
WiFiUDP ntpUDP;
NTPClient timeClient(ntpUDP, "ntp.pagasa.dost.gov.ph", 28800, 60000);

// Preferences and WebServer
Preferences preferences;
WebServer server(80);

// WiFi settings
const char* apSSID = "ESP32_Relay";
const char* apPassword = "12345678";
bool isClientConnected = false;
String serialInput = "";

// Debounce and state variables for switches
unsigned long lastDebounceTime[numSwitches] = {0, 0, 0, 0};
int lastButtonState[numSwitches] = {LOW, LOW, LOW, LOW};
int buttonState[numSwitches] = {LOW, LOW, LOW, LOW};
bool relayState[numRelays] = {false, false, false, false, false, false};

// Mode selection and exit tracking
unsigned long switch2PressStartTime = 0;
bool isExiting = false;
bool inMenu = true;
int cursorPosition = 0;
int menuOffset = 0; // Tracks the first visible mode
unsigned long lastCursorBlinkTime = 0;
bool cursorState = true;

// Test bulb mode variables
int selectedRelay = 0; // 0-based index for selected relay in TEST_BULB mode (0 to 5)

// Timer mode variables
enum TimerState { TIMER_SETUP, TIMER_RUNNING, TIMER_PAUSED, TIMER_BLINKING };
TimerState timerState = TIMER_SETUP;
int timerField = 0;
int timerValues[3] = {0, 0, 0};
unsigned long timerStartTime = 0;
unsigned long lastTimerUpdate = 0;
unsigned long lastBlinkTime = 0;
bool relaysBlinkingOn = false;

// Scheduling mode variables
bool schedulingMode = false;
int selectedScheduleRelay = 0; // 0 = none, 1-6 = Relay 1-6 for scheduling
int selectedParam = 0; // 0 = onHour, 1 = onMinute, 2 = offHour, 3 = offMinute
int tempOnHour[numRelays], tempOnMinute[numRelays], tempOffHour[numRelays], tempOffMinute[numRelays];
int onHour1, onMinute1, offHour1, offMinute1;
int onHour2, onMinute2, offHour2, offMinute2;
int onHour3, onMinute3, offHour3, offMinute3;
int onHour4, onMinute4, offHour4, offMinute4;
int onHour5, onMinute5, offHour5, offMinute5;
int onHour6, onMinute6, offHour6, offMinute6;

// Startup state
enum StartupState { SHOW_AP, SHOW_MENU };
StartupState startupState = SHOW_AP;
unsigned long startupStartTime = 0;

// No network message state
bool showingNoNetworkMessage = false;
unsigned long noNetworkMessageStartTime = 0;

// Mode enumeration
enum Mode { SCHEDULING, TEST_BULB, RESET_ESP, TIMER, SHOW_IP };
Mode currentMode = SCHEDULING;
int numModes = 4; // Default without SHOW_IP

void setup() {
  Serial.begin(115200);
  Wire.begin();

  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Initializing...");

  // Initialize relays (active LOW)
  for (int i = 0; i < numRelays; i++) {
    pinMode(relayPins[i], OUTPUT);
    digitalWrite(relayPins[i], HIGH);
    relayState[i] = false;
  }

  // Initialize switches (active-high, external pull-down)
  for (int i = 0; i < numSwitches; i++) {
    pinMode(switchPins[i], INPUT);
  }

  // Try to connect with saved credentials
  preferences.begin("wifi", true);
  String savedSsid = preferences.getString("ssid", "");
  String savedPassword = preferences.getString("password", "");
  preferences.end();

  if (savedSsid.length() > 0) {
    Serial.println("Connecting to WiFi: " + savedSsid);
    WiFi.mode(WIFI_STA);
    WiFi.begin(savedSsid.c_str(), savedPassword.c_str());
    int attempts = 0;
    const int maxAttempts = 20;
    while (WiFi.status() != WL_CONNECTED && attempts < maxAttempts) {
      delay(500);
      Serial.print(".");
      attempts++;
    }
    Serial.println();
    if (WiFi.status() == WL_CONNECTED) {
      String ip = WiFi.localIP().toString();
      Serial.println("WiFi connected, IP: " + ip);
      numModes = 5; // Include SHOW_IP mode
    } else {
      Serial.println("Failed to connect, starting AP");
      WiFi.disconnect();
      WiFi.mode(WIFI_AP);
      WiFi.softAP(apSSID, apPassword);
      Serial.println("AP mode, IP: 192.168.4.1");
    }
  } else {
    Serial.println("No WiFi creds, starting AP");
    WiFi.mode(WIFI_AP);
    WiFi.softAP(apSSID, apPassword);
    Serial.println("AP mode, IP: 192.168.4.1");
  }

  // Initialize NTP client
  timeClient.begin();

  // Load saved schedules
  preferences.begin("relay_settings", true);
  onHour1 = preferences.getUInt("R1_onHour", 8);
  onMinute1 = preferences.getUInt("R1_onMinute", 0);
  offHour1 = preferences.getUInt("R1_offHour", 18);
  offMinute1 = preferences.getUInt("R1_offMinute", 0);
  onHour2 = preferences.getUInt("R2_onHour", 9);
  onMinute2 = preferences.getUInt("R2_onMinute", 0);
  offHour2 = preferences.getUInt("R2_offHour", 19);
  offMinute2 = preferences.getUInt("R2_offMinute", 0);
  onHour3 = preferences.getUInt("R3_onHour", 10);
  onMinute3 = preferences.getUInt("R3_onMinute", 0);
  offHour3 = preferences.getUInt("R3_offHour", 20);
  offMinute3 = preferences.getUInt("R3_offMinute", 0);
  onHour4 = preferences.getUInt("R4_onHour", 11);
  onMinute4 = preferences.getUInt("R4_onMinute", 0);
  offHour4 = preferences.getUInt("R4_offHour", 21);
  offMinute4 = preferences.getUInt("R4_offMinute", 0);
  onHour5 = preferences.getUInt("R5_onHour", 12);
  onMinute5 = preferences.getUInt("R5_onMinute", 0);
  offHour5 = preferences.getUInt("R5_offHour", 20);
  offMinute5 = preferences.getUInt("R5_offMinute", 0);
  onHour6 = preferences.getUInt("R6_onHour", 13);
  onMinute6 = preferences.getUInt("R6_onMinute", 0);
  offHour6 = preferences.getUInt("R6_offHour", 21);
  offMinute6 = preferences.getUInt("R6_offMinute", 0);
  preferences.end();

  // Setup web server
  server.on("/", handleRoot);
  server.on("/setWiFi", HTTP_POST, handleSetWiFi);
  server.on("/setWiFi", HTTP_OPTIONS, handleOptions);
  server.on("/disconnect", HTTP_POST, handleDisconnect);
  server.on("/set", HTTP_POST, handleSet);
  server.on("/setSingle", HTTP_POST, handleSetSingle);
  server.on("/reset", HTTP_POST, handleReset);
  server.on("/toggle", HTTP_POST, handleToggle);
  server.on("/getStatus", HTTP_GET, handleGetStatus);
  server.on("/set", HTTP_OPTIONS, handleOptions);
  server.on("/setSingle", HTTP_OPTIONS, handleOptions);
  server.on("/toggle", HTTP_OPTIONS, handleOptions);
  server.on("/getStatus", HTTP_OPTIONS, handleOptions);
  server.begin();
  Serial.println("HTTP server started");

  startupStartTime = millis();
  updateLCD();
}

void loop() {
  // Handle serial input for CLEAR_WIFI
  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      serialInput.trim();
      if (serialInput.equalsIgnoreCase("CLEAR_WIFI")) {
        Serial.println("Clearing WiFi, restarting");
        preferences.begin("wifi", false);
        preferences.clear();
        preferences.end();
        preferences.begin("relay_settings", false);
        preferences.clear();
        preferences.end();
        WiFi.disconnect();
        delay(500);
        WiFi.mode(WIFI_AP);
        WiFi.softAP(apSSID, apPassword);
        isClientConnected = false;
        Serial.println("AP mode, restarting...");
        delay(1000);
        ESP.restart();
      }
      serialInput = "";
    } else {
      serialInput += c;
    }
  }

  // Handle switches
  for (int i = 0; i < numSwitches; i++) {
    handleSwitch(i);
  }

  // Handle web server
  server.handleClient();

  // Update NTP and relay states if WiFi is connected
  static unsigned long lastNTPUpdate = 0;
  if (WiFi.status() == WL_CONNECTED && millis() - lastNTPUpdate >= 1000) {
    timeClient.update();
    lastNTPUpdate = millis();
    if (currentMode == SCHEDULING && !inMenu && !schedulingMode) {
      int currentHour = timeClient.getHours();
      int currentMinute = timeClient.getMinutes();
      updateRelayState(currentHour, currentMinute);
    }
  }

  // Handle startup transition
  if (startupState == SHOW_AP && millis() - startupStartTime >= STARTUP_AP_DISPLAY_DURATION) {
    startupState = SHOW_MENU;
    inMenu = true;
    updateLCD();
  }

  // Handle no network message timeout
  if (showingNoNetworkMessage && millis() - noNetworkMessageStartTime >= NO_NETWORK_MESSAGE_DURATION) {
    showingNoNetworkMessage = false;
    inMenu = true;
    updateLCD();
  }

  // Handle timer countdown and blinking
  handleTimer();

  // Update blinking cursor
  if ((inMenu || (currentMode == TIMER && timerState == TIMER_SETUP) || 
       (currentMode == SCHEDULING && schedulingMode)) && 
      millis() - lastCursorBlinkTime >= CURSOR_BLINK_INTERVAL) {
    cursorState = !cursorState;
    lastCursorBlinkTime = millis();
    updateLCD();
  }

  // Force LCD update for real-time clock in scheduling mode
  if (currentMode == SCHEDULING && !inMenu && !schedulingMode) {
    updateLCD();
  }
}

void handleSwitch(int index) {
  int reading = digitalRead(switchPins[index]);

  if (reading != lastButtonState[index]) {
    lastDebounceTime[index] = millis();
  }

  if ((millis() - lastDebounceTime[index]) > DEBOUNCE_DELAY) {
    if (reading != buttonState[index]) {
      buttonState[index] = reading;
      if (buttonState[index] == HIGH) {
        if (startupState == SHOW_AP || showingNoNetworkMessage) {
          return; // Ignore switches during AP display or no network message
        }
        if (inMenu) {
          if (index == 2) { // Switch 3 (Up)
            if (cursorPosition > 0) {
              cursorPosition--;
              if (cursorPosition < menuOffset) {
                menuOffset--;
              }
            } else {
              cursorPosition = numModes - 1;
              menuOffset = max(0, numModes - 3);
            }
            Serial.printf("S3: Cursor to Mode %d: %s, offset: %d\n", 
                          cursorPosition + 1, modeToString(cursorPosition), menuOffset);
            updateLCD();
          } else if (index == 3) { // Switch 4 (Down)
            if (cursorPosition < numModes - 1) {
              cursorPosition++;
              if (cursorPosition > menuOffset + 2) {
                menuOffset++;
              }
            } else {
              cursorPosition = 0;
              menuOffset = 0;
            }
            Serial.printf("S4: Cursor to Mode %d: %s, offset: %d\n", 
                          cursorPosition + 1, modeToString(cursorPosition), menuOffset);
            updateLCD();
          } else if (index == 0) { // Switch 1 (Select)
            currentMode = (Mode)cursorPosition;
            if (currentMode == SCHEDULING && WiFi.status() != WL_CONNECTED) {
              showingNoNetworkMessage = true;
              noNetworkMessageStartTime = millis();
              Serial.println("SCHEDULING selected, no network");
              updateLCD();
              return;
            }
            inMenu = false;
            for (int i = 0; i < numRelays; i++) {
              if (currentMode != SCHEDULING) {
                digitalWrite(relayPins[i], HIGH);
                relayState[i] = false;
              }
            }
            if (currentMode == TIMER) {
              timerState = TIMER_SETUP;
              timerField = 0;
              timerValues[0] = 0;
              timerValues[1] = 0;
              timerValues[2] = 0;
            } else if (currentMode == SCHEDULING) {
              schedulingMode = false;
              selectedScheduleRelay = 0;
            } else if (currentMode == TEST_BULB) {
              selectedRelay = 0;
            }
            Serial.printf("S1: Selected Mode %d: %s\n", 
                          currentMode + 1, modeToString(currentMode));
            updateLCD();
          }
        } else if (currentMode == TEST_BULB) {
          if (index == 0) { // Switch 1 (Toggle selected relay)
            relayState[selectedRelay] = !relayState[selectedRelay];
            digitalWrite(relayPins[selectedRelay], relayState[selectedRelay] ? LOW : HIGH);
            Serial.printf("S1: Relay %d to %s\n", 
                          selectedRelay + 1, relayState[selectedRelay] ? "ON" : "OFF");
            updateLCD();
          } else if (index == 2) { // Switch 3 (Next relay)
            selectedRelay = (selectedRelay + 1) % numRelays;
            Serial.printf("S3: Selected Relay %d\n", selectedRelay + 1);
            updateLCD();
          } else if (index == 3) { // Switch 4 (Previous relay)
            selectedRelay = (selectedRelay - 1 + numRelays) % numRelays;
            Serial.printf("S4: Selected Relay %d\n", selectedRelay + 1);
            updateLCD();
          }
        } else if (currentMode == RESET_ESP) {
          if (index == 2) {
            Serial.println("S3: Cancel reset, back to menu");
            inMenu = true;
            updateLCD();
          } else if (index == 3) {
            Serial.println("S4: Resetting ESP...");
            preferences.begin("wifi", false);
            preferences.clear();
            preferences.end();
            preferences.begin("relay_settings", false);
            preferences.clear();
            preferences.end();
            delay(100);
            ESP.restart();
          }
        } else if (currentMode == TIMER) {
          if (timerState == TIMER_SETUP) {
            if (index == 2) {
              if (timerField == 0) {
                timerValues[0] = (timerValues[0] + 1) % 24;
              } else if (timerField == 1) {
                timerValues[1] = (timerValues[1] + 1) % 60;
              } else if (timerField == 2) {
                timerValues[2] = (timerValues[2] + 1) % 60;
              }
              Serial.printf("S3: %s set to %d\n", 
                            timerField == 0 ? "Hours" : timerField == 1 ? "Minutes" : "Seconds", 
                            timerValues[timerField]);
              updateLCD();
            } else if (index == 3) {
              if (timerField == 0) {
                timerValues[0] = (timerValues[0] == 0) ? 23 : timerValues[0] - 1;
              } else if (timerField == 1) {
                timerValues[1] = (timerValues[1] == 0) ? 59 : timerValues[1] - 1;
              } else if (timerField == 2) {
                timerValues[2] = (timerValues[2] == 0) ? 59 : timerValues[2] - 1;
              }
              Serial.printf("S4: %s set to %d\n", 
                            timerField == 0 ? "Hours" : timerField == 1 ? "Minutes" : "Seconds", 
                            timerValues[timerField]);
              updateLCD();
            } else if (index == 0) {
              timerField++;
              if (timerField > 2) {
                if (timerValues[0] == 0 && timerValues[1] == 0 && timerValues[2] == 0) {
                  timerField = 0;
                  Serial.println("Invalid timer (00:00:00)");
                } else {
                  timerState = TIMER_RUNNING;
                  timerStartTime = millis();
                  lastTimerUpdate = millis();
                  Serial.printf("S1: Timer started: %02d:%02d:%02d\n", 
                                timerValues[0], timerValues[1], timerValues[2]);
                }
              }
              updateLCD();
            }
          } else if (timerState == TIMER_RUNNING || timerState == TIMER_PAUSED) {
            if (index == 0) {
              timerState = (timerState == TIMER_RUNNING) ? TIMER_PAUSED : TIMER_RUNNING;
              Serial.printf("S1: Timer %s\n", 
                            timerState == TIMER_PAUSED ? "paused" : "resumed");
              updateLCD();
            }
          } else if (timerState == TIMER_BLINKING && index == 0) {
            for (int i = 0; i < numRelays; i++) {
              digitalWrite(relayPins[i], HIGH);
              relayState[i] = false;
            }
            timerState = TIMER_SETUP;
            timerField = 0;
            timerValues[0] = 0;
            timerValues[1] = 0;
            timerValues[2] = 0;
            Serial.println("S1: Stopped blinking, back to setup");
            updateLCD();
          }
        } else if (currentMode == SCHEDULING) {
          if (index == 0) {
            if (!schedulingMode) {
              schedulingMode = true;
              selectedScheduleRelay = 1;
              selectedParam = 0;
              tempOnHour[0] = onHour1; tempOnMinute[0] = onMinute1;
              tempOffHour[0] = offHour1; tempOffMinute[0] = offMinute1;
              tempOnHour[1] = onHour2; tempOnMinute[1] = onMinute2;
              tempOffHour[1] = offHour2; tempOffMinute[1] = offMinute2;
              tempOnHour[2] = onHour3; tempOnMinute[2] = onMinute3;
              tempOffHour[2] = offHour3; tempOffMinute[2] = offMinute3;
              tempOnHour[3] = onHour4; tempOnMinute[3] = onMinute4;
              tempOffHour[3] = offHour4; tempOffMinute[3] = offMinute4;
              tempOnHour[4] = onHour5; tempOnMinute[4] = onMinute5;
              tempOffHour[4] = offHour5; tempOffMinute[4] = offMinute5;
              tempOnHour[5] = onHour6; tempOnMinute[5] = onMinute6;
              tempOffHour[5] = offHour6; tempOffMinute[5] = offMinute6;
              Serial.println("Entered scheduling, Relay 1");
            } else {
              selectedScheduleRelay++;
              if (selectedScheduleRelay > numRelays) {
                schedulingMode = false;
                selectedScheduleRelay = 0;
                onHour1 = tempOnHour[0]; onMinute1 = tempOnMinute[0];
                offHour1 = tempOffHour[0]; offMinute1 = tempOffMinute[0];
                onHour2 = tempOnHour[1]; onMinute2 = tempOnMinute[1];
                offHour2 = tempOffHour[1]; offMinute2 = tempOffMinute[1];
                onHour3 = tempOnHour[2]; onMinute3 = tempOnMinute[2];
                offHour3 = tempOffHour[2]; offMinute3 = tempOffMinute[2];
                onHour4 = tempOnHour[3]; onMinute4 = tempOnMinute[3];
                offHour4 = tempOffHour[3]; offMinute4 = tempOffMinute[3];
                onHour5 = tempOnHour[4]; onMinute5 = tempOnMinute[4];
                offHour5 = tempOffHour[4]; offMinute5 = tempOffMinute[4];
                onHour6 = tempOnHour[5]; onMinute6 = tempOnMinute[5];
                offHour6 = tempOffHour[5]; offMinute6 = tempOffMinute[5];
                saveSchedule();
                Serial.println("Exiting scheduling, saved");
              } else {
                selectedParam = 0;
                Serial.printf("Selected Relay %d\n", selectedScheduleRelay);
              }
            }
            updateLCD();
          } else if (schedulingMode) {
            if (index == 1) {
              selectedParam = (selectedParam + 1) % 4;
              Serial.printf("Selected: %s\n", 
                            selectedParam == 0 ? "onHour" : 
                            selectedParam == 1 ? "onMinute" : 
                            selectedParam == 2 ? "offHour" : "offMinute");
              updateLCD();
            } else if (index == 2) {
              int relayIndex = selectedScheduleRelay - 1;
              if (selectedParam == 0) {
                tempOnHour[relayIndex] = (tempOnHour[relayIndex] + 1) % 24;
              } else if (selectedParam == 1) {
                tempOnMinute[relayIndex] = (tempOnMinute[relayIndex] + 1) % 60;
              } else if (selectedParam == 2) {
                tempOffHour[relayIndex] = (tempOffHour[relayIndex] + 1) % 24;
              } else if (selectedParam == 3) {
                tempOffMinute[relayIndex] = (tempOffMinute[relayIndex] + 1) % 60;
              }
              Serial.printf("S3: Relay %d %s to %d\n", 
                            selectedScheduleRelay, 
                            selectedParam == 0 ? "onHour" : 
                            selectedParam == 1 ? "onMinute" : 
                            selectedParam == 2 ? "offHour" : "offMinute",
                            selectedParam == 0 ? tempOnHour[relayIndex] :
                            selectedParam == 1 ? tempOnMinute[relayIndex] :
                            selectedParam == 2 ? tempOffHour[relayIndex] : tempOffMinute[relayIndex]);
              updateLCD();
            } else if (index == 3) {
              int relayIndex = selectedScheduleRelay - 1;
              if (selectedParam == 0) {
                tempOnHour[relayIndex] = (tempOnHour[relayIndex] - 1 + 24) % 24;
              } else if (selectedParam == 1) {
                tempOnMinute[relayIndex] = (tempOnMinute[relayIndex] - 1 + 60) % 60;
              } else if (selectedParam == 2) {
                tempOffHour[relayIndex] = (tempOffHour[relayIndex] - 1 + 24) % 24;
              } else if (selectedParam == 3) {
                tempOffMinute[relayIndex] = (tempOffMinute[relayIndex] - 1 + 60) % 60;
              }
              Serial.printf("S4: Relay %d %s to %d\n", 
                            selectedScheduleRelay, 
                            selectedParam == 0 ? "onHour" : 
                            selectedParam == 1 ? "onMinute" : 
                            selectedParam == 2 ? "offHour" : "offMinute",
                            selectedParam == 0 ? tempOnHour[relayIndex] :
                            selectedParam == 1 ? tempOnMinute[relayIndex] :
                            selectedParam == 2 ? tempOffHour[relayIndex] : tempOffMinute[relayIndex]);
              updateLCD();
            }
          }
        } else if (currentMode == SHOW_IP) {
          // No actions needed, just display IP
        }
      }
    }
  }

  // Handle Switch 2 long press for exit
  if (index == 1 && !inMenu && !showingNoNetworkMessage && startupState != SHOW_AP) {
    if (buttonState[index] == HIGH) {
      if (!isExiting) {
        switch2PressStartTime = millis();
        isExiting = true;
      }
      unsigned long holdTime = millis() - switch2PressStartTime;
      if (holdTime >= EXIT_DURATION) {
        for (int i = 0; i < numRelays; i++) {
          if (currentMode != SCHEDULING) {
            digitalWrite(relayPins[i], HIGH);
            relayState[i] = false;
          }
        }
        inMenu = true;
        isExiting = false;
        if (currentMode == TIMER) {
          timerState = TIMER_SETUP;
          timerField = 0;
          timerValues[0] = 0;
          timerValues[1] = 0;
          timerValues[2] = 0;
        } else if (currentMode == SCHEDULING) {
          schedulingMode = false;
          selectedScheduleRelay = 0;
          selectedParam = 0;
        } else if (currentMode == TEST_BULB) {
          selectedRelay = 0;
        }
        Serial.println("S2 held 3s, back to menu");
        updateLCD();
      }
    } else if (isExiting) {
      isExiting = false;
    }
  }

  lastButtonState[index] = reading;
}

void updateLCD() {
  lcd.clear();

  if (startupState == SHOW_AP) {
    displayAPMode();
    return;
  }

  if (showingNoNetworkMessage) {
    lcd.setCursor(0, 0);
    lcd.print("No Network!");
    lcd.setCursor(0, 1);
    lcd.print("Sched Disabled");
    lcd.setCursor(0, 2);
    lcd.print("Wait...");
    return;
  }

  if (inMenu) {
    lcd.setCursor(0, 0);
    lcd.print("Select Mode:");
    for (int i = 0; i < 3; i++) { // Show 3 modes max
      int modeIndex = menuOffset + i;
      if (modeIndex < numModes) {
        lcd.setCursor(1, i + 1);
        String modeStr = modeToString(modeIndex);
        if (modeStr.length() > 13) modeStr = modeStr.substring(0, 13);
        lcd.print(modeStr);
        if (modeIndex == cursorPosition) {
          lcd.setCursor(15, i + 1);
          lcd.print(cursorState ? ">" : " ");
        }
      }
    }
    return;
  }

  // --- SCHEDULING MODE ---
  if (currentMode == SCHEDULING) {
    if (schedulingMode) {
      int relayIndex = selectedScheduleRelay - 1;
      String paramStr = selectedParam == 0 ? "ON H" :
                        selectedParam == 1 ? "ON M" :
                        selectedParam == 2 ? "OFF H" : "OFF M";
      int value = selectedParam == 0 ? tempOnHour[relayIndex] :
                  selectedParam == 1 ? tempOnMinute[relayIndex] :
                  selectedParam == 2 ? tempOffHour[relayIndex] : tempOffMinute[relayIndex];
      String valueStr = (selectedParam % 2 == 0) ? String(value) :
                        (value < 10 ? "0" + String(value) : String(value));
      lcd.setCursor(0, 0);
      lcd.printf("R%d %s", selectedScheduleRelay, paramStr.c_str());
      lcd.setCursor(0, 1);
      lcd.printf("Val:%s %s", valueStr.c_str(), cursorState ? "<" : " ");
      lcd.setCursor(0, 2);
      lcd.print("S1:Nxt S2:Par");
      lcd.setCursor(0, 3);
      lcd.print("S3:+   S4:-");
    } else {
      int currentHour = timeClient.getHours();
      int currentMinute = timeClient.getMinutes();
      int currentSecond = timeClient.getSeconds();
      String timeStr = formatTime(currentHour, currentMinute) + ":" +
                       (currentSecond < 10 ? "0" + String(currentSecond) : String(currentSecond));
      lcd.setCursor(0, 0);
      lcd.printf("T:%s", timeStr.c_str());

      // Show 1 relay at a time, scroll with time
      static int scrollOffset = 0;
      static unsigned long lastSwitchTime = 0;
      unsigned long now = millis();
      if (now - lastSwitchTime >= DISPLAY_SWITCH_INTERVAL) {
        scrollOffset = (scrollOffset + 1) % numRelays;
        lastSwitchTime = now;
      }

      String relayStrings[] = {
        String("R1:") + (relayState[0] ? "ON " : "OFF") + formatTime(onHour1, onMinute1),
        String("R2:") + (relayState[1] ? "ON " : "OFF") + formatTime(onHour2, onMinute2),
        String("R3:") + (relayState[2] ? "ON " : "OFF") + formatTime(onHour3, onMinute3),
        String("R4:") + (relayState[3] ? "ON " : "OFF") + formatTime(onHour4, onMinute4),
        String("R5:") + (relayState[4] ? "ON " : "OFF") + formatTime(onHour5, onMinute5),
        String("R6:") + (relayState[5] ? "ON " : "OFF") + formatTime(onHour6, onMinute6)
      };
      int relayIndex = scrollOffset;
      lcd.setCursor(0, 1);
      String line = relayStrings[relayIndex];
      if (line.length() > 16) line = line.substring(0, 16);
      lcd.print(line);
      lcd.setCursor(0, 2);
      lcd.printf("Relay %d/6", relayIndex + 1);
      lcd.setCursor(0, 3);
      lcd.print("S1:Edit S2:Exit");
    }
    return;
  }

  // --- TEST BULB MODE ---
  if (currentMode == TEST_BULB) {
    lcd.setCursor(0, 0);
    lcd.printf("R%d:%s", selectedRelay + 1, relayState[selectedRelay] ? "ON" : "OFF");
    lcd.setCursor(0, 1);
    lcd.printf("R1:%s R2:%s", relayState[0] ? "ON" : "O", relayState[1] ? "ON" : "O");
    lcd.setCursor(0, 2);
    lcd.printf("R3:%s R4:%s", relayState[2] ? "ON" : "O", relayState[3] ? "ON" : "O");
    lcd.setCursor(0, 3);
    lcd.printf("R5:%s R6:%s", relayState[4] ? "ON" : "O", relayState[5] ? "ON" : "O");
    // Controls: S1:Toggle, S3/S4:Select
    return;
  }

  // --- RESET ESP MODE ---
  if (currentMode == RESET_ESP) {
    lcd.setCursor(0, 0);
    lcd.print("Reset ESP?");
    lcd.setCursor(0, 1);
    lcd.print("S4:Confirm");
    lcd.setCursor(0, 2);
    lcd.print("S3:Cancel");
    return;
  }

  // --- TIMER MODE ---
  if (currentMode == TIMER) {
    if (timerState == TIMER_SETUP) {
      lcd.setCursor(0, 0);
      lcd.print("Set Timer:");
      lcd.setCursor(0, 1);
      lcd.printf("%02d:%02d:%02d", timerValues[0], timerValues[1], timerValues[2]);
      lcd.setCursor(0, 2);
      lcd.print("S1:Nxt S3:+ S4:-");
      lcd.setCursor(0, 3);
      int cursorCol = (timerField == 0) ? 0 : (timerField == 1) ? 3 : 6;
      lcd.setCursor(cursorCol, 3);
      lcd.print(cursorState ? "^" : " ");
    } else if (timerState == TIMER_RUNNING || timerState == TIMER_PAUSED) {
      unsigned long remainingTime = calculateRemainingTime();
      int hours = remainingTime / 3600;
      int minutes = (remainingTime % 3600) / 60;
      int seconds = remainingTime % 60;
      lcd.setCursor(0, 0);
      lcd.print(timerState == TIMER_RUNNING ? "Timer Run" : "Timer Pause");
      lcd.setCursor(0, 1);
      lcd.printf("%02d:%02d:%02d", hours, minutes, seconds);
      lcd.setCursor(0, 2);
      lcd.print("S1:");
      lcd.print(timerState == TIMER_RUNNING ? "Pause" : "Resume");
    } else if (timerState == TIMER_BLINKING) {
      lcd.setCursor(0, 0);
      lcd.print("Timer Done!");
      lcd.setCursor(0, 1);
      lcd.print("Relays Blink");
      lcd.setCursor(0, 2);
      lcd.print("S1:Stop");
    }
    return;
  }

  // --- SHOW_IP MODE ---
  if (currentMode == SHOW_IP) {
    lcd.setCursor(0, 0);
    lcd.print("WiFi Connected");
    lcd.setCursor(0, 1);
    lcd.print("IP:");
    lcd.setCursor(0, 2);
    String ip = WiFi.localIP().toString();
    if (ip.length() > 16) ip = ip.substring(0, 16);
    lcd.print(ip);
    lcd.setCursor(0, 3);
    lcd.print("S2:Exit");
    return;
  }
}

// Update last states
  lastMode = currentMode;
  lastInMenu = inMenu;
  lastCursorPosition = cursorPosition;
  lastMenuOffset = menuOffset;
  lastCursorState = cursorState;
  lastTimerState = timerState;
  lastTimerField = timerField;
  lastSchedulingMode = schedulingMode;
  lastSelectedScheduleRelay = selectedScheduleRelay;
  lastSelectedParam = selectedParam;
  lastStartupState = startupState;
  lastShowingNoNetworkMessage = showingNoNetworkMessage;
  lastScrollOffset = scrollOffset;
  lastSelectedRelay = selectedRelay;
  lastWiFiConnected = (WiFi.status() == WL_CONNECTED);
  for (int i = 0; i < numSwitches; i++) {
    lastButtonState[i] = buttonState[i];
  }
  for (int i = 0; i < numRelays; i++) {
    lastRelayState[i] = relayState[i];
  }
  for (int i = 0; i < 3; i++) {
    lastTimerValues[i] = timerValues[i];
  }
  for (int i = 0; i < numRelays; i++) {
    lastTempValues[i][0] = tempOnHour[i];
    lastTempValues[i][1] = tempOnMinute[i];
    lastTempValues[i][2] = tempOffHour[i];
    lastTempValues[i][3] = tempOffMinute[i];
  }
  lastRemainingTime = calculateRemainingTime();
}

unsigned long calculateRemainingTime() {
  if (timerState != TIMER_RUNNING && timerState != TIMER_PAUSED) {
    return 0;
  }
  unsigned long totalSeconds = timerValues[0] * 3600 + timerValues[1] * 60 + timerValues[2];
  if (timerState == TIMER_PAUSED) {
    return totalSeconds;
  }
  unsigned long elapsed = (millis() - timerStartTime) / 1000;
  return (totalSeconds > elapsed) ? totalSeconds - elapsed : 0;
}

void handleTimer() {
  if (currentMode != TIMER || inMenu) {
    return;
  }

  if (timerState == TIMER_RUNNING) {
    unsigned long currentTime = millis();
    if (currentTime - lastTimerUpdate >= TIMER_UPDATE_INTERVAL) {
      unsigned long remainingTime = calculateRemainingTime();
      if (remainingTime == 0) {
        timerState = TIMER_BLINKING;
        lastBlinkTime = currentTime;
        relaysBlinkingOn = true;
        for (int i = 0; i < numRelays; i++) {
          digitalWrite(relayPins[i], LOW);
          relayState[i] = true;
        }
        Serial.println("Timer zero, relays blinking");
        updateLCD();
      }
      lastTimerUpdate = currentTime;
      updateLCD();
    }
  } else if (timerState == TIMER_BLINKING) {
    unsigned long currentTime = millis();
    if (currentTime - lastBlinkTime >= BLINK_INTERVAL) {
      relaysBlinkingOn = !relaysBlinkingOn;
      for (int i = 0; i < numRelays; i++) {
        digitalWrite(relayPins[i], relaysBlinkingOn ? LOW : HIGH);
        relayState[i] = relaysBlinkingOn;
      }
      lastBlinkTime = currentTime;
      Serial.printf("Relays %s\n", relaysBlinkingOn ? "ON" : "OFF");
      updateLCD();
    }
  }
}

void updateRelayState(int hour, int minute) {
  if (currentMode == SCHEDULING && !inMenu && !schedulingMode && WiFi.status() == WL_CONNECTED) {
    if (hour == onHour1 && minute == onMinute1) {
      relayState[0] = true;
      digitalWrite(RELAY1_PIN, LOW);
    } else if (hour == offHour1 && minute == offMinute1) {
      relayState[0] = false;
      digitalWrite(RELAY1_PIN, HIGH);
    }
    if (hour == onHour2 && minute == onMinute2) {
      relayState[1] = true;
      digitalWrite(RELAY2_PIN, LOW);
    } else if (hour == offHour2 && minute == offMinute2) {
      relayState[1] = false;
      digitalWrite(RELAY2_PIN, HIGH);
    }
    if (hour == onHour3 && minute == onMinute3) {
      relayState[2] = true;
      digitalWrite(RELAY3_PIN, LOW);
    } else if (hour == offHour3 && minute == offMinute3) {
      relayState[2] = false;
      digitalWrite(RELAY3_PIN, HIGH);
    }
    if (hour == onHour4 && minute == onMinute4) {
      relayState[3] = true;
      digitalWrite(RELAY4_PIN, LOW);
    } else if (hour == offHour4 && minute == offMinute4) {
      relayState[3] = false;
      digitalWrite(RELAY4_PIN, HIGH);
    }
    if (hour == onHour5 && minute == onMinute5) {
      relayState[4] = true;
      digitalWrite(RELAY5_PIN, LOW);
    } else if (hour == offHour5 && minute == offMinute5) {
      relayState[4] = false;
      digitalWrite(RELAY5_PIN, HIGH);
    }
    if (hour == onHour6 && minute == onMinute6) {
      relayState[5] = true;
      digitalWrite(RELAY6_PIN, LOW);
    } else if (hour == offHour6 && minute == offMinute6) {
      relayState[5] = false;
      digitalWrite(RELAY6_PIN, HIGH);
    }
  }
}

String formatTime(int hour, int minute) {
  char buffer[6];
  snprintf(buffer, sizeof(buffer), "%02d:%02d", hour, minute);
  return String(buffer);
}

void displayAPMode() {
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("AP Mode");
  lcd.setCursor(0, 1);
  lcd.print("SSID:ESP32_Relay");
  lcd.setCursor(0, 2);
  lcd.print("Pass:12345678");
  lcd.setCursor(0, 3);
  lcd.print("IP:192.168.4.1");
  Serial.println("LCD: AP mode info");
}

void sendCorsHeaders() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
}

void handleRoot() {
  sendCorsHeaders();
  DynamicJsonDocument doc(256);
  doc["success"] = true;
  doc["ip"] = WiFi.localIP().toString();
  doc["ssid"] = WiFi.SSID();
  String output;
  serializeJson(doc, output);
  server.send(200, "application/json", output);
  isClientConnected = true;
  Serial.println("App connected via /");
}

void handleSetWiFi() {
  sendCorsHeaders();
  DynamicJsonDocument doc(512);
  if (!server.hasArg("plain")) {
    doc["success"] = false;
    doc["error"] = "No data provided";
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("Failed: No data provided");
    return;
  }

  DeserializationError error = deserializeJson(doc, server.arg("plain"));
  if (error) {
    doc.clear();
    doc["success"] = false;
    doc["error"] = "Invalid JSON";
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("Failed: " + String(error.c_str()));
    return;
  }

  String ssid = doc["ssid"] | "";
  String password = doc["password"] | "";

  if (ssid.isEmpty()) {
    doc.clear();
    doc["success"] = false;
    doc["error"] = "SSID cannot be empty";
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("SSID is empty");
    return;
  }

  Serial.println("Connecting to WiFi: " + ssid);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), password.c_str());
  int attempts = 0;
  const int maxAttempts = 20;
  while (WiFi.status() != WL_CONNECTED && attempts < maxAttempts) {
    delay(500);
    attempts++;
    Serial.print(".");
  }
  Serial.println();

  doc.clear();
  if (WiFi.status() == WL_CONNECTED) {
    String ip = WiFi.localIP().toString();
    preferences.begin("wifi", false);
    preferences.putString("ssid", ssid);
    preferences.putString("password", password);
    preferences.end();
    doc["success"] = true;
    doc["ip"] = ip;
    doc["ssid"] = ssid;
    isClientConnected = false;
    numModes = 5; // Enable SHOW_IP mode
    Serial.println("WiFi connected, IP: " + ip);
    String output;
    serializeJson(doc, output);
    server.send(200, "application/json", output);
    WiFi.softAPdisconnect(true);
  } else {
    doc["success"] = false;
    doc["error"] = "Failed to connect WiFi";
    String output;
    serializeJson(doc, output);
    server.send(500, "application/json", output);
    WiFi.disconnect();
    WiFi.mode(WIFI_AP);
    WiFi.softAP(apSSID, apPassword);
    numModes = 4; // Disable SHOW_IP mode
    Serial.println("Failed WiFi, AP mode, IP: 192.168.4.1");
  }
}

void handleDisconnect() {
  sendCorsHeaders();
  preferences.begin("wifi", false);
  preferences.clear();
  preferences.end();
  WiFi.disconnect();
  delay(500);
  WiFi.mode(WIFI_AP);
  WiFi.softAP(apSSID, apPassword);
  isClientConnected = false;
  numModes = 4;
  Serial.println("Disconnected, AP mode, IP: 192.168.4.1");
  server.send(200, "application/json", "{\"success\": true, \"message\": \"Disconnected, AP mode\"}");
}

void handleSet() {
  sendCorsHeaders();
  DynamicJsonDocument doc(1024);
  if (!server.hasArg("plain")) {
    doc["success"] = false;
    doc["error"] = "No data provided";
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("handleSet: No data");
    return;
  }

  String rawJson = server.arg("plain");
  Serial.println("handleSet: JSON: " + rawJson);
  DeserializationError error = deserializeJson(doc, rawJson);
  if (error) {
    doc.clear();
    doc["success"] = false;
    doc["error"] = "Invalid JSON: " + String(error.c_str());
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("handleSet: JSON error: " + String(error.c_str()));
    return;
  }

  String onTime1 = doc["onTime1"] | "";
  String offTime1 = doc["offTime1"] | "";
  String onTime2 = doc["onTime2"] | "";
  String offTime2 = doc["offTime2"] | "";
  String onTime3 = doc["onTime3"] | "";
  String offTime3 = doc["offTime3"] | "";
  String onTime4 = doc["onTime4"] | "";
  String offTime4 = doc["offTime4"] | "";
  String onTime5 = doc["onTime5"] | "";
  String offTime5 = doc["offTime5"] | "";
  String onTime6 = doc["onTime6"] | "";
  String offTime6 = doc["offTime6"] | "";

  bool valid = true;
  String errorMsg = "";
  if (!validateTimeFormat(onTime1)) { valid = false; errorMsg += "Invalid onTime1; "; }
  if (!validateTimeFormat(offTime1)) { valid = false; errorMsg += "Invalid offTime1; "; }
  if (!validateTimeFormat(onTime2)) { valid = false; errorMsg += "Invalid onTime2; "; }
  if (!validateTimeFormat(offTime2)) { valid = false; errorMsg += "Invalid offTime2; "; }
  if (!validateTimeFormat(onTime3)) { valid = false; errorMsg += "Invalid onTime3; "; }
  if (!validateTimeFormat(offTime3)) { valid = false; errorMsg += "Invalid offTime3; "; }
  if (!validateTimeFormat(onTime4)) { valid = false; errorMsg += "Invalid onTime4; "; }
  if (!validateTimeFormat(offTime4)) { valid = false; errorMsg += "Invalid offTime4; "; }
  if (!validateTimeFormat(onTime5)) { valid = false; errorMsg += "Invalid onTime5; "; }
  if (!validateTimeFormat(offTime5)) { valid = false; errorMsg += "Invalid offTime5; "; }
  if (!validateTimeFormat(onTime6)) { valid = false; errorMsg += "Invalid onTime6; "; }
  if (!validateTimeFormat(offTime6)) { valid = false; errorMsg += "Invalid offTime6; "; }

  if (!valid) {
    doc.clear();
    doc["success"] = false;
    doc["error"] = "Invalid time: " + errorMsg;
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("handleSet: Failed: " + errorMsg);
    return;
  }

  int tempOnHour1 = onTime1.substring(0, 2).toInt();
  int tempOnMinute1 = onTime1.substring(3, 5).toInt();
  int tempOffHour1 = offTime1.substring(0, 2).toInt();
  int tempOffMinute1 = offTime1.substring(3, 5).toInt();
  int tempOnHour2 = onTime2.substring(0, 2).toInt();
  int tempOnMinute2 = onTime2.substring(3, 5).toInt();
  int tempOffHour2 = offTime2.substring(0, 2).toInt();
  int tempOffMinute2 = offTime2.substring(3, 5).toInt();
  int tempOnHour3 = onTime3.substring(0, 2).toInt();
  int tempOnMinute3 = onTime3.substring(3, 5).toInt();
  int tempOffHour3 = offTime3.substring(0, 2).toInt();
  int tempOffMinute3 = offTime3.substring(3, 5).toInt();
  int tempOnHour4 = onTime4.substring(0, 2).toInt();
  int tempOnMinute4 = onTime4.substring(3, 5).toInt();
  int tempOffHour4 = offTime4.substring(0, 2).toInt();
  int tempOffMinute4 = offTime4.substring(3, 5).toInt();
  int tempOnHour5 = onTime5.substring(0, 2).toInt();
  int tempOnMinute5 = onTime5.substring(3, 5).toInt();
  int tempOffHour5 = offTime5.substring(0, 2).toInt();
  int tempOffMinute5 = offTime5.substring(3, 5).toInt();
  int tempOnHour6 = onTime6.substring(0, 2).toInt();
  int tempOnMinute6 = onTime6.substring(3, 5).toInt();
  int tempOffHour6 = offTime6.substring(0, 2).toInt();
  int tempOffMinute6 = offTime6.substring(3, 5).toInt();

  if (!validateTimeRange(tempOnHour1, tempOnMinute1) ||
      !validateTimeRange(tempOffHour1, tempOffMinute1) ||
      !validateTimeRange(tempOnHour2, tempOnMinute2) ||
      !validateTimeRange(tempOffHour2, tempOffMinute2) ||
      !validateTimeRange(tempOnHour3, tempOnMinute3) ||
      !validateTimeRange(tempOffHour3, tempOffMinute3) ||
      !validateTimeRange(tempOnHour4, tempOnMinute4) ||
      !validateTimeRange(tempOffHour4, tempOffMinute4) ||
      !validateTimeRange(tempOnHour5, tempOnMinute5) ||
      !validateTimeRange(tempOffHour5, tempOffMinute5) ||
      !validateTimeRange(tempOnHour6, tempOnMinute6) ||
      !validateTimeRange(tempOffHour6, tempOffMinute6)) {
    doc.clear();
    doc["success"] = false;
    doc["error"] = "Time out of range";
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("handleSet: Time out of range");
    return;
  }

  onHour1 = tempOnHour1; onMinute1 = tempOnMinute1;
  offHour1 = tempOffHour1; offMinute1 = tempOffMinute1;
  onHour2 = tempOnHour2; onMinute2 = tempOnMinute2;
  offHour2 = tempOffHour2; offMinute2 = tempOffMinute2;
  onHour3 = tempOnHour3; onMinute3 = tempOnMinute3;
  offHour3 = tempOffHour3; offMinute3 = tempOffMinute3;
  onHour4 = tempOnHour4; onMinute4 = tempOnMinute4;
  offHour4 = tempOffHour4; offMinute4 = tempOffMinute4;
  onHour5 = tempOnHour5; onMinute5 = tempOnMinute5;
  offHour5 = tempOffHour5; offMinute5 = tempOffMinute5;
  onHour6 = tempOnHour6; onMinute6 = tempOnMinute6;
  offHour6 = tempOffHour6; offMinute6 = tempOffMinute6;

  saveSchedule();

  doc.clear();
  doc["success"] = true;
  String output;
  serializeJson(doc, output);
  server.send(200, "application/json", output);
  Serial.println("handleSet: Schedule saved");
}

void handleSetSingle() {
  sendCorsHeaders();
  DynamicJsonDocument doc(256);
  if (!server.hasArg("plain")) {
    doc["success"] = false;
    doc["error"] = "No data provided";
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("handleSetSingle: No data");
    return;
  }

  String rawJson = server.arg("plain");
  DeserializationError error = deserializeJson(doc, rawJson);
  if (error) {
    doc.clear();
    doc["success"] = false;
    doc["error"] = "Invalid JSON: " + String(error.c_str());
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("handleSetSingle: JSON error: " + String(error.c_str()));
    return;
  }

  String relayStr = doc["relay"] | "";
  String type = doc["type"] | "";
  String time = doc["time"] | "";

  int relayIndex = relayStr.toInt() - 1;
  if (relayIndex < 0 || relayIndex >= numRelays) {
    doc.clear();
    doc["success"] = false;
    doc["error"] = "Invalid relay number";
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("handleSetSingle: Invalid relay: " + relayStr);
    return;
  }

  if (type != "onTime" && type != "offTime") {
    doc.clear();
    doc["success"] = false;
    doc["error"] = "Invalid type";
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("handleSetSingle: Invalid type: " + type);
    return;
  }

  if (!validateTimeFormat(time)) {
    doc.clear();
    doc["success"] = false;
    doc["error"] = "Invalid time: " + time;
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("handleSetSingle: Invalid time: " + time);
    return;
  }

  int hour = time.substring(0, 2).toInt();
  int minute = time.substring(3, 5).toInt();
  if (!validateTimeRange(hour, minute)) {
    doc.clear();
    doc["success"] = false;
    doc["error"] = "Time out of range";
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("handleSetSingle: Time out: " + time);
    return;
  }

  switch (relayIndex) {
    case 0:
      if (type == "onTime") { onHour1 = hour; onMinute1 = minute; }
      else { offHour1 = hour; offMinute1 = minute; }
      break;
    case 1:
      if (type == "onTime") { onHour2 = hour; onMinute2 = minute; }
      else { offHour2 = hour; offMinute2 = minute; }
      break;
    case 2:
      if (type == "onTime") { onHour3 = hour; onMinute3 = minute; }
      else { offHour3 = hour; offMinute3 = minute; }
      break;
    case 3:
      if (type == "onTime") { onHour4 = hour; onMinute4 = minute; }
      else { offHour4 = hour; offMinute4 = minute; }
      break;
    case 4:
      if (type == "onTime") { onHour5 = hour; onMinute5 = minute; }
      else { offHour5 = hour; offMinute5 = minute; }
      break;
    case 5:
      if (type == "onTime") { onHour6 = hour; onMinute6 = minute; }
      else { offHour6 = hour; offMinute6 = minute; }
      break;
  }

  saveSchedule();

  doc.clear();
  doc["success"] = true;
  String output;
  serializeJson(doc, output);
  server.send(200, "application/json", output);
  Serial.println("handleSetSingle: Updated R" + String(relayIndex + 1) + " " + type + ": " + time);
}

bool validateTimeFormat(String time) {
  if (time.length() != 5 || time[2] != ':') return false;
  for (int i = 0; i < 5; i++) {
    if (i == 2) continue;
    if (!isDigit(time[i])) return false;
  }
  return true;
}

bool validateTimeRange(int hour, int minute) {
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

void handleReset() {
  sendCorsHeaders();
  preferences.begin("wifi", false);
  preferences.clear();
  preferences.end();
  preferences.begin("relay_settings", false);
  preferences.clear();
  preferences.end();
  DynamicJsonDocument doc(256);
  doc["success"] = true;
  doc["message"] = "Settings cleared. Restarting...";
  String output;
  serializeJson(doc, output);
  server.send(200, "application/json", output);
  delay(3000);
  ESP.restart();
}

void handleToggle() {
  sendCorsHeaders();
  DynamicJsonDocument doc(256);
  if (!server.hasArg("plain")) {
    doc["success"] = false;
    doc["error"] = "No data provided";
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("handleToggle: No data");
    return;
  }

  DeserializationError error = deserializeJson(doc, server.arg("plain"));
  if (error) {
    doc.clear();
    doc["success"] = false;
    doc["error"] = "Invalid JSON";
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("handleToggle: JSON error: " + String(error.c_str()));
    return;
  }

  String relayNum = doc["relay"] | "";
  String state = doc["state"] | "";
  
  int relayIndex = relayNum.toInt() - 1;
  bool newState = (state == "1");
  
  if (relayIndex >= 0 && relayIndex < numRelays) {
    relayState[relayIndex] = newState;
    digitalWrite(relayPins[relayIndex], newState ? LOW : HIGH);
  } else {
    doc.clear();
    doc["success"] = false;
    doc["error"] = "Invalid relay number";
    String output;
    serializeJson(doc, output);
    server.send(400, "application/json", output);
    Serial.println("handleToggle: Invalid relay: " + relayNum);
    return;
  }
  
  doc.clear();
  doc["success"] = true;
  doc["relay"] = relayNum;
  doc["state"] = state;
  String output;
  serializeJson(doc, output);
  server.send(200, "application/json", output);
  Serial.println("handleToggle: R" + relayNum + " to " + state);
}

void handleGetStatus() {
  sendCorsHeaders();
  DynamicJsonDocument doc(1024);
  doc["success"] = true;
  JsonArray relays = doc.createNestedArray("relays");
  
  JsonObject relay1 = relays.createNestedObject();
  relay1["relay"] = 1;
  relay1["state"] = relayState[0] ? 1 : 0;
  relay1["onTime"] = formatTime(onHour1, onMinute1);
  relay1["offTime"] = formatTime(offHour1, offMinute1);
  
  JsonObject relay2 = relays.createNestedObject();
  relay2["relay"] = 2;
  relay2["state"] = relayState[1] ? 1 : 0;
  relay2["onTime"] = formatTime(onHour2, onMinute2);
  relay2["offTime"] = formatTime(offHour2, offMinute2);
  
  JsonObject relay3 = relays.createNestedObject();
  relay3["relay"] = 3;
  relay3["state"] = relayState[2] ? 1 : 0;
  relay3["onTime"] = formatTime(onHour3, onMinute3);
  relay3["offTime"] = formatTime(offHour3, offMinute3);
  
  JsonObject relay4 = relays.createNestedObject();
  relay4["relay"] = 4;
  relay4["state"] = relayState[3] ? 1 : 0;
  relay4["onTime"] = formatTime(onHour4, onMinute4);
  relay4["offTime"] = formatTime(offHour4, offMinute4);
  
  JsonObject relay5 = relays.createNestedObject();
  relay5["relay"] = 5;
  relay5["state"] = relayState[4] ? 1 : 0;
  relay5["onTime"] = formatTime(onHour5, onMinute5);
  relay5["offTime"] = formatTime(offHour5, offMinute5);
  
  JsonObject relay6 = relays.createNestedObject();
  relay6["relay"] = 6;
  relay6["state"] = relayState[5] ? 1 : 0;
  relay6["onTime"] = formatTime(onHour6, onMinute6);
  relay6["offTime"] = formatTime(offHour6, offMinute6);

  String output;
  serializeJson(doc, output);
  server.send(200, "application/json", output);
  Serial.println("handleGetStatus: Sent status");
}

void handleOptions() {
  sendCorsHeaders();
  server.send(200, "text/plain", "");
}

void saveSchedule() {
  preferences.begin("relay_settings", false);
  preferences.putUInt("R1_onHour", onHour1);
  preferences.putUInt("R1_onMinute", onMinute1);
  preferences.putUInt("R1_offHour", offHour1);
  preferences.putUInt("R1_offMinute", offMinute1);
  preferences.putUInt("R2_onHour", onHour2);
  preferences.putUInt("R2_onMinute", onMinute2);
  preferences.putUInt("R2_offHour", offHour2);
  preferences.putUInt("R2_offMinute", offMinute2);
  preferences.putUInt("R3_onHour", onHour3);
  preferences.putUInt("R3_onMinute", onMinute3);
  preferences.putUInt("R3_offHour", offHour3);
  preferences.putUInt("R3_offMinute", offMinute3);
  preferences.putUInt("R4_onHour", onHour4);
  preferences.putUInt("R4_onMinute", onMinute4);
  preferences.putUInt("R4_offHour", offHour4);
  preferences.putUInt("R4_offMinute", offMinute4);
  preferences.putUInt("R5_onHour", onHour5);
  preferences.putUInt("R5_onMinute", onMinute5);
  preferences.putUInt("R5_offHour", offHour5);
  preferences.putUInt("R5_offMinute", offMinute5);
  preferences.putUInt("R6_onHour", onHour6);
  preferences.putUInt("R6_onMinute", onMinute6);
  preferences.putUInt("R6_offHour", offHour6);
  preferences.putUInt("R6_offMinute", offMinute6);
  preferences.end();
  Serial.println("saveSchedule: Saved");
}

String modeToString(int mode) {
  switch (mode) {
    case SCHEDULING: return "SCHEDULE";
    case TEST_BULB: return "TEST BULB";
    case RESET_ESP: return "RESET ESP";
    case TIMER: return "TIMER";
    case SHOW_IP: return "SHOW IP";
    default: return "UNKNOWN";
  }
}