import processing.serial.*;

Serial myPort;
boolean serialConnected = false;
PFont monoFont;
PFont cjkFont;

// === Thread-safe 序列埠同步變數 ===
volatile int r_seq = 0;
volatile int r_state = 0;
volatile int r_remMs = 30000;
volatile int r_val = 0;
volatile int r_tStart = 3;
volatile int r_tEnd = 6;
volatile int r_diff = 2;
volatile int r_evt = 0;
volatile int r_vccMv = 5000;
volatile int r_loopUs = 0;
volatile int r_freeRam = 0;
volatile int r_ledMask = 0;
volatile int r_btn = 0;
volatile int r_buzFreq = 0;
volatile int r_pktOk = 0;
volatile int r_pktErr = 0;
volatile int r_rxPulse = 0;
volatile String r_rawFrame = "$TLM,WAITING_FOR_ATMEGA328P*00";

// === 主執行緒狀態與統計 ===
int gameState = 0, prevGameState = 0, highestStage = 0;
int remainingMs = 30000, val = 0, targetStart = 3, targetEnd = 6, difficulty = 2;
int vccMv = 5000, loopUs = 0, freeRam = 0, ledMask = 0, btnActive = 0, buzFreq = 0;
int bestRemainingMs = -1;
int totalHits = 0, totalMisses = 0, fsmTransitions = 0;
int txPulse = 0;

int lastHzCheckMs = 0, lastPktSnapshot = 0;
float measuredHz = 0.0;

// === 人物情緒互動引擎 (OPERATOR NOVA) ===
// mood: 0=冷靜, 1=興奮誇獎, 2=緊張(<12s), 3=極度恐慌(<7s), 4=驚嚇扣秒, 5=大勝歡呼, 6=爆炸暈眩
int charMood = 0;
int moodOverrideUntil = 0;
boolean warned12s = false;
boolean warned7s = false;
float operatorBpm = 72.0;

String currentDialogue = "";
float shownChars = 0;
int lastBlinkMs = 0;
float blinkAmount = 0;
float sweatDropY = 0;

// 高情緒價值隨機台詞庫
final String[] LINES_IDLE = {
  "指揮官，系統就緒了！深呼吸，我相信你一定拆得掉。準備好就按 Pin 2 吧！",
  "已經同步 MakerUNO 訊號囉～今天也來刷個讓全場尖叫的新紀錄吧！",
  "別緊張，我在通訊頻道全程陪著你！選好難度按下 Pin 2 就能出發。"
};
final String[] LINES_STAGE1 = {
  "倒數啟動！盯緊綠色鎖定框，別急，你的節奏一直都很穩的！",
  "第一條黃線交給你了！看準光點進綠框就果斷按下去，你可以的！"
};
final String[] LINES_STAGE2 = {
  "漂亮！！第一條線秒斷！指揮官你也太帥了吧！快狂按 Pin 2 灌滿能量！",
  "水啦！這反應速度根本神人等級！接著連按別停，把 10 顆燈全衝滿！"
};
final String[] LINES_STAGE3 = {
  "天啊手速超快！！只剩最後一條核心紅線了，深呼吸、一擊必殺！",
  "太強了吧！最後一關速度會變快，相信你的直覺，你一定能成功！"
};
final String[] LINES_WARN12 = {
  "時間剩不到 12 秒囉！別慌別慌，專心看燈號，還有時間的！",
  "只剩 12 秒了！我在這裡幫你盯著數據，穩住手速沒問題的！"
};
final String[] LINES_PANIC7 = {
  "啊啊啊只剩不到 7 秒了！！快快快！我心臟快跳出來了啦！！",
  "要炸了要炸了！！指揮官撐住啊！！快抓準時機按下去拜託！！"
};
final String[] LINES_MISS = {
  "嗚哇按歪了！扣 3 秒了啦！沒事沒事別被嚇到，下一次一定中！",
  "哎呀差一點點！快深呼吸穩住節奏，你還是來得及的，加油！"
};
final String[] LINES_WIN = {
  "太神啦！！拆彈成功！！你真的是我見過最靠譜、最帥的拆彈專家！！",
  "拆掉了！！嗚嗚剛剛緊張死我了，指揮官你真的超強，滿分過關！！"
};
final String[] LINES_LOSE = {
  "轟——！炸、炸掉了啦...咳咳，沒關係！你剛剛其實很棒了，再來雪恥！",
  "嗚嗚差一點點就拆掉了...拍拍灰塵別灰心，按 Pin 2 我們下一局一定贏！"
};

// === 12 通道邏輯分析儀 ===
final int LA_LEN = 180;
int[][] laBuf = new int[12][LA_LEN];
int laHead = 0, laDivider = 0;
String[] laNames = {"D2_BTN", "D8_BUZ", "D13", "D12", "D11", "D10", "D09", "D07", "D06", "D05", "D04", "D03"};
String[] pinLabels = {"13", "12", "11", "10", "9", "7", "6", "5", "4", "3"};

// === 3D 二十面體核心 ===
PVector[] icoVerts = new PVector[12];
ArrayList<int[]> icoEdges = new ArrayList<int[]>();
float rotX = 0.3, rotY = 0.5, rotZ = 0.0, corePulse = 0;

// === 特效 ===
float shakeMag = 0, redFlash = 0, greenFlash = 0, glitchTimer = 0;
float penaltyAlpha = 0, penaltyY = 0, buzzerWave = 0;
float[] ledGlow = new float[10];
ArrayList<Particle> particles = new ArrayList<Particle>();
ArrayList<Shockwave> shockwaves = new ArrayList<Shockwave>();

final boolean[][] SEG_MAP = {
  {true,  true,  true,  true,  true,  true,  false},
  {false, true,  true,  false, false, false, false},
  {true,  true,  false, true,  true,  false, true },
  {true,  true,  true,  true,  false, false, true },
  {false, true,  true,  false, false, true,  true },
  {true,  false, true,  true,  false, true,  true },
  {true,  false, true,  true,  true,  true,  true },
  {true,  true,  true,  false, false, false, false},
  {true,  true,  true,  true,  true,  true,  true },
  {true,  true,  true,  true,  false, true,  true }
};

void setup() {
  size(1280, 760);
  frameRate(60);
  monoFont = createFont("Monospaced", 24, true);
  cjkFont  = createFont("Microsoft JhengHei", 16, true);
  textFont(monoFont);
  smooth(4);

  init3DIcosahedron();
  try {
    myPort = new Serial(this, "COM3", 115200);
    myPort.bufferUntil('\n');
    serialConnected = true;
    sayDialogue(pickRandom(LINES_IDLE), 0, 0);
  } catch (Exception e) {
    serialConnected = false;
    sayDialogue("咦？我好像還沒連到 COM3 耶！指揮官幫我確認一下 USB 線跟埠號喔～", 4, 0);
  }
  lastHzCheckMs = millis();
  lastBlinkMs = millis();
}

void init3DIcosahedron() {
  float phi = (1.0 + sqrt(5.0)) * 0.5;
  float[][] raw = {
    {0,  1,  phi}, {0, -1,  phi}, {0,  1, -phi}, {0, -1, -phi},
    { 1,  phi, 0}, {-1,  phi, 0}, { 1, -phi, 0}, {-1, -phi, 0},
    { phi, 0,  1}, { phi, 0, -1}, {-phi, 0,  1}, {-phi, 0, -1}
  };
  for (int i = 0; i < 12; i++) {
    PVector v = new PVector(raw[i][0], raw[i][1], raw[i][2]);
    v.normalize();
    icoVerts[i] = v;
  }
  for (int i = 0; i < 12; i++) {
    for (int j = i + 1; j < 12; j++) {
      if (PVector.dist(icoVerts[i], icoVerts[j]) < 1.2) icoEdges.add(new int[]{i, j});
    }
  }
}

void draw() {
  syncTelemetryAndEvents();
  sampleLogicAnalyzer();
  updateCharacterAnimation();

  pushMatrix();
  if (shakeMag > 0.25) {
    translate(random(-shakeMag, shakeMag), random(-shakeMag, shakeMag));
    shakeMag *= 0.85;
  } else {
    shakeMag = 0;
  }

  drawBlueprintBackground();
  drawTopTelemetryBar();
  draw3DCorePanel();
  drawFsmAndWirePanel();
  drawChronoPanel();
  drawLogicAnalyzerPanel();
  drawOperatorCommsPanel();
  drawPacketFooterPanel();
  drawMakerUnoHardwareDeck();
  updateAndDrawShockwaves();
  updateAndDrawParticles();
  drawPenaltyPopup();
  popMatrix();

  drawPostOverlays();
}

