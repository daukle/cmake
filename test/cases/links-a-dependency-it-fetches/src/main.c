#include <stdio.h>

#include "ir.h"

int main(void) {
    if (basekit_ir_answer() != 42) return 1;
    FILE *evidence = fopen("linked.txt", "w");
    if (evidence == NULL) return 1;
    fputs("linked\n", evidence);
    fclose(evidence);
    return 0;
}
