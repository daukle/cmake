#include <stdio.h>
#include "greet.h"

int main(void) {
    printf("%d %d\n", greet(), GREET_BASE);
    return 0;
}
