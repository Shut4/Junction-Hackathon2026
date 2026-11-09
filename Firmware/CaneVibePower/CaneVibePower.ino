#include <stdint.h>

// 電源ボタン専用：動作中に1回押して離すとOFF、System OFF中の押下でON。
namespace cane {
enum class PowerAction : uint8_t { None, ShutdownRequested, EnterSystemOff };
class PowerButton {
 public:
  static constexpr uint32_t debounceMs=30;
  PowerAction update(bool pressed,uint32_t now) {
    if (!started) {
      started=true;lastReading=stablePressed=pressed;changedAt=now;
      return PowerAction::None;
    }
    if (pressed != lastReading) { lastReading=pressed;changedAt=now; }
    if (uint32_t(now-changedAt) >= debounceMs && (!settled || stablePressed != pressed)) {
      settled=true;stablePressed=pressed;
      // 起動・復帰に使った押下ではOFFにしない。一度離してから次の押下を受け付ける。
      if (!armed) {
        if (!pressed) armed=true;
        return PowerAction::None;
      }
      if (pressed) { shutdownReported=true;return PowerAction::ShutdownRequested; }
      if (shutdownReported) return PowerAction::EnterSystemOff;
    }
    return PowerAction::None;
  }
  bool released() const { return settled && !stablePressed; }
 private:
  bool started=false,settled=false,armed=false,lastReading=false,stablePressed=false,shutdownReported=false;
  uint32_t changedAt=0;
};
}

#ifndef CANE_POWER_BUTTON_TEST
#include <Adafruit_TinyUSB.h>
#include <Wire.h>
#include <Adafruit_DRV2605.h>
#include <bluefruit.h>
#include <atomic>
#include <nrf_gpio.h>
#include <nrf_soc.h>
#include <nrf_sdm.h>
// 危険度・振動パターンの処理もこのファイル内に収録。
#include <stdint.h>
#include <stddef.h>

// iOS Core/CaneProtocol.swift と共通の10バイト形式。
namespace cane {
enum State : uint8_t { Clear=0, Caution=1, Danger=2, Unavailable=3 };

class Control {
 public:
  State state=Unavailable;
  uint8_t errors=0;
  uint16_t sequence=0;

  void reset() {
    state=Unavailable;errors=0;sequence=0;hasSequence=false;armed=false;phaseStart=0;lastAccepted=0;
  }

  // 受信時刻でTTLを管理。キューで古くなった指示も駆動に使用しない。
  bool receive(const uint8_t* data, size_t length, uint32_t receivedAt, uint32_t now) {
    if (length != 10 || data[0] != 1 || data[1] > Unavailable ||
        read16(data+4) != 1000 || (data[8] & 0xFC) != 0 || data[9] != 0 ||
        ((data[1] == Clear || data[1] == Unavailable) && read16(data+6) != 0xFFFF)) {
      errors |= 2;return false;
    }
    const uint16_t next=read16(data+2);
    if (hasSequence) {
      const uint16_t delta=uint16_t(next-sequence);
      if (delta == 0 || delta >= 0x8000) { errors |= 2;return false; }
    }
    if (uint32_t(now-receivedAt) >= 1000) { errors |= 2;return false; }
    const State nextState=State(data[1]);
    if (nextState != state) phaseStart=now;
    state=nextState;sequence=next;hasSequence=true;armed=true;lastAccepted=receivedAt;errors=0;
    return true;
  }

  bool expire(uint32_t now) {
    if (!armed || uint32_t(now-lastAccepted) < 1000) return false;
    armed=false;state=Unavailable;errors |= 1;return true;
  }

  bool motorOn(uint32_t now) const {
    if (!armed || uint32_t(now-lastAccepted) >= 1000) return false;
    const uint32_t elapsed=uint32_t(now-phaseStart);
    // 注意は長めの単発、危険は短い3連続。強度ではなくリズムで区別する。
    // 危険：120ms ON / 100ms OFFを挟んで3回、最後に440ms OFF（1秒周期）。
    if (state == Danger) {
      const uint32_t phase=elapsed % 1000;
      return phase < 560 && phase % 220 < 120;
    }
    // 注意：300ms ON / 1700ms OFF（2秒周期）。
    if (state == Caution) return elapsed % 2000 < 300;
    return false;
  }

