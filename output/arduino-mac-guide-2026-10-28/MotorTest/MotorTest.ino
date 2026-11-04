#include <Wire.h>
#include <Adafruit_DRV2605.h>

Adafruit_DRV2605 drv;

void setup() {
  // Macへログを表示する準備
  Serial.begin(115200);
  delay(2000);
  Serial.println("Motor test start");

  // SDA: D4 = GPIO6 / SCL: D5 = GPIO7
  Wire.begin(6, 7);

  // ADA-2305との通信確認
  if (!drv.begin(&Wire)) {
    while (true) {
      Serial.println("ERROR: DRV2605L not found");
      delay(2000);
    }
  }

  drv.selectLibrary(1);  // ERM用
  drv.setMode(DRV2605_MODE_INTTRIG);
  Serial.println("DRV2605L ready");
}

void loop() {
  drv.setWaveform(0, 14);  // Strong Buzz
  drv.setWaveform(1, 0);   // シーケンス終了
  drv.go();               // 振動を開始
  Serial.println("Vibration");
  delay(2000);            // 次の再生まで待つ
}
