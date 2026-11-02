#ifndef PCM_H
#define PCM_H

#include <Arduino.h>

void startPlayback(const unsigned char *data, int length);
void stopPlayback();

#endif
