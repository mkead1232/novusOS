[bits 32]
[org 0x1000]

cursor_pos dd 0xB81E0    ; Track current write position
input_buffer:
    times 64 db 0
buffer_index dd 0

compare_strings:
    .loop:
        mov al, [esi]
        mov bl, [edi]
        cmp al, bl
        jne .not_equal
        test al, al
        je .equal
        inc esi
        inc edi
        jmp .loop

    .equal:
        xor eax, eax
        ret

    .not_equal:
        mov eax, 1
        ret
    
kernel_start:
    ; Clear registers and buffer
    xor eax, eax
    xor ebx, ebx
    mov dword [buffer_index], 0
    
    ; Clear any pending keyboard data
    in al, 0x60          ; Read and discard any pending data
    in al, 0x60          ; Read twice to ensure buffer is clear
    
    call display_info
    call show_prompt
    call update_hardware_cursor  ; Set initial cursor position
    
main_loop:
    call wait_for_key    ; AL has ASCII character
    
    ; Check if it's a special key that was already handled
    test al, al
    jz main_loop         ; If AL is 0, key was already processed
    
    ; Write character to screen at cursor position
    mov edi, [cursor_pos]
    mov [edi], al        ; Write character
    mov byte [edi+1], 0x07  ; Write color
    
    ; Store in buffer
    mov ebx, [buffer_index]
    mov [input_buffer + ebx], al
    inc dword [buffer_index]

    ; Move cursor forward
    add dword [cursor_pos], 2
    mov edi, [cursor_pos]
    cmp edi, 0xB8FA0           ; End of screen (line 25)
    jl .ok
    mov dword [cursor_pos], 0xB81E0  ; Reset to line 3
.ok:
    call update_hardware_cursor  ; Update cursor to new position
    jmp main_loop

; Update hardware cursor position based on cursor_pos
update_hardware_cursor:
    push eax
    push ebx
    push edx
    
    ; Calculate cursor position (convert memory address to screen position)
    mov eax, [cursor_pos]
    sub eax, 0xB8000     ; Subtract video memory base
    shr eax, 1           ; Divide by 2 (each char is 2 bytes)
    
    ; EAX now contains the cursor position (0-1999 for 80x25)
    mov ebx, eax         ; Save position
    
    ; Set low byte of cursor position
    mov dx, 0x3D4        ; VGA CRTC index register
    mov al, 0x0F         ; Cursor Location Low register
    out dx, al
    
    mov dx, 0x3D5        ; VGA CRTC data register
    mov al, bl           ; Low byte of cursor position
    out dx, al
    
    ; Set high byte of cursor position
    mov dx, 0x3D4        ; VGA CRTC index register
    mov al, 0x0E         ; Cursor Location High register
    out dx, al
    
    mov dx, 0x3D5        ; VGA CRTC data register
    mov al, bh           ; High byte of cursor position
    out dx, al
    
    pop edx
    pop ebx
    pop eax
    ret

; Enable cursor with specific shape (optional - call this in kernel_start if needed)
enable_cursor:
    push eax
    push edx
    
    ; Set cursor start line (top of cursor)
    mov dx, 0x3D4
    mov al, 0x0A         ; Cursor Start Register
    out dx, al
    
    mov dx, 0x3D5
    mov al, 0x0E         ; Start at line 14 (for underscore cursor)
    out dx, al
    
    ; Set cursor end line (bottom of cursor)
    mov dx, 0x3D4
    mov al, 0x0B         ; Cursor End Register
    out dx, al
    
    mov dx, 0x3D5
    mov al, 0x0F         ; End at line 15 (for underscore cursor)
    out dx, al
    
    pop edx
    pop eax
    ret