  void status(uint8_t* out, uint32_t now) const {
    out[0]=1;out[1]=state;out[2]=errors;
    // v1のoffset 3はGPIO3の実出力値。この基板はGPIO3を駆動しないため常に0。
    // RTP値やモーター実振動の検出値として扱わない。
    out[3]=0;out[4]=uint8_t(sequence);out[5]=uint8_t(sequence >> 8);
    for (uint8_t i=0;i<4;++i) out[6+i]=uint8_t(now >> (8*i));
  }

 private:
  bool hasSequence=false;
  bool armed=false;
  uint32_t phaseStart=0;
  uint32_t lastAccepted=0;
  static uint16_t read16(const uint8_t* p) { return uint16_t(p[0]) | uint16_t(p[1]) << 8; }
};
}


// 対象：Seeed nRF52 Boards / Seeed XIAO nRF52840（mbed版ではありません）。
Adafruit_DRV2605 drv;
BLEService caneService("77D6F146-E62C-4ED3-BAAA-6C1526D79D28");
BLECharacteristic commandCharacteristic("BC6B696D-E8D3-4566-9730-EA6B057EE324");
BLECharacteristic statusCharacteristic("D9B72442-A4CC-4E98-9352-CED78C12B22F");
cane::Control control;

// 提示スケッチの0x75を維持。0x40ではありません。適正値はLRA仕様に合わせて確認してください。
const uint8_t VIBRATION_LEVEL=0x75;
const uint16_t VIBRATION_TIME_MS=250;
const uint16_t PAUSE_TIME_MS=750;
const uint8_t VIBRATION_COUNT=10;
const uint32_t AUTO_TEST_DELAY_MS=8000;
const uint32_t COOLDOWN_TIME_MS=10000;
// BLE利用時に起動だけで振動しないよう、8秒後の自動テストは既定で無効。
const bool ENABLE_AUTO_TEST=false;

bool driverReady=false;
bool bluetoothReady=false;
bool autoTestFinished=false;
bool testRunning=false;
bool hasFinishedTest=false;
bool motorActive=false;
bool statusPending=false;
bool queueFault=false;
bool stopRequested=false;
// Step6と同じArduino D0（nRF52840のP0.02）。ボタンはD0とGNDの間。
const uint8_t BUTTON_PIN=0;
cane::PowerButton powerButton;
bool powerOffRequested=false;
std::atomic<bool> shuttingDown(false);
uint32_t readyTime=0;
uint32_t lastTestFinished=0;
uint32_t testStarted=0;
uint32_t lastStatusSent=0;
uint16_t connectionHandle=BLE_CONN_HANDLE_INVALID;

// BLEコールバックとloopは別タスク。I2Cと制御状態の更新はloopだけで実行する。
enum EventKind : uint8_t { Connected, Disconnected, Command };
struct CaneEvent {
  EventKind kind;
  uint16_t handle;
  uint16_t length;
  uint32_t receivedAt;
  uint8_t data[20];
};
QueueHandle_t eventQueue=nullptr;
std::atomic<bool> queueOverflow(false);

void enqueueEvent(const CaneEvent& event) {
  if (shuttingDown.load()) return;
  if (eventQueue == nullptr || xQueueSend(eventQueue,&event,0) != pdTRUE) queueOverflow.store(true);
}
void onConnect(uint16_t handle) {
  CaneEvent event={};event.kind=Connected;event.handle=handle;enqueueEvent(event);
}
void onDisconnect(uint16_t handle,uint8_t reason) {
  (void)reason;
  CaneEvent event={};event.kind=Disconnected;event.handle=handle;enqueueEvent(event);
}
void onCommand(uint16_t handle,BLECharacteristic* characteristic,uint8_t* data,uint16_t length) {
  (void)characteristic;
  CaneEvent event={};event.kind=Command;event.handle=handle;event.length=length;event.receivedAt=millis();
  if (length <= sizeof(event.data)) memcpy(event.data,data,length);
  enqueueEvent(event);
}