color getAccentColor() {
  if (gameState == 4) return color(0, 235, 145);
  if (gameState == 5) return color(255, 42, 72);
  if (gameState >= 1 && gameState <= 3) {
    if (remainingMs < 7000) return color(255, 42, 72);
    if (remainingMs < 15000) return color(255, 165, 30);
    return color(255, 200, 45);
  }
  return color(0, 220, 255);
}

void sayDialogue(String line, int mood, int holdMs) {
  currentDialogue = line;
  shownChars = 0;
  charMood = mood;
  moodOverrideUntil = (holdMs > 0) ? (millis() + holdMs) : 0;
}

String pickRandom(String[] arr) {
  return arr[int(random(arr.length))];
}

void syncTelemetryAndEvents() {
  gameState = r_state;
  remainingMs = r_remMs;
  val = r_val;
  targetStart = r_tStart;
  targetEnd = r_tEnd;
  difficulty = r_diff;
  vccMv = r_vccMv;
  loopUs = r_loopUs;
  freeRam = r_freeRam;
  ledMask = r_ledMask;
  btnActive = r_btn;
  buzFreq = r_buzFreq;

  int now = millis();
  if (now - lastHzCheckMs >= 1000) {
    int okNow = r_pktOk;
    measuredHz = (okNow - lastPktSnapshot) * 1000.0 / (now - lastHzCheckMs);
    lastPktSnapshot = okNow;
    lastHzCheckMs = now;
  }

  if (buzFreq > 0) {
    buzzerWave = max(buzzerWave, 0.95);
    corePulse = max(corePulse, 0.75);
  }
  buzzerWave *= 0.88;
  corePulse *= 0.90;
  if (r_rxPulse > 0) r_rxPulse--;
  if (txPulse > 0) txPulse--;
  if (glitchTimer > 0) glitchTimer--;

  // 狀態切換時觸發人物台詞與情緒
  if (gameState != prevGameState) {
    fsmTransitions++;
    if (gameState == 0) {
      highestStage = 0;
      warned12s = false;
      warned7s = false;
      sayDialogue(pickRandom(LINES_IDLE), 0, 0);
    } else if (gameState == 1) {
      highestStage = 1;
      warned12s = false;
      warned7s = false;
      sayDialogue(pickRandom(LINES_STAGE1), 0, 0);
      shockwaves.add(new Shockwave(622, 170, color(255, 200, 45), 340));
    } else if (gameState == 2) {
      highestStage = max(highestStage, 2);
      totalHits++;
      sayDialogue(pickRandom(LINES_STAGE2), 1, 2400);
    } else if (gameState == 3) {
      highestStage = max(highestStage, 3);
      totalHits++;
      sayDialogue(pickRandom(LINES_STAGE3), 1, 2200);
    } else if (gameState == 4) {
      highestStage = 4;
      totalHits++;
      if (remainingMs > bestRemainingMs) bestRemainingMs = remainingMs;
      String winMsg = "太神啦！！還剩 " + nf(remainingMs / 1000.0, 2, 2) + " 秒拆彈成功！指揮官你剛剛真的超帥、滿分過關！！";
      sayDialogue(random(1) > 0.5 ? winMsg : pickRandom(LINES_WIN), 5, 0);
    } else if (gameState == 5) {
      sayDialogue(pickRandom(LINES_LOSE), 6, 0);
    }
    prevGameState = gameState;
  }

  // 倒數危急時刻自動觸發緊張 / 恐慌反應
  if (gameState >= 1 && gameState <= 3) {
    if (remainingMs < 7000 && !warned7s) {
      warned7s = true;
      sayDialogue(pickRandom(LINES_PANIC7), 3, 0);
    } else if (remainingMs < 12000 && remainingMs >= 7000 && !warned12s) {
      warned12s = true;
      sayDialogue(pickRandom(LINES_WARN12), 2, 0);
    }
  }

  // 推播事件特效
  int evt = r_evt;
  r_evt = 0;
  if (evt == 1) {
    greenFlash = 75;
    spawnBurst(1084, 210, 26, color(0, 245, 165), 5.5);
    shockwaves.add(new Shockwave(1084, 210, color(0, 235, 145), 220));
  } else if (evt == 2) {
    totalMisses++;
    shakeMag = 18;
    redFlash = 145;
    glitchTimer = 12;
    penaltyAlpha = 255;
    penaltyY = 180;
    int idx = constrain(val, 0, 9);
    spawnBurst(getLedX(idx), 664, 24, color(255, 45, 72), 5.2);
    shockwaves.add(new Shockwave(getLedX(idx), 664, color(255, 45, 72), 160));
    sayDialogue(pickRandom(LINES_MISS), 4, 1800);
  } else if (evt == 3) {
    greenFlash = 140;
    spawnBurst(1084, 210, 48, color(0, 245, 165), 7.5);
    spawnBurst(622, 180, 65, color(255, 225, 85), 8.5);
    shockwaves.add(new Shockwave(622, 180, color(0, 235, 145), 620));
  } else if (evt == 4) {
    shakeMag = 34;
    redFlash = 215;
    glitchTimer = 28;
    spawnBurst(width / 2, height / 2, 120, color(255, 75, 35), 12.5);
    spawnBurst(width / 2, height / 2, 60, color(255, 215, 75), 8.5);
    shockwaves.add(new Shockwave(width / 2, height / 2, color(255, 55, 45), 960));
  }

  for (int i = 0; i < 10; i++) {
    boolean lit = ((ledMask >> i) & 1) == 1;
    if (lit) ledGlow[i] = 1.0;
    else ledGlow[i] *= 0.76;
  }
}

void updateCharacterAnimation() {
  int now = millis();
  // 打字機速度
  if (shownChars < currentDialogue.length()) {
    shownChars = min(currentDialogue.length(), shownChars + 0.85);
  }

  // 短暫情緒結束後自動回歸當下局勢情緒
  if (moodOverrideUntil > 0 && now > moodOverrideUntil) {
    moodOverrideUntil = 0;
    if (gameState == 4) charMood = 5;
    else if (gameState == 5) charMood = 6;
    else if (gameState >= 1 && gameState <= 3) {
      if (remainingMs < 7000) charMood = 3;
      else if (remainingMs < 12000) charMood = 2;
      else charMood = 0;
    } else {
      charMood = 0;
    }
  }

  // 支援官即時心率 (BPM) 平滑變化
  float targetBpm = 72;
  if (charMood == 1) targetBpm = 112;
  else if (charMood == 2) targetBpm = 128;
  else if (charMood == 3) targetBpm = 168;
  else if (charMood == 4) targetBpm = 152;
  else if (charMood == 5) targetBpm = 104;
  else if (charMood == 6) targetBpm = 140;
  operatorBpm = lerp(operatorBpm, targetBpm + sin(now * 0.005) * 3.0, 0.06);

  // 自然眨眼
  if (now - lastBlinkMs > 3200) {
    blinkAmount = sin(constrain((now - lastBlinkMs - 3200) / 140.0, 0, 1) * PI);
    if (now - lastBlinkMs > 3350) {
      lastBlinkMs = now + int(random(-500, 1200));
      blinkAmount = 0;
    }
  } else {
    blinkAmount = 0;
  }

  // 緊張冷汗動畫
  sweatDropY = (sweatDropY + 0.55) % 24.0;
}

void sampleLogicAnalyzer() {
  laDivider++;
  if (laDivider % 2 != 0) return;
  laBuf[0][laHead] = btnActive;
  laBuf[1][laHead] = (buzFreq > 0) ? 1 : 0;
  for (int i = 0; i < 10; i++) laBuf[2 + i][laHead] = ((ledMask >> i) & 1);
  laHead = (laHead + 1) % LA_LEN;
}

// === 背景與情緒氣氛光 ===
void drawBlueprintBackground() {
  if (gameState == 5) {
    background((millis() / 130) % 2 == 0 ? color(28, 6, 10) : color(8, 5, 8));
  } else if (gameState == 4) {
    background(6, 16, 14);
  } else {
    background(7, 10, 16);
  }

  stroke(19, 28, 42, 120);
  strokeWeight(1);
  for (int x = 0; x < width; x += 32) line(x, 0, x, height);
  for (int y = 0; y < height; y += 32) line(0, y, width, y);

  stroke(42, 66, 94, 95);
  for (int x = 64; x < width; x += 128) {
    for (int y = 64; y < height; y += 128) {
      line(x - 4, y, x + 4, y);
      line(x, y - 4, x, y + 4);
    }
  }

  if ((gameState >= 1 && gameState <= 3 && remainingMs < 7000) || gameState == 5) {
    float p = 85 + 75 * sin(millis() * 0.016);
    drawHazardStripe(0, 0, width, 8, color(255, 42, 72, p));
    drawHazardStripe(0, height - 8, width, 8, color(255, 42, 72, p));
  }
}

