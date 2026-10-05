// week05_1_Arduino_do_re_mi_seria
// 寫完程式，用 工具Tool-序列埠監控視窗SerialMonitor 來傳送 1 2 3 測試很麻煩
//修改日 week02_5_arduino_do_re_mi_Serial_begin_available_read_if_tone
// google: 我想要把 Arduino 跟 Processing 結合
// 在 Processing 按下 key 1 2 3 對應 Arduino 的 Do Re Mi 使用 USB Serial
// 寫完程式, 用 Tool-SerialMonitor 來傳送 1 2 3 測試很麻煩
void setup() {
  Serial.begin(9600); // USB Serial 開始傳輸, 速度 9600 bps
  tone(8, 523, 100); // Do 0.1秒
  delay(200); // 等一下聲音出來，不要滑過去

  tone(8, 587, 100); // Re 0.1秒
  delay(200); // 等一下聲音出來，不要滑過去

  tone(8, 659, 100); // Mi 0.1秒
}

void loop() {
  if (Serial.available()){ // 如果 USB Serial 有收到資料
    char c = Serial.read(); // 就讀進來
    if (c=='1') tone(8, 523, 100); // Do 0.1秒
    if (c=='2') tone(8, 587, 100); // Re 0.1秒
    if (c=='3') tone(8, 659, 100); // Mi 0.1秒
  }
}
