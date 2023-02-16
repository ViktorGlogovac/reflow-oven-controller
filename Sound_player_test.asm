$NOLIST
$MODLP51RC2
$LIST

org 0x0000 ; Reset vector
    ljmp main

org 0x001B ; Timer/Counter 1 overflow interrupt vector. Used in this code to replay the wave file.
	ljmp Timer1_ISR
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR

TIMER1_RATE    EQU 22050     ; 22050Hz is the sampling rate of the wav file we are playing
TIMER1_RELOAD  EQU 0x10000-(SYSCLK/TIMER1_RATE)
SPEAKER  EQU P2.6 ; Used with a MOSFET to turn off speaker when not in use
SYSCLK         EQU 22118400  ; Microcontroller system clock frequency in Hz
CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

; The pins used for SPI
FLASH_CE  EQU  P2.5
MY_MOSI   EQU  P2.4 
MY_MISO   EQU  P2.1
MY_SCLK   EQU  P2.0 

; Commands supported by the SPI flash memory according to the datasheet
WRITE_ENABLE     EQU 0x06  ; Address:0 Dummy:0 Num:0
WRITE_DISABLE    EQU 0x04  ; Address:0 Dummy:0 Num:0
READ_STATUS      EQU 0x05  ; Address:0 Dummy:0 Num:1 to infinite
READ_BYTES       EQU 0x03  ; Address:3 Dummy:0 Num:1 to infinite
READ_SILICON_ID  EQU 0xab  ; Address:0 Dummy:3 Num:1 to infinite
FAST_READ        EQU 0x0b  ; Address:3 Dummy:1 Num:1 to infinite
WRITE_STATUS     EQU 0x01  ; Address:0 Dummy:0 Num:1
WRITE_BYTES      EQU 0x02  ; Address:3 Dummy:0 Num:1 to 256
ERASE_ALL        EQU 0xc7  ; Address:0 Dummy:0 Num:0
ERASE_BLOCK      EQU 0xd8  ; Address:3 Dummy:0 Num:0
READ_DEVICE_ID   EQU 0x9f  ; Address:0 Dummy:2 Num:1 to infinite



; Variables used in the program:
dseg at 30H
	w:   ds 3 ; 24-bit play counter.  Decremented in Timer 1 ISR.

; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Count1ms:     ds 2 ; Used to determine when half second has passed
sec_counter:  ds 1 ; The BCD counter incrememted in the ISR and displayed in the main loop
; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
sound_done: ds 1 ;flag for when sound is done
state2: ds 1

bseg
half_seconds_flag: dbit 1 ; Set to one in the ISR every time 500 ms had passed

cseg
; These 'equ' must match the hardware wiring
LCD_RS equ P3.2
;LCD_RW equ PX.X ; Not used in this code, connect the pin to GND
LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST
	
;-------------------------------------;
; ISR for Timer 1.  Used to playback  ;
; the WAV file stored in the SPI      ;
; flash memory.                       ;
;-------------------------------------;


