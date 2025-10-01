section .data
    num1 db 3
    num2 db 5

section .bss
    result resb 1

section .text
    global _start

_start:
    mov al, [num1]      ; Load VALUE from num1
    add al, [num2]      ; Add VALUE from num2
    add al, '0'         ; Convert to ASCII character
    mov [result], al    ; Store in result memory location
    
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    mov rsi, result     ; pointer to result
    mov rdx, 1          ; write 1 byte
    syscall
    
    mov rax, 60         ; sys_exit  
    mov rdi, 0          ; exit status
    syscall             ; Don't forget this!