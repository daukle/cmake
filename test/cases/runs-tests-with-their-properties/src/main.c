#include <stdio.h>

int main(int argc, char **argv) {
  FILE *file = fopen(argc > 1 ? argv[1] : "input.txt", "r");
  if (file == NULL) return 1;
  fclose(file);
  return 0;
}
