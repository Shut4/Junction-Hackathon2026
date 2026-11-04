#define CANE_POWER_BUTTON_TEST
#include "../CaneVibePower/CaneVibePower.ino"
#include <assert.h>
#include <stdio.h>
using cane::PowerAction;

static void arm(cane::PowerButton& button,uint32_t now=0) {
  assert(button.update(false,now) == PowerAction::None);
  assert(button.update(false,now+30) == PowerAction::None);
  assert(button.released());
}
int main() {
  cane::PowerButton button;arm(button);
  // 通常の1回押しで停止要求。離した後でSystem OFFへ進む。
  assert(button.update(true,100) == PowerAction::None);
  assert(button.update(true,129) == PowerAction::None);
  assert(button.update(true,130) == PowerAction::ShutdownRequested);
  assert(!button.released());
  assert(button.update(false,300) == PowerAction::None);
  assert(button.update(false,329) == PowerAction::None);
  assert(button.update(false,330) == PowerAction::EnterSystemOff);
  assert(button.released());
  // 押しっぱなしでも停止要求を繰り返さず、離すまではSystem OFFにしない。
  cane::PowerButton held;arm(held);
  assert(held.update(true,100) == PowerAction::None);
  assert(held.update(true,130) == PowerAction::ShutdownRequested);
  assert(held.update(true,2000) == PowerAction::None);
  assert(held.update(true,10000) == PowerAction::None);
  assert(!held.released());
  // 復帰に使用した押下で直ちにOFFへ戻らない。一度離した後の次の押下でOFF。
  cane::PowerButton waking;
  assert(waking.update(true,0) == PowerAction::None);
  assert(waking.update(true,30) == PowerAction::None);
  assert(waking.update(true,5000) == PowerAction::None);
  assert(waking.update(false,5100) == PowerAction::None);
  assert(waking.update(false,5130) == PowerAction::None);
  assert(waking.update(true,5200) == PowerAction::None);
  assert(waking.update(true,5230) == PowerAction::ShutdownRequested);
  // 30ms未満のチャタリングでは停止しない。
  cane::PowerButton noisy;arm(noisy);
  assert(noisy.update(true,100) == PowerAction::None);
  assert(noisy.update(false,120) == PowerAction::None);
  assert(noisy.update(false,2000) == PowerAction::None);
  assert(noisy.released());
  // millis()の周回をまたいでも押下・離す判定が正常。
  cane::PowerButton wrapping;arm(wrapping,0xFFFFFE00u);
  assert(wrapping.update(true,0xFFFFFFF0u) == PowerAction::None);
  assert(wrapping.update(true,14) == PowerAction::ShutdownRequested);
  assert(wrapping.update(false,20) == PowerAction::None);
  assert(wrapping.update(false,50) == PowerAction::EnterSystemOff);
  puts("Power button tests passed: one-press OFF, release gating, wake-press suppression, debounce, rollover.");
}