void drawHazardStripe(float x, float y, float w, float h, color c) {
  noStroke();
  fill(c);
  float offset = (millis() * 0.06) % 24;
  for (float sx = x - 24 + offset; sx < x + w; sx += 24) {
    quad(sx, y + h, sx + 10, y + h, sx + 18, y, sx + 8, y);
  }
}

// === 頂部工程遙測列 ===
void drawTopTelemetryBar() {
  color acc = getAccentColor();
  drawTechPanel(16, 14, 1248, 46, color(11, 16, 25, 240), color(red(acc), green(acc), blue(acc), 130));

  noStroke();
  fill(acc);
  rect(26, 24, 4, 26);

  textFont(monoFont);
  textAlign(LEFT, CENTER);
  fill(235, 244, 255);
  textSize(16);
  text("AEGIS-HIL // ATMEGA328P + LIVE COMMS", 40, 36);

  int totalPkt = r_pktOk + r_pktErr;
  float crcPct = (totalPkt > 0) ? (r_pktOk * 100.0 / totalPkt) : 100.0;

  drawMetricChip(468, 22, 92,  30, "VCC",  nf(vccMv / 1000.0, 1, 2) + "V", color(179, 136, 255));
  drawMetricChip(568, 22, 96,  30, "LOOP", loopUs + "us",                 color(0, 220, 255));
  drawMetricChip(672, 22, 100, 30, "SRAM", freeRam + "B",                 color(0, 235, 145));
  drawMetricChip(780, 22, 114, 30, "LINK", nf(measuredHz, 0, 1) + "Hz " + int(crcPct) + "%", serialConnected ? color(0, 235, 145) : color(255, 65, 80));

  drawHudBtn(905,  22, 78, 30, "[1] L1",  difficulty == 1, color(0, 235, 145));
  drawHudBtn(991,  22, 78, 30, "[2] L2",  difficulty == 2, color(255, 200, 45));
  drawHudBtn(1077, 22, 78, 30, "[3] L3",  difficulty == 3, color(255, 42, 72));
  drawHudBtn(1163, 22, 86, 30, "[R] RST", false,           color(0, 220, 255));
}

void drawMetricChip(float x, float y, float w, float h, String k, String v, color c) {
  fill(14, 21, 33);
  stroke(38, 56, 80);
  strokeWeight(1);
  rect(x, y, w, h, 3);
  textAlign(LEFT, CENTER);
  fill(115, 140, 170);
  textSize(9);
  text(k, x + 6, y + 9);
  fill(c);
  textSize(12);
  text(v, x + 6, y + 22);
}

void drawHudBtn(float x, float y, float w, float h, String label, boolean active, color c) {
  boolean hover = (mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h);
  color bg = active ? color(red(c), green(c), blue(c), 65) :
             (hover ? color(red(c), green(c), blue(c), 32) : color(16, 23, 35));
  color brd = (active || hover) ? c : color(52, 70, 95);
  drawTechPanel(x, y, w, h, bg, brd);
  textAlign(CENTER, CENTER);
  textSize(12);
  fill((active || hover) ? color(255) : color(165, 185, 210));
  text(label, x + w / 2, y + h / 2);
}

// === 左上：3D 旋轉矩陣投影核心 ===
void draw3DCorePanel() {
  float px = 16, py = 72, pw = 324, ph = 238;
  color acc = getAccentColor();
  drawTechPanel(px, py, pw, ph, color(10, 15, 24, 240), color(38, 58, 84));
  drawPanelHeader(px, py, pw, "3D CORE MATRIX // R(x,y,z)", gameState == 4 ? "SAFE" : "ACTIVE", acc);

  float cx = px + pw / 2.0, cy = py + 132;
  float urgency = (gameState >= 1 && gameState <= 3) ? constrain(map(remainingMs, 30000, 0, 0.25, 1.0), 0.25, 1.0) : 0.12;
  float speed = (gameState == 4) ? 0.005 : (gameState == 5 ? 0.08 : 0.012 + urgency * 0.055);
  rotX += speed * 0.72; rotY += speed * 1.05; rotZ += speed * 0.35;

  noFill();
  stroke(28, 44, 66);
  strokeWeight(1);
  ellipse(cx, cy, 168, 168);
  ellipse(cx, cy, 110, 110);
  line(cx - 95, cy, cx + 95, cy);
  line(cx, cy - 88, cx, cy + 88);

  draw3DRing(cx, cy, 76, rotX * 1.4, rotY * 0.8, 0, color(red(acc), green(acc), blue(acc), 110));
  draw3DRing(cx, cy, 62, -rotY * 1.1, rotX * 1.2, HALF_PI, color(0, 210, 255, 90));

  float baseR = 46 + corePulse * 6;
  PVector[] proj = new PVector[12];
  float[] zVals = new float[12];
  float fov = 240;

  for (int i = 0; i < 12; i++) {
    PVector v = rotate3D(icoVerts[i], rotX, rotY, rotZ);
    float r = baseR + (gameState == 5 ? random(-8, 12) : 0);
    float s = fov / (fov + v.z * r + 110);
    proj[i] = new PVector(cx + v.x * r * s, cy + v.y * r * s);
    zVals[i] = v.z * r;
  }

  for (int[] e : icoEdges) {
    float avgZ = (zVals[e[0]] + zVals[e[1]]) * 0.5;
    float a = constrain(map(avgZ, -baseR, baseR, 240, 45), 40, 245);
    stroke(red(acc), green(acc), blue(acc), a);
    strokeWeight(avgZ < 0 ? 1.8 : 0.9);
    line(proj[e[0]].x, proj[e[0]].y, proj[e[1]].x, proj[e[1]].y);
  }

  noStroke();
  for (int i = 0; i < 12; i++) {
    float a = constrain(map(zVals[i], -baseR, baseR, 255, 65), 60, 255);
    fill(255, 255, 255, a);
    ellipse(proj[i].x, proj[i].y, zVals[i] < 0 ? 4 : 2.3, zVals[i] < 0 ? 4 : 2.3);
  }

  textAlign(LEFT, CENTER);
  fill(115, 145, 175);
  textSize(9.5);
  text("RX:" + nf(degrees(rotX) % 360, 3, 0) + " RY:" + nf(degrees(rotY) % 360, 3, 0) + " RZ:" + nf(degrees(rotZ) % 360, 3, 0), px + 12, py + ph - 12);
  textAlign(RIGHT, CENTER);
  fill(acc);
  text("w=" + nf(speed * 60, 1, 2) + " rad/s", px + pw - 12, py + ph - 12);
}

PVector rotate3D(PVector p, float ax, float ay, float az) {
  float y1 = p.y * cos(ax) - p.z * sin(ax);
  float z1 = p.y * sin(ax) + p.z * cos(ax);
  float x2 = p.x * cos(ay) + z1 * sin(ay);
  float z2 = -p.x * sin(ay) + z1 * cos(ay);
  float x3 = x2 * cos(az) - y1 * sin(az);
  float y3 = x2 * sin(az) + y1 * cos(az);
  return new PVector(x3, y3, z2);
}

void draw3DRing(float cx, float cy, float r, float ax, float ay, float az, color c) {
  int segs = 26;
  float fov = 240;
  noFill();
  stroke(c);
  strokeWeight(1.1);
  beginShape();
  for (int i = 0; i <= segs; i++) {
    float t = TWO_PI * i / segs;
    PVector v = rotate3D(new PVector(cos(t), sin(t), 0), ax, ay, az);
    float s = fov / (fov + v.z * r + 110);
    vertex(cx + v.x * r * s, cy + v.y * r * s);
  }
  endShape();
}

