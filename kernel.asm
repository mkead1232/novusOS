[bits 32]
[org 0x1000]
jmp kernel_start
; Function to read a sector in protected mode
; Input:
;   EAX = LBA (Logical Block Address)
;   EDI = destination buffer
read_sector_pm:
    pushad
    
    mov [.lba], eax
    mov [.buffer], edi
    
    ; Send highest byte of LBA
    mov edx, 0x1F6
    shr eax, 24
    or al, 0xE0
    out dx, al
    
    ; Send sector count
    mov edx, 0x1F2
    mov al, 1
    out dx, al
    
    ; Send more bits of LBA
    mov eax, [.lba]
    mov edx, 0x1F3
    out dx, al
    
    mov edx, 0x1F4
    mov eax, [.lba]
    shr eax, 8
    out dx, al
    
    mov edx, 0x1F5
    mov eax, [.lba]
    shr eax, 16
    out dx, al
    
    ; Send read command
    mov edx, 0x1F7
    mov al, 0x20
    out dx, al
    
.wait_ready:
    in al, dx
    test al, 8
    jz .wait_ready
    
    ; Read the data
    mov ecx, 256
    mov edx, 0x1F0
    mov edi, [.buffer]
    rep insw
    
    popad
    ret
    
.lba    dd 0
.buffer dd 0

; Function to write a sector in protected mode
; Input:
;   EAX = LBA
;   ESI = source buffer
write_sector_pm:
    pushad
    
    mov [.lba], eax
    mov [.buffer], esi
    
    ; Send highest byte of LBA
    mov edx, 0x1F6
    shr eax, 24
    or al, 0xE0
    out dx, al
    
    ; Send sector count
    mov edx, 0x1F2
    mov al, 1
    out dx, al
    
    ; Send more bits of LBA
    mov eax, [.lba]
    mov edx, 0x1F3
    out dx, al
    
    mov edx, 0x1F4
    mov eax, [.lba]
    shr eax, 8
    out dx, al
    
    mov edx, 0x1F5
    mov eax, [.lba]
    shr eax, 16
    out dx, al
    
    ; Send write command
    mov edx, 0x1F7
    mov al, 0x30
    out dx, al
    
.wait_ready:
    in al, dx
    test al, 8
    jz .wait_ready
    
    ; Write the data
    mov ecx, 256
    mov edx, 0x1F0
    mov esi, [.buffer]
    rep outsw
    
    ; Wait for write to complete
    mov edx, 0x1F7
.wait_complete:
    in al, dx
    test al, 0x80
    jnz .wait_complete
    
    popad
    ret
    
.lba    dd 0
.buffer dd 0
cursor_pos dd 0xB81E0
input_buffer:
    times 64 db 0
buffer_index dd 0

; Filesystem structures
FS_BASE_SECTOR equ 20       ; Start after bootloader (1) + kernel (16) + safety margin (3)
FS_FAT_SECTOR equ 21       ; Base + 1
FS_FAT_SECTORS equ 32
FS_DIR_SECTOR equ 53       ; FAT sector + FAT sectors
FS_DIR_SECTORS equ 32
FS_DATA_SECTOR equ 85       ; DIR sector + DIR sectors
FS_MAX_FILES equ 256
FS_BLOCK_SIZE equ 512

FS_BUFFER equ 0x10000
FAT_BUFFER equ 0x20000
DIR_BUFFER equ 0x30000

struc DirEntry
    .name: resb 16
    .size: resd 1
    .firstBlock: resw 1
    .flags: resb 1
    .reserved: resb 9
endstruc

struc Superblock
    .magic: resd 1
    .totalBlocks: resd 1
    .freeBlocks: resd 1
    .reserved: resb 500
endstruc

fs_initialized db 0

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
    xor eax, eax
    xor ebx, ebx
    mov dword [buffer_index], 0
    
    ; Try to load filesystem
    mov eax, FS_BASE_SECTOR
    mov edi, FS_BUFFER
    call read_sector_pm
    
    ; Check filesystem magic
    mov eax, [FS_BUFFER + Superblock.magic]
    cmp eax, 0x4E4F5653  ; "NOVS"
    jne .no_fs
    
    ; Load FAT
    mov ecx, FS_FAT_SECTORS
    mov eax, FS_FAT_SECTOR
    mov edi, FAT_BUFFER
