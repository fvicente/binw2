;********************************************************************
;* binw2 Binary Wrist Watch
;*
;* Copyright 2012 Fernando Gabriel Vicente (fvicente@gmail.com)
;*
;* www.alfersoft.com.ar
;*
;* Version       : 1.0
;* Date          :
;* Author        :
;* Target MCU    : attiny13
;********************************************************************

; Total of leds required: 13
;
; x <- AM/PM
;
;   x     x
;   x   x x
;   x   x x
; x x   x x
; H H : M M

; For the sake of simplicity and optimum code, the 4 charlie-plexed pins must be relative to the
; port pin order, CP1 = pin 0, CP2 = pin 1, etc.
;
;                       ATtiny13
;                  +-----------------+
;                  |                 |
;        AM/PM ----| 1 (PB5) (VCC) 8 |---- +5V
;                  |                 |
;          CP4 ----| 2 (PB3) (PB2) 7 |---- CP3
;                  |                 |
;        INPUT ----| 3 (PB4) (PB1) 6 |---- CP2
;                  |                 |
;          GND ----| 4 (GND) (PB0) 5 |---- CP1
;                  |                 |
;                  +-----------------+
;

;
;	FUSE Bits
;
;	Bit		Low											High
;
;	7		√ SPIEN
;			SPI programming enable
;
;	6		EESAVE
;			Keep EEprom contents during chip erase
;
;	5		WDTON
;			Watch dog timer always on
;
;	4		CKDIV8										SELFPRGEN
;			Start up with system clock divided by 8		Self Programming Enable
;
;	3		SUT1										DWEN
;			Select start-up time						DebugWire Enable
;
;	2		√ SUT0										BODLEVEL1
;			Select start-up time						Enable BOD and select level
;
;	1		√ CKSEL1									BODLEVEL0
;			Select Clock Source							Enable BOD and select level
;
;	0		CKSEL0										RSTDISBL
;			Select Clock Source							Disable external reset
;

; Internal RC oscillator @ 4.8Mhz
; -U lfuse:w:0x79:m -U hfuse:w:0xff:m

#define __SFR_OFFSET 0 /* needed to subtract 0x20 from I/O addresses */

#define INPUT		4
#define PIN_AMPM	5
#define PORT		_SFR_IO_ADDR(PORTB)
#define DISPLAY_DLY	10
#include <avr/io.h>

	.global TIM0_COMPA_vect
	.global main

; MACROS

.macro bitled bit led
	ldi r16, 0
	sbrc r27, \bit
	ldi r16, \led
	rcall turnled
.endm

TIM0_COMPA_vect:
	in r1, SREG
	inc r25
	cpi r25, 75
	brne exittimer
	ldi r25, 0
	inc r19			; increment seconds
	cpi r19, 60
	brne exittimer
	ldi r19, 0
	inc r18			; increment minutes
	cpi r18, 60
	brne exittimer
	ldi r18, 0
	inc r17			; increment hour
	cpi r17, 24
	brne exittimer
	ldi r17, 0
exittimer:
	out SREG, r1
	reti

cpbits:
	; Tells which of the 4 charlie-plexed pins should be configured as input / output and
	; in case of output which ones should be on / off, for each led:
	; xxxxyyyy where x == 1 output, x == 0 input, y == 1 on, y == 0 off
	.byte 0x00, 0x31, 0x51, 0x91, 0xA2, 0x62, 0x32, 0x64, 0xC4, 0x54, 0xA8, 0xC8, 0x98
	.align 2

main:
	; Initialize stack
	; Stack is so small that SPH is not even present in this model
	ldi r16, lo8(RAMEND)
	out _SFR_IO_ADDR(SPL), r16

	; Disable interruptions
	cli

	; Initialize ports
	sbi _SFR_IO_ADDR(DDRB), 0x00	; output
	sbi _SFR_IO_ADDR(DDRB), 0x01	; output
	sbi _SFR_IO_ADDR(DDRB), 0x02	; output
	cbi _SFR_IO_ADDR(DDRB), INPUT	; make input

	; Initialize registers
	ldi r16, 0x00		; aux
	ldi r17, 7; 0x08		; hour (0 to 23)
	ldi r18, 37;0x12		; minute (0 to 59)
	ldi r19, 0x00		; second (0 to 59)
	ldi r20, 0xFF		; loop counter
	ldi r21, 0x00		; display active counter
	ldi r22, 0x00		; display am/pm
	ldi r23, 0x00		; loop counter 2
	ldi r24, 0x00		; zero
	ldi r25, 0x00		; aux
	ldi r26, 0x00		; store DDRB and PORTB during turnled
	ldi r27, 0x00		; store result from dec2bcd

	mov r0, r24			; used by lpm instruction
	mov r1, r24			; to save SREG during interrupt

	; Disable ACD (analog comparator)
	sbi _SFR_IO_ADDR(ACSR), ACD
	; Disable ADC (analog to digital conversor)
	cbi _SFR_IO_ADDR(ADCSRA), ADEN
	cbi _SFR_IO_ADDR(ADCSRA), ADATE
	; Read MCU control register
	in r16, _SFR_IO_ADDR(MCUCR)
	; Set sleep mode to idle (SM0 = 0, SM1 = 0)
	andi r16, ~(_BV(SM0) | _BV(SM1))
	; Write MCU control register
	out _SFR_IO_ADDR(MCUCR), r16

	; Prescale timer to 1/256th the clock rate
