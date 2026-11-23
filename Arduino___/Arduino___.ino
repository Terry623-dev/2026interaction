// === AEGIS-HIL v4.3 // MakerUNO Telemetry + 《說了再見》鋼琴譜精準版 (D Major, 124 BPM) ===
// Baud: 115200 | Protocol: $TLM,...*CHK

#include <avr/pgmspace.h>

const int BTN_PIN = 2;
const int BUZZER_PIN = 8;
const int LED_COUNT = 10;
const int ledPins[LED_COUNT] = {13, 12, 11, 10, 9, 7, 6, 5, 4, 3}; // USB 朝左，由左至右 1:1 對應

const int STATE_WAIT   = 0;
const int STATE_STAGE1 = 1;
const int STATE_STAGE2 = 2;
const int STATE_STAGE3 = 3;
const int STATE_WIN    = 4;
const int STATE_LOSE   = 5;

// === D 大調精準音高表 (Hz)，對應譜上 F# 與 C# ===
#define N_R    0
#define N_C4S  277
#define N_D4   294
#define N_E4   330
#define N_F4S  370
#define N_G4   392
#define N_A4   440
#define N_B4   494
#define N_C5S  554
#define N_D5   587
#define N_E5   659
#define N_F5S  740
#define N_G5   784
#define N_A5   880

// ♩ = 124 BPM 基準時值 (ms)
// 16分=121, 8分=242, 4分=484, 附點4分(8+4)=726, 2分=968, 8+2分=1210, 8+附點2分=1694
struct Note {
  uint16_t freq;
  uint16_t dur;
};

// 對應鋼琴譜第 1 頁 M2 ~ M17 右手主旋律 (存於 Flash PROGMEM 省 SRAM)
const Note WIN_SONG[] PROGMEM = {
  // M2 ~ M3：天涼了 雨下了 妳走了
  {N_A4,  484}, {N_D5,  484}, {N_C5S, 242}, {N_D5,  726},
  {N_D5,  242}, {N_D5,  726}, {N_D5,  242}, {N_C5S, 726},

  // M4 ~ M6：清楚了 我愛的 遺失了
  {N_C5S, 242}, {N_E5,  726}, {N_B4,  242}, {N_A4, 1210},
  {N_E4,  484}, {N_C4S, 484},
  {N_D4,  484}, {N_A4,  484}, {N_D5,  484}, {N_E5,  484},

  // M7 ~ M9：落葉飄在湖面上睡著了 (+ 鋼琴過門)
  {N_F5S, 484}, {N_F5S, 242}, {N_F5S, 726}, {N_F5S, 242}, {N_F5S, 726},
  {N_E5,  242}, {N_F5S, 726}, {N_G5,  242}, {N_F5S, 1210},
  {N_B4,  968},

  // M10 ~ M12：想要放 放不掉 淚在飄
  {N_A4,  484}, {N_E5,  484}, {N_F5S, 484}, {N_E5,  484},
  {N_A5,  968}, {N_A5,  121}, {N_G5,  121}, {N_F5S, 242}, {N_F5S, 242}, {N_E5, 1694},
  {N_E5,  242}, {N_E5,  242},

  // M13 ~ M14
  {N_D5,  484}, {N_E5,  242}, {N_F5S, 726}, {N_B4,  242}, {N_D5, 1210},
  {N_G4,  484}, {N_A4,  484},

  // M15 ~ M17 結尾收在主音 D5
  {N_A4,  484}, {N_D5,  242}, {N_D5,  726}, {N_F5S, 242}, {N_E5,  726},
  {N_D5,  242}, {N_D5,  726}, {N_C5S, 242}, {N_D5, 1450}
};
const int WIN_SONG_LEN = sizeof(WIN_SONG) / sizeof(WIN_SONG[0]);

// 非阻斷音樂播放器狀態
bool winSongPlaying = false;
int winNoteIdx = 0;
unsigned long nextNoteAt = 0;

// === 遊戲狀態與參數 ===
int difficulty = 2;
long totalTime = 30000;
int stage1Speed = 105, stage1Width = 3;
int stage2Drain = 620;
int stage3Speed = 65, stage3Width = 2;

