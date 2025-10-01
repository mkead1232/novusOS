#include <stdio.h>

void print_binary(int num) {
    for (int i = 31; i >= 0; i--) {
        if (num & (1 << i)) {    // Check if bit i is set in num
            printf("1");
        } else {
            printf("0");
        }
    }
    printf("\n");  // Add a newline at the end
}

void check_even_odd(int number) {
    if ((number & 1) == 0) {
        printf("%d is even!\n", number);
    } else {
        printf("%d is NOT even :(", number);
    }
}

int main() {
    printf("5 = "); print_binary(5);
    printf("10 = "); print_binary(10);
    printf("42 = "); print_binary(42);
    printf("255 = "); print_binary(255);

    int a = 42, b = 27;

    printf("a & b = %d\n", a & b);  // Bitwise AND
    printf("a | b = %d\n", a | b);  // Bitwise OR  
    printf("a ^ b = %d\n", a ^ b);  // Bitwise XOR
    printf("~a = %d\n", ~a);        // Bitwise NOT
    printf("a << 2 = %d\n", a << 2); // Left shift
    printf("a >> 1 = %d\n", a >> 1); // Right shift
    check_even_odd(7);
    return 0;
}