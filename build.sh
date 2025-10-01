#!/bin/bash

echo "Building NovusOS..."

# Clean previous builds
rm -f *.o *.bin disk.img kernel.elf

# Assemble bootloader
echo "Assembling bootloader..."
nasm -f bin boot.asm -o boot.bin
if [ $? -ne 0 ]; then
    echo "Bootloader assembly failed!"
    exit 1
fi

# Assemble kernel (assembly, not C)
echo "Assembling kernel..."
nasm -f bin kernel.asm -o kernel.bin
if [ $? -ne 0 ]; then
    echo "Kernel assembly failed!"
    exit 1
fi

# Create disk image
echo "Creating disk image..."
dd if=/dev/zero of=disk.img bs=512 count=2880 2>/dev/null
dd if=boot.bin of=disk.img bs=512 count=1 conv=notrunc 2>/dev/null
dd if=kernel.bin of=disk.img bs=512 seek=1 conv=notrunc 2>/dev/null

echo "Build complete!"
echo "Bootloader size: $(ls -lh boot.bin | awk '{print $5}')"
echo "Kernel size: $(ls -lh kernel.bin | awk '{print $5}')"
echo "Boot with: qemu-system-x86_64 -fda disk.img"