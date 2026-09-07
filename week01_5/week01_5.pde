// week01_5_google_gemini_mouse_wheel
// google gemini: Processing 怎麼用到 mouse wheel
float circleSize = 50; // 宣告全域變數控制大小

void setup() {
  size(400, 400);
}

void draw() {
  background(220);
  // 畫出依滾輪改變大小的圓形
  ellipse(width / 2, height / 2, circleSize, circleSize);
}

void mouseWheel(MouseEvent event) {
  float e = event.getCount(); // 取得滾動數值
  
  // 每次滾動改變大小 (往下滾放大, 往上滾縮小)
  circleSize -= e * 5;
  
  // 限制圓形大小的最小值與最大值, 避免過大或消失
  circleSize = constrain(circleSize, 10, 300);
}