void setMotor(bool on) {
  if (!driverReady || motorActive == on) return;
  drv.setRealtimeValue(on ? VIBRATION_LEVEL:0);
  motorActive=on;
}
void stopLocalTest() {
  if (testRunning) { testRunning=false;hasFinishedTest=true;lastTestFinished=millis(); }
  setMotor(false);
}
void runVibrationPattern() {
  if (!driverReady || testRunning || queueFault) return;
  if (Bluefruit.connected() || connectionHandle != BLE_CONN_HANDLE_INVALID) {
    Serial.println("Local test disabled while BLE is connected. Use the iOS test buttons.");return;
  }
  const uint32_t now=millis();
  if (hasFinishedTest && uint32_t(now-lastTestFinished) < COOLDOWN_TIME_MS) {
    Serial.println("Cooling down. Wait 10 seconds.");return;
  }
  testRunning=true;testStarted=now;setMotor(true);
  Serial.println("Local LRA test: 10 pulses, 250ms ON / 750ms OFF. Send s to stop.");
}
void updateLocalTest(uint32_t now) {
  const uint32_t elapsed=uint32_t(now-testStarted);
  const uint32_t period=uint32_t(VIBRATION_TIME_MS)+PAUSE_TIME_MS;
  if (elapsed >= (VIBRATION_COUNT-1)*period+VIBRATION_TIME_MS) {
    stopLocalTest();Serial.println("Local test stopped. Wait 10 seconds before running again.");return;
  }
  setMotor(elapsed % period < VIBRATION_TIME_MS);
}
void publishStatus(uint32_t now) {
  uint8_t packet[10];control.status(packet,now);
  statusCharacteristic.write(packet,sizeof(packet));
  if (connectionHandle != BLE_CONN_HANDLE_INVALID && statusCharacteristic.notifyEnabled(connectionHandle)) {
    // 送信枠不足なら次のloopで再試行。最新状態だけを保持する。
    if (!statusCharacteristic.notify(connectionHandle,packet,sizeof(packet))) { statusPending=true;return; }
  }
  statusPending=false;lastStatusSent=now;
}
void handleEvent(const CaneEvent& event,uint32_t now) {
  if (event.kind == Connected) {
    stopLocalTest();autoTestFinished=true;stopRequested=false;connectionHandle=event.handle;control.reset();
    Serial.println("BLE connected. Waiting for iOS command.");statusPending=true;return;
  }
  if (event.handle != connectionHandle) return;
  if (event.kind == Disconnected) {
    stopLocalTest();connectionHandle=BLE_CONN_HANDLE_INVALID;control.reset();statusPending=true;
    Serial.println("BLE disconnected. Motor stopped.");return;
  }
  if (stopRequested) return;
  const cane::State previous=control.state;
  const bool accepted=control.receive(event.data,event.length,event.receivedAt,now);
  // 最新の受理状態を反映してからStatusを通知する。
  setMotor(control.motorOn(now));statusPending=true;
  if (accepted && previous != control.state) {
    Serial.print("BLE state: ");Serial.println(uint8_t(control.state));
  }
  publishStatus(now);
}

