#!/bin/sh

# AVR Microcontroller model
MMCU=attiny13

[ -e "/dev/tty.usbserial-A8008VmU" ] && PORT=/dev/tty.usbserial-A8008VmU || PORT=/dev/ttyUSB0
avrdude -F -P $PORT -p $MMCU -c avrisp -b 19200 -U flash:w:binw2.hex -Ulfuse:w:0x69:m -Uhfuse:w:0xff:m

# Fuses
# Read
#avrdude -n -p $MMCU -P $PORT -b 19200 -c avrisp -U hfuse:r:high.txt:s -U lfuse:r:low.txt:s
# Default for attiny13
#avrdude -F -P $PORT -p $MMCU -c avrisp -b 19200 -Ulfuse:w:0x6A:m -Uhfuse:w:0xff:m
# Clock at 128KHz
#avrdude -F -P $PORT -p $MMCU -c avrisp -b 19200 -Ulfuse:w:0x6B:m -Uhfuse:w:0xff:m
# Clock at 4.8MHz
#avrdude -F -P $PORT -p $MMCU -c avrisp -b 19200 -Ulfuse:w:0x69:m -Uhfuse:w:0xff:m
# WARNING: next line will set the fuses with PB5 as I/O port (won't be able to program again unless you reset the fuses with HV programmer)
#avrdude -F -P $PORT -p attiny45 -c avrisp -b 19200 -U flash:w:binw2.hex -Ulfuse:w:0xce:m -Uhfuse:w:0x5f:m -Uefuse:w:0xff:m