// === 左下：有限狀態機 (FSM) + 3 條引信狀態條 ===
void drawFsmAndWirePanel() {
  float px = 16, py = 322, pw = 324, ph = 234;
  color acc = getAccentColor();
  drawTechPanel(px, py, pw, ph, color(10, 15, 24, 240), color(38, 58, 84));
  drawPanelHeader(px, py, pw, "FSM TOPOLOGY & 3-CH WIRES", "TR:" + fsmTransitions, acc);

  float[][] pos = {
    {px + 50,  py + 70},
    {px + 132, py + 70},
    {px + 214, py + 70},
    {px + 286, py + 112},
    {px + 188, py + 148},
    {px + 74,  py + 148}
  };
  String[] names = {"S0\nIDLE", "S1\nLOCK", "S2\nSURG", "S3\nCORE", "S4\nSAFE", "S5\nFAIL"};

  drawFsmEdge(pos[0], pos[1], gameState == 1, acc);
  drawFsmEdge(pos[1], pos[2], gameState == 2, acc);
  drawFsmEdge(pos[2], pos[3], gameState == 3, acc);
  drawFsmEdge(pos[3], pos[4], gameState == 4, color(0, 235, 145));
  drawFsmEdge(pos[1], pos[5], gameState == 5, color(255, 42, 72));
  drawFsmEdge(pos[2], pos[5], gameState == 5, color(255, 42, 72));
  drawFsmEdge(pos[3], pos[5], gameState == 5, color(255, 42, 72));
  drawFsmEdge(pos[5], pos[0], gameState == 0, color(70, 125, 175));
  drawFsmEdge(pos[4], pos[0], gameState == 0, color(70, 125, 175));

  for (int i = 0; i < 6; i++) {
    boolean active = (gameState == i);
    color nc = (i == 4) ? color(0, 235, 145) : (i == 5 ? color(255, 42, 72) : acc);
    if (active) {
      noFill();
      stroke(red(nc), green(nc), blue(nc), 120 + 95 * sin(millis() * 0.012));
      strokeWeight(2);
      ellipse(pos[i][0], pos[i][1], 46, 46);
    }
    fill(active ? color(red(nc), green(nc), blue(nc), 55) : color(16, 24, 38));
    stroke(active ? nc : color(55, 78, 108));
    strokeWeight(active ? 2 : 1.1);
    ellipse(pos[i][0], pos[i][1], 36, 36);
    textAlign(CENTER, CENTER);
    fill(active ? color(255) : color(140, 165, 195));
    textSize(9.5);
    text(names[i], pos[i][0], pos[i][1]);
  }

  // 底部 3 條引信狀態膠囊
  stroke(32, 48, 70);
  strokeWeight(1);
  line(px + 12, py + 182, px + pw - 12, py + 182);

  drawCompactWirePill(px + 14,  py + 194, 94, 28, "W1 LOCK",  color(255, 205, 50), highestStage >= 2, gameState == 1);
  drawCompactWirePill(px + 115, py + 194, 94, 28, "W2 SURG",  color(0, 215, 255),  highestStage >= 3, gameState == 2);
  drawCompactWirePill(px + 216, py + 194, 94, 28, "W3 CORE",  color(255, 55, 78),  highestStage >= 4, gameState == 3);
}

void drawCompactWirePill(float x, float y, float w, float h, String name, color c, boolean cut, boolean act) {
  fill(cut ? color(0, 235, 145, 35) : (act ? color(red(c), green(c), blue(c), 45) : color(16, 23, 36)));
  stroke(cut ? color(0, 235, 145) : (act ? c : color(50, 68, 92)));
  strokeWeight(act || cut ? 1.5 : 1);
  rect(x, y, w, h, 4);
  textAlign(CENTER, CENTER);
  textSize(9.5);
  fill(cut ? color(0, 245, 160) : (act ? color(255) : color(135, 155, 180)));
  text(name, x + w / 2, y + 9);
  textSize(9);
  fill(cut ? color(0, 245, 160) : (act ? c : color(95, 115, 140)));
  text(cut ? "[CUT]" : (act ? "[ACTIVE]" : "[ARMED]"), x + w / 2, y + 20);
}

void drawFsmEdge(float[] a, float[] b, boolean hi, color c) {
  stroke(hi ? c : color(42, 60, 84));
  strokeWeight(hi ? 2 : 1);
  line(a[0], a[1], b[0], b[1]);
}

// === 中上：7 段電子管計時器 ===
void drawChronoPanel() {
  float px = 352, py = 72, pw = 540, ph = 212;
  color acc = getAccentColor();
  drawTechPanel(px, py, pw, ph, color(10, 15, 24, 240), color(red(acc), green(acc), blue(acc), 160));
  drawPanelHeader(px, py, pw, "CHRONO DETONATOR // PRECISION TUBE", "STATE: S" + gameState, acc);

  fill(4, 7, 12);
  stroke(32, 48, 70);
  strokeWeight(1);
  rect(px + 18, py + 34, pw - 36, 116, 6);

  int ms = max(0, remainingMs);
  int sec = ms / 1000;
  int centi = (ms % 1000) / 10;
  float sx = px + 84, dy = py + 45, dw = 68, dh = 94;

  drawSevenSegDigit(sx,       dy, dw, dh, (sec / 10) % 10, acc);
  drawSevenSegDigit(sx + 88,  dy, dw, dh, sec % 10,        acc);
  boolean colonOn = (gameState == 4 || gameState == 5) || ((millis() / 350) % 2 == 0);
  drawColon(sx + 174, dy + dh / 2.0, acc, colonOn);
  drawSevenSegDigit(sx + 194, dy, dw, dh, (centi / 10) % 10, acc);
  drawSevenSegDigit(sx + 282, dy, dw, dh, centi % 10,        acc);

  float maxMs = (difficulty == 1) ? 35000.0 : (difficulty == 2 ? 30000.0 : 22000.0);
  float ratio = constrain(ms / maxMs, 0, 1);
  float bx = px + 18, by = py + 160, bw = pw - 36;
  noStroke();
  fill(20, 30, 44);
  rect(bx, by, bw, 10, 2);
  fill(acc);
  rect(bx, by, bw * ratio, 10, 2);

  stroke(60, 84, 112);
  strokeWeight(1);
  for (int i = 0; i <= 20; i++) {
    float tx = bx + bw * (i / 20.0);
    line(tx, by + 10, tx, by + (i % 5 == 0 ? 15 : 12));
  }

  String dir = "";
  switch (gameState) {
    case 0: dir = "STANDBY // SELECT L1-L3 ON PC -> PRESS PIN 2 ON MAKERUNO"; break;
    case 1: dir = "STAGE 1 // HIT PIN 2 INSIDE GREEN TARGET LOCK (MISS -3.0s)"; break;
    case 2: dir = "STAGE 2 // MASH PIN 2 TO CHARGE 10/10 LEDS BEFORE DRAIN"; break;
    case 3: dir = "STAGE 3 // HIGH-SPEED FINAL CUT IN GREEN LOCK (MISS -3.0s)"; break;
    case 4: dir = "MISSION CLEAR // C4 SAFE - PRESS PIN 2 OR [R] TO RESET"; break;
    case 5: dir = "DETONATED // SYSTEM FAILED - PRESS PIN 2 OR [R] TO RE-ARM"; break;
  }
  textAlign(LEFT, CENTER);
  fill(acc);
  textSize(11.5);
  text(dir, px + 18, py + 193);
}

void drawSevenSegDigit(float x, float y, float w, float h, int num, color c) {
  float t = 9.5, hh = h / 2.0;
  boolean[] s = SEG_MAP[constrain(num, 0, 9)];
  drawHSeg(x + t * 0.6, y, w - t * 1.2, t, s[0], c);
  drawVSeg(x + w - t, y + t * 0.6, t, hh - t * 0.9, s[1], c);
  drawVSeg(x + w - t, y + hh + t * 0.3, t, hh - t * 0.9, s[2], c);
  drawHSeg(x + t * 0.6, y + h - t, w - t * 1.2, t, s[3], c);
  drawVSeg(x, y + hh + t * 0.3, t, hh - t * 0.9, s[4], c);
  drawVSeg(x, y + t * 0.6, t, hh - t * 0.9, s[5], c);
  drawHSeg(x + t * 0.6, y + hh - t / 2.0, w - t * 1.2, t, s[6], c);
}

void drawHSeg(float x, float y, float w, float t, boolean on, color c) {
  float k = t * 0.5;
  noStroke();
  if (on) { fill(red(c), green(c), blue(c), 42); rect(x - 2, y - 2, w + 4, t + 4, 3); fill(c); }
  else fill(20, 28, 42, 130);
  beginShape();
  vertex(x, y + k); vertex(x + k, y); vertex(x + w - k, y);
  vertex(x + w, y + k); vertex(x + w - k, y + t); vertex(x + k, y + t);
  endShape(CLOSE);
}

void drawVSeg(float x, float y, float t, float h, boolean on, color c) {
  float k = t * 0.5;
  noStroke();
  if (on) { fill(red(c), green(c), blue(c), 42); rect(x - 2, y - 2, t + 4, h + 4, 3); fill(c); }
  else fill(20, 28, 42, 130);
  beginShape();
  vertex(x + k, y); vertex(x + t, y + k); vertex(x + t, y + h - k);
  vertex(x + k, y + h); vertex(x, y + h - k); vertex(x, y + k);
  endShape(CLOSE);
}

void drawColon(float x, float y, color c, boolean on) {
  noStroke();
  if (on) { fill(red(c), green(c), blue(c), 65); ellipse(x, y - 18, 18, 18); ellipse(x, y + 18, 18, 18); fill(c); }
  else fill(22, 30, 44);
  ellipse(x, y - 18, 9, 9); ellipse(x, y + 18, 9, 9);
}