int gameState = STATE_WAIT;
unsigned long startTime = 0;
unsigned long stateEnterTime = 0;
long penaltyMs = 0;
long remainingMs = 30000;

int lastBtnState = HIGH;
unsigned long lastPressTime = 0;

int scanPos = 0, scanDir = 1, charge = 0;
int targetStart = 3, targetEnd = 6;
int pendingEvent = 0;

// 底層硬體遙測變數
unsigned long seqCounter = 0;
unsigned int currentLedMask = 0;
long cachedVccMv = 5000;
unsigned long lastLoopUs = 120;
int activeBuzFreq = 0;
unsigned long buzEndAt = 0;

unsigned long lastScanTime = 0;
unsigned long lastDrainTime = 0;
unsigned long lastTickTime = 0;
unsigned long lastSerialTime = 0;
unsigned long lastVccTime = 0;
unsigned long muteTickUntil = 0;

extern int __heap_start, *__brkval;
int getFreeRam() {
  int v;
  return (int)&v - (__brkval == 0 ? (int)&__heap_start : (int)__brkval);
}

long readVccMv() {
  ADMUX = _BV(REFS0) | _BV(MUX3) | _BV(MUX2) | _BV(MUX1);
  delay(2);
  ADCSRA |= _BV(ADSC);
  while (bit_is_set(ADCSRA, ADSC));
  uint8_t low  = ADCL;
  uint8_t high = ADCH;
  long result = (high << 8) | low;
  if (result == 0) return 5000;
  return 1125300L / result;
}

void playTone(int freq, unsigned long dur) {
  if (freq > 0) {
    tone(BUZZER_PIN, freq, dur);
    activeBuzFreq = freq;
    buzEndAt = millis() + dur;
  } else {
    noTone(BUZZER_PIN);
    activeBuzFreq = 0;
  }
}

void setLed(int idx, int state) {
  digitalWrite(ledPins[idx], state);
  if (state == HIGH) currentLedMask |= (1U << idx);
  else currentLedMask &= ~(1U << idx);
}

void setAllLeds(int state) {
  for (int i = 0; i < LED_COUNT; i++) setLed(i, state);
}

void setup() {
  Serial.begin(115200);
  pinMode(BTN_PIN, INPUT_PULLUP);
  pinMode(BUZZER_PIN, OUTPUT);
  for (int i = 0; i < LED_COUNT; i++) {
    pinMode(ledPins[i], OUTPUT);
    setLed(i, LOW);
  }
  cachedVccMv = readVccMv();
  applyDifficulty(2);
}

void loop() {
  unsigned long loopStartUs = micros();
  unsigned long now = millis();
  bool sampledVcc = false;

  if (activeBuzFreq > 0 && now >= buzEndAt) {
    activeBuzFreq = 0;
  }

  if (now - lastVccTime >= 500) {
    lastVccTime = now;
    cachedVccMv = readVccMv();
    sampledVcc = true;
  }

  checkSerialCommands(now);
  bool pressed = checkButtonPressed(now);

  if (gameState >= STATE_STAGE1 && gameState <= STATE_STAGE3) {
    remainingMs = totalTime - (long)(now - startTime) - penaltyMs;
    if (remainingMs <= 0) {
      remainingMs = 0;
      triggerLose(now);
      return;
    }
    updateBombTick(now);
  }

  switch (gameState) {
    case STATE_WAIT:
      runIdleAnimation(now);
      if (pressed) startGame(now);
      break;

    case STATE_STAGE1:
      updateScanner(now, stage1Speed);
      if (pressed) {
        if (scanPos >= targetStart && scanPos <= targetEnd) advanceStage(STATE_STAGE2, now);
        else applyPenalty(now);
      }
      break;

    case STATE_STAGE2:
      if (pressed) {
        charge++;
        playTone(420 + charge * 75, 45);
        muteTickUntil = now + 80;
        if (charge >= LED_COUNT) {
          charge = LED_COUNT;
          advanceStage(STATE_STAGE3, now);
          break;
        }
      }
      if (now - lastDrainTime >= (unsigned long)stage2Drain) {
        lastDrainTime = now;
        if (charge > 0) charge--;
      }
      showChargeBar(charge);
      break;

    case STATE_STAGE3:
      updateScanner(now, stage3Speed);
      if (pressed) {
        if (scanPos >= targetStart && scanPos <= targetEnd) triggerWin(now);
        else applyPenalty(now);
      }
      break;

    case STATE_WIN:
      updateWinSongAndLeds(now);
      if (pressed && (now - stateEnterTime > 1500)) resetToWait(now);
      break;

    case STATE_LOSE:
      runLoseAnimation(now);
      if (pressed && (now - stateEnterTime > 1500)) resetToWait(now);
      break;
  }

  if (now - lastSerialTime >= 33) {
    lastSerialTime = now;
    sendTelemetry();
  }

  if (!sampledVcc) {
    lastLoopUs = micros() - loopStartUs;
  }
}