; Create an info display function
display_info:
    mov edi, 0xB8F00      ; Move to a different position at bottom
    mov esi, os_name
    call print_string_at
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
    in al, 0x64          ; Read keyboard controller status
    test al, 0x01        ; Check if output buffer is full
    jz wait_for_key      ; If not, keep waiting
    in al, 0x60          ; Read scancode
    
    cmp al, 0x2A         ; Left Shift press
    je shift_press
    cmp al, 0x36         ; Right Shift press
    je shift_press
    cmp al, 0xAA         ; Left Shift release
    je shift_release
    cmp al, 0xB6         ; Right Shift release
    je shift_release
    
    cmp al, 0x80         ; If it's a key release
    jae wait_for_key     ; Ignore key releases
    
    ; Check for backspace
    cmp al, 0x0E
    je handle_backspace
    
    ; Check for Enter
    cmp al, 0x1C
    je handle_enter
    
    ; Normal character lookup
    movzx ebx, al
    mov al, [shift_pressed]
    test al, al
    jz .no_shift
    mov al, [scancode_to_ascii_shift + ebx]
    jmp .check_char
.no_shift:
    mov al, [scancode_to_ascii + ebx]
.check_char:
    test al, al          ; Check if we got a valid character
    jz wait_for_key      ; If not, keep waiting
    ret

.shift_press:
    mov byte [shift_pressed], 1
    jmp wait_for_key

.shift_release:
    mov byte [shift_pressed], 0
    jmp wait_for_key
    
handle_enter:
    ; Null-terminate the buffer BEFORE comparison
    mov ebx, [buffer_index]
    mov byte [input_buffer + ebx], 0
    
    ; Move cursor to new line
    call newline
    
    ; Compare with "help" command
    mov esi, input_buffer
    mov edi, help_cmd
    call compare_strings
    cmp eax, 0
    je cmd_help
    
    ; Compare with "clear" command
    mov esi, input_buffer
    mov edi, clear_cmd
    call compare_strings
    cmp eax, 0
    je cmd_clear
    
    ; Compare with "about" command
    mov esi, input_buffer
    mov edi, about_cmd
    call compare_strings
    cmp eax, 0
    je cmd_about
    
    ; Compare with "casc" command
    mov esi, input_buffer
    mov edi, casc_cmd
    call compare_strings
    cmp eax, 0
    je cmd_casc

    ; Check if command is "echo"
    mov esi, input_buffer
    mov edi, echo_cmd
    mov ecx, 4              ; Length of "echo" (without space)
.check_echo:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .not_echo          ; Not "echo", continue to next command
    inc esi
    inc edi
    loop .check_echo
    
    ; Check if it's just "echo" or "echo " (space or null after)
    mov al, [esi]
    cmp al, 0              ; Is it end of string?
    je cmd_echo            ; Yes, jump to echo command
    cmp al, ' '           ; Is it a space?
    je cmd_echo            ; Yes, jump to echo command
    jmp .not_echo         ; No, must be something else
    
.not_echo:
    ; Compare with "specs" command
    mov esi, input_buffer
    mov edi, specs_cmd
    call compare_strings
    cmp eax, 0
    je cmd_specs
    
    ; Compare with "about" command
    mov esi, input_buffer
    
    ; Unknown command - only show if buffer has more than prompt
    mov ebx, [buffer_index]
    cmp ebx, 2              ; Check if there's anything after prompt
    jle .skip_unknown       ; Skip if only prompt or less
    
    mov esi, msg_unknown
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    
.skip_unknown:
    call clear_input_buffer
    xor al, al          ; Return 0 to indicate key was processed
    ret

; Define system info structure address
SYSINFO_ADDR equ 0x500