// === 中下：12 通道即時數位邏輯分析儀 ===
void drawLogicAnalyzerPanel() {
  float px = 352, py = 296, pw = 540, ph = 260;
  drawTechPanel(px, py, pw, ph, color(9, 14, 22, 240), color(38, 58, 84));
  drawPanelHeader(px, py, pw, "12-CH DIGITAL LOGIC ANALYZER", "30Hz REAL-TIME GPIO TRACE", color(0, 220, 255));

  float gx = px + 68, gy = py + 34, gw = pw - 82, gh = ph - 44;
  fill(5, 9, 15);
  stroke(26, 40, 58);
  strokeWeight(1);
  rect(gx, gy, gw, gh);

  stroke(22, 35, 52);
  for (int i = 1; i < 6; i++) line(gx + gw * (i / 6.0), gy, gx + gw * (i / 6.0), gy + gh);

  float rowH = gh / 12.0;
  float dx = gw / (float)(LA_LEN - 1);

  for (int ch = 0; ch < 12; ch++) {
    float baseY = gy + ch * rowH + rowH * 0.78;
    float hiY   = gy + ch * rowH + rowH * 0.22;
    stroke(18, 28, 42);
    strokeWeight(1);
    line(gx, gy + (ch + 1) * rowH, gx + gw, gy + (ch + 1) * rowH);

    color chCol = (ch == 0) ? color(0, 235, 145) : (ch == 1 ? color(255, 195, 45) : color(0, 210, 255));
    int latestIdx = (laHead - 1 + LA_LEN) % LA_LEN;
    boolean isHighNow = (laBuf[ch][latestIdx] == 1);

    textAlign(RIGHT, CENTER);
    fill(isHighNow ? chCol : color(110, 132, 160));
    textSize(10);
    text(laNames[ch], gx - 8, gy + ch * rowH + rowH * 0.5);

    stroke(chCol);
    strokeWeight(isHighNow ? 1.6 : 1.15);
    int prevBit = laBuf[ch][laHead];
    for (int s = 1; s < LA_LEN; s++) {
      int idx = (laHead + s) % LA_LEN;
      int curBit = laBuf[ch][idx];
      float x0 = gx + (s - 1) * dx, x1 = gx + s * dx;
      float y0 = (prevBit == 1) ? hiY : baseY;
      float y1 = (curBit == 1) ? hiY : baseY;
      if (curBit != prevBit) line(x0, y0, x0, y1);
      line(x0, y1, x1, y1);
      prevBit = curBit;
    }
  }
}

// === 右側主戰場：全像戰術支援官 (LIVE COMMS + 即時情緒對話框) ===
void drawOperatorCommsPanel() {
  float px = 904, py = 72, pw = 360, ph = 384;
  color acc = getAccentColor();
  color moodCol = getMoodColor();

  drawTechPanel(px, py, pw, ph, color(10, 15, 24, 244), color(red(moodCol), green(moodCol), blue(moodCol), 175));
  drawPanelHeader(px, py, pw, "LIVE COMMS // OPERATOR NOVA", "HR: " + int(operatorBpm) + " BPM", moodCol);

  // 全像人物視窗框
  float vx = px + 12, vy = py + 32, vw = pw - 24, vh = 216;
  fill(7, 13, 24);
  stroke(red(moodCol), green(moodCol), blue(moodCol), 120);
  strokeWeight(1.2);
  rect(vx, vy, vw, vh, 6);

  // 全像背景光暈 + 格線
  noStroke();
  for (int r = 180; r > 30; r -= 35) {
    fill(red(moodCol), green(moodCol), blue(moodCol), 9);
    ellipse(vx + vw / 2, vy + vh * 0.55, r * 1.4, r);
  }
  stroke(red(moodCol), green(moodCol), blue(moodCol), 22);
  strokeWeight(1);
  for (float y = vy + 12; y < vy + vh; y += 16) line(vx, y, vx + vw, y);

  // 繪製向量戰術支援官角色 (含呼吸、抖動、眨眼、對嘴、情緒特效)
  drawTacticalOperator(vx + vw / 2.0, vy + 106, vy + vh - 1, moodCol);

  // 左上情緒標籤
  String moodLabel = "CALM";
  if (charMood == 1) moodLabel = "HYPED !!";
  else if (charMood == 2) moodLabel = "NERVOUS";
  else if (charMood == 3) moodLabel = "PANIC !!";
  else if (charMood == 4) moodLabel = "SHOCKED!";
  else if (charMood == 5) moodLabel = "ECSTATIC";
  else if (charMood == 6) moodLabel = "DIZZY...";

  fill(10, 16, 26, 200);
  stroke(moodCol);
  strokeWeight(1);
  rect(vx + 8, vy + 8, 92, 20, 3);
  textFont(monoFont);
  textAlign(CENTER, CENTER);
  fill(moodCol);
  textSize(10);
  text("MOOD:" + moodLabel, vx + 54, vy + 18);

  // 右上 LIVE 錄影紅點
  fill(10, 16, 26, 200);
  stroke(255, 65, 85, 160);
  rect(vx + vw - 66, vy + 8, 58, 20, 3);
  noStroke();
  fill((millis() / 400) % 2 == 0 ? color(255, 50, 70) : color(100, 25, 35));
  ellipse(vx + vw - 54, vy + 18, 7, 7);
  fill(235);
  textSize(10);
  text("LIVE", vx + vw - 28, vy + 18);

  // 左下即時語音聲紋條 (說話時劇烈跳動)
  boolean isTalking = (shownChars < currentDialogue.length());
  for (int i = 0; i < 12; i++) {
    float h = isTalking ? random(4, 24) : (2 + 2 * sin(millis() * 0.008 + i));
    noStroke();
    fill(red(moodCol), green(moodCol), blue(moodCol), isTalking ? 220 : 90);
    rect(vx + 10 + i * 6, vy + vh - 8 - h, 4, h, 1);
  }

  // 下方繁中打字機對話框
  float dx = px + 12, dy = py + 256, dw = pw - 24, dh = 116;
  fill(6, 11, 20, 245);
  stroke(red(moodCol), green(moodCol), blue(moodCol), 165);
  strokeWeight(1.4);
  rect(dx, dy, dw, dh, 6);

  // 角色名牌
  noStroke();
  fill(moodCol);
  rect(dx + 10, dy + 9, 4, 16, 1);
  textFont(cjkFont);
  textAlign(LEFT, CENTER);
  fill(moodCol);
  textSize(13);
  text("NOVA // 戰術支援官", dx + 20, dy + 17);

  // 繁體中文自動換行打字機文字
  int len = constrain(int(shownChars), 0, currentDialogue.length());
  String visibleTxt = currentDialogue.substring(0, len);
  if (isTalking && (millis() / 200) % 2 == 0) visibleTxt += "_";

  fill(236, 245, 255);
  textSize(15);
  drawWrappedCjkText(visibleTxt, dx + 14, dy + 42, dw - 28, 22);

  // 切回等寬字體給其餘工程模組
  textFont(monoFont);
}

color getMoodColor() {
  if (charMood == 1 || charMood == 5) return color(0, 245, 165);
  if (charMood == 2) return color(255, 195, 55);
  if (charMood == 3 || charMood == 4 || charMood == 6) return color(255, 55, 85);
  return color(0, 220, 255);
}