.load_fat:
    push ecx
    call read_sector_pm
    inc eax
    add edi, 512
    pop ecx
    loop .load_fat
    
    ; Load directory
    mov ecx, FS_DIR_SECTORS
    mov eax, FS_DIR_SECTOR
    mov edi, DIR_BUFFER
.load_dir:
    push ecx
    call read_sector_pm
    inc eax
    add edi, 512
    pop ecx
    loop .load_dir
    
    mov byte [fs_initialized], 1
    
.no_fs:
    call display_info
    call show_prompt
    call update_hardware_cursor
    
main_loop:
    call wait_for_key
    test al, al
    jz main_loop
    mov edi, [cursor_pos]
    mov [edi], al
    mov byte [edi+1], 0x07
    mov ebx, [buffer_index]
    mov [input_buffer + ebx], al
    inc dword [buffer_index]
    add dword [cursor_pos], 2
    mov edi, [cursor_pos]
    cmp edi, 0xB8FA0
    jl .ok
    mov dword [cursor_pos], 0xB81E0
.ok:
    call update_hardware_cursor
    jmp main_loop

update_hardware_cursor:
    push eax
    push ebx
    push edx
    mov eax, [cursor_pos]
    sub eax, 0xB8000
    shr eax, 1
    mov ebx, eax
    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al
    mov dx, 0x3D5
    mov al, bl
    out dx, al
    mov dx, 0x3D4
    mov al, 0x0E
    out dx, al
    mov dx, 0x3D5
    mov al, bh
    out dx, al
    pop edx
    pop ebx
    pop eax
    ret

display_info:
    mov edi, 0xB8F00
    mov esi, os_name
    call print_string_at
    ret

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
    cmp al, 0x2A
    je shift_press
    cmp al, 0x36
    je shift_press
    cmp al, 0xAA
    je shift_release
    cmp al, 0xB6
    je shift_release
    cmp al, 0x80
    jae wait_for_key
    cmp al, 0x0E
    je handle_backspace
    cmp al, 0x1C
    je handle_enter
    movzx ebx, al
    mov al, [shift_pressed]
    test al, al
    jz .no_shift
    mov al, [scancode_to_ascii_shift + ebx]
    jmp .check_char
.no_shift:
    mov al, [scancode_to_ascii + ebx]
.check_char:
    test al, al
    jz wait_for_key
    ret
.shift_press:
    mov byte [shift_pressed], 1
    jmp wait_for_key
.shift_release:
    mov byte [shift_pressed], 0
    jmp wait_for_key
    
handle_enter:
    mov ebx, [buffer_index]
    mov byte [input_buffer + ebx], 0
    call newline
    
    ; Check filesystem commands
    mov esi, input_buffer
    mov edi, mkfs_cmd
    call compare_strings
    cmp eax, 0
    je cmd_mkfs
    
    mov esi, input_buffer
    mov edi, ls_cmd
    call compare_strings
    cmp eax, 0
    je cmd_ls
    
    ; Check touch with args
    mov esi, input_buffer
    mov edi, touch_cmd
    mov ecx, 5
.check_touch:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .not_touch
    inc esi
    inc edi
    loop .check_touch
    mov al, [esi]
    cmp al, 0
    je cmd_touch
    cmp al, ' '
    je cmd_touch
    
.not_touch:
    ; Check rm with args
    mov esi, input_buffer
    mov edi, rm_cmd
    mov ecx, 2
.check_rm:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .not_rm
    inc esi
    inc edi
    loop .check_rm
    mov al, [esi]
    cmp al, 0
    je cmd_rm
    cmp al, ' '
    je cmd_rm
    
.not_rm:
    ; Check cat with args
    mov esi, input_buffer
    mov edi, cat_cmd
    mov ecx, 3
.check_cat:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .not_cat_cmd
    inc esi
    inc edi
    loop .check_cat
    mov al, [esi]
    cmp al, 0
    je cmd_cat
    cmp al, ' '
    je cmd_cat
    