cmd_specs:
    ; Get CPU info using CPUID
    mov eax, 0          ; Get vendor ID
    cpuid
    
    ; Print CPU vendor
    mov edi, [cursor_pos]
    mov esi, cpu_msg
    call print_string_at
    
    ; Store and print vendor string (12 chars: 4 from each register)
    push eax            ; Save EAX
    
    ; Print first part (from EBX)
    mov eax, ebx
    call print_cpu_chars
    
    ; Print middle part (from EDX)
    mov eax, edx
    call print_cpu_chars
    
    ; Print last part (from ECX)
    mov eax, ecx
    call print_cpu_chars
    
    pop eax             ; Restore EAX
    call newline
    
    ; Define system info structure address
    SYSINFO_ADDR equ 0x500
    
    ; Verify system info structure
    mov esi, SYSINFO_ADDR     ; System info structure location
    mov edi, sysinfo_sig
    mov ecx, 8                ; Length of signature + null
    call compare_strings
    cmp eax, 0
    jne .no_sysinfo
    
    ; Print RAM size
    mov edi, [cursor_pos]
    mov esi, ram_msg
    call print_string_at
    
    ; Convert RAM size to string
    mov ax, [SYSINFO_ADDR + 7] ; Load RAM size from structure
    mov cx, 0                  ; Digit counter
    mov bx, 10                 ; Divisor
.convert_loop:
    xor dx, dx              ; Clear for division
    div bx
    push dx                 ; Save remainder
    inc cx
    test ax, ax
    jnz .convert_loop
    
.print_digits:
    pop ax
    add al, '0'            ; Convert to ASCII
    mov [edi], al
    mov byte [edi+1], 0x07
    add edi, 2
    loop .print_digits
    
    ; Print KB
    mov esi, kb_msg
    call print_string_at
    call newline
    
    ; Print BIOS vendor
    mov edi, [cursor_pos]
    mov esi, bios_msg
    call print_string_at
    mov esi, SYSINFO_ADDR + 9    ; Point to BIOS vendor in structure
    call print_string_at
    call newline
    
    ; Print BIOS date
    mov edi, [cursor_pos]
    mov esi, bios_date_msg
    call print_string_at
    mov esi, SYSINFO_ADDR + 26   ; Point to BIOS date in structure
    call print_string_at
    call newline
    jmp .done
    
.no_sysinfo:
    ; Print error message if system info not found
    mov edi, [cursor_pos]
    mov esi, sysinfo_error
    call print_string_at
    call newline
    
.done:
    mov [cursor_pos], edi
    call clear_input_buffer
    xor al, al
    call newline
    ret

; Helper function to print hex string
print_hex_string:
    push ecx
    mov ecx, 4         ; 4 bytes
.hex_loop:
    rol eax, 8         ; Get next byte
    push eax
    and al, 0xFF
    cmp al, ' '        ; Check if printable
    jb .skip
    mov [edi], al
    mov byte [edi+1], 0x07
    add edi, 2
.skip:
    pop eax
    loop .hex_loop
    pop ecx
    ret

cmd_echo:
    ; Skip past "echo "
    mov esi, input_buffer
    add esi, 5          ; Skip past "echo" + space
    
    ; Check if there's anything after "echo "
    mov al, [esi]
    test al, al
    jz .echo_no_args    ; If nothing after "echo ", just return
    
    ; Print the rest of the string
    mov edi, [cursor_pos]
    
.echo_loop:
    mov al, [esi]       ; Get character from input
    test al, al         ; Check for null terminator
    jz .echo_done
    
    mov [edi], al       ; Write character
    mov byte [edi+1], 0x07  ; Gray color
    add edi, 2          ; Move to next screen position
    inc esi             ; Move to next input character
    jmp .echo_loop
    
.echo_done:
    mov [cursor_pos], edi
    call newline
    
.echo_no_args:
    call clear_input_buffer
    xor al, al
    ret

; ==== Command Handlers ====
cmd_help:
    mov esi, msg_help
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    call clear_input_buffer
    xor al, al
    ret

cmd_clear:
    call clear_screen
    call clear_input_buffer
    xor al, al
    ret
cmd_casc:
    mov esi, msg_casc
    mov edi, [cursor_pos]
    call print_string32_rainbow
    call newline
    call clear_input_buffer
    xor al, al
    ret
cmd_about:
    mov esi, msg_about
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    call clear_input_buffer
    xor al, al
    ret