; Approximate index of sounds in file 'C:\Users\takau\OneDrive\Desktop\elec_291\Sound_New\Sound_oven-sound-9-1.wav'
sound_index:
    db 0x00, 0x38, 0xa4 ; 0 start
    db 0x00, 0x65, 0x0e ; 1 ramp to soak
    db 0x00, 0xd2, 0x8d ; 2 soak
    db 0x01, 0x22, 0x8d ; 3 ramp to peak
    db 0x01, 0x89, 0x8d ; 4 reflow
    db 0x01, 0xe7, 0x0d ; 5 cooling
    db 0x02, 0x2e, 0x0d ; 6 finished
    db 0x02, 0x7b, 0x8d ; 7 deg c
    db 0x03, 0x00, 0xcd ; 8 1
    db 0x03, 0x3a, 0x0d ; 9 2
    db 0x03, 0x78, 0x8d ; 10 3
    db 0x03, 0xbf, 0x58 ; 11 4
    db 0x04, 0x09, 0x0d ; 12 5
    db 0x04, 0x4e, 0x4d ; 13 6
    db 0x04, 0x92, 0x8d ; 14 7
    db 0x04, 0xd9, 0x40 ; 15 8
    db 0x05, 0x14, 0x01 ; 16 9
    db 0x05, 0x5e, 0xcd ; 17 10
    db 0x05, 0x9a, 0x4d ; 18 11
    db 0x05, 0xe4, 0x06 ; 19 12
    db 0x06, 0x1e, 0xcd ; 20 13
    db 0x06, 0x6b, 0xce ; 21 14
    db 0x06, 0xb3, 0xc9 ; 22 15
    db 0x06, 0xf3, 0x0e ; 23 16
    db 0x07, 0x38, 0xce ; 24 17
    db 0x07, 0x85, 0x3c ; 25 18
    db 0x07, 0xc2, 0xcd ; 26 19
    db 0x08, 0x0e, 0x8d ; 27 20
    db 0x08, 0x45, 0x4d ; 28 30
    db 0x08, 0x8b, 0x7d ; 29 40
    db 0x08, 0xcf, 0xce ; 30 50
    db 0x09, 0x14, 0xcd ; 31 60
    db 0x09, 0x5e, 0xce ; 32 70
    db 0x09, 0xb3, 0x2b ; 33 80
    db 0x09, 0xf4, 0x8d ; 34 90
    db 0x0a, 0x42, 0x09 ; 35 100
    db 0x0a, 0x86, 0x0d ; 36 200

; Size of each sound in 'sound_index'
Size_sound:
    db 0x00, 0x2c, 0x6a ; 0 
    db 0x00, 0x6d, 0x7f ; 1 
    db 0x00, 0x50, 0x00 ; 2 
    db 0x00, 0x67, 0x00 ; 3 
    db 0x00, 0x5d, 0x80 ; 4 
    db 0x00, 0x47, 0x00 ; 5 
    db 0x00, 0x45, 0x80 ; 6 
    db 0x00, 0x85, 0x40 ; 7 
    db 0x00, 0x39, 0x40 ; 8 
    db 0x00, 0x3e, 0x80 ; 9 
    db 0x00, 0x46, 0xcb ; 10 
    db 0x00, 0x49, 0xb5 ; 11 
    db 0x00, 0x45, 0x40 ; 12 
    db 0x00, 0x44, 0x40 ; 13 
    db 0x00, 0x46, 0xb3 ; 14 
    db 0x00, 0x31, 0x80 ; 15 
    db 0x00, 0x4a, 0xcc ; 16 
    db 0x00, 0x3b, 0x80 ; 17 
    db 0x00, 0x49, 0xb9 ; 18 
    db 0x00, 0x3a, 0xc7 ; 19 
    db 0x00, 0x4d, 0x01 ; 20 
    db 0x00, 0x47, 0xfb ; 21 
    db 0x00, 0x3f, 0x45 ; 22 
    db 0x00, 0x45, 0xc0 ; 23 
    db 0x00, 0x4c, 0x6e ; 24 
    db 0x00, 0x3d, 0x91 ; 25 
    db 0x00, 0x4b, 0xc0 ; 26 
    db 0x00, 0x36, 0xc0 ; 27 
    db 0x00, 0x46, 0x30 ; 28 
    db 0x00, 0x44, 0x51 ; 29 
    db 0x00, 0x44, 0xff ; 30 
    db 0x00, 0x4a, 0x01 ; 31 
    db 0x00, 0x54, 0x5d ; 32 
    db 0x00, 0x41, 0x62 ; 33 
    db 0x00, 0x4d, 0x7c ; 34 
    db 0x00, 0x44, 0x04 ; 35 
    db 0x00, 0x4c, 0x42 ; 36 


Timer1_ISR:
	; The registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Check if the play counter is zero.  If so, stop playing sound.
	mov a, w+0
	orl a, w+1
	orl a, w+2
	jz stop_playing
	
	; Decrement play counter 'w'.  In this implementation 'w' is a 24-bit counter.
	mov a, #0xff
	dec w+0
	cjne a, w+0, keep_playing
	dec w+1
	cjne a, w+1, keep_playing
	dec w+2
	