void setup() {
  // GPIO SENSEによる復帰後も通常入力に戻す。復帰に使った押下は無視する。
  pinMode(BUTTON_PIN,INPUT_PULLUP);
  powerButton.update(digitalRead(BUTTON_PIN) == LOW,millis());
  Serial.begin(115200);
  const uint32_t serialWaitStarted=millis();
  while (!Serial && uint32_t(millis()-serialWaitStarted) < 2000) delay(10);
  Serial.println("Power button D0: press once and release to turn OFF (System OFF).");
  Serial.println("Press D0 again to turn ON. No long-press or vibration-toggle action.");
  // XIAO nRF52840：D4=SDA、D5=SCL。
  Wire.begin();Wire.setClock(100000);
  if (!drv.begin()) {
    Serial.println("DRV2605L not found. Check 3V3, GND, D4/SDA and D5/SCL.");return;
  }
  drv.useLRA();drv.setMode(DRV2605_MODE_REALTIME);drv.setRealtimeValue(0);
  driverReady=true;readyTime=millis();
  eventQueue=xQueueCreate(16,sizeof(CaneEvent));
  if (eventQueue == nullptr) { Serial.println("BLE event queue allocation failed. Motor remains stopped.");return; }

  // サービスと2つの特性は異なる128-bit UUIDベースを使う。
  Bluefruit.configUuid128Count(3);
  if (!Bluefruit.begin(1,0)) { Serial.println("BLE initialization failed.");return; }
  Bluefruit.setName("CaneVibe-01");Bluefruit.setTxPower(0);
  Bluefruit.Periph.setConnectCallback(onConnect);Bluefruit.Periph.setDisconnectCallback(onDisconnect);
  if (caneService.begin() != ERROR_NONE) { Serial.println("BLE service initialization failed.");return; }
  commandCharacteristic.setProperties(CHR_PROPS_WRITE);
  commandCharacteristic.setPermission(SECMODE_NO_ACCESS,SECMODE_OPEN);
  // 最大20バイトとして受け付け、10バイト以外はアプリ層で明示的に拒否する。
  commandCharacteristic.setMaxLen(20);commandCharacteristic.setWriteCallback(onCommand);
  if (commandCharacteristic.begin() != ERROR_NONE) { Serial.println("Command initialization failed.");return; }
  statusCharacteristic.setProperties(CHR_PROPS_READ | CHR_PROPS_NOTIFY);
  statusCharacteristic.setPermission(SECMODE_OPEN,SECMODE_NO_ACCESS);
  statusCharacteristic.setFixedLen(10);
  if (statusCharacteristic.begin() != ERROR_NONE) { Serial.println("Status initialization failed.");return; }
  control.reset();publishStatus(millis());
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addService(caneService);Bluefruit.ScanResponse.addName();
  Bluefruit.Advertising.restartOnDisconnect(true);Bluefruit.Advertising.setInterval(32,244);
  Bluefruit.Advertising.setFastTimeout(30);
  if (!Bluefruit.Advertising.start(0)) { Serial.println("BLE advertising failed.");return; }
  bluetoothReady=true;
  Serial.println("DRV2605L ready. BLE advertising: CaneVibe-01");
  Serial.println("State 2=DANGER: three 120ms pulses per second; state 1=CAUTION: one 300ms pulse per 2 seconds.");
  Serial.println("State 0/3, disconnect or 1000ms without fresh commands: STOP.");
  Serial.println("Disconnected only: t=10-pulse test, s=stop. Startup auto test is disabled by default.");
}

void requestPowerOff() {
  if (powerOffRequested) return;
  powerOffRequested=true;shuttingDown.store(true);stopRequested=true;
  stopLocalTest();control.reset();
  if (bluetoothReady) {
    Bluefruit.Advertising.restartOnDisconnect(false);
    Bluefruit.Advertising.stop();
    if (connectionHandle != BLE_CONN_HANDLE_INVALID) Bluefruit.disconnect(connectionHandle);
  }
  Serial.println("POWER OFF requested. Motor and BLE stopped. Release D0.");
}