// === 手工向量賽博龐克戰術支援官 ===
void drawTacticalOperator(float cx, float baseY, float bottomClipY, color moodCol) {
  float bob = sin(millis() * 0.0045) * 3.0;
  float jitterX = 0, jitterY = 0;
  if (charMood == 3 || charMood == 4) {
    jitterX = random(-2.2, 2.2);
    jitterY = random(-1.6, 1.6);
  } else if (charMood == 1 || charMood == 5) {
    bob = -abs(sin(millis() * 0.011)) * 6.5; // 開心彈跳！
  }

  float hx = cx + jitterX;
  float hy = baseY + bob + jitterY;
  boolean isTalking = (shownChars < currentDialogue.length());

  // 1. 恐慌/驚嚇背景張力線
  if (charMood == 3 || charMood == 4) {
    stroke(255, 65, 90, 95);
    strokeWeight(1.5);
    for (int i = 0; i < 10; i++) {
      float a = i * TWO_PI / 10.0 + millis() * 0.002;
      line(hx + cos(a) * 78, hy + sin(a) * 70, hx + cos(a) * 105, hy + sin(a) * 90);
    }
  }

  // 2. 後層長髮 (深藍紫科技髮色)
  noStroke();
  fill(28, 34, 62);
  ellipse(hx, hy - 4, 118, 124);
  quad(hx - 58, hy + 4, hx + 58, hy + 4, hx + 66, bottomClipY, hx - 66, bottomClipY);

  // 3. 戰術夾克肩膀與高領 (貼齊視窗底部不溢出)
  fill(22, 30, 48);
  stroke(58, 78, 112);
  strokeWeight(1.5);
  beginShape();
  vertex(hx - 82, bottomClipY);
  vertex(hx - 64, hy + 72);
  vertex(hx - 24, hy + 58);
  vertex(hx + 24, hy + 58);
  vertex(hx + 64, hy + 72);
  vertex(hx + 82, bottomClipY);
  endShape(CLOSE);

  // 夾克發光條紋與領口
  stroke(moodCol);
  strokeWeight(2);
  line(hx - 44, hy + 68, hx - 22, bottomClipY);
  line(hx + 44, hy + 68, hx + 22, bottomClipY);
  noStroke();
  fill(14, 20, 34);
  triangle(hx - 20, hy + 58, hx + 20, hy + 58, hx, hy + 94);

  // 4. 脖子與下巴陰影
  fill(244, 212, 194);
  rect(hx - 13, hy + 38, 26, 26, 4);
  fill(218, 178, 160);
  arc(hx, hy + 42, 26, 18, 0, PI);

  // 5. 耳麥頭帶 (在臉後方半圓)
  noFill();
  stroke(46, 58, 84);
  strokeWeight(8);
  arc(hx, hy - 8, 118, 122, PI, TWO_PI);
  stroke(moodCol);
  strokeWeight(2);
  arc(hx, hy - 8, 118, 122, PI + 0.3, TWO_PI - 0.3);

  // 6. 臉型輪廓 (乾淨日系柔和下巴)
  fill(254, 226, 210);
  stroke(212, 174, 158);
  strokeWeight(1.2);
  beginShape();
  vertex(hx - 44, hy - 22);
  bezierVertex(hx - 46, hy + 18, hx - 28, hy + 44, hx, hy + 47);
  bezierVertex(hx + 28, hy + 44, hx + 46, hy + 18, hx + 44, hy - 22);
  bezierVertex(hx + 44, hy - 58, hx - 44, hy - 58, hx - 44, hy - 22);
  endShape(CLOSE);

  // 7. 腮紅 (開心 / 誇獎 / 害羞時更明顯)
  noStroke();
  float blushA = (charMood == 1 || charMood == 5) ? 145 : (charMood == 2 || charMood == 3 ? 65 : 85);
  fill(255, 115, 140, blushA);
  ellipse(hx - 28, hy + 13, 18, 9);
  ellipse(hx + 28, hy + 13, 18, 9);

  // 8. 雙眼 (核心情緒表達)
  drawOperatorEyes(hx, hy, moodCol);

  // 9. 鼻子微點與動態眉毛
  stroke(195, 152, 136);
  strokeWeight(1.4);
  line(hx, hy + 9, hx - 2, hy + 14);
  drawOperatorBrows(hx, hy);

  // 10. 動態對嘴嘴巴
  drawOperatorMouth(hx, hy, isTalking);

  // 11. 前瀏海與兩側鬢角 (修飾臉型更立體)
  noStroke();
  fill(34, 42, 76);
  // 頂部髮冠
  arc(hx, hy - 24, 98, 76, PI, TWO_PI);
  // 瀏海分束
  triangle(hx - 46, hy - 26, hx - 22, hy - 32, hx - 34, hy - 2);
  triangle(hx - 26, hy - 34, hx - 2,  hy - 34, hx - 14, hy - 4);
  triangle(hx - 4,  hy - 34, hx + 22, hy - 34, hx + 10, hy - 6);
  triangle(hx + 18, hy - 32, hx + 46, hy - 26, hx + 34, hy - 2);
  // 兩側長鬢角
  triangle(hx - 49, hy - 22, hx - 38, hy - 14, hx - 44, hy + 56);
  triangle(hx + 49, hy - 22, hx + 38, hy - 14, hx + 44, hy + 56);

  // 瀏海霓虹挑染光澤
  stroke(red(moodCol), green(moodCol), blue(moodCol), 130);
  strokeWeight(2.5);
  noFill();
  arc(hx, hy - 32, 68, 22, PI + 0.4, TWO_PI - 0.4);

  // 12. 雙側發光戰術耳罩 + 通訊麥克風
  fill(30, 38, 58);
  stroke(moodCol);
  strokeWeight(2);
  rect(hx - 62, hy - 18, 16, 38, 6);
  rect(hx + 46, hy - 18, 16, 38, 6);
  noStroke();
  fill(moodCol);
  rect(hx - 57, hy - 8, 6, 18, 2);
  rect(hx + 51, hy - 8, 6, 18, 2);

  // 麥克風桿 + 發光收音頭
  noFill();
  stroke(75, 92, 122);
  strokeWeight(3);
  bezier(hx - 52, hy + 14, hx - 48, hy + 34, hx - 28, hy + 32, hx - 16, hy + 29);
  noStroke();
  fill(isTalking ? color(255, 255, 255) : moodCol);
  ellipse(hx - 15, hy + 29, isTalking ? 8 : 6, isTalking ? 8 : 6);

  // 13. 專屬情緒配件 (冷汗 / 閃亮星星 / 爆炸煙霧)
  if (charMood == 2 || charMood == 3) {
    // 動漫冷汗珠
    float sx = hx + 36, sy = hy - 18 + sweatDropY * 0.5;
    fill(100, 215, 255, 220);
    noStroke();
    triangle(sx, sy - 9, sx - 5, sy, sx + 5, sy);
    ellipse(sx, sy + 1, 10, 10);
  }
  if (charMood == 1 || charMood == 5) {
    // 勝利與稱讚閃亮星星
    float sp = 6 + 3 * sin(millis() * 0.015);
    drawSparkle(hx - 64, hy - 42, sp, color(255, 230, 90));
    drawSparkle(hx + 66, hy - 34, sp * 1.2, color(0, 255, 175));
    drawSparkle(hx + 58, hy + 24, sp * 0.8, color(255, 230, 90));
  }
  if (charMood == 6) {
    // 爆炸暈眩頭頂小煙霧
    noStroke();
    float t = (millis() * 0.03) % 28;
    fill(180, 190, 210, map(t, 0, 28, 180, 0));
    ellipse(hx - 16, hy - 64 - t, 14, 14);
    ellipse(hx + 14, hy - 70 - (t + 12) % 28, 12, 12);
  }
}

void drawOperatorEyes(float hx, float hy, color moodCol) {
  float ey = hy + 1;
  float lx = hx - 20, rx = hx + 20;

  if (charMood == 5 || charMood == 1) {
    // 超開心彎彎笑眼 (^ ^)
    noFill();
    stroke(35, 38, 60);
    strokeWeight(3.2);
    arc(lx, ey + 4, 22, 18, PI + 0.25, TWO_PI - 0.25);
    arc(rx, ey + 4, 22, 18, PI + 0.25, TWO_PI - 0.25);
    return;
  }
  if (charMood == 6) {
    // 爆炸暈眩眼 (> <)
    stroke(40, 42, 65);
    strokeWeight(2.8);
    noFill();
    line(lx - 8, ey - 5, lx + 6, ey); line(lx - 8, ey + 5, lx + 6, ey);
    line(rx + 8, ey - 5, rx - 6, ey); line(rx + 8, ey + 5, rx - 6, ey);
    return;
  }

  float openH = max(2.0, 20.0 * (1.0 - blinkAmount));
  if (blinkAmount > 0.82) {
    stroke(38, 42, 65);
    strokeWeight(2.5);
    line(lx - 10, ey, lx + 10, ey);
    line(rx - 10, ey, rx + 10, ey);
    return;
  }

  for (int side = -1; side <= 1; side += 2) {
    float ex = hx + side * 20;
    // 眼白
    noStroke();
    fill(255);
    ellipse(ex, ey, 22, openH);

    // 虹膜 (恐慌或驚嚇時縮瞳！)
    float irisS = (charMood == 3 || charMood == 4) ? 9.5 : 14.5;
    fill(red(moodCol) * 0.7, green(moodCol) * 0.75, blue(moodCol) * 0.85);
    ellipse(ex, ey + 0.5, irisS, min(irisS, openH - 1));
    fill(20, 26, 48);
    ellipse(ex, ey + 0.5, irisS * 0.52, min(irisS * 0.52, openH - 2));

    // 靈魂雙高光
    fill(255);
    ellipse(ex - 3.5, ey - 3, 4.2, min(4.2, openH * 0.4));
    ellipse(ex + 3, ey + 3, 2.2, min(2.2, openH * 0.25));

    // 上眼睫毛
    noFill();
    stroke(28, 32, 54);
    strokeWeight(2.8);
    arc(ex, ey, 23, openH + 1, PI + 0.12, TWO_PI - 0.12);
  }
}

