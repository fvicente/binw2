#!/bin/sh

# AVR Microcontroller model
MMCU=attiny13

# Name of the source and output, no extension (only works for one source)
FILENAME=binw2

rm $FILENAME.elf

# Build HEX
avr-gcc -mmcu=$MMCU -Wall -gdwarf-2 -Os -std=gnu99 -funsigned-char -funsigned-bitfields -fpack-struct -fshort-enums -MD -MP -MT $FILENAME.o -MF $FILENAME.o.d -x assembler-with-cpp -Wa,-gdwarf2 -c $FILENAME.S
avr-gcc -mmcu=$MMCU -Wl,-Map=$FILENAME.map $FILENAME.o -o $FILENAME.elf
avr-objcopy -O ihex -R .eeprom -R .fuse -R .lock -R .signature $FILENAME.elf $FILENAME.hex
avr-objcopy -j .eeprom --set-section-flags=.eeprom="alloc,load" --change-section-lma .eeprom=0 --no-change-warnings -O ihex $FILENAME.elf $FILENAME.eep || exit 0
avr-size -C --mcu=$MMCU $FILENAME.elf

# Remove temporary files
rm *.o
rm *.o.d
rm $FILENAME.eep
rm $FILENAME.map