void enterSystemOff() {
  // LOWのままSENSE_LOWで停止すると即復帰するため、必ず離してから停止する。
  if (digitalRead(BUTTON_PIN) == LOW) return;
  stopLocalTest();
  if (driverReady) {
    drv.setRealtimeValue(0);
    // DRV2605L MODE bit6=STANDBY。電源の物理遮断ではない。
    drv.setMode(0x40);
  }
  if (bluetoothReady) Bluefruit.autoConnLed(false);
  digitalWrite(LED_RED,HIGH);digitalWrite(LED_GREEN,HIGH);digitalWrite(LED_BLUE,HIGH);
  Wire.end();
  Serial.println("Entering System OFF. Press D0 to restart; reconnect from the iOS app.");
  // USBの切断通知を行う。USB給電中の消費電流・復帰条件は実機で別途確認する。
  TinyUSBDevice.detach();
  const uint32_t wakePin=digitalPinToPinName(BUTTON_PIN);
  nrf_gpio_cfg_sense_input(wakePin,NRF_GPIO_PIN_PULLUP,NRF_GPIO_PIN_SENSE_LOW);
  __DSB();__ISB();
  uint8_t softDeviceEnabled=0;
  sd_softdevice_is_enabled(&softDeviceEnabled);
  if (softDeviceEnabled) {
    // Bluefruit稼働中はSoftDevice APIを使う。通常はこの呼び出しから戻らない。
    sd_power_system_off();
  } else {
    NRF_POWER->SYSTEMOFF=1;
  }
  // デバッガ接続等でSystem OFFがエミュレートされても、処理や振動を再開しない。
  while (true) { __WFE(); }
}

void updatePowerButton() {
  const cane::PowerAction action=powerButton.update(digitalRead(BUTTON_PIN) == LOW,millis());
  if (action == cane::PowerAction::ShutdownRequested || action == cane::PowerAction::EnterSystemOff) {
    requestPowerOff();
  }
  if (powerOffRequested && powerButton.released()) enterSystemOff();
}

void loop() {
  updatePowerButton();
  if (powerOffRequested) { delay(2);return; }
  if (!driverReady || !bluetoothReady || queueFault) { delay(2);return; }
  if (queueOverflow.exchange(false)) {
    // 処理しきれない場合は古い危険指示を実行せず、停止してリセットを待つ。
    queueFault=true;stopLocalTest();control.reset();control.errors=2;
    publishStatus(millis());Bluefruit.Advertising.restartOnDisconnect(false);Bluefruit.Advertising.stop();
    if (connectionHandle != BLE_CONN_HANDLE_INVALID) Bluefruit.disconnect(connectionHandle);
    Serial.println("BLE event queue overflow. Motor stopped. Reset the board.");return;
  }
  // 受理済み指示を処理待ちイベントで延命させない。
  if (control.expire(millis())) { setMotor(false);statusPending=true;Serial.println("Command TTL expired. Motor stopped."); }
  CaneEvent event;
  // 1周の処理数を制限し、TTLと停止処理を必ず再評価する。
  for (uint8_t i=0;i<16 && xQueueReceive(eventQueue,&event,0) == pdTRUE;++i) handleEvent(event,millis());
  const uint32_t now=millis();
  if (control.expire(now)) { setMotor(false);statusPending=true;Serial.println("Command TTL expired. Motor stopped."); }
  if (!autoTestFinished && ENABLE_AUTO_TEST && uint32_t(now-readyTime) >= AUTO_TEST_DELAY_MS) {
    autoTestFinished=true;runVibrationPattern();
  }
  if (Serial.available()) {
    const char command=Serial.read();
    if (command == 't' || command == 'T') runVibrationPattern();
    else if (command == 's' || command == 'S') {
      stopRequested=true;stopLocalTest();control.reset();statusPending=true;
      // 接続も解除し、次の危険パケットによる即再駆動を防ぐ。
      if (connectionHandle != BLE_CONN_HANDLE_INVALID) Bluefruit.disconnect(connectionHandle);
    }
  }
  const uint32_t outputNow=millis();
  if (testRunning) updateLocalTest(outputNow);
  else setMotor(control.motorOn(outputNow));
  // Notify有効化直後や送信失敗時にも最新Statusを送れるよう1秒ごとに更新。
  if (statusPending || uint32_t(outputNow-lastStatusSent) >= 1000) publishStatus(outputNow);
  delay(2);
}

#endif
