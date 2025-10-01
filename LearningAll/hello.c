#include "../strlen-strcpy.c"

int main() {
    char name1[20] = "Alice";
    char name2[20];
    char name3[20] = "Alice";
    char name4[20] = "Bob";
    
    // Test my_strlen
    printf("Length of '%s': %d\n", name1, my_strlen(name1));
    
    // Test my_strcpy
    my_strcpy(name2, name1);
    printf("Copied string: '%s'\n", name2);
    
    // Test my_strcmp
    printf("'%s' vs '%s': %d\n", name1, name3, my_strcmp(name1, name3)); // Should be 0
    printf("'%s' vs '%s': %d\n", name1, name4, my_strcmp(name1, name4)); // Should be non-zero
    
    return 0;
}