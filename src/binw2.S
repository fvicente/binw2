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

; Total of leds required: 14
;
; x <- AM
; x <- PM
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

.macro turnled reg bit ddrb portb offlabel onlabel
	; turn all leds off to avoid ghost leds
	andi r26, 0xF0
	out _SFR_IO_ADDR(PORTB), r26
	andi r27, 0xF0
	out _SFR_IO_ADDR(DDRB), r27
	; check bit corresponding to this led
	sbrs \reg, \bit
	rjmp \offlabel
	; turn on led
	; in/out
	andi r27, 0xF0
	ori r27, \ddrb
	out _SFR_IO_ADDR(DDRB), r27
	; on/off
	ori r26, \portb
	out _SFR_IO_ADDR(PORTB), r26
	rjmp \onlabel
\offlabel:
	nop
	nop
	nop
	nop
	nop
	nop
	nop
\onlabel:
.endm

TIM0_COMPA_vect:
	in r1, SREG
	inc r25
	cpi r25, 75		; 75 interruptions = 1 second
	brne exittimer
	ldi r25, 0		; reset interruption counter
	inc r19			; increment seconds
	cpi r19, 60		; reached 60 seconds?
	brne exittimer
	ldi r19, 0		; reset seconds
	inc r18			; increment minutes
	mov r20, r18	; load minutes to aux
	andi r20, 0x0F	; low nibble only (second minute digit)
	cpi r20, 10		; check if reached 10 on the second digit
	brne exittimer
	andi r18, 0xF0	; clear low nibble
	ldi r20, 0x10
	add r18, r20	; increment high nibble
	cpi r18, 0x60	; reached 60 minutes?
	brne exittimer
	ldi r18, 0		; reset minutes
	inc r17			; increment hour
	mov r20, r17	; load hour to aux
	andi r20, 0x1F	; discard AM/PM flag
	cpi r20, 10		; check if reached 10
	brne checkampm
	andi r17, 0xF0	; clear low nibble
	ldi r20, 0x10
	add r17, r20	; increment high nibble
checkampm:
	mov r20, r17	; load new hour to aux
	andi r20, 0x1F	; discard AM/PM flag
	cpi r20, 0x13	; flip AM/PM?
	brne exittimer
	ldi r20, 0x80
	eor	r17, r20	; toggle AM/PM flag
	andi r17, 0x80	; keep AM/PM flag only
	ori r17, 0x01	; reset hour to 1
exittimer:
	out SREG, r1
	reti

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
	sbi _SFR_IO_ADDR(DDRB), 0x03	; output

	; Initialize registers
	ldi r16, 0x00		; aux
						;
						; AM H HHHH
						; PM 1 2222
						; |  | ||||
	ldi r17, 0x12		; 0000 0000 hour and AM/PM flag
	;ldi r17, 0x9F		; 0000 0000 hour and AM/PM flag
						;
						;  MMM MMMM
						;  111 2222
						;  ||| ||||
	ldi r18, 0x00		; 0000 0000 minute
	;ldi r18, 0x7F		; 0000 0000 minute
						;
	ldi r19, 0x00		; second (0 to 59)
	ldi r20, 0x00		; aux used during interruption
	ldi r21, 0x00		; display active counter
	ldi r22, 0x00		; - unused
	ldi r23, 0x00		; loop counter 2
	ldi r24, 0x00		; - unused
	ldi r25, 0x00		; interruption counter
	ldi r26, 0x00		; store DDRB and PORTB during turnled
	ldi r27, 0x00		; store result from dec2bcd

	mov r1, r16			; to save SREG during interrupt
	;
	; The device always starts in program mode, so the user can set current time
	;
programmode:
	; Read the input, we have two buttons attached with different resistance
	; values so, we make an ADC conversion to figure out which button is pressed
	cbi _SFR_IO_ADDR(DDRB), INPUT	; make input

	; Start ADC conversion
;	sbi _SFR_IO_ADDR(ACSR), ACD
	; Wait until ADC conversion finishes
;adcconv:
;	sbic _SFR_IO_ADDR(ADCSRA), ADSC
;	rjmp adcconv
	; Conversion done, read result


  ;  ADCSRA |= (1 << ADSC); // start conversion
  ;  while( ADCSRA & ( 1<< ADSC ) ); // wait under conversion done
  ;  result = ADCH

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

begindisplay:
	cbi _SFR_IO_ADDR(PORTB), PIN_AMPM	; clear am/pm pin
	sbi _SFR_IO_ADDR(DDRB), PIN_AMPM	; output
displaytime:
	; display time, this is a loop that keeps turning the leds on and off in
	; sequence during DISPLAY_DLY seconds
	dec r21
	cpi r21, 0
	breq jmpdisplayoff
	ldi r23, 0xFF
	rjmp disptime
jmpdisplayoff:
	; note: relative jump (rjmp) wont work, because the label is too far
	ldi ZL, lo8(displayoff)
	ldi ZH, hi8(displayoff)
	ijmp
disptime:
	in r26, _SFR_IO_ADDR(PORTB)
	in r27, _SFR_IO_ADDR(DDRB)
	; turnled <reg> <bit> <ddrb> <portb> <offlabel> <onlabel>
leds:
	; first is the AM/PM led
	turnled r17 7 0x20 0x20 led1delay led1
	turnled r17 4 0x03 0x01 led2delay led2
	turnled r17 0 0x05 0x01 led3delay led3
	turnled r17 1 0x09 0x01 led4delay led4
	turnled r17 2 0x0A 0x02 led5delay led5
	turnled r17 3 0x06 0x02 led6delay led6
	turnled r18 4 0x03 0x02 led7delay led7
	turnled r18 5 0x06 0x04 led8delay led8
	turnled r18 6 0x0C 0x04 led9delay led9
	turnled r18 0 0x05 0x04 led10delay led10
	turnled r18 1 0x0A 0x08 led11delay led11
	turnled r18 2 0x0C 0x08 led12delay led12
	turnled r18 3 0x09 0x08 allsetdelay allset
	; check input again
	rcall chkinput
	; decrement second loop counter
	dec r23
	brne jmpdisptime
	rjmp displaytime
jmpdisptime:
	; note: relative jump (rjmp) wont work, because the label is too far
	ldi ZL, lo8(disptime)
	ldi ZH, hi8(disptime)
	ijmp

displayoff:
	; turn off display
	in r16, _SFR_IO_ADDR(DDRB)
	andi r16, 0xF0				; make the 4 charlie-plexing pins input (clear)
	andi r16, ~(_BV(PIN_AMPM))	; make am/pm pin input
	out _SFR_IO_ADDR(DDRB), r16
	in r16, _SFR_IO_ADDR(PORTB)
	andi r16, 0xF0				; turn the 4 charlie-plexing pins off
	andi r16, ~(_BV(PIN_AMPM))	; turn am/pm pin off
	out _SFR_IO_ADDR(PORTB), r16
	rjmp loop
