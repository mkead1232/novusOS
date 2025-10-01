[org 0x7C00]
[bits 16]
start:
    ; Save boot drive number (BIOS puts it in DL)
    mov [boot_drive], dl
    mov ax, 0
    mov ds, ax
    mov es, ax
    mov si, boot_msg
    call print_string
    call load_kernel
    mov si, kernel_loaded_msg
    call print_string
    cli
    xor ax, ax
    mov ds, ax
    in al, 0x92
    or al, 2
    out 0x92, al

    lgdt [gdt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 08h:clear_pipe

print_string:
    mov ah, 0x0E
.loop:
    mov al, [si]
    cmp al, 0
    je .done
    int 0x10
    inc si
    jmp .loop
.done:
    ret

load_kernel:
    mov dl, [boot_drive]    ; Use the drive we booted from
    mov ah, 0x02
    mov al, 0x01
    mov ch, 0x00
    mov dh, 0x00
    mov bx, 0x1000
    mov cl, 0x02
    int 0x13
    jc disk_error
    ret

disk_error:
    mov si, error_msg
    call print_string
    jmp $
boot_drive db 0            ; Storage for boot drive number
error_msg db 'DISK READ FAILED!', 0

boot_msg db 'NovusOS Bootloader starting...', 13, 10, 0
kernel_loaded_msg db 'Kernel loaded! Jumping to kernel...', 13, 10, 0

; GDT MUST come before 32-bit code
gdt:
gdt_null:
    dd 0
    dd 0
gdt_code:
    dw 0FFFFh
    dw 0
    db 0
    db 10011010b
    db 11001111b
    db 0
gdt_data:
    dw 0FFFFh
    dw 0
    db 0
    db 10010010b
    db 11001111b
    db 0
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt

[BITS 32]
clear_pipe:
    mov ax, 10h
    mov ds, ax
    mov ss, ax
    mov esp, 0x90000
    
    ; Clear screen
    mov edi, 0xB8000
    mov ecx, 2000
    mov ax, 0x0720
    rep stosw
    
    ; Rainbow text
    mov edi, 0xB8000
    mov byte [edi], 'n'
    mov byte [edi+1], 0x04
    add edi, 2
    mov byte [edi], 'o'
    mov byte [edi+1], 0x0E
    add edi, 2
    mov byte [edi], 'v'
    mov byte [edi+1], 0x0A
    add edi, 2
    mov byte [edi], 'u'
    mov byte [edi+1], 0x0B
    add edi, 2
    mov byte [edi], 's'
    mov byte [edi+1], 0x0D
    add edi, 2
    mov byte [edi], 'O'
    mov byte [edi+1], 0x0F
    add edi, 2
    mov byte [edi], 'S'
    mov byte [edi+1], 0x0F
    
    ; Jump to kernel
    jmp 0x1000

times 510-($-$$) db 0
dw 0xAA55