; Back to wait_for_key handlers
shift_press:
    mov byte [shift_pressed], 1
    jmp wait_for_key

shift_release:
    mov byte [shift_pressed], 0
    jmp wait_for_key

handle_backspace:
    mov edi, [cursor_pos]
    sub edi, 2              ; Position we'd backspace to
    
    ; Calculate column position
    mov eax, edi
    sub eax, 0xB8000       ; Get offset from start of video memory
    mov ecx, 160           ; Bytes per line (80 columns * 2 bytes per char)
    xor edx, edx
    div ecx                ; EDX now contains byte offset within line
    
    ; Don't backspace if we're at prompt position (first 2 bytes of line)
    cmp edx, 2             ; Smiley + space (4 bytes total, but we're checking position after backspace)
    jle .backspace_done    ; If at or before prompt, don't backspace
    
    ; Safe to backspace
    mov dword [cursor_pos], edi  ; Update cursor position
    mov byte [edi], ' '          ; Write space
    mov byte [edi+1], 0x07       ; Write color
    
    ; Remove from buffer
    mov ebx, [buffer_index]
    test ebx, ebx
    jz .backspace_done
    dec dword [buffer_index]
    
    call update_hardware_cursor  ; Update cursor after backspace
    
.backspace_done:
    xor al, al              ; Return 0 to indicate key was processed
    ret

newline:
    ; Calculate current line
    mov eax, [cursor_pos]
    sub eax, 0xB8000
    mov ecx, 160
    xor edx, edx
    div ecx             ; EAX = line number, EDX = column offset
    
    ; Move to start of next line
    inc eax             ; Next line
    mul ecx             ; EAX = byte offset of next line
    add eax, 0xB8000
    
    ; Check if we need to wrap
    cmp eax, 0xB8FA0    ; End of screen
    jl .no_wrap
    mov eax, 0xB81E0    ; Reset to line 3
    
.no_wrap:
    mov [cursor_pos], eax
    call show_prompt
    call update_hardware_cursor  ; Update cursor after newline
    ret

clear_screen:
    mov edi, 0xB8000
    mov ecx, 2000       ; 80x25 characters
.clear_loop:
    mov byte [edi], ' '
    mov byte [edi+1], 0x07
    add edi, 2
    loop .clear_loop
    
    ; Reset cursor to top after clear
    mov dword [cursor_pos], 0xB8000
    call display_info   ; Redraw info
    mov dword [cursor_pos], 0xB81E0  ; Reset to line 3
    call show_prompt
    call update_hardware_cursor  ; Update cursor after clear
    ret

clear_input_buffer:
    ; Clear buffer
    mov edi, input_buffer
    mov ecx, 64
    xor eax, eax
    rep stosb
    
    ; Reset index
    mov dword [buffer_index], 0
    ret

; Initialize keyboard controller
init_keyboard:
    ; Wait for keyboard buffer to be empty
    call wait_kbd_empty
    
    ; Disable both PS/2 ports
    mov al, 0xAD
    out 0x64, al
    call wait_kbd_empty
    mov al, 0xA7
    out 0x64, al
    call wait_kbd_empty
    
    ; Flush output buffer (read until empty)
.flush_loop:
    in al, 0x64
    test al, 1
    jz .flush_done
    in al, 0x60
    jmp .flush_loop
.flush_done:

    ; Set command byte
    mov al, 0x20          ; Read command byte
    out 0x64, al
    call wait_kbd_read
    in al, 0x60
    push ax
    
    ; Write new command byte
    mov al, 0x60          ; Write command byte
    out 0x64, al
    call wait_kbd_empty
    pop ax
    and al, 0x10          ; Keep translation
    or al, 0x47           ; Enable port 1, interrupts, translation
    out 0x60, al
    call wait_kbd_empty
    
    ; Enable first PS/2 port
    mov al, 0xAE
    out 0x64, al
    call wait_kbd_empty
    
    ; Reset keyboard and wait for ACK
    mov al, 0xFF
    out 0x60, al
.wait_ack:
    call wait_kbd_read
    in al, 0x60
    cmp al, 0xFA          ; Check for ACK
    jne .wait_ack
    
    ; Enable scanning
    mov al, 0xF4
    out 0x60, al
.wait_final_ack:
    call wait_kbd_read
    in al, 0x60
    cmp al, 0xFA          ; Check for ACK
    jne .wait_final_ack
    
    ret

; Wait for keyboard controller buffer to be empty
wait_kbd_empty:
    in al, 0x64
    test al, 2
    jnz wait_kbd_empty
    ret

; Wait for keyboard controller output
wait_kbd_read:
    in al, 0x64
    test al, 1
    jz wait_kbd_read
    ret
; Function to print 4 characters from EAX (for CPU vendor string)
print_cpu_chars:
    push ecx
    push edi
    mov ecx, 4          ; Process 4 characters
.loop:
    mov edi, [cursor_pos]
    mov [edi], al       ; Write character
    mov byte [edi+1], 0x07  ; Gray color
    add dword [cursor_pos], 2
    ror eax, 8         ; Get next character
    loop .loop
    pop edi
    pop ecx
    ret

shift_pressed db 0     ; Track shift key state

scancode_to_ascii:
    times 0x02 db 0
    db '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '='  ; 0x02-0x0D
    times 0x10-0x0E db 0
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']'  ; 0x10-0x1B
    db 0  ; Enter (0x1C)
    db 0  ; Left Ctrl (0x1D)
    db 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", '`'  ; 0x1E-0x29
    db 0  ; Left Shift (0x2A)
    db '\', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/'       ; 0x2B-0x35
    times 0x39-0x36 db 0
    db ' '  ; Space (0x39)
    times 256-0x3A db 0  ; Fill rest with zeros

scancode_to_ascii_shift:
    times 0x02 db 0
    db '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+'  ; 0x02-0x0D
    times 0x10-0x0E db 0
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}'  ; 0x10-0x1B
    db 0  ; Enter (0x1C)
    db 0  ; Left Ctrl (0x1D)
    db 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~'  ; 0x1E-0x29
    db 0  ; Left Shift (0x2A)
    db '|', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?'       ; 0x2B-0x35
    times 0x39-0x36 db 0
    db ' '  ; Space (0x39)
    times 256-0x3A db 0  ; Fill rest with zeros
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
    