.not_cat_cmd:
    ; Check write with args
    mov esi, input_buffer
    mov edi, write_cmd
    mov ecx, 5
.check_write:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .not_write
    inc esi
    inc edi
    loop .check_write
    mov al, [esi]
    cmp al, 0
    je cmd_write
    cmp al, ' '
    je cmd_write
    
.not_write:
    ; Check shutdown command
    mov esi, input_buffer
    mov edi, shutdown_cmd
    call compare_strings
    cmp eax, 0
    je cmd_shutdown
    
    ; Original commands
    mov esi, input_buffer
    mov edi, help_cmd
    call compare_strings
    cmp eax, 0
    je cmd_help
    
    mov esi, input_buffer
    mov edi, clear_cmd
    call compare_strings
    cmp eax, 0
    je cmd_clear
    
    mov esi, input_buffer
    mov edi, about_cmd
    call compare_strings
    cmp eax, 0
    je cmd_about
    
    mov esi, input_buffer
    mov edi, casc_cmd
    call compare_strings
    cmp eax, 0
    je cmd_casc

    ; Check echo
    mov esi, input_buffer
    mov edi, echo_cmd
    mov ecx, 4
.check_echo:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .not_echo
    inc esi
    inc edi
    loop .check_echo
    mov al, [esi]
    cmp al, 0
    je cmd_echo
    cmp al, ' '
    je cmd_echo
    
.not_echo:
    mov esi, input_buffer
    mov edi, specs_cmd
    call compare_strings
    cmp eax, 0
    je cmd_specs
    
    mov ebx, [buffer_index]
    cmp ebx, 2
    jle .skip_unknown
    mov esi, msg_unknown
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    
.skip_unknown:
    call clear_input_buffer
    xor al, al
    ret

; Filesystem commands
cmd_mkfs:
    mov esi, fs_creating_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    
    ; Initialize superblock
    mov edi, FS_BUFFER
    mov dword [edi + Superblock.magic], 0x4E4F5653
    mov dword [edi + Superblock.totalBlocks], 446
    mov dword [edi + Superblock.freeBlocks], 446
    
    ; Write superblock to disk
    mov eax, FS_BASE_SECTOR
    mov esi, FS_BUFFER
    call write_sector_pm
    
    ; Initialize FAT
    mov edi, FAT_BUFFER
    mov ecx, 512
    mov ax, 0xFFFF
.clear_fat:
    mov [edi], ax
    add edi, 2
    loop .clear_fat
    
    ; Write FAT to disk
    mov ecx, FS_FAT_SECTORS
    mov eax, FS_FAT_SECTOR
    mov esi, FAT_BUFFER
.write_fat:
    push ecx
    call write_sector_pm
    inc eax
    add esi, 512
    pop ecx
    loop .write_fat
    
    ; Initialize directory
    mov edi, DIR_BUFFER
    mov ecx, (FS_MAX_FILES * 32) / 4
    xor eax, eax
.clear_dir:
    mov [edi], eax
    add edi, 4
    loop .clear_dir
    
    ; Write directory to disk
    mov ecx, FS_DIR_SECTORS
    mov eax, FS_DIR_SECTOR
    mov esi, DIR_BUFFER
.write_dir:
    push ecx
    call write_sector_pm
    inc eax
    add esi, 512
    pop ecx
    loop .write_dir
    
    mov byte [fs_initialized], 1
    mov esi, fs_created_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    call clear_input_buffer
    xor al, al
    ret

cmd_ls:
    cmp byte [fs_initialized], 0
    je .not_init
    mov esi, DIR_BUFFER
    xor ecx, ecx
.check_entry:
    cmp ecx, FS_MAX_FILES
    jge .done
    mov al, [esi + DirEntry.flags]
    test al, 0x01
    jz .next_entry
    push esi
    push ecx
    mov edi, [cursor_pos]
    call print_string_at
    mov [cursor_pos], edi
    mov edi, [cursor_pos]
    push esi
    mov esi, size_msg
    call print_string_at
    pop esi
    mov [cursor_pos], edi
    pop ecx
    pop esi
    push esi
    push ecx
    mov eax, [esi + DirEntry.size]
    call print_number
    mov edi, [cursor_pos]
    push esi
    mov esi, bytes_msg
    call print_string_at
    pop esi
    mov [cursor_pos], edi
    call newline
    pop ecx
    pop esi
