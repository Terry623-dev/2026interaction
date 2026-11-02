#include "PCM.h"
#include <avr/pgmspace.h>
#include <avr/interrupt.h>

const int speakerPin = 8; 

volatile const unsigned char *playlist;
volatile int soundLength = 0;
volatile int playIndex = 0;
volatile unsigned char currentSample = 127;
volatile unsigned char pwmCounter = 0;

void startPlayback(const unsigned char *data, int length) {
  playlist = data;
  soundLength = length;
  playIndex = 0;

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
    currentSample = pgm_read_byte(&playlist[playIndex++]);
  } else {
    stopPlayback();
  }
}

void checkSoundPWM() {
  pwmCounter++;
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