keep_playing:
	setb SPEAKER
	lcall Send_SPI ; Read the next byte from the SPI Flash...
	mov P0, a ; WARNING: Remove this if not using an external DAC to use the pins of P0 as GPIO
	add a, #0x80
	mov DADH, a ; Output to DAC. DAC output is pin P2.3
	orl DADC, #0b_0100_0000 ; Start DAC by setting GO/BSY=1
	sjmp Timer1_ISR_Done

stop_playing:
	clr TR1 ; Stop timer 1
	setb FLASH_CE  ; Disable SPI Flash
	clr SPEAKER ; Turn off speaker.  Removes hissing noise when not playing sound.
	mov DADH, #0x80 ; middle of range
	orl DADC, #0b_0100_0000 ; Start DAC by setting GO/BSY=1

Timer1_ISR_Done:	
	pop psw
	pop acc
	reti

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer2_Init:
    mov R0, #184
    mov R1, #0
    mov R2, #0
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	; Set the reload value
	mov RCAP2H, #high(TIMER2_RELOAD)
	mov RCAP2L, #low(TIMER2_RELOAD)
	; Init One millisecond interrupt counter.  It is a 16-bit variable made with two 8-bit parts
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
    setb ET2  ; Enable timer 2 interrupt
    setb TR2  ; Enable timer 2
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR
	cpl P1.0 ; To check the interrupt rate with oscilloscope. It must be precisely a 1 ms pulse.
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	; Check if half second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Timer2_ISR_done_b1 ;nstruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done_b1
	
	; 500 milliseconds have passed.  Set a flag so the main program knows
	setb half_seconds_flag ; Let the main program know half second had passed
	cpl TR0 ; Enable/disable timer/counter 0. This line creates a beep-silence-beep-silence sound.
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Increment the BCD counter
	mov a, sec_counter
	add a, #0x01
Timer2_ISR_da:
	da a ; Decimal adjust instruction.  Check datasheet for more details!
	cjne a, #0x05, sec_b1 ;check if 5 sec have passed
	mov a, R0
	mov R1, a
	
;FSM2
FSM2_0:
	
FSM2_1:
	mov a, state2
	cjne a, #1, FSM2_2
	mov b, #200
	mov a, R1
	div ab
	cjne a, #0, play_200
	mov b, #100
	mov a, R1
	div ab
	cjne a, #0, play_100
	mov state2, #2
	ljmp FSM2_2
	

play_200:
	mov R2, #36
	lcall Play_sound
	mov a, R1
	subb a, #200
	mov R1, a
	mov state2, #2
	ljmp FSM2_2


play_100:
	mov R2, #35
	lcall Play_sound
	mov a, R1
	subb a, #100
	mov R1, a
	mov state2, #2
	ljmp FSM2_2


FSM2_2:
	mov a, state2
	cjne a, #2, FSM2_3
	jb SPEAKER, FSM2_2
	mov state2, #3
	ljmp FSM2_3

Timer2_ISR_done_b1:
	ljmp Timer2_ISR_done	
sec_b1:
	ljmp sec
	
FSM2_3:
	mov a, state2
	cjne a, #3, FSM2_4_b1
	mov b, #90
	mov a, R1
	div ab
	cjne a, #0, play_90
	mov a, R1
	mov b, #80
	div ab
	cjne a, #0, play_80
	mov a, R1
	mov b, #70
	div ab
	cjne a, #0, play_70
	mov a, R1
	mov b, #60
	div ab
	cjne a, #0, play_60
	mov a, R1
	mov b, #50
	div ab
	cjne a, #0, play_50
	mov a, R1
	mov b, #40
	div ab
	cjne a, #0, play_40
	mov a, R1
	mov b, #30
	div ab
	cjne a, #0, play_30
	mov a, R1
	mov b, #20
	div ab
	cjne a, #0, play_20
	mov state2, #4
	ljmp FSM2_4_b1

FSM2_4_b1:
	ljmp FSM2_4


