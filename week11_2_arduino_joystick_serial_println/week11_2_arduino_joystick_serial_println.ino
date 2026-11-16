// week11_2_arduino_joystick_serial_println
void setup() {
  Serial.begin(9600);
  pinMode(2, INPUT_PULLUP); // 再加這行
}

void loop() {
  int x = analogRead(A0); // 讀入 x 座標
  int y = analogRead(A1); // 讀入 y 座標
  int sw = digitalRead(2); // joystick 壓鈕
  if (digitalRead(2)==LOW) sw = 1; // 按下去, 設1
  else sw = 0; // 彈起來, 設0
  char line[200];
  sprintf(line, "x:%d y:%d sw:%d\n", x, y, sw);
  Serial.print(line); // 改用 print() 不要 println()
}
