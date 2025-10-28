[org 0x7C00]
[bits 16]

start:
    mov [boot_drive], dl
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    
    ; Check 64-bit support
    call check_long_mode
    test ax, ax
    jz no_long_mode
    
    ; Get system info
    call get_system_info
    
    ; Load kernel
    call load_kernel
    
    ; Setup paging
    call setup_paging
    
    ; Enable A20
    in al, 0x92
    or al, 2
    out 0x92, al
    
    ; Load GDT
    lgdt [gdt_desc]
    
    ; Enter protected mode
    cli
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    
    jmp dword 0x08:protected_mode

check_long_mode:
    pushfd
    pop eax
    mov ecx, eax
    xor eax, 0x200000
    push eax
    popfd
    pushfd
    pop eax
    push ecx
    popfd
    xor eax, ecx
    jz .no
    
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb .no
    
    mov eax, 0x80000001
    cpuid
    test edx, 0x20000000
    jz .no
    
    mov ax, 1
    ret
.no:
    xor ax, ax
    ret

no_long_mode:
    cli
    hlt

setup_paging:
    mov edi, 0x1000
    mov ecx, 0x1000
    xor eax, eax
    rep stosd
    
    mov edi, 0x1000
    mov dword [edi], 0x2003
    mov edi, 0x2000
    mov dword [edi], 0x3003
    mov edi, 0x3000
    mov dword [edi], 0x83
    ret

load_kernel:
    mov dl, [boot_drive]
    mov ah, 0x02
    mov al, 16
    mov ch, 0
    mov dh, 0
    mov bx, 0x1000
    mov cl, 2
    int 0x13
    ret

get_system_info:
    mov di, 0x500
    mov si, sysinfo_sig
    mov cx, 8
    rep movsb
    int 0x12
    mov [di], ax
    ret

boot_drive db 0
sysinfo_sig db 'SYSINFO', 0

align 8
gdt:
    dq 0
    dw 0xFFFF, 0, 0x9A00, 0x00CF
    dw 0xFFFF, 0, 0x9200, 0x00CF
    dw 0, 0, 0x9A00, 0x0020
    dw 0, 0, 0x9200, 0
gdt_end:

gdt_desc:
    dw gdt_end - gdt - 1
    dd gdt

[bits 32]
protected_mode:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000
    
    mov eax, cr4
    or eax, 0x20
    mov cr4, eax
    
    mov eax, 0x1000
    mov cr3, eax
    
    mov ecx, 0xC0000080
    rdmsr
    or eax, 0x100
    wrmsr
    
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    
    jmp 0x18:long_mode

[bits 64]
long_mode:
    ; Setup segments
    xor rax, rax
    mov ax, 0x20
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov rsp, 0x90000
    
    ; Print a character to show we're in 64-bit mode
    mov byte [0xB8000], 'X'
    mov byte [0xB8001], 0x0F
    
    ; Jump directly to kernel
    mov rax, 0x1000
    jmp rax

times 510-($-$$) db 0
dw 0xAA55