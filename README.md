# NovusOS

A simple x86 operating system written in Assembly, featuring a basic command line interface.

![License](https://img.shields.io/badge/license-MIT-blue.svg)

## Features

- Protected mode operation
- Command-line interface with prompt
- Basic keyboard input handling with shift key support
- VGA text mode display
- System information display
- Several built-in commands

## Commands

- `help` - Display available commands
- `clear` - Clear the screen
- `about` - Show kernel version
- `specs` - Display system information
- `echo` - Print text to screen
- `casc` - Easter egg :)

## Building

Requires:
- NASM assembler
- QEMU emulator (for testing)

To build and run:
```bash
./build.sh     # Assemble and create disk image
```

## Running on Real Hardware

1. Write the disk image to a USB drive:
```bash
sudo dd if=disk.img of=/dev/sdX bs=512
```
(Replace sdX with your USB drive letter, BE CAREFUL with this command!)

2. Boot Configuration:
   - Disable Secure Boot in BIOS
   - Enable Legacy Boot/CSM Support
   - Set boot priority to USB first
   - Disable Fast Boot

## Technical Details

- Written in x86 Assembly
- Uses BIOS interrupts for disk I/O
- Implements PS/2 keyboard support
- VGA text mode (80x25) display
- Protected mode operation

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Author

Created by Aden Kirk (mkead1232)