#ifndef VIDEO_H
#define VIDEO_H

#include "wdc816.h"

#include <string.h>
#include <iostream>

#include <SDL.h>

/*

Simple bitmap video

*/

class Video {
 public:
  Video();
  ~Video();
  wdc816::Byte getByte(wdc816::Addr ea);
  void setByte(wdc816::Addr ea, wdc816::Byte data);
  void reset();
  void run();
 private:
  wdc816::Byte mem[0xFFFF];

  int _w;
  int _h;
  
  SDL_Window* window;
  SDL_Renderer* renderer;
};

#endif
