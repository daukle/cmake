#include <stdio.h>

int greet(void);
int count(void);

int main(void) {
    FILE *evidence = fopen("ran.txt", "w");
    if (evidence == NULL) return 1;
    fprintf(evidence, "%d\n", greet() + count());
    fclose(evidence);
    return 0;
}
