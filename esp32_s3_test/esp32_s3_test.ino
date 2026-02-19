/*
 * ESP32-S3 BLE Server — minimal foundation
 * Advertises a service and exposes one writable characteristic.
 * When the iOS app writes 2 bytes [AdjustDirection, AngleDiff],
 * the values are printed to Serial for verification.
 *
 * Motor control will be added in the next step.
 */

#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>

// Must match the iOS BLEManager UUIDs exactly
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// Motor pins (not driven yet — kept for next step)
// #define MOTOR1_PIN 1 // D00
#define MOTOR1_PIN 6  // D08 — left motor
#define MOTOR2_PIN 8  // D10 — right motor

bool deviceConnected = false;

// Shared state between BLE callback and loop() — marked volatile
volatile uint8_t lastDir   = 0;
volatile uint8_t lastAngle = 0;
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
    if (value.length() >= 2) {
      // Just store — never call Serial from this callback (different task)
      lastDir   = (uint8_t)value[0];
      lastAngle = (uint8_t)value[1];
      newData   = true;
    }
  }
};

void setup() {
  Serial.begin(115200);
  Serial.println("Starting ESP32-S3 BLE Server...");

  // Motor pins (idle for now)
  pinMode(MOTOR1_PIN, OUTPUT);
  pinMode(MOTOR2_PIN, OUTPUT);
  digitalWrite(MOTOR1_PIN, LOW);
  digitalWrite(MOTOR2_PIN, LOW);

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

void loop() {
  // Print from loop() only — safe, single-threaded, throttled
  if (newData) {
    unsigned long now = millis();
    if (now - lastPrintMs >= PRINT_INTERVAL) {
      lastPrintMs = now;
      char buf[64];
      snprintf(buf, sizeof(buf), "[BLE] Dir:%u  Angle:%u", lastDir, lastAngle);
      Serial.println(buf);
    }
    newData = false;
  }
  delay(20);
}