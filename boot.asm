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
    
    ; Get system information before loading kernel
    call get_system_info
    call load_kernel
    mov si, kernel_loaded_msg
    call print_string
    cli
    xor ax, ax
    mov ds, ax
    in al, 0x92
    or al, 2
    out 0x92, al

    ; Load GDT
    lgdt [gdt_desc]
    
    ; Enter protected mode
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    
    ; Far jump to flush the pipeline and load CS
    jmp dword 0x08:clear_pipe    ; Use dword to ensure 32-bit jump

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
    mov ah, 0x02            ; BIOS read sectors function
    mov al, 16              ; Read 16 sectors (8KB should be enough)
    mov ch, 0x00            ; Cylinder 0
    mov dh, 0x00            ; Head 0
    mov bx, 0x1000          ; Load to 0x1000
    mov cl, 0x02            ; Start from sector 2
    int 0x13                ; Call BIOS
    jc disk_error           ; Check for error
    ret

disk_error:
    mov si, error_msg
    call print_string
    jmp $

; Function to gather system information
get_system_info:
    ; Set up destination address
    mov di, SYSINFO_ADDR
    
    ; Copy signature
    mov si, SYSINFO_SIG
    mov cx, 8                  ; Length of "SYSINFO\0"
    rep movsb
    
    ; Get conventional memory size
    int 0x12                   ; Returns KB in AX
    mov [di], ax              ; Store memory size
    add di, 2                 ; Move past memory size
    
    ; Get BIOS information
    push es
    mov ax, 0xF000
    mov es, ax
    
    ; Copy BIOS vendor string
    mov si, 0xE000            ; Typical BIOS vendor location
    mov cx, 16                ; Max length to copy
.copy_vendor:
    mov al, [es:si]
    test al, al
    jz .vendor_done
    cmp al, ' '
    jb .vendor_done
    mov [di], al
    inc si
    inc di
    loop .copy_vendor
.vendor_done:
    mov byte [di], 0          ; Null terminate
    inc di                    ; Move past null terminator
    
    ; Copy BIOS date string
    mov si, 0xFFF5            ; Typical BIOS date location
    mov cx, 8                 ; Date string length
.copy_date:
    mov al, [es:si]
    mov [di], al
    inc si
    inc di
    loop .copy_date
    mov byte [di], 0          ; Null terminate
    
    pop es
    ret

boot_drive db 0            ; Storage for boot drive number
error_msg db 'DISK READ FAILED!', 0

boot_msg db 'NovusOS Bootloader starting...', 13, 10, 0

; Constants for system info structure
SYSINFO_ADDR equ 0x500
SYSINFO_SIG  db 'SYSINFO', 0
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
    ; Setup data segments
    mov ax, 0x10        ; Data segment selector
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000    ; Setup stack
    
    ; Enable A20 line again to be sure
    in al, 0x92
    or al, 2
    out 0x92, al
    
    ; Clear VGA text buffer (80x25)
    mov edi, 0xB8000
    mov ecx, 80*25
    mov ax, 0x0720     ; Space with gray attribute
    rep stosw
    
    ; Print boot message
    mov esi, boot_msg32
    mov edi, 0xB8000
    call print_string32_rainbow
    
    ; Give a short delay to show the message
    mov ecx, 0x100000
.delay:
    loop .delay
    
    ; Jump to kernel (use far jump to ensure CS is set correctly)
    jmp dword 0x08:0x1000      ; Jump to kernel

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