void checkSerialCommands(unsigned long now) {
  while (Serial.available() > 0) {
    char cmd = Serial.read();
    if ((cmd == '1' || cmd == '2' || cmd == '3') && gameState == STATE_WAIT) {
      applyDifficulty(cmd - '0');
      playTone(650 + difficulty * 180, 60);
      sendTelemetry();
    } else if (cmd == 'R' || cmd == 'r') {
      resetToWait(now);
    }
  }
}

void applyDifficulty(int level) {
  difficulty = level;
  if (level == 1) {
    totalTime = 35000; stage1Speed = 135; stage1Width = 4;
    stage2Drain = 800; stage3Speed = 85;  stage3Width = 2;
  } else if (level == 2) {
    totalTime = 30000; stage1Speed = 105; stage1Width = 3;
    stage2Drain = 620; stage3Speed = 65;  stage3Width = 2;
  } else {
    totalTime = 22000; stage1Speed = 80;  stage1Width = 3;
    stage2Drain = 480; stage3Speed = 50;  stage3Width = 1;
  }
  remainingMs = totalTime;
}

void randomizeTarget(int width) {
  int minPos = (width <= 2) ? 2 : 1;
  int maxPos = LED_COUNT - width;
  if (maxPos <= minPos) maxPos = minPos + 1;
  targetStart = random(minPos, maxPos);
  targetEnd = targetStart + width - 1;
}

bool checkButtonPressed(unsigned long now) {
  int reading = digitalRead(BTN_PIN);
  bool triggered = false;
  if (lastBtnState == HIGH && reading == LOW && (now - lastPressTime > 55)) {
    triggered = true;
    lastPressTime = now;
  }
  lastBtnState = reading;
  return triggered;
}

void startGame(unsigned long now) {
  randomSeed(analogRead(A0) + micros());
  winSongPlaying = false;
  gameState = STATE_STAGE1;
  startTime = now;
  penaltyMs = 0;
  remainingMs = totalTime;
  scanPos = 0; scanDir = 1; charge = 0;
  randomizeTarget(stage1Width);
  lastScanTime = now;
  lastTickTime = now;
  playTone(1000, 110);
  muteTickUntil = now + 200;
  sendTelemetry();
}

void advanceStage(int nextStage, unsigned long now) {
  gameState = nextStage;
  scanPos = 0; scanDir = 1; charge = 0;
  lastScanTime = now;
  lastDrainTime = now;
  if (nextStage == STATE_STAGE3) randomizeTarget(stage3Width);
  pendingEvent = 1;
  sendTelemetry();

  playTone(880, 80); delay(90);
  playTone(1320, 120); delay(130);
  muteTickUntil = millis() + 150;
}

void applyPenalty(unsigned long now) {
  penaltyMs += 3000;
  pendingEvent = 2;
  playTone(175, 220);
  muteTickUntil = now + 260;
  sendTelemetry();
}

void triggerWin(unsigned long now) {
  gameState = STATE_WIN;
  stateEnterTime = now;
  pendingEvent = 3;
  winSongPlaying = true;
  winNoteIdx = 0;
  nextNoteAt = now + 140;
  noTone(BUZZER_PIN);
  activeBuzFreq = 0;
  sendTelemetry();
}

