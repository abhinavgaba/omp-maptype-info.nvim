#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

const char* getAsHex(const char* Input) {
  static char Output[100];
  unsigned long long UL = strtoull(Input, NULL, 0);
  sprintf(Output, "0x%016llx", UL);
  return Output;
}

const char* getAsDec(const char* Input) {
  static char Output[100];
  unsigned long long UL = strtoull(Input, NULL, 0);
  sprintf(Output, "%llu", UL);
  return Output;
}