.next_entry:
    add esi, 32
    inc ecx
    jmp .check_entry
.done:
    call clear_input_buffer
    xor al, al
    ret
.not_init:
    mov esi, fs_not_init_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    call clear_input_buffer
    xor al, al
    ret

cmd_touch:
    cmp byte [fs_initialized], 0
    je .not_init
    mov esi, input_buffer
    add esi, 6
    mov al, [esi]
    test al, al
    jz .no_filename
    call fs_create_file
    test eax, eax
    jz .created
    mov esi, fs_error_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    jmp .done
.created:
    mov esi, file_created_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    jmp .done
.no_filename:
    mov esi, no_filename_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    jmp .done
.not_init:
    mov esi, fs_not_init_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
.done:
    call clear_input_buffer
    xor al, al
    ret

cmd_write:
    cmp byte [fs_initialized], 0
    je .not_init
    mov esi, input_buffer
    add esi, 6
    mov edi, esi
.find_space:
    mov al, [edi]
    test al, al
    jz .no_text
    cmp al, ' '
    je .found_space
    inc edi
    jmp .find_space
.found_space:
    mov byte [edi], 0
    inc edi
    push edi
    call fs_find_file
    pop edi
    test eax, eax
    jnz .not_found
    push ecx
    mov esi, edi
    call strlen
    mov edx, eax
    pop ecx
    mov esi, edi
    call fs_write_file
    mov esi, file_written_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    jmp .done
.not_found:
    mov esi, file_not_found_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    jmp .done
.no_text:
    mov esi, no_text_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    jmp .done
.not_init:
    mov esi, fs_not_init_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
.done:
    call clear_input_buffer
    xor al, al
    ret

cmd_cat:
    cmp byte [fs_initialized], 0
    je .not_init
    mov esi, input_buffer
    add esi, 4
    mov al, [esi]
    test al, al
    jz .no_filename
    call fs_find_file
    test eax, eax
    jnz .not_found
    mov eax, [ecx + DirEntry.size]
    test eax, eax
    jz .empty
    call fs_read_file
    mov esi, FS_BUFFER
    mov edi, [cursor_pos]
.display_loop:
    mov al, [esi]
    test al, al
    jz .display_done
    mov [edi], al
    mov byte [edi+1], 0x07
    add edi, 2
    inc esi
    cmp al, 10
    je .newline_char
    jmp .continue
.newline_char:
    mov [cursor_pos], edi
    call newline
    mov edi, [cursor_pos]
    jmp .display_loop
.continue:
    jmp .display_loop
.display_done:
    mov [cursor_pos], edi
    call newline
    jmp .done
.empty:
    mov esi, file_empty_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    jmp .done
.not_found:
    mov esi, file_not_found_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    jmp .done
.no_filename:
    mov esi, no_filename_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    jmp .done
.not_init:
    mov esi, fs_not_init_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
.done:
    call clear_input_buffer
    xor al, al
    ret

cmd_rm:
    cmp byte [fs_initialized], 0
    je .not_init
    mov esi, input_buffer
    add esi, 3
    mov al, [esi]
    test al, al
    jz .no_filename
    call fs_delete_file
    test eax, eax
    jz .deleted
    mov esi, file_not_found_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    jmp .done
.deleted:
    mov esi, file_deleted_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    jmp .done
.no_filename:
    mov esi, no_filename_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    jmp .done
.not_init:
    mov esi, fs_not_init_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
.done:
    call clear_input_buffer
    xor al, al
    ret

; Filesystem helper functions
fs_create_file:
    push ebx
    push ecx
    push edi
    mov edi, DIR_BUFFER
    xor ecx, ecx