void updateWinSongAndLeds(unsigned long now) {
  if (winSongPlaying) {
    if (now >= nextNoteAt) {
      if (winNoteIdx >= WIN_SONG_LEN) {
        winSongPlaying = false;
        noTone(BUZZER_PIN);
        activeBuzFreq = 0;
        return;
      }
      uint16_t f = pgm_read_word(&WIN_SONG[winNoteIdx].freq);
      uint16_t d = pgm_read_word(&WIN_SONG[winNoteIdx].dur);

      if (f > 0) {
        // 留 12% 氣口讓重複音與連音都有鋼琴顆粒感
        playTone(f, (unsigned long)(d * 0.88));
        int bars = map(constrain(f, 277, 880), 277, 880, 1, LED_COUNT);
        showChargeBar(bars);
      } else {
        noTone(BUZZER_PIN);
        activeBuzFreq = 0;
        setAllLeds(LOW);
      }
      nextNoteAt = now + d;
      winNoteIdx++;
    }
  } else {
    bool on = ((now / 220) % 2) == 0;
    for (int i = 0; i < LED_COUNT; i++) setLed(i, ((i % 2 == 0) == on) ? HIGH : LOW);
  }
}

void triggerLose(unsigned long now) {
  winSongPlaying = false;
  gameState = STATE_LOSE;
  stateEnterTime = now;
  pendingEvent = 4;
  sendTelemetry();

  for (int i = 0; i < 3; i++) {
    setAllLeds(HIGH);
    playTone(220, 170); delay(190);
    setAllLeds(LOW);
    playTone(110, 170); delay(190);
  }
  noTone(BUZZER_PIN);
  activeBuzFreq = 0;
}

void resetToWait(unsigned long now) {
  winSongPlaying = false;
  noTone(BUZZER_PIN);
  activeBuzFreq = 0;
  gameState = STATE_WAIT;
  remainingMs = totalTime;
  setAllLeds(LOW);
  playTone(600, 80);
  sendTelemetry();
}

void updateScanner(unsigned long now, int interval) {
  if (now - lastScanTime >= (unsigned long)interval) {
    lastScanTime = now;
    scanPos += scanDir;
    if (scanPos >= LED_COUNT - 1) { scanPos = LED_COUNT - 1; scanDir = -1; }
    else if (scanPos <= 0) { scanPos = 0; scanDir = 1; }
  }
  for (int i = 0; i < LED_COUNT; i++) setLed(i, i == scanPos ? HIGH : LOW);
}

void showChargeBar(int level) {
  for (int i = 0; i < LED_COUNT; i++) setLed(i, i < level ? HIGH : LOW);
}

void updateBombTick(unsigned long now) {
  if (now < muteTickUntil) return;
  unsigned long tickInterval = 1000;
  int freq = 1000;
  if (remainingMs < 7000) { tickInterval = 210; freq = 1650; }
  else if (remainingMs < 15000) { tickInterval = 480; freq = 1280; }
  if (now - lastTickTime >= tickInterval) {
    lastTickTime = now;
    playTone(freq, 35);
  }
}

void runIdleAnimation(unsigned long now) {
  scanPos = (now / 130) % LED_COUNT;
  for (int i = 0; i < LED_COUNT; i++) setLed(i, i == scanPos ? HIGH : LOW);
}

void runLoseAnimation(unsigned long now) {
  setAllLeds(((now / 110) % 2 == 0) ? HIGH : LOW);
}

void sendTelemetry() {
  char payload[96];
  int val = (gameState == STATE_STAGE2) ? charge : scanPos;
  int btnActive = (digitalRead(BTN_PIN) == LOW) ? 1 : 0;

  snprintf(payload, sizeof(payload),
           "TLM,%lu,%d,%ld,%d,%d,%d,%d,%d,%ld,%lu,%d,%X,%d,%d",
           seqCounter++, gameState, remainingMs, val,
           targetStart, targetEnd, difficulty, pendingEvent,
           cachedVccMv, lastLoopUs, getFreeRam(), currentLedMask,
           btnActive, activeBuzFreq);

  uint8_t chk = 0;
  for (int i = 0; payload[i] != '\0'; i++) chk ^= (uint8_t)payload[i];

  Serial.print('$');
  Serial.print(payload);
  Serial.print('*');
  if (chk < 0x10) Serial.print('0');
  Serial.println(chk, HEX);

  pendingEvent = 0;
}
