#include <string.h>

int main(int argc, char **argv) { return argc == 2 && strcmp(argv[1], "ok") == 0 ? 0 : 1; }
