#include <stdio.h>

int main(void) {
    FILE *evidence = fopen("ran.txt", "w");
    if (evidence == NULL) return 1;
    fputs("ran\n", evidence);
    fclose(evidence);
    return 0;
}