void drawOperatorBrows(float hx, float hy) {
  stroke(38, 44, 74);
  strokeWeight(2.2);
  float by = hy - 14;
  if (charMood == 2 || charMood == 3 || charMood == 6) {
    // 擔心八字眉
    line(hx - 29, by + 3, hx - 12, by - 3);
    line(hx + 29, by + 3, hx + 12, by - 3);
  } else if (charMood == 4) {
    // 驚嚇高挑眉
    line(hx - 29, by - 4, hx - 12, by - 6);
    line(hx + 29, by - 4, hx + 12, by - 6);
  } else {
    // 自信微笑眉
    line(hx - 29, by, hx - 12, by - 2);
    line(hx + 29, by, hx + 12, by - 2);
  }
}

void drawOperatorMouth(float hx, float hy, boolean talking) {
  float my = hy + 27;
  if (talking) {
    // 說話對嘴動畫
    float open = 3 + 7 * abs(sin(millis() * 0.028));
    fill(210, 88, 105);
    stroke(145, 58, 72);
    strokeWeight(1.4);
    ellipse(hx, my, 13, open);
    return;
  }

  noFill();
  stroke(165, 75, 88);
  strokeWeight(2.0);
  if (charMood == 1 || charMood == 5) {
    // 大大開心笑嘴
    fill(235, 105, 120);
    arc(hx, my - 2, 18, 15, 0, PI, CHORD);
  } else if (charMood == 3 || charMood == 4) {
    // 緊張張嘴
    fill(195, 78, 95);
    ellipse(hx, my + 1, 11, 12);
  } else if (charMood == 2 || charMood == 6) {
    // 波浪緊張嘴
    beginShape();
    vertex(hx - 9, my + 2);
    vertex(hx - 4, my - 1);
    vertex(hx,     my + 2);
    vertex(hx + 4, my - 1);
    vertex(hx + 9, my + 2);
    endShape();
  } else {
    // 溫柔自信微笑
    arc(hx, my - 3, 15, 10, 0.15 * PI, 0.85 * PI);
  }
}

void drawSparkle(float x, float y, float s, color c) {
  noStroke();
  fill(c);
  beginShape();
  vertex(x, y - s); vertex(x + s * 0.28, y - s * 0.28);
  vertex(x + s, y); vertex(x + s * 0.28, y + s * 0.28);
  vertex(x, y + s); vertex(x - s * 0.28, y + s * 0.28);
  vertex(x - s, y); vertex(x - s * 0.28, y - s * 0.28);
  endShape(CLOSE);
}

// 專為繁體中文寫的精準自動換行工具，保證絕不超出對話框
void drawWrappedCjkText(String txt, float x, float y, float maxW, float lineH) {
  textAlign(LEFT, TOP);
  String line = "";
  float cy = y;
  int lineCount = 0;
  for (int i = 0; i < txt.length(); i++) {
    char ch = txt.charAt(i);
    if (textWidth(line + ch) > maxW) {
      text(line, x, cy);
      line = "" + ch;
      cy += lineH;
      lineCount++;
      if (lineCount >= 3) break;
    } else {
      line += ch;
    }
  }
  if (line.length() > 0 && lineCount < 3) {
    text(line, x, cy);
  }
}

// === 右下：精簡工業級封包與最佳紀錄列 ===
void drawPacketFooterPanel() {
  float px = 904, py = 468, pw = 360, ph = 88;
  drawTechPanel(px, py, pw, ph, color(10, 15, 24, 240), color(38, 58, 84));
  drawPanelHeader(px, py, pw, "UART XOR-8 INSPECTOR", "PKT:" + r_pktOk + " ERR:" + r_pktErr, color(0, 235, 145));

  textAlign(LEFT, CENTER);
  fill(0, 235, 165);
  textSize(10);
  String fStr = r_rawFrame;
  if (fStr.length() > 48) fStr = fStr.substring(0, 48);
  text(fStr, px + 12, py + 42);

  stroke(30, 46, 68);
  strokeWeight(1);
  line(px + 12, py + 56, px + pw - 12, py + 56);

  textSize(11);
  fill(255, 210, 70);
  text("BEST: " + (bestRemainingMs >= 0 ? nf(bestRemainingMs / 1000.0, 2, 2) + "s" : "--.--s"), px + 12, py + 72);
  fill(buzFreq > 0 ? color(255, 185, 45) : color(110, 135, 165));
  textAlign(CENTER, CENTER);
  text("BUZ: " + buzFreq + "Hz", px + pw * 0.54, py + 72);
  fill(0, 220, 255);
  textAlign(RIGHT, CENTER);
  text("HIT:" + totalHits + " MISS:" + totalMisses, px + pw - 12, py + 72);
}

// === 底部：MakerUNO 1:1 實體硬體同步甲板 ===
float getLedX(int i) {
  return (i < 5) ? (196 + i * 86) : (740 + (i - 5) * 86);
}

void drawMakerUnoHardwareDeck() {
  float px = 16, py = 568, pw = 1248, ph = 176;
  color acc = getAccentColor();
  drawTechPanel(px, py, pw, ph, color(16, 12, 28, 242), color(120, 82, 205, 165));
  drawPanelHeader(px, py, pw, "CYTRON MAKER UNO // 1:1 HARDWARE GPIO MIRROR (D13 -> D3)", "MASK: 0x" + hex(ledMask, 3), color(185, 150, 255));

  stroke(130, 95, 210, 48);
  strokeWeight(1.5);
  line(px + 125, py + 96, px + pw - 125, py + 96);
  line(px + 145, py + 142, px + pw - 145, py + 142);

  fill(78, 92, 112);
  stroke(148, 165, 190);
  rect(px + 2, py + 64, 34, 60, 3);
  fill(18, 24, 34);
  noStroke();
  rect(px + 8, py + 74, 18, 40, 2);

  textAlign(CENTER, CENTER);
  fill(170, 190, 215);
  textSize(10);
  text("USB 5V", px + 68, py + 76);
  fill(r_rxPulse > 0 ? color(0, 245, 155) : color(35, 62, 52));
  ellipse(px + 58, py + 98, 9, 9);
  fill(txPulse > 0 ? color(255, 195, 50) : color(65, 55, 35));
  ellipse(px + 78, py + 98, 9, 9);
  fill(135, 155, 180);
  textSize(9);
  text("RX   TX", px + 68, py + 114);

  float bx = px + pw - 96, by = py + 60;
  fill(btnActive == 1 ? color(0, 235, 145, 55) : color(26, 20, 44));
  stroke(btnActive == 1 ? color(0, 235, 145) : color(120, 95, 185));
  strokeWeight(1.5);
  rect(bx, by, 72, 68, 6);
  fill(btnActive == 1 ? color(0, 235, 145) : color(52, 40, 82));
  ellipse(bx + 36, by + 34, 34, 34);
  fill(btnActive == 1 ? color(10, 20, 15) : color(220));
  textSize(10);
  text(btnActive == 1 ? "LOW" : "HIGH", bx + 36, by + 34);
  fill(185, 165, 230);
  textSize(10);
  text("D2 BTN", bx + 36, by + 82);

  float cy = py + 96;
  if (buzzerWave > 0.04) {
    noFill();
    stroke(red(acc), green(acc), blue(acc), buzzerWave * 210);
    strokeWeight(2);
    float r = 46 + (1.0 - buzzerWave) * 64;
    ellipse(640, cy, r, r);
  }
  fill(18, 20, 32);
  stroke(buzFreq > 0 ? acc : color(125, 105, 185));
  strokeWeight(1.8);
  rectMode(CENTER);
  rect(640, cy, 56, 56, 8);
  rectMode(CORNER);
  noStroke();
  fill(8, 10, 16);
  ellipse(640, cy, 20, 20);
  fill(190, 175, 235);
  textSize(11);
  text("D8 BUZ", 640, cy + 44);

  for (int i = 0; i < 10; i++) {
    float x = getLedX(i);
    boolean isTarget = (gameState == 1 || gameState == 3) && (i >= targetStart && i <= targetEnd);
    if (isTarget) {
      float pulse = 180 + 75 * sin(millis() * 0.015);
      drawTargetBrackets(x, cy, 62, color(0, 245, 155, pulse));
      fill(0, 245, 155, pulse);
      textSize(9.5);
      text("LOCK", x, cy - 42);
    }

    fill(24, 18, 40);
    stroke(74, 56, 118);
    strokeWeight(1.3);
    ellipse(x, cy, 42, 42);

    float g = ledGlow[i];
    noStroke();
    if (g > 0.04) {
      color lc = (gameState == 4) ? color(0, 235, 145) :
                 (gameState == 2) ? color(0, 215, 255) :
                 (gameState == 0) ? color(95, 195, 255) : color(255, 48, 72);
      fill(red(lc), green(lc), blue(lc), 42 * g);  ellipse(x, cy, 70, 70);
      fill(red(lc), green(lc), blue(lc), 115 * g); ellipse(x, cy, 46, 46);
      fill(red(lc), green(lc), blue(lc), 255 * g); ellipse(x, cy, 28, 28);
      fill(255, 255, 255, 210 * g);                ellipse(x - 4, cy - 4, 9, 9);
    } else {
      fill(36, 30, 56);
      ellipse(x, cy, 24, 24);
    }

    fill(isTarget ? color(80, 255, 175) : color(175, 165, 210));
    textSize(12);
    text("D" + pinLabels[i], x, cy + 44);
  }
}