.find_free:
    cmp ecx, FS_MAX_FILES
    jge .no_space
    mov al, [edi + DirEntry.flags]
    test al, 0x01
    jz .found_free
    add edi, 32
    inc ecx
    jmp .find_free
.found_free:
    push edi
    mov ecx, 16
.copy_name:
    mov al, [esi]
    mov [edi], al
    test al, al
    jz .name_done
    inc esi
    inc edi
    loop .copy_name
.name_done:
    pop edi
    mov dword [edi + DirEntry.size], 0
    mov word [edi + DirEntry.firstBlock], 0xFFFF
    mov byte [edi + DirEntry.flags], 0x01
    xor eax, eax
    jmp .done
.no_space:
    mov eax, 1
.done:
    pop edi
    pop ecx
    pop ebx
    ret

fs_find_file:
    push ebx
    push edx
    push edi
    mov edi, DIR_BUFFER
    xor ecx, ecx
.search:
    cmp ecx, FS_MAX_FILES
    jge .not_found
    mov al, [edi + DirEntry.flags]
    test al, 0x01
    jz .next
    push esi
    push edi
    mov edx, 16
.cmp_loop:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .name_diff
    test al, al
    jz .name_match
    inc esi
    inc edi
    dec edx
    jnz .cmp_loop
.name_match:
    pop edi
    pop esi
    mov ecx, edi
    xor eax, eax
    jmp .done
.name_diff:
    pop edi
    pop esi
.next:
    add edi, 32
    inc ecx
    jmp .search
.not_found:
    mov eax, 1
.done:
    pop edi
    pop edx
    pop ebx
    ret

fs_write_file:
    push eax
    push ebx
    push edi
    mov ax, [ecx + DirEntry.firstBlock]
    cmp ax, 0xFFFF
    jne .has_block
    call fs_alloc_block
    mov [ecx + DirEntry.firstBlock], ax
.has_block:
    ; Copy data to buffer
    mov edi, FS_BUFFER
    push ecx
    mov ecx, edx
    rep movsb
    mov byte [edi], 0
    pop ecx
    mov [ecx + DirEntry.size], edx
    
    ; Write data to disk
    movzx eax, word [ecx + DirEntry.firstBlock]
    add eax, FS_DATA_SECTOR
    mov esi, FS_BUFFER
    call write_sector_pm
    
    ; Write updated directory entry
    push ecx
    sub ecx, DIR_BUFFER
    shr ecx, 5          ; Divide by 32 (size of directory entry)
    mov eax, ecx
    shr eax, 4          ; Divide by 16 (entries per sector)
    add eax, FS_DIR_SECTOR
    mov esi, DIR_BUFFER
    call write_sector_pm
    pop ecx
    
    pop edi
    pop ebx
    pop eax
    ret

fs_read_file:
    push eax
    push esi
    push edi
    
    ; Read data from disk
    movzx eax, word [ecx + DirEntry.firstBlock]
    add eax, FS_DATA_SECTOR
    mov edi, FS_BUFFER
    call read_sector_pm
    
    pop edi
    pop esi
    pop eax
    ret

fs_delete_file:
    call fs_find_file
    test eax, eax
    jnz .not_found
    mov byte [ecx + DirEntry.flags], 0
    mov word [ecx + DirEntry.firstBlock], 0xFFFF
    xor eax, eax
    ret
.not_found:
    mov eax, 1
    ret

fs_alloc_block:
    push ebx
    push edi
    mov edi, FAT_BUFFER
    xor ebx, ebx
.find_free:
    mov ax, [edi]
    cmp ax, 0xFFFF
    je .found
    add edi, 2
    inc ebx
    cmp ebx, 512
    jl .find_free
    mov ax, 0xFFFF
    jmp .done
.found:
    mov word [edi], 0xFFFE
    mov ax, bx
.done:
    pop edi
    pop ebx
    ret

strlen:
    push esi
    xor eax, eax
.loop:
    mov bl, [esi]
    test bl, bl
    jz .done
    inc esi
    inc eax
    jmp .loop
.done:
    pop esi
    ret

print_number:
    push eax
    push ebx
    push ecx
    push edx
    mov ebx, 10
    xor ecx, ecx
