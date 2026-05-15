/*
 * ESP32-S3 BLE Server — 4-byte LiDAR haptic protocol
 *
 * Supports two packet formats:
 *   Legacy 2-byte: [AdjustDirection, AngleDiff]  (macro navigation)
 *   New 4-byte:    [0x01, L, F, R]               (LiDAR micro-navigation)
 *
 * Motor control: 3 motors via PWM (0-255 intensity)
 *   Requires MOSFET/transistor on each pin for adequate current.
 *   Without MOSFET, motors may not spin (GPIO max ~40mA).
 */

#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>

// Must match the iOS BLEManager UUIDs exactly
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// Motor pins — update these to match your wiring
// (Pin numbers = GPIO numbers on XIAO ESP32S3)
#define MOTOR_L_PIN  9   // D10 / GPIO9  — Left motor
#define MOTOR_F_PIN  44  // D7  / GPIO44 — Front motor
#define MOTOR_R_PIN  2   // D1  / GPIO2  — Right motor

// PWM configuration
#define PWM_FREQ     1000  // 1 kHz PWM frequency
#define PWM_RES      8     // 8-bit resolution (0-255)

bool deviceConnected = false;

// Shared state between BLE callback and loop() — marked volatile
// Legacy 2-byte protocol
volatile uint8_t lastDir   = 0;
volatile uint8_t lastAngle = 0;
// New 4-byte protocol
volatile uint8_t motorL = 0;
volatile uint8_t motorF = 0;
volatile uint8_t motorR = 0;
volatile uint8_t lastCmd = 0;
volatile bool    newData   = false;
unsigned long lastPrintMs  = 0;
const unsigned long PRINT_INTERVAL = 100; // print at most every 100 ms

// --- BLE Server connection callbacks ---
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("[BLE] Client connected");
  }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("[BLE] Client disconnected — restarting advertising");
    // Restart advertising so the phone can reconnect
    BLEDevice::startAdvertising();
  }
};

// --- Characteristic write callback ---
class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String value = pCharacteristic->getValue();
    if (value.length() >= 4 && (uint8_t)value[0] == 0x01) {
      // 4-byte LiDAR haptic packet: [0x01, L, F, R] — pulse mode
      lastCmd = 0x01;
      motorL  = (uint8_t)value[1];
      motorF  = (uint8_t)value[2];
      motorR  = (uint8_t)value[3];
      newData = true;
    } else if (value.length() >= 4 && (uint8_t)value[0] == 0x02) {
      // 4-byte Macro nav packet: [0x02, L, F, R] — continuous mode
      lastCmd = 0x02;
      motorL  = (uint8_t)value[1];
      motorF  = (uint8_t)value[2];
      motorR  = (uint8_t)value[3];
      newData = true;
    } else if (value.length() >= 2) {
      // Legacy 2-byte (unused, kept for compat)
      lastCmd   = 0x00;
      lastDir   = (uint8_t)value[0];
      lastAngle = (uint8_t)value[1];
      newData   = true;
    }
  }
};

void setup() {
  Serial.begin(115200);
  Serial.println("Starting ESP32-S3 BLE Server (4-byte protocol)...");

  // Motor PWM setup (3 motors: L/F/R)
  ledcAttach(MOTOR_L_PIN, PWM_FREQ, PWM_RES);
  ledcAttach(MOTOR_F_PIN, PWM_FREQ, PWM_RES);
  ledcAttach(MOTOR_R_PIN, PWM_FREQ, PWM_RES);
  ledcWrite(MOTOR_L_PIN, 0);
  ledcWrite(MOTOR_F_PIN, 0);
  ledcWrite(MOTOR_R_PIN, 0);

  // --- BLE init ---
  BLEDevice::init("XIAO_ESP32S3");
  BLEServer* pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  BLECharacteristic* pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
  );
  pCharacteristic->setCallbacks(new CommandCallbacks());

  pService->start();

  // --- Advertising ---
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // helps with iPhone connection
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Advertising started — waiting for connection...");
}

// ── Pulse-rate motor control ──
// Values from iOS: 0=off, 255=constant, 1-254=pulsing (higher=faster)
// Fixed vibration strength when ON; vary the off-time between pulses.

#define PULSE_ON_MS     100   // each pulse burst = 100ms
#define PULSE_INTENSITY 230   // PWM when motor is ON
#define NUM_MOTORS      3

// Motor state arrays: [0]=Left, [1]=Front, [2]=Right
const int motorPins[NUM_MOTORS] = {MOTOR_L_PIN, MOTOR_F_PIN, MOTOR_R_PIN};
uint8_t       mTarget[NUM_MOTORS]    = {0, 0, 0};  // urgency from BLE
bool          mIsOn[NUM_MOTORS]      = {false, false, false};
unsigned long mLastToggle[NUM_MOTORS] = {0, 0, 0};
uint8_t       mMode = 0x01;  // 0x01=pulse (LiDAR), 0x02=continuous (macro)

void updateMotor(int i) {
  if (mTarget[i] == 0) {
    ledcWrite(motorPins[i], 0);
    mIsOn[i] = false;
    return;
  }
  if (mTarget[i] == 255) {
    ledcWrite(motorPins[i], PULSE_INTENSITY);
    mIsOn[i] = true;
    return;
  }
  // Pulsing: map value → off-time (254→0ms, 1→500ms)
  unsigned long offMs;
  if (mTarget[i] >= 254) offMs = 0;
  else if (mTarget[i] <= 1) offMs = 500;
  else offMs = (unsigned long)map(mTarget[i], 1, 254, 500, 0);

  unsigned long now = millis();
  if (mIsOn[i]) {
    if (now - mLastToggle[i] >= PULSE_ON_MS) {
      ledcWrite(motorPins[i], 0);
      mIsOn[i] = false;
      mLastToggle[i] = now;
    }
  } else {
    if (now - mLastToggle[i] >= offMs) {
      ledcWrite(motorPins[i], PULSE_INTENSITY);
      mIsOn[i] = true;
      mLastToggle[i] = now;
    }
  }
}

void loop() {
  // Update target values and mode from BLE data
  if (newData) {
    if (lastCmd == 0x01 || lastCmd == 0x02) {
      mTarget[0] = motorL;
      mTarget[1] = motorF;
      mTarget[2] = motorR;
      mMode = lastCmd;
    }
    newData = false;
  }

  // Drive motors based on mode
  if (mMode == 0x02) {
    // Continuous mode (macro nav): direct PWM, no pulsing
    for (int i = 0; i < NUM_MOTORS; i++) {
      ledcWrite(motorPins[i], mTarget[i]);
    }
  } else {
    // Pulse mode (LiDAR): run pulse state machines
    for (int i = 0; i < NUM_MOTORS; i++) {
      updateMotor(i);
    }
  }

  // Safety: if disconnected, stop all motors
  if (!deviceConnected) {
    for (int i = 0; i < NUM_MOTORS; i++) {
      mTarget[i] = 0;
      ledcWrite(motorPins[i], 0);
    }
  }

  // Throttled serial logging
  unsigned long now = millis();
  if (now - lastPrintMs >= PRINT_INTERVAL) {
    lastPrintMs = now;
    if (mTarget[0] > 0 || mTarget[1] > 0 || mTarget[2] > 0) {
      char buf[80];
      const char* modeStr = (mMode == 0x02) ? "CONT" : "PULSE";
      snprintf(buf, sizeof(buf), "[%s] L=%3u F=%3u R=%3u",
               modeStr, mTarget[0], mTarget[1], mTarget[2]);
      Serial.println(buf);
    }
  }

  delay(5);  // 200Hz loop for smooth pulse timing
}