void drawTargetBrackets(float cx, float cy, float s, color c) {
  float h = s * 0.5, k = 11;
  stroke(c);
  strokeWeight(2.5);
  noFill();
  line(cx - h, cy - h, cx - h + k, cy - h); line(cx - h, cy - h, cx - h, cy - h + k);
  line(cx + h, cy - h, cx + h - k, cy - h); line(cx + h, cy - h, cx + h, cy - h + k);
  line(cx - h, cy + h, cx - h + k, cy + h); line(cx - h, cy + h, cx - h, cy + h - k);
  line(cx + h, cy + h, cx + h - k, cy + h); line(cx + h, cy + h, cx + h, cy + h - k);
}

void drawTechPanel(float x, float y, float w, float h, color fillC, color strokeC) {
  float c = 10;
  fill(fillC);
  stroke(strokeC);
  strokeWeight(1.2);
  beginShape();
  vertex(x + c, y); vertex(x + w - c, y); vertex(x + w, y + c);
  vertex(x + w, y + h - c); vertex(x + w - c, y + h); vertex(x + c, y + h);
  vertex(x, y + h - c); vertex(x, y + c);
  endShape(CLOSE);
}

void drawPanelHeader(float x, float y, float w, String leftTxt, String rightTxt, color rightCol) {
  noStroke();
  fill(18, 28, 42, 175);
  rect(x + 1, y + 1, w - 2, 24);
  stroke(36, 54, 78);
  strokeWeight(1);
  line(x, y + 25, x + w, y + 25);
  textFont(monoFont);
  textAlign(LEFT, CENTER);
  fill(140, 170, 205);
  textSize(11);
  text(leftTxt, x + 12, y + 13);
  textAlign(RIGHT, CENTER);
  fill(rightCol);
  textSize(11);
  text(rightTxt, x + w - 12, y + 13);
}

void drawPenaltyPopup() {
  if (penaltyAlpha > 2) {
    textFont(monoFont);
    textAlign(CENTER, CENTER);
    textSize(38);
    fill(255, 45, 70, penaltyAlpha);
    text("-3.00s PHASE FAULT", 622, penaltyY);
    penaltyY -= 1.3;
    penaltyAlpha *= 0.92;
  }
}

void drawPostOverlays() {
  if (redFlash > 1) { noStroke(); fill(255, 20, 45, redFlash); rect(0, 0, width, height); redFlash *= 0.87; }
  if (greenFlash > 1) { noStroke(); fill(0, 235, 145, greenFlash); rect(0, 0, width, height); greenFlash *= 0.87; }
  if (glitchTimer > 0) {
    noStroke();
    for (int i = 0; i < 6; i++) {
      fill(random(1) > 0.5 ? color(255, 42, 72, 105) : color(0, 225, 255, 90));
      rect(0, random(height), width, random(3, 18));
    }
  }
  stroke(0, 0, 0, 22);
  strokeWeight(1);
  for (int y = 0; y < height; y += 4) line(0, y, width, y);
}

// === 雙向指令與人物互動回應 ===
void sendCmd(char c) {
  if (myPort != null && serialConnected) {
    myPort.write(c);
    txPulse = 8;
  }
  if (gameState == 0) {
    if (c == '1') sayDialogue("選簡單模式先暖身很聰明喔！穩穩拆就對了，我挺你～", 1, 2200);
    else if (c == '2') sayDialogue("標準難度！剛剛好展現你真正的實力，準備好就按 Pin 2！", 0, 0);
    else if (c == '3') sayDialogue("哇...地獄難度！？指揮官你也太猛了吧，我手心已經開始冒汗了！", 2, 2600);
  }
  if (c == 'R') sayDialogue("收到！系統遠端重置完畢，調整一下呼吸我們重新來過！", 0, 0);
}

void keyPressed() {
  if (key == '1' || keyCode == 49 || keyCode == 97) sendCmd('1');
  else if (key == '2' || keyCode == 50 || keyCode == 98) sendCmd('2');
  else if (key == '3' || keyCode == 51 || keyCode == 99) sendCmd('3');
  else if (key == 'r' || key == 'R' || keyCode == 82) sendCmd('R');
}

void mousePressed() {
  if (mouseY >= 22 && mouseY <= 52) {
    if (mouseX >= 905 && mouseX <= 983) sendCmd('1');
    else if (mouseX >= 991 && mouseX <= 1069) sendCmd('2');
    else if (mouseX >= 1077 && mouseX <= 1155) sendCmd('3');
    else if (mouseX >= 1163 && mouseX <= 1249) sendCmd('R');
  }
}

void serialEvent(Serial p) {
  try {
    String line = p.readStringUntil('\n');
    if (line == null) return;
    line = trim(line);
    int starIdx = line.indexOf('*');
    if (!line.startsWith("$") || starIdx < 5 || starIdx + 2 >= line.length()) { r_pktErr++; return; }

    String body = line.substring(1, starIdx);
    int expectedChk = Integer.parseInt(line.substring(starIdx + 1), 16);
    int calcChk = 0;
    for (int i = 0; i < body.length(); i++) calcChk ^= (body.charAt(i) & 0xFF);
    if (calcChk != expectedChk) { r_pktErr++; return; }

    String[] parts = split(body, ',');
    if (parts.length == 15 && parts[0].equals("TLM")) {
      r_seq = int(parts[1]);     r_state = int(parts[2]);   r_remMs = int(parts[3]);
      r_val = int(parts[4]);     r_tStart = int(parts[5]);  r_tEnd = int(parts[6]);
      r_diff = int(parts[7]);    int evt = int(parts[8]);   if (evt > 0) r_evt = evt;
      r_vccMv = int(parts[9]);   r_loopUs = int(parts[10]); r_freeRam = int(parts[11]);
      r_ledMask = Integer.parseInt(parts[12], 16);
      r_btn = int(parts[13]);    r_buzFreq = int(parts[14]);
      r_rawFrame = line;
      r_pktOk++;
      r_rxPulse = 6;
    }
  } catch (Exception e) {
    r_pktErr++;
  }
}

void spawnBurst(float x, float y, int count, color c, float maxSpeed) {
  for (int i = 0; i < count; i++) particles.add(new Particle(x, y, c, maxSpeed));
}

void updateAndDrawParticles() {
  noStroke();
  for (int i = particles.size() - 1; i >= 0; i--) {
    Particle pt = particles.get(i);
    pt.update();
    pt.display();
    if (pt.life <= 0) particles.remove(i);
  }
}

void updateAndDrawShockwaves() {
  for (int i = shockwaves.size() - 1; i >= 0; i--) {
    Shockwave sw = shockwaves.get(i);
    sw.update();
    sw.display();
    if (sw.alpha <= 2) shockwaves.remove(i);
  }
}

class Particle {
  float x, y, vx, vy, life, size;
  color c;
  Particle(float x, float y, color c, float maxSpeed) {
    this.x = x; this.y = y; this.c = c;
    float a = random(TWO_PI), s = random(1.4, maxSpeed);
    vx = cos(a) * s; vy = sin(a) * s; life = 255; size = random(2.5, 5.5);
  }
  void update() { x += vx; y += vy; vy += 0.15; life -= 7.0; }
  void display() { fill(red(c), green(c), blue(c), max(life, 0)); rect(x, y, size, size); }
}

class Shockwave {
  float x, y, r, maxR, alpha;
  color c;
  Shockwave(float x, float y, color c, float maxR) {
    this.x = x; this.y = y; this.c = c; this.maxR = maxR; r = 14; alpha = 220;
  }
  void update() { r += (maxR - r) * 0.14; alpha *= 0.88; }
  void display() {
    noFill();
    stroke(red(c), green(c), blue(c), alpha);
    strokeWeight(2.5);
    ellipse(x, y, r, r);
  }
}