; Data section
os_name db 'This kernel is under the MIT license.', 0
help_cmd db 'help', 0
clear_cmd db 'clear', 0
about_cmd db 'about', 0
echo_cmd db 'echo', 0     ; Note: no space included
specs_cmd db 'specs', 0
casc_cmd db 'casc', 0

; System information strings
cpu_msg db 'CPU: ', 0
ram_msg db 'RAM: ', 0
kb_msg db ' KB', 0
bios_msg db 'BIOS: ', 0
bios_date_msg db 'BIOS Date: ', 0
sysinfo_sig db 'SYSINFO', 0
sysinfo_error db 'System information not available', 0
msg_help db 'Available commands: help, clear, about, echo, specs', 0
msg_about db 'novusOS Kernel (popcorn) v0.1 (C) Aden Kirk, 2025', 0
msg_unknown db 'Unknown command. Type help for available commands.', 0
msg_casc db 'CASCOS is REAL :)', 0

rainbow_colors db 0x04, 0x0E, 0x0A, 0x0B, 0x0D
rainbow_count  equ ($ - rainbow_colors)

; Function to display the prompt
show_prompt:
    push edi
    mov edi, [cursor_pos]
    mov byte [edi], '>'
    mov byte [edi+1], 0x02   ; green color
    mov byte [edi+2], ':'    ; Space after smiley
    mov byte [edi+3], 0x07
    add dword [cursor_pos], 4 ; Move cursor past prompt
    pop edi
    ret
dw 0xAA55