.convert:
    xor edx, edx
    div ebx
    push dx
    inc ecx
    test eax, eax
    jnz .convert
    mov edi, [cursor_pos]
.print:
    pop ax
    add al, '0'
    mov [edi], al
    mov byte [edi+1], 0x07
    add edi, 2
    loop .print
    mov [cursor_pos], edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; Original commands
SYSINFO_ADDR equ 0x500

cmd_specs:
    mov eax, 0
    cpuid
    mov edi, [cursor_pos]
    mov esi, cpu_msg
    call print_string_at
    push eax
    mov eax, ebx
    call print_cpu_chars
    mov eax, edx
    call print_cpu_chars
    mov eax, ecx
    call print_cpu_chars
    pop eax
    call newline
    mov esi, SYSINFO_ADDR
    mov edi, sysinfo_sig
    mov ecx, 8
    call compare_strings
    cmp eax, 0
    jne .no_sysinfo
    mov edi, [cursor_pos]
    mov esi, ram_msg
    call print_string_at
    mov ax, [SYSINFO_ADDR + 7]
    mov cx, 0
    mov bx, 10
    call newline
.convert_loop:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .convert_loop
.print_digits:
    pop ax
    add al, '0'
    mov [edi], al
    mov byte [edi+1], 0x07
    add edi, 2
    loop .print_digits
    mov esi, kb_msg
    call print_string_at
    call newline
    mov edi, [cursor_pos]
    mov esi, bios_msg
    call print_string_at
    mov esi, SYSINFO_ADDR + 9
    call print_string_at
    call newline
    mov edi, [cursor_pos]
    mov esi, bios_date_msg
    call print_string_at
    mov esi, SYSINFO_ADDR + 26
    call print_string_at
    call newline
    jmp .done
.no_sysinfo:
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

cmd_echo:
    mov esi, input_buffer
    add esi, 5
    mov al, [esi]
    test al, al
    jz .echo_no_args
    mov edi, [cursor_pos]
.echo_loop:
    mov al, [esi]
    test al, al
    jz .echo_done
    mov [edi], al
    mov byte [edi+1], 0x07
    add edi, 2
    inc esi
    jmp .echo_loop
.echo_done:
    mov [cursor_pos], edi
    call newline
.echo_no_args:
    call clear_input_buffer
    xor al, al
    ret

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

; Shutdown command - attempts ACPI shutdown, falls back to halt
cmd_shutdown:
    mov esi, shutdown_msg
    mov edi, [cursor_pos]
    call print_string_at
    call newline
    
    ; Try ACPI shutdown first
    mov dx, 0x604
    mov ax, 0x2000
    out dx, ax
    
    ; If ACPI shutdown failed, halt the CPU
    cli             ; Disable interrupts
    hlt            ; Halt the CPU
    jmp $          ; Just in case an NMI wakes us

shift_press:
    mov byte [shift_pressed], 1
    jmp wait_for_key

shift_release:
    mov byte [shift_pressed], 0
    jmp wait_for_key

handle_backspace:
    mov edi, [cursor_pos]
    sub edi, 2
    mov eax, edi
    sub eax, 0xB8000
    mov ecx, 160
    xor edx, edx
    div ecx
    cmp edx, 2
    jle .backspace_done
    mov dword [cursor_pos], edi
    mov byte [edi], ' '
    mov byte [edi+1], 0x07
    mov ebx, [buffer_index]
    test ebx, ebx
    jz .backspace_done
    dec dword [buffer_index]
    call update_hardware_cursor
.backspace_done:
    xor al, al
    ret

newline:
    mov eax, [cursor_pos]
    sub eax, 0xB8000
    mov ecx, 160
    xor edx, edx
    div ecx
    inc eax
    mul ecx
    add eax, 0xB8000
    cmp eax, 0xB8FA0
    jl .no_wrap
    mov eax, 0xB81E0
.no_wrap:
    mov [cursor_pos], eax
    call show_prompt
    call update_hardware_cursor
    ret

clear_screen:
    mov edi, 0xB8000
    mov ecx, 2000
