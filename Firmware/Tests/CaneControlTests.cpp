#include "../CaneVibe/CaneControl.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include <initializer_list>

static void packet(uint8_t* out,cane::State state,uint16_t seq) {
  const uint8_t base[10]={1,uint8_t(state),uint8_t(seq),uint8_t(seq>>8),0xE8,3,0xFF,0xFF,0,0};
  memcpy(out,base,10);
}
int main() {
  cane::Control c;uint8_t p[10];
  // Swiftの共通例：危険、seq1、1000ms、1500mm。
  const uint8_t danger[10]={1,2,1,0,0xE8,3,0xDC,5,0,0};
  assert(c.receive(danger,10,100,100));assert(c.state == cane::Danger);assert(c.motorOn(100));
  assert(c.motorOn(219));assert(!c.motorOn(220));
  assert(!c.motorOn(319));assert(c.motorOn(320));
  assert(c.motorOn(439));assert(!c.motorOn(440));
  assert(!c.motorOn(539));assert(c.motorOn(540));
  assert(c.motorOn(659));assert(!c.motorOn(660));
  // 250msごとの再送では周期の位相をリセットしない。
  packet(p,cane::Danger,2);assert(c.receive(p,10,350,350));assert(c.motorOn(350));
  packet(p,cane::Danger,3);assert(c.receive(p,10,600,600));assert(c.motorOn(600));
  packet(p,cane::Danger,4);assert(c.receive(p,10,850,850));assert(c.motorOn(1100));
  assert(!c.expire(1849));assert(c.expire(1850));assert(c.state == cane::Unavailable);
  assert(c.errors & 1);assert(!c.motorOn(1850));
  packet(p,cane::Danger,5);assert(c.receive(p,10,1900,1900));assert(c.errors == 0);assert(c.motorOn(1900));
  // 検出なし・検知不能は即停止。
  packet(p,cane::Clear,6);assert(c.receive(p,10,1950,1950));assert(!c.motorOn(1950));
  packet(p,cane::Unavailable,7);assert(c.receive(p,10,2000,2000));assert(!c.motorOn(2000));
  // 注意は300ms ON、1700ms OFF。
  packet(p,cane::Caution,8);assert(c.receive(p,10,2100,2100));assert(c.motorOn(2399));assert(!c.motorOn(2400));
  packet(p,cane::Caution,9);assert(c.receive(p,10,2900,2900));
  packet(p,cane::Caution,10);assert(c.receive(p,10,3700,3700));assert(c.motorOn(4100));
  // 250ms再送を継続しながら、2周期の各ミリ秒を検証。
  // パケット更新で位相がずれたり、4発目が出たりしないことを確認。
  for (cane::State state : {cane::Caution,cane::Danger}) {
    c.reset();uint16_t seq=0;
    for (uint32_t t=0;t<4000;++t) {
      if (t % 250 == 0) { packet(p,state,seq++);assert(c.receive(p,10,t,t)); }
      const uint32_t phase=t % 1000;
      const bool expected=state == cane::Caution ? t % 2000 < 300 :
          phase < 120 || (phase >= 220 && phase < 340) || (phase >= 440 && phase < 560);
      assert(c.motorOn(t) == expected);
    }
  }
  // 状態変更時は次の周期を待たず先頭から開始。解除・resetは即停止。
  c.reset();packet(p,cane::Caution,1);assert(c.receive(p,10,0,0));assert(!c.motorOn(500));
  packet(p,cane::Danger,2);assert(c.receive(p,10,500,500));assert(c.motorOn(500));
  packet(p,cane::Caution,3);assert(c.receive(p,10,700,700));assert(c.motorOn(700));
  c.reset();assert(!c.motorOn(701));
  // TTL直前に振動中でも、期限に達した瞬間にmotorOnがfalseになる。
  packet(p,cane::Danger,1);assert(c.receive(p,10,0,0));
  packet(p,cane::Danger,2);assert(c.receive(p,10,50,50));
  assert(c.motorOn(1049));assert(!c.motorOn(1050));assert(c.expire(1050));
  // 重複・古いseqは受理せず、TTLも延命しない。
  c.reset();packet(p,cane::Danger,100);assert(c.receive(p,10,100,100));
  assert(!c.receive(p,10,900,900));packet(p,cane::Danger,99);assert(!c.receive(p,10,950,950));
  assert(c.expire(1100));assert(!c.motorOn(1100));
  // seqの周回と接続ごとの初期化。
  c.reset();packet(p,cane::Danger,65535);assert(c.receive(p,10,10,10));
  packet(p,cane::Danger,0);assert(c.receive(p,10,20,20));
  packet(p,cane::Danger,32768);assert(!c.receive(p,10,30,30));
  c.reset();assert(!c.motorOn(30));packet(p,cane::Danger,0);assert(c.receive(p,10,40,40));
  // 不正長・版・state・TTL・予約ビット/バイト・距離は状態を変更しない。
  for (unsigned i=0;i<7;++i) {
    c.reset();packet(p,cane::Clear,1);
    size_t len=10;
    if (i==0) len=9;
    if (i==1) p[0]=2;
    if (i==2) p[1]=4;
    if (i==3) p[4]=0;
    if (i==4) p[8]=4;
    if (i==5) p[9]=1;
    if (i==6) p[6]=0;
    assert(!c.receive(p,len,10,10));assert(c.state == cane::Unavailable);assert(c.errors == 2);
    assert(!c.motorOn(10));
  }
  // キューに溜まっていた古い指示は駆動に使用しない。
  c.reset();packet(p,cane::Danger,1);assert(!c.receive(p,10,100,1100));assert(!c.motorOn(1100));
  // millis()周回前後もTTLは経過時間で判定。
  c.reset();packet(p,cane::Danger,1);assert(c.receive(p,10,0xFFFFFF00u,0xFFFFFF00u));
  assert(!c.expire(743));assert(c.expire(744));assert(!c.motorOn(744));
  // StatusはSwiftの復号形式と同一。GPIO3は未使用で0。
  c.reset();packet(p,cane::Danger,0x1234);assert(c.receive(p,10,0,0));
  uint8_t status[10];c.status(status,0x12345678);
  const uint8_t expected[10]={1,2,0,0,0x34,0x12,0x78,0x56,0x34,0x12};
  assert(memcmp(status,expected,10)==0);
  puts("CaneControl tests passed: packet validation, sequence, TTL, motor phases, status.");
}
