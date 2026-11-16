//week11-4-processing-joystick-serial-2048
//修改自week10-4-processing-2048-keycode-up-down
import processing.serial.*; //
Serial myPort;
void setup(){
  size(550, 550);
  genNewBlock();
  myPort = new Serial( this, "COM3", 9600);
}
//int[][] a = {{0, 2, 0, 0}, {0, 0, 0, 0}, {0, 2, 2, 2}, {4, 4, 4, 4}};
int[][] a = new int[4][4];//java 的2D陣列宣告 裡面都是0
void genNewBlock(){//產生新的小方塊
  int zeros = 0; //有幾個是0 將會在裡面亂數挑
  for(int i=0; i<4; i++){
    for(int j=0; j<4; j++){
      if (a[i][j]==0) zeros++;
    }
  }
  int choose = int(random(zeros));
  for(int i=0; i<4; i++){
    for(int j=0; j<4; j++){
      if (a[i][j]==0){
        if(choose==0) a[i][j] = 2;
        choose--;
      }
    }
  }
}
//
void keyPressed(){
  if(keyCode==RIGHT) move(1);
  if(keyCode==LEFT) move(2);
  if(keyCode==UP) move(3);
  if(keyCode==DOWN) move(4);
}
void move(int type){
  if(type==1){
    for(int i=0; i<4; i++){
      int j2 = 3;
      for(int j=3; j>=0; j--){//裡面的迴圈 要往右
        if(a[i][j]>0){ //有格子要移動
          int temp = a[i][j2];//有點像交換
          a[i][j2] = a[i][j];//移動最右邊
          a[i][j] = temp;
          j2--;// 次右邊的格子
        }
      }
    }
  }else if(type==2){//左鍵往左
    for(int i=0; i<4; i++){
      int j2 = 0;
      for(int j=0; j<4; j++){
        if(a[i][j]>0){ //有格子 要移動
          int temp = a[i][j2];//有點像交換
          a[i][j2] = a[i][j];//移動最右邊
          a[i][j] = temp;
          j2++;// 次右邊的格子
        }
      }
    }
  }else if (type==3){
   for(int j=0; j<4; j++){
     int i2 = 0;
     for(int i=0; i<4; i++){
       if(a[i][j]>0){
         int temp = a[i2][j];
         a[i2][j] = a[i][j];
         a[i][j] = temp;
         i2++;
       }
     }
   }
  }else if(type==4){
    for(int j=0; j<4; j++){
      int i2 = 3;
      for(int i=3; i>=0; i--){
        if(a[i][j]>0){
          int temp = a[i2][j];
          a[i2][j] = a[i][j];
          a[i][j] = temp;
          i2--;
        }
      }
    }
   }
  genNewBlock();
}
int x = 128, y = 128, sw = 0;
void draw(){
  background(250, 248, 239); //淡淡的背景色
  if(myPort.available()  >=3){
    int x2 = (int) myPort.read();
    int y2 = (int) myPort.read();
    int sw2 = (int) myPort.read();
    if(x < 128+50 && x2 >= 128+50) move(1);
    if(x > 128-50 && x2 <= 128-50) move(2);
    if(y < 128+50 && y2 >= 128+50) move(4);
    if(y > 128-50 && y2 <= 128-50) move(3);
    x = x2;
    y = y2;
  }
  noStroke(); //不要黑線
  fill(187, 173, 160); //大格子色彩
  rect(40, 40, 450, 455, 9); //大格子
  for(int i=0; i<4; i++){ //用迴圈 畫4X4格子
    for(int j=0; j<4; j++){
      int x =50 + j*(100+10);
      int y =50 + i*(100+10); // 加點位移 間隔
      fill(tileColor(a[i][j]));
      rect(x, y, 100, 100, 6);
    }
  }
}
int tileColor(int n) {
  switch(n) {
    case 0:return color(205,193,180);
    case 2:return color(238,228,218);
    case 4:return color(237,224,200);
    case 8:return color(242,177,121);
    case 16:return color(245,149,99);
    case 32:return color(246,124,95);
    case 64:return color(246,94,59);
    case 128:return color(237,207,114);
    case 256:return color(237,204,97);
    case 512:return color(237,200,80);
    case 1024:return color(237,197,63);
    default:return color(237,194,46);
  }
}
