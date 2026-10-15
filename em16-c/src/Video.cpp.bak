#include "Video.h"

#include "emu816.h"

#include <string.h>
#include <iostream>

#ifdef NO_SDL

Video::Video()
{
  _w = 320;
  _h = 240;
}

Video::~Video()
{
}

void Video::reset()
{
}

wdc816::Byte Video::getByte(wdc816::Addr ea)
{
  return mem[ea & 0xFFFF];
}

void Video::setByte(wdc816::Addr ea, wdc816::Byte data)
{
  mem[ea & 0xFFFF] = data;
}

void Video::run()
{
  while (!emu816::isStopped()) {
    emu816::step();
  }
}

#else // SDL enabled

Video::Video()
{
  _w = 320;
  _h = 240;

  if (SDL_Init(SDL_INIT_VIDEO) != 0) {
	std::cout << "SDL_Init Error: " << SDL_GetError() << std::endl;
	return;
  }

  window = SDL_CreateWindow("RSC Forth", SDL_WINDOWPOS_CENTERED,
							SDL_WINDOWPOS_CENTERED, _w, _h, 0);
  if (window == NULL) {
	std::cout << "SDL_CreateWindow Error: " << SDL_GetError() << std::endl;
	return;
  }

  renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
  if (renderer == NULL) {
	std::cout << "SDL_CreateRenderer Error: " << SDL_GetError() << std::endl;
	return;
  }

  SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
  SDL_RenderClear(renderer);
  SDL_RenderPresent(renderer);
}

Video::~Video()
{
  SDL_DestroyRenderer(renderer);
  SDL_DestroyWindow(window);
  SDL_Quit();
}

void Video::reset()
{
}

wdc816::Byte Video::getByte(wdc816::Addr ea)
{
  return mem[ea & 0xFFFF];
}

void Video::setByte(wdc816::Addr ea, wdc816::Byte data)
{
  int banka = ea & 0xFFFF;
  int x = banka % (_w / 8);
  int y = x; //banka / BytesPerRow;

  mem[banka] = data;

  for (int iy = 0; iy < _h; iy++) {
	for (int ix = 0; ix < (_w / 8); ix++) {
	  int data = mem[iy * (_w / 8) + ix];
	  for (int i = 0; i < 8; i++) {
		if (data & (1 << i)) {
		  SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
		  std::cout << "Draw(" << ix * 8 + (7 - i) << ", " << iy << ")" << std::endl;
		} else {
		  SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
		}
		SDL_RenderDrawPoint(renderer, ix * 8 + (7 - i), iy);
	  }
	}
  }
  SDL_RenderPresent(renderer);

  std::cout << "Set byte at [" << std::hex << ea << "]" << std::dec << x << ", " << y << " to " << data << std::endl;
}

void Video::run()
{
  SDL_Event Event;

  while (true) {
	while (SDL_PollEvent(&Event)) {
	  if (Event.type == SDL_QUIT) [[unlikely]] {
		std::cout << "Quitting" << std::endl;
		SDL_Quit();
		return;
	  }
	}
	if (emu816::isStopped ()) {
	  return;
	}
	emu816::step();
  }
}

#endif
