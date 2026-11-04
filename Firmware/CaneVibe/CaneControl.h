#pragma once
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
