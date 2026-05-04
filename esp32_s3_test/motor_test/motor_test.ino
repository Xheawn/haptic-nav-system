/*
 * XIAO ESP32S3 3.3V Vibration Motor Pin Scanner
 *
 * 接法：
 * 电机一根线 -> GND
 * 电机另一根线 -> 当前测试的 D 口
 *
 * 看到 Serial Monitor 显示哪个 pin 时电机震动，
 * 就记录那个 D 口 / GPIO。
 */

struct PinEntry {
  int gpio;
  const char* label;
};

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
  {9,  "D10 / GPIO9 "}
};

const int NUM_PINS = 11;

const int ON_TIME = 800;
const int OFF_TIME = 1200;
const int ROUND_DELAY = 3000;

const bool LOOP_ENABLED = false;  // true = 持续循环, false = 只跑一次
bool hasRun = false;

void setAllLow() {
  for (int i = 0; i < NUM_PINS; i++) {
    digitalWrite(allPins[i].gpio, LOW);
  }
}

void setup() {
  Serial.begin(115200);
  delay(2000);

  Serial.println("=== XIAO ESP32S3 3.3V Motor Pin Scanner ===");
  Serial.println("接法：D口 -> 电机 -> GND");
  Serial.println("HIGH 时电机应该震动。");
  Serial.println();

  for (int i = 0; i < NUM_PINS; i++) {
    pinMode(allPins[i].gpio, OUTPUT);
    digitalWrite(allPins[i].gpio, LOW);
  }

  Serial.println("初始化完成，开始循环扫描。");
  Serial.println();
}

void loop() {
  if (!LOOP_ENABLED && hasRun) return;

  Serial.println("=== New Scan Round ===");

  for (int i = 0; i < NUM_PINS; i++) {
    setAllLow();

    Serial.printf(">>> Testing [%2d/%d] %s  GPIO=%d  -> HIGH\n",
                  i + 1, NUM_PINS, allPins[i].label, allPins[i].gpio);

    digitalWrite(allPins[i].gpio, HIGH);
    delay(ON_TIME);

    digitalWrite(allPins[i].gpio, LOW);

    Serial.printf("<<< Done: %s -> LOW\n\n", allPins[i].label);

    delay(OFF_TIME);
  }

  setAllLow();

  Serial.println("=== Scan Round Done ===");
  Serial.println();

  delay(ROUND_DELAY);

  hasRun = true;
}