;	in r16, _SFR_IO_ADDR(TCCR0B)
;	andi r16, ~(_BV(CS01) | _BV(CS00))
;	ori r16, _BV(CS02)
	; Prescale timer to 1/64th the clock rate
	in r16, _SFR_IO_ADDR(TCCR0B)
	andi r16, ~(_BV(CS02))
	ori r16, _BV(CS00) | _BV(CS01)
	out _SFR_IO_ADDR(TCCR0B), r16

	; Set TOP to 125
	ldi r16, 125
	out _SFR_IO_ADDR(OCR0A), r16

	; Set compare mode to "Clear Timer on Compare Match (CTC) mode"
	in r16, _SFR_IO_ADDR(TCCR0A)
	andi r16, ~(_BV(COM0A0) | _BV(COM0A1) | _BV(COM0B0) | _BV(COM0B1) | _BV(WGM00))
	ori r16, (_BV(WGM01))
	out _SFR_IO_ADDR(TCCR0A), r16

	in r16, _SFR_IO_ADDR(TCCR0B)
	andi r16, ~(_BV(WGM02))
	out _SFR_IO_ADDR(TCCR0B), r16

	; Enable counter interrupt
	in r16, _SFR_IO_ADDR(TIMSK0)
	ori r16, _BV(OCIE0A)
	out _SFR_IO_ADDR(TIMSK0), r16

	; Enable global interrupts
	sei
	rjmp displayoff

loop:
	; Enable sleep mode bit
	in r16, _SFR_IO_ADDR(MCUCR)
	ori r16, _BV(SE)
	out _SFR_IO_ADDR(MCUCR), r16

	sleep

	; Disable sleep mode bit
	in r16, _SFR_IO_ADDR(MCUCR)
	andi r16, ~(_BV(SE))
	out _SFR_IO_ADDR(MCUCR), r16

	; check input
	rcall chkinput
;ldi r21, DISPLAY_DLY
	cpi r21, 0
	brne begindisplay
	rjmp loop

chkinput:
	in r16, _SFR_IO_ADDR(PINB)		; 1 clock
	sbrc r16, INPUT
	ldi r21, DISPLAY_DLY
	nop
	ret

turnled:
	; r16 must contain the number of led to turn on, or 0 to turn all off
	ldi ZL, lo8(cpbits)
	ldi ZH, hi8(cpbits)
	add ZL, r16
	adc ZH, r24
	lpm				; lpm = 3 cycles
	; in/out
	in r26, _SFR_IO_ADDR(DDRB)
	andi r26, 0xF0
	mov r16, r0
	swap r16
	andi r16, 0x0F
	or r26, r16
	out _SFR_IO_ADDR(DDRB), r26
	; on/off
	in r26, _SFR_IO_ADDR(PORTB)
	andi r26, 0xF0
	mov r16, r0
	andi r16, 0x0F
	or r26, r16
	out _SFR_IO_ADDR(PORTB), r26
	ret

dec2bcd:
	; convert decimal number (from 0 to 59) to BCD format
	; r16 must contain the number to convert
	; return result in r27
	ldi r27, 0
	ldi r28, 50
	ldi r29, 0x50
convloop:
	cp r16, r28
	brlo islower
	or r27, r29
	sub r16, r28
islower:
	subi r28, 10
	subi r29, 0x10
	brne convloop
	or r27, r16
	ret

begindisplay:
	cbi _SFR_IO_ADDR(PORTB), PIN_AMPM	; clear am/pm pin
	sbi _SFR_IO_ADDR(DDRB), PIN_AMPM	; output
displaytime:
	; display time, this is a loop that keeps turning the leds on and off in sequence during
	; DISPLAY_DLY seconds
	dec r21
	cpi r21, 0
	breq displayoff
	ldi r23, 0xFF
disptime:
	; first digit hour
	mov r16, r17
	cpi r16, 13
	brlo ampmoff
	subi r16, 12
	; turn am/pm led on
	sbi _SFR_IO_ADDR(PORTB), PIN_AMPM
	rjmp disphour
ampmoff:
	; turn am/pm led off
	cbi _SFR_IO_ADDR(PORTB), PIN_AMPM
disphour:
	rcall dec2bcd
	mov r16, r27
	swap r16
	andi r16, 0x01
	rcall turnled
	; second digit hour
	bitled 0 2
	bitled 1 3
	bitled 2 4
	bitled 3 5
	; first digit minutes
	mov r16, r19
	rcall dec2bcd
	bitled 4 6
	bitled 5 7
	bitled 6 8
	; second digit minutes
	bitled 0 9
	bitled 1 10
	bitled 2 11
	bitled 3 12
	; check input again
	rcall chkinput
	; decrement second loop counter
	dec r23
	brne disptime
	rjmp displaytime

displayoff:
	; turn off display
	in r16, _SFR_IO_ADDR(DDRB)
;	andi r16, 0xF0				; make the 4 charlie-plexing pins input (clear the bits)
;	andi r16, ~(_BV(PIN_AMPM))	; make am/pm pin input

	; test all output
	ori r16, 0x0F				; make the 4 charlie-plexing pins input (clear the bits)

	out _SFR_IO_ADDR(DDRB), r16
	cbi _SFR_IO_ADDR(PORTB), 0
	cbi _SFR_IO_ADDR(PORTB), 1
	cbi _SFR_IO_ADDR(PORTB), 2
	cbi _SFR_IO_ADDR(PORTB), 3
	rjmp loop
