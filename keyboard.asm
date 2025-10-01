[bits 32]
[org 0x1000]

cursor_pos dd 0xB81E0    ; Track current write position

kernel_start:
    call display_info
    
    call wait_for_key    ; AL has ASCII character
    
    ; Write character to screen at cursor position
    mov edi, [cursor_pos]
    mov [edi], al        ; Write character
    mov byte [edi+1], 0x07  ; Write color
    
    add dword [cursor_pos], 2
    mov edi, [cursor_pos]
    cmp edi, 0xB8FA0           ; End of screen (line 25)
    jl .ok
    mov dword [cursor_pos], 0xB81E0  ; Reset to line 3
    .ok:
    jmp kernel_start
; Create an info display function
display_info:
    mov edi, 0xB8000        ; Top of screen
    mov esi, os_name
    call print_string_at
    ; TODO: Display more info
    ret

; Prints null-terminated string at EDI position
; ESI = pointer to string
; EDI = screen memory position
print_string_at:
    mov al, [esi]
    cmp al, 0
    je .done
    
    mov [edi], al
    mov byte [edi + 1], 0x0F
    inc esi
    add edi, 2
    jmp print_string_at

.done:
    ret



wait_for_key:
    in al, 0x64
    test al, 0x01
    jz wait_for_key
    in al, 0x60
    
    cmp al, 0x80
    jae wait_for_key
    
    ; Check for backspace BEFORE table lookup
    cmp al, 0x0E
    je .handle_backspace
    
    ; Normal character lookup
    movzx ebx, al
    mov al, [scancode_to_ascii + ebx]
    test al, al
    jz wait_for_key
    ret


.handle_backspace:
    mov edi, [cursor_pos]        ; Get current cursor position
    cmp edi, 0xB81E0             ; Compare to line 3 start (or whatever line you're using)
    jle kernel_start             ; If at or before start, ignore backspace
    
    ; Safe to backspace
    sub dword [cursor_pos], 2    ; Move back one character
    mov edi, [cursor_pos]        ; Get new position
    mov byte [edi], ' '          ; Write space
    mov byte [edi+1], 0x07       ; Write color
    jmp wait_for_key

scancode_to_ascii:
    times 0x02 db 0
    db '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '='  ; 0x02-0x0D
    times 0x10-0x0E db 0
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']'  ; 0x10-0x1B
    db 0  ; Enter (0x1C)
    db 0  ; Left Ctrl (0x1D)
    db 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', 0x27      ; 0x1E-0x28
    db 0  ; backtick (0x29)
    db 0  ; Left Shift (0x2A)
    db '\'  ; backslash (0x2B)
    db 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/'            ; 0x2C-0x35
    times 0x39-0x36 db 0
    db ' '  ; Space (0x39)
    times 256-0x3A db 0  ; Fill rest with zeros
os_name db 'novusOS v0.1', 0