play_90:
	mov R2, #34
	lcall Play_sound
	mov a, R1
	subb a, #90
	mov R1, a
	mov state2, #4
	ljmp FSM2_4

play_80:
	mov R2, #33
	lcall Play_sound
	mov a, R1
	subb a, #80
	mov R1, a
	mov state2, #4
	ljmp FSM2_4
	
play_70:
	mov R2, #32
	lcall Play_sound
	mov a, R1
	subb a, #70
	mov R1, a
	mov state2, #4
	ljmp FSM2_4

play_60:
	mov R2, #31
	lcall Play_sound
	mov a, R1
	subb a, #60
	mov R1, a
	mov state2, #4
	ljmp FSM2_4

play_50:
	mov R2, #30
	lcall Play_sound
	mov a, R3
	subb a, #50
	mov R1, a
	mov state2, #4
	ljmp FSM2_4

play_40:
	mov R2, #29
	lcall Play_sound
	mov a, R1
	subb a, #40
	mov R1, a
	mov state2, #4
	ljmp FSM2_4

play_30:
	mov R2, #28
	lcall Play_sound
	mov a, R1
	subb a, #30
	mov R1, a
	mov state2, #4
	ljmp FSM2_4

play_20:
	mov R2, #27
	lcall Play_sound
	mov a, R1
	subb a, #20
	mov R1, a
	mov state2, #4
	ljmp FSM2_4
	
FSM2_4:
	mov a, state2
	cjne a, #4, FSM2_5
	jb SPEAKER, FSM2_4
	mov state2, #5
	ljmp FSM2_5

FSM2_5:
	mov a, state2
	cjne a, #5, FSM2_6_b1
	ljmp check_19
	
check_19:
	mov a, R1
	cjne a, #19, check_18
	mov R2, #26
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
check_18:
	mov a, R1
	cjne a, #18, check_17
	mov R2, #25
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
check_17:
	mov a, R1
	cjne a, #17, check_16
	mov R2, #24
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
check_16:
	mov a, R1
	cjne a, #16, check_15
	mov R2, #23
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
check_15:
	mov a, R1
	cjne a, #15, check_14
	mov R2, #22
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
check_14:
	mov a, R1
	cjne a, #14, check_13
	mov R2, #21
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
check_13:
	mov a, R1
	cjne a, #13, check_12
	mov R2, #20
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
	
FSM2_6_b1:
	ljmp FSM2_6
FSM2_0_b1:
	ljmp FSM2_0

check_12:
	mov a, R1
	cjne a, #12, check_11
	mov R2, #19
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
check_11:
	mov a, R1
	cjne a, #11, check_10
	mov R2, #18
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6

check_10:
	mov a, R1
	cjne a, #10, check_9
	mov R2, #17
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
check_9:
	mov a, R1
	cjne a, #9, check_8
	mov R2, #16
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
check_8:
	mov a, R1
	cjne a, #8, check_7
	mov R2, #15
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
check_7:
	mov a, R1
	cjne a, #7, check_6
	mov R2, #14
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
	
FSM2_0_b2:
	ljmp FSM2_0
	
check_6:
	mov a, R1
	cjne a, #6, check_5
	mov R2, #13
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
check_5:
	mov a, R1
	cjne a, #5, check_4
	mov R2, #12
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6

check_4:
	mov a, R1
	cjne a, #4, check_3
	mov R2, #11
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
check_3:
	mov a, R1
	cjne a, #3, check_2
	mov R2, #10
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
check_2:
	mov a, R1
	cjne a, #2, check_1
	mov R2, #9
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6
check_1:
	mov a, R1
	cjne a, #1, FSM2_6
	mov R2, #8
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_6

FSM2_6:
	mov a, state2
	cjne a, #6, FSM2_7
	jb SPEAKER, FSM2_6
	mov state2, #7
	ljmp FSM2_7
	
FSM2_7:
	mov a, state2
	cjne a, #7, FSM2_0_b2
	mov a, #0
	mov state2, #1
sec:
	mov sec_counter, a
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti

;---------------------------------;
; Sends AND receives a byte via   ;
; SPI.                            ;
;---------------------------------;
spi:
Send_SPI:
	SPIBIT MAC
	    ; Send/Receive bit %0
		rlc a
		mov MY_MOSI, c
		setb MY_SCLK
		mov c, MY_MISO
		clr MY_SCLK
		mov acc.0, c
	ENDMAC
	
	SPIBIT(7)
	SPIBIT(6)
	SPIBIT(5)
	SPIBIT(4)
	SPIBIT(3)
	SPIBIT(2)
	SPIBIT(1)
	SPIBIT(0)

	ret

init:
	; Configure P2.0, P2.4, P2.5 as open drain outputs
	orl P2M0, #0b_0011_0001
	orl P2M1, #0b_0011_0001
	setb MY_MISO  ; Configured as input
	setb FLASH_CE ; CS=1 for SPI flash memory
	clr MY_SCLK   ; Rest state of SCLK=0
	clr SPEAKER   ; Turn off speaker.
	
	; Configure timer 1
	anl	TMOD, #0x0F ; Clear the bits of timer 1 in TMOD
	orl	TMOD, #0x10 ; Set timer 1 in 16-bit timer mode.  Don't change the bits of timer 0
	mov TH1, #high(TIMER1_RELOAD)
	mov TL1, #low(TIMER1_RELOAD)
	; Set autoreload value
	mov RH1, #high(TIMER1_RELOAD)
	mov RL1, #low(TIMER1_RELOAD)

	; Enable the timer and interrupts
    setb ET1  ; Enable timer 1 interrupt
	; setb TR1 ; Timer 1 is only enabled to play stored sound

	; Configure the DAC.  The DAC output we are using is P2.3, but P2.2 is also reserved.
	mov DADI, #0b_1010_0000 ; ACON=1
	mov DADC, #0b_0011_1010 ; Enabled, DAC mode, Left adjusted, CLK/4
	mov DADH, #0x80 ; Middle of scale
	mov DADL, #0
	orl DADC, #0b_0100_0000 ; Start DAC by GO/BSY=1
check_DAC_init:
	mov a, DADC
	jb acc.6, check_DAC_init ; Wait for DAC to finish	
	setb EA ; Enable interrupts	
	ret
	
Play_sound:
	clr TR1 ; stops timer 1 ISR from playing previous request
	setb FLASH_CE
	clr SPEAKER ; turn off speaker
	
	clr FLASH_CE ; enable SPI flash
	mov a, #READ_BYTES
	lcall Send_SPI ; set initial position in memory where to start playing

	mov dptr, #sound_index ; The beginning of the index (3 bytes per entry)
	; multiply R0 by 3 and add it to the dptr
	mov a, R2
	mov b, #3
	mul ab
	add a, dpl
	mov dpl, a
	mov a, b
	addc a, dph
	mov dph, a
	
	; dptr is pointing to the MSB of the 24-bit flash memory address
	clr a
	movc a, @a+dptr
	lcall spi
	
	inc dptr
	clr a
	movc a, @a+dptr
	lcall spi
	
	inc dptr
	clr a
	movc a, @a+dptr
	lcall spi
	
	mov dptr, #size_sound
	
	mov a, R2
	mov b, #3
	mul ab
	add a, dpl
	mov dpl, a
	mov a, b
	addc a, dph
	mov dph, a
	
	; dptr is pointing to the MSB of the 24-bit flash memory address
	clr a
	movc a, @a+dptr
	mov w+2, a
	
	inc dptr
	clr a
	movc a, @a+dptr
	mov w+1, a
	
	inc dptr
	clr a
	movc a, @a+dptr
	mov w+0, a
	
	setb SPEAKER ; turn on speaker
	setb TR1 ; start playback by enabling timer 1
	ret
	
main:
	mov SP, #0x7f ; Setup stack pointer to the start of indirectly accessable data memory minus one
    lcall Init ; Initialize the hardware
    mov sec_counter, #0x00
    lcall Timer2_Init
	setb EA
    setb half_seconds_flag
    mov state2, #1

loop:

	ljmp loop

END	