#include "PCM.h"
#include <avr/pgmspace.h>
#include <avr/interrupt.h>

const int speakerPin = 8; 

volatile const unsigned char *playlist;
volatile int soundLength = 0;
volatile int playIndex = 0;
volatile unsigned char currentSample = 128;
volatile unsigned char pwmCounter = 0;

// 新增：用來延長每個音色段落並產生豐富音調變化的計數器
volatile int repeatCount = 0;

void startPlayback(const unsigned char *data, int length) {
  playlist = data;
  soundLength = length;
  playIndex = 0;
  repeatCount = 0;

  pinMode(speakerPin, OUTPUT);

  cli();
  TCCR1A = 0;
  TCCR1B = 0;
  TCNT1  = 0;
  OCR1A = 249; 
  TCCR1B |= (1 << WGM12);
  TCCR1B |= (1 << CS11);
  TIMSK1 |= (1 << OCIE1A);
  sei();
}

ISR(TIMER1_COMPA_vect) {
  if (playIndex < soundLength) {
    currentSample = pgm_read_byte(&playlist[playIndex]);
    
    // 每播放 16 個取樣點（一個完整波形週期），就重複循環 25 次，把 0.1 秒的陣列拉長成 2.5 秒的豐富旋律！
    playIndex++;
    if (playIndex % 16 == 0) {
      repeatCount++;
      if (repeatCount < 25) {
        playIndex -= 16; // 退回這一個波形週期的開頭，讓該音色持續發聲
      } else {
        repeatCount = 0; // 進入下一個音色段落！
      }
    }
  } else {
    stopPlayback();
  }
}

void checkSoundPWM() {
  pwmCounter += 8; // 加快軟體 PWM 步進頻率，消除高頻雜音，讓聲音更乾淨宏亮！
  if (pwmCounter < currentSample) {
    PORTB |= B00000001;
  } else {
    PORTB &= B11111110;
  }
}

void stopPlayback() {
  TIMSK1 &= ~(1 << OCIE1A);
  digitalWrite(speakerPin, LOW);
  soundLength = 0;
}
