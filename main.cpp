/*
    Autor: Yosel Balibrea Lastre
    SDL + verilator test bench, based on:
    https://projectf.io/posts/verilog-sim-verilator-sdl/
*/

#include <iostream>
#include <SDL.h>
#include <verilated.h>
#include "Vs_axis.h"      // verilog model

const int HRES = 640;
const int VRES = 480;

using namespace std;

typedef struct Pixel {  // for SDL texture
    uint8_t a;  // transparency
    uint8_t b;  // blue
    uint8_t g;  // green
    uint8_t r;  // red
} Pixel;

int main(int argc, char* argv[]){

    Pixel screenbuffer[HRES*VRES]; // screen buffer

    // SDL configuration
    SDL_Window*   sdl_window   = NULL;
    SDL_Renderer* sdl_renderer = NULL;
    SDL_Texture*  sdl_texture  = NULL;

    Verilated::commandArgs(argc, argv);  // verilator init

    // Initialize SDL
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        cout << "SDL init failed." << endl;
        return 1;
    }

    sdl_window = SDL_CreateWindow("Square", SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED, HRES, VRES, SDL_WINDOW_SHOWN);
    if (!sdl_window) {
        cout << "Window creation failed: " << SDL_GetError() << endl;
        return 1;
    }

    sdl_renderer = SDL_CreateRenderer(sdl_window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!sdl_renderer) {
        cout << "Renderer creation failed: " << SDL_GetError() << endl;
        return 1;
    }

    sdl_texture = SDL_CreateTexture(sdl_renderer, SDL_PIXELFORMAT_RGBA8888,
        SDL_TEXTUREACCESS_TARGET, HRES, VRES);
    if (!sdl_texture) {
        cout << "Texture creation failed: " << SDL_GetError() << endl;
        return 1;
    }

    const Uint8 *keyb_state = SDL_GetKeyboardState(NULL);  // keyboard

    cout << "Simulation running press Q to stop" << endl;

    // initialized verilog module
    Vs_axis* top = new Vs_axis;

    // reset
    top->arst_n = 0;  // assert reset
    top->aclk = 0;
    top->eval();
    top->aclk = 1;
    top->eval();
    top->arst_n = 1;
    top->aclk = 0;
    top->eval();

    // initialize frame rate
    uint64_t start_ticks = SDL_GetPerformanceCounter();
    uint64_t frame_count = 0;

    // main loop
    while(1){
        //cycle clock
        top->aclk = 1;
        top->eval();
        top->aclk = 0;
        top->eval();

        // update pixel if not in blanking interval
        if (top->de_o) {
            Pixel* p = &screenbuffer[top->sy_o*HRES + top->sx_o];
            p->a = 0xFF;  // transparency
            p->b = top->blue;
            p->g = top->green;
            p->r = top->red;
        }

        // update texture once per frame (in blanking)
        if (top->sy_o == VRES && top->sx_o == 0) {
            // check for quit event
            SDL_Event e;
            if (SDL_PollEvent(&e)) {
                if (e.type == SDL_QUIT) {
                    break;
                }
            }

            if (keyb_state[SDL_SCANCODE_Q]) break;  // quit if user presses 'Q'

            SDL_UpdateTexture(sdl_texture, NULL, screenbuffer, HRES*sizeof(Pixel));
            SDL_RenderClear(sdl_renderer);
            SDL_RenderCopy(sdl_renderer, sdl_texture, NULL, NULL);
            SDL_RenderPresent(sdl_renderer);
            frame_count++;
        }

    }

    // calculate frame rate
    uint64_t end_ticks = SDL_GetPerformanceCounter();
    double duration = ((double)(end_ticks-start_ticks))/SDL_GetPerformanceFrequency();
    double fps = (double)frame_count/duration;
    printf("Frames per second: %.1f\n", fps);

    top->final();  // simulation done

    SDL_DestroyTexture(sdl_texture);
    SDL_DestroyRenderer(sdl_renderer);
    SDL_DestroyWindow(sdl_window);
    SDL_Quit();

    return 0;
}