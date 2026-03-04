/**
 * RUAXEAI ESP32 Firmware
 * USB Serial communication with Android Tablet
 * Controls 6 relays for car wash services
 * 
 * Protocol (JSON over USB Serial):
 * → Tablet sends: {"action":"ON","relay":1}
 * ← ESP32 responds: {"ok":true,"relay":1,"state":"ON"}
 * 
 * Commands:
 *   ON    — Turn on relay (1-6)
 *   OFF   — Turn off relay (1-6)
 *   OFF_ALL — Turn off all relays
 *   STATUS — Get all relay states
 *   PING   — Heartbeat check
 */

#include <ArduinoJson.h>

// Relay pins (adjust for your ESP32 board)
const int RELAY_PINS[] = {
  26,  // Relay 1: Rửa nước
  27,  // Relay 2: Bọt tuyết
  14,  // Relay 3: Hút bụi
  12,  // Relay 4: Khí nén
  13,  // Relay 5: Hơi nóng
  15,  // Relay 6: Nước rửa tay
};
const int NUM_RELAYS = 6;

// Relay states (true = ON)
bool relayStates[6] = {false, false, false, false, false, false};

// Watchdog: auto-off if no command received for 30 seconds
unsigned long lastCommandTime = 0;
const unsigned long WATCHDOG_TIMEOUT = 30000; // 30s

// Heartbeat LED
const int LED_PIN = 2; // Built-in LED
unsigned long lastBlink = 0;
bool ledState = false;

void setup() {
  Serial.begin(115200);
  
  // Initialize relay pins
  for (int i = 0; i < NUM_RELAYS; i++) {
    pinMode(RELAY_PINS[i], OUTPUT);
    digitalWrite(RELAY_PINS[i], HIGH); // HIGH = OFF (active low relay)
  }
  
  // LED
  pinMode(LED_PIN, OUTPUT);
  
  lastCommandTime = millis();
  
  Serial.println("{\"event\":\"BOOT\",\"firmware\":\"RUAXEAI_v1.0\",\"relays\":6}");
}

void loop() {
  // Read serial commands
  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    if (input.length() > 0) {
      processCommand(input);
      lastCommandTime = millis();
    }
  }
  
  // Watchdog: turn off all relays if no command for too long
  if (millis() - lastCommandTime > WATCHDOG_TIMEOUT) {
    bool anyOn = false;
    for (int i = 0; i < NUM_RELAYS; i++) {
      if (relayStates[i]) anyOn = true;
    }
    if (anyOn) {
      allOff();
      Serial.println("{\"event\":\"WATCHDOG\",\"message\":\"All relays OFF - no communication\"}");
    }
    lastCommandTime = millis(); // Reset to avoid spam
  }
  
  // Blink LED to show alive
  if (millis() - lastBlink > 1000) {
    ledState = !ledState;
    digitalWrite(LED_PIN, ledState);
    lastBlink = millis();
  }
}

void processCommand(String input) {
  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, input);
  
  if (error) {
    Serial.println("{\"ok\":false,\"error\":\"Invalid JSON\"}");
    return;
  }
  
  const char* action = doc["action"];
  if (!action) {
    Serial.println("{\"ok\":false,\"error\":\"Missing action\"}");
    return;
  }
  
  String act = String(action);
  
  if (act == "ON") {
    int relay = doc["relay"] | 0;
    if (relay < 1 || relay > NUM_RELAYS) {
      Serial.println("{\"ok\":false,\"error\":\"Invalid relay (1-6)\"}");
      return;
    }
    setRelay(relay - 1, true);
    sendRelayResponse(relay, true);
  }
  else if (act == "OFF") {
    int relay = doc["relay"] | 0;
    if (relay < 1 || relay > NUM_RELAYS) {
      Serial.println("{\"ok\":false,\"error\":\"Invalid relay (1-6)\"}");
      return;
    }
    setRelay(relay - 1, false);
    sendRelayResponse(relay, false);
  }
  else if (act == "OFF_ALL") {
    allOff();
    Serial.println("{\"ok\":true,\"action\":\"OFF_ALL\"}");
  }
  else if (act == "STATUS") {
    sendStatus();
  }
  else if (act == "PING") {
    Serial.println("{\"ok\":true,\"action\":\"PONG\",\"uptime\":" + String(millis()) + "}");
  }
  else {
    Serial.println("{\"ok\":false,\"error\":\"Unknown action\"}");
  }
}

void setRelay(int index, bool on) {
  relayStates[index] = on;
  digitalWrite(RELAY_PINS[index], on ? LOW : HIGH); // Active LOW
}

void allOff() {
  for (int i = 0; i < NUM_RELAYS; i++) {
    setRelay(i, false);
  }
}

void sendRelayResponse(int relay, bool state) {
  JsonDocument doc;
  doc["ok"] = true;
  doc["relay"] = relay;
  doc["state"] = state ? "ON" : "OFF";
  
  String output;
  serializeJson(doc, output);
  Serial.println(output);
}

void sendStatus() {
  JsonDocument doc;
  doc["ok"] = true;
  doc["action"] = "STATUS";
  doc["uptime"] = millis();
  doc["firmware"] = "RUAXEAI_v1.0";
  
  JsonArray relays = doc["relays"].to<JsonArray>();
  for (int i = 0; i < NUM_RELAYS; i++) {
    relays.add(relayStates[i]);
  }
  
  String output;
  serializeJson(doc, output);
  Serial.println(output);
}
