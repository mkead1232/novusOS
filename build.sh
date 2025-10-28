#!/bin/bash

echo "Building NovusOS..."

# Clean previous builds
rm -f *.bin disk.img

# Assemble bootloader
echo "Assembling bootloader..."
nasm -f bin boot.asm -o boot.bin
if [ $? -ne 0 ]; then
    echo "Bootloader assembly failed!"
    exit 1
fi

# Assemble kernel
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

# Write filesystem data starting at sector 20
sector=20
echo "Writing filesystem data..."

# Write file count at sector 20
file_count=$(ls -1 fs/ 2>/dev/null | wc -l)
printf "%04x" $file_count | xxd -r -p | dd of=disk.img bs=1 seek=$((sector * 512)) conv=notrunc 2>/dev/null

# Write files starting at sector 21
sector=21
for file in fs/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        filesize=$(stat -c %s "$file")
        
        # Write filename (null-terminated, up to 32 bytes)
        printf "%-31s\0" "$filename" | dd of=disk.img bs=1 seek=$((sector * 512)) conv=notrunc 2>/dev/null
        
        # Write file size (4 bytes)
        printf "%08x" $filesize | xxd -r -p | dd of=disk.img bs=1 seek=$((sector * 512 + 32)) conv=notrunc 2>/dev/null
        
        # Write file content
        dd if="$file" of=disk.img bs=1 seek=$((sector * 512 + 36)) conv=notrunc 2>/dev/null
        
        # Move to next sector (round up to nearest sector)
        sectors_needed=$(((filesize + 36 + 511) / 512))
        sector=$((sector + sectors_needed))
    fi
done

echo "Build complete!"
echo "Bootloader size: $(ls -lh boot.bin | awk '{print $5}')"
echo "Kernel size: $(ls -lh kernel.bin | awk '{print $5}')"
echo "Filesystem starts at sector 20"
echo "Files written: $file_count"
echo "Boot with: qemu-system-i386 -drive format=raw,file=disk.img -boot a"