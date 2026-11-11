#include <vendored.h>

int main(void) {
  for (int index = 0; index < 1; index++) {}
  return VENDORED_VALUE == 5 ? 0 : 1;
}