.clear_loop:
    mov byte [edi], ' '
    mov byte [edi+1], 0x07
    add edi, 2
    loop .clear_loop
    mov dword [cursor_pos], 0xB8000
    call display_info
    mov dword [cursor_pos], 0xB81E0
    call show_prompt
    call update_hardware_cursor
    ret

clear_input_buffer:
    mov edi, input_buffer
    mov ecx, 64
    xor eax, eax
    rep stosb
    mov dword [buffer_index], 0
    ret

print_cpu_chars:
    push ecx
    push edi
    mov ecx, 4
.loop:
    mov edi, [cursor_pos]
    mov [edi], al
    mov byte [edi+1], 0x07
    add dword [cursor_pos], 2
    ror eax, 8
    loop .loop
    pop edi
    pop ecx
    ret

print_string32_rainbow:
    pushad
    mov ebx, rainbow_colors
    xor ecx, ecx
.loop:
    mov al, [esi]
    test al, al
    je .done
    and al, 0x7F
    mov [edi], al
    mov dl, [ebx + ecx]
    mov [edi+1], dl
    add edi, 2
    inc esi
    inc ecx
    cmp ecx, rainbow_count
    jl .no_wrap
    xor ecx, ecx
.no_wrap:
    jmp .loop
.done:
    popad
    ret

show_prompt:
    push edi
    mov edi, [cursor_pos] ; prints >: and puts commands typed after it
    mov byte [edi], '>'
    mov byte [edi+1], 0x02
    mov byte [edi+2], ':'
    mov byte [edi+3], 0x07
    add dword [cursor_pos], 4
    pop edi
    ret

; Data section
shift_pressed db 0
os_name db 'This kernel is under the MIT license.', 0
help_cmd db 'help', 0
clear_cmd db 'clear', 0
about_cmd db 'about', 0
echo_cmd db 'echo', 0
specs_cmd db 'specs', 0
casc_cmd db 'casc', 0
mkfs_cmd db 'mkfs', 0
ls_cmd db 'ls', 0
touch_cmd db 'touch', 0
rm_cmd db 'rm', 0
cat_cmd db 'cat', 0
write_cmd db 'write', 0
shutdown_cmd db 'shutdown', 0
cpu_msg db 'CPU: ', 0
ram_msg db 'RAM: ', 0
kb_msg db ' KB', 0
bios_msg db 'BIOS: ', 0
bios_date_msg db 'BIOS Date: ', 0
sysinfo_sig db 'SYSINFO', 0
sysinfo_error db 'System information not available', 0
msg_help db 'Commands: help, clear, about, echo, specs, mkfs, ls, touch, write, cat, rm, shutdown', 0
msg_about db 'novusOS Kernel (popcorn) v0.2 with Filesystem (C) Aden Kirk, 2025', 0
shutdown_msg db 'Shutting down...', 0
msg_unknown db 'Unknown command. Type help for available commands.', 0
msg_casc db 'CASCOS is REAL :)', 0
fs_creating_msg db 'Creating filesystem...', 0
fs_created_msg db 'Filesystem created successfully!', 0
fs_not_init_msg db 'Filesystem not initialized. Run mkfs first.', 0
fs_error_msg db 'Filesystem error occurred.', 0
file_created_msg db 'File created.', 0
file_deleted_msg db 'File deleted.', 0
file_written_msg db 'Data written to file.', 0
file_not_found_msg db 'File not found.', 0
file_empty_msg db '(empty file)', 0
no_filename_msg db 'No filename specified.', 0
no_text_msg db 'Usage: write filename text', 0
size_msg db ' (', 0
bytes_msg db ' bytes)', 0
rainbow_colors db 0x04, 0x0E, 0x0A, 0x0B, 0x0D
rainbow_count equ ($ - rainbow_colors)

scancode_to_ascii:
    times 0x02 db 0
    db '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '='
    times 0x10-0x0E db 0
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']'
    db 0
    db 0
    db 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', 0x27, '`'
    db 0
    db 0x5C, 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/'
    times 0x39-0x36 db 0
    db ' '
    times 256-0x3A db 0

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

dw 0xAA55