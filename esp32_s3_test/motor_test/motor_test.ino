/*
 * ESP32-S3 Pin Scanner — 逐个测试 XIAO ESP32S3 所有引脚
 *
 * 把你能动的那个电机的信号线接到每个引脚上测试，
 * 观察 Serial Monitor 输出，记录哪些引脚能让电机动。
 *
 * 或者：三个电机全接着，看 Serial 打到哪个引脚时哪个电机动了。
 */

struct PinEntry {
  int gpio;
  const char* label;
};

// XIAO ESP32-S3 全部可用引脚
PinEntry allPins[] = {
  {1,  "D0  / GPIO1 "},
  {2,  "D1  / GPIO2 "},
  {3,  "D2  / GPIO3 "},
  {4,  "D3  / GPIO4 "},
  {5,  "D4  / GPIO5 "},
  {6,  "D5  / GPIO6 "},
  {43, "D6  / GPIO43"},
  {44, "D7  / GPIO44"},
  {7,  "D8  / GPIO7 "},
  {8,  "D9  / GPIO8 "},
  {9,  "D10 / GPIO9 "},
};
const int NUM_PINS = 11;

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("=== XIAO ESP32-S3 Pin Scanner ===");
  Serial.println("逐个引脚 digitalWrite HIGH 2秒");
  Serial.println("观察哪个电机在哪个引脚时振动\n");

  // Init all LOW
  for (int i = 0; i < NUM_PINS; i++) {
    pinMode(allPins[i].gpio, OUTPUT);
    digitalWrite(allPins[i].gpio, LOW);
  }

  // Scan each pin
  for (int i = 0; i < NUM_PINS; i++) {
    Serial.printf(">>> [%2d/%d] %s  (gpio=%d) → HIGH\n",
                  i + 1, NUM_PINS, allPins[i].label, allPins[i].gpio);
    digitalWrite(allPins[i].gpio, HIGH);
    delay(2000);
    digitalWrite(allPins[i].gpio, LOW);
    Serial.printf("<<<  %s → LOW\n\n", allPins[i].label);
    delay(1000);
  }

  Serial.println("=== Scan Done ===");
  Serial.println("记录哪些引脚让电机振动了，告诉我结果");
}

void loop() {
  delay(10000);
}
