#include <stdio.h>

int main(int argc, char **argv) {
    printf("argv:");
    for (int index = 1; index < argc; index++) {
        printf("[%s]", argv[index]);
    }
    printf("\n");
    return 0;
}
