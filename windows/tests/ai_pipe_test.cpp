#define UNICODE
#define _UNICODE
#include <windows.h>
#include "ZephyrAiPipe.h"
#include <iostream>
int main() {
  zephyr::AiPipe client;
  client.submit({123,7,"hello world",false,false});
  for(int i=0;i<60;++i) {
    Sleep(50);auto result=client.take(123);
    if(result) {
      if(result->revision!=7||!result->segmentation||!result->candidates.empty())return 2;
      std::cout<<"Native C++ broker named-pipe round trip passed (AI disabled, no cloud request)\n";return 0;
    }
  }
  std::cerr<<"Named-pipe response timed out\n";return 1;
}
