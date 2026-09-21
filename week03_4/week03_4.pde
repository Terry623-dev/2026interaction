//week03-4-processing-NS-SHAFT-01
//小朋友下樓梯
void setup(){
  size(600,600); //小畫家截YT圖片 得到大小
}
void draw(){
  background(0, 5, 95); //小畫家的吸管 吸色彩 再編輯
  fill(47, 105, 190); //左右磚的色彩
  for(int i=0; i<=10; i++){
    rect(0, i*70, 25, 60); //左邊的牆
    rect(600-25, i*70, 25, 60); //右邊的牆
  }
}
