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
    ; Setup data segments and stack
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000

    ; Clear VGA text buffer (80x25)
    mov edi, 0xB8000
    mov ecx, 80*25
    mov ax, 0x0720
    rep stosw

    ; Example: print "NovusOS Bootloader"
    mov esi, boot_msg32         ; ESI = string pointer (linear)
    mov edi, 0xB8000            ; EDI = VGA text memory
    call print_string32_rainbow

    jmp 0x1000                  ; Jump to kernel

; --------------------------------------------------------------------
; print_string32_rainbow
; IN:  ESI -> zero-terminated string
;      EDI -> VGA text buffer position
; OUT: prints characters with rainbow colors (forces 7-bit ASCII)
; --------------------------------------------------------------------
print_string32_rainbow:
    pushad
    mov ebx, rainbow_colors
    xor ecx, ecx                ; color index = 0

.loop:
    mov al, [esi]               ; load byte from string
    test al, al
    je .done

    and al, 0x7F                ; <-- FIX: ensure ASCII (strip high bit)
    mov [edi], al               ; write char to VGA
    mov dl, [ebx + ecx]         ; pick color attribute
    mov [edi+1], dl             ; write attribute

    add edi, 2                  ; next cell
    inc esi
    inc ecx
    cmp ecx, rainbow_count
    jl .no_wrap
    xor ecx, ecx                ; wrap colors
.no_wrap:
    jmp .loop

.done:
    popad
    ret

; --------------------------------------------------------------------
boot_msg32 db 'novusOS', 0

; Rainbow attributes (cycle through them)
rainbow_colors db 0x04, 0x0E, 0x0A, 0x0B, 0x0D
rainbow_count  equ ($ - rainbow_colors)

times 510-($-$$) db 0
dw 0xAA55