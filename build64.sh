#!/bin/bash

echo "Building NovusOS..."

# Clean previous builds and scripts
rm -f *.o *.bin disk.img kernel.elf kernel_test.py create_disk.py run.sh

# Assemble bootloader
echo "Assembling bootloader..."
nasm -f bin boot64.asm -o boot64.bin
if [ $? -ne 0 ]; then
    echo "Bootloader assembly failed!"
    exit 1
fi

# Assemble kernel
echo "Assembling kernel..."
nasm -f bin kernel64.asm -o kernel64.bin
if [ $? -ne 0 ]; then
    echo "Kernel assembly failed!"
    exit 1
fi

# Create disk image
echo "Creating disk image..."
dd if=/dev/zero of=disk64.img bs=512 count=2880 2>/dev/null
dd if=boot64.bin of=disk64.img bs=512 count=1 conv=notrunc 2>/dev/null
dd if=kernel64.bin of=disk64.img bs=512 seek=1 conv=notrunc 2>/dev/null

echo "Build complete!"
echo "Bootloader size: $(ls -lh boot64.bin | awk '{print $5}')"
echo "Kernel size: $(ls -lh kernel64.bin | awk '{print $5}')"
echo "Boot with: qemu-system-i386 -display curses -drive format=raw,file=disk64.img -boot a"