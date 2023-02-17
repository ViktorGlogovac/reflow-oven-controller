$NOLIST
$MODLP51RC2
$LIST

; setup buttons
shift_PB   equ P2.2
TEMP_SOAK_PB equ P0.7
TIME_SOAK_PB equ P0.6
TEMP_REFL_PB equ P0.5
TIME_REFL_PB equ P0.4
RESET_PB equ P2.7
START_PB equ P4.5
RETURN_PB equ P4.4

CLK           EQU 22118400  ; Microcontroller system crystal frequency in Hz
SYSCLK        EQU 22118400  ; Microcontroller system clock frequency in Hz
TIMER1_RATE   EQU 22050     ; 22050Hz is the sampling rate of the wav file we are playing
TIMER1_RELOAD EQU 0x10000-(SYSCLK/TIMER1_RATE)
TIMER2_RATE   EQU 1000      ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))
BAUD 		  EQU 115200
BRG_VAL		  EQU (0x100-(CLK/(16*BAUD)))
SPEAKER  EQU P2.6 ; Used with a MOSFET to turn off speaker when not in use

MY_SCLK equ P0.0
MY_MISO equ P0.1
MY_MOSI equ P0.2
CE_ADC equ P0.3
; The pins used for SPI
FLASH_CE  EQU  P2.5
MY_MOSIs   EQU  P2.4 
MY_MISOs  EQU  P2.1
MY_SCLKs   EQU  P2.0 

; Commands supported by the SPI flash memory according to the datasheet
WRITE_ENABLE     EQU 0x06  ; Address:0 Dummy:0 Num:0
WRITE_DISABLE    EQU 0x04  ; Address:0 Dummy:0 Num:0
READ_STATUS      EQU 0x05  ; Address:0 Dummy:0 Num:1 to infinite
READ_BYTES       EQU 0x03  ; Address:3 Dummy:0 Num:1 to infinite
READ_SILICON_ID  EQU 0xab  ; Address:0 Dummy:3 Num:1 to infinite
FAST_READ        EQU 0x0b  ; Address:3 Dummy:1 Num:1 to infinite
WRITE_STATUS     EQU 0x01  ; Address:0 Dummy:0 Num:1
WRITE_BYTES      EQU 0x02  ; Address:3 Dummy:0 Num:1 to 256
ERASE_ALL        EQU 0xc7  ; Address:0 Dummy:0 Num:n0
ERASE_BLOCK      EQU 0xd8  ; Address:3 Dummy:0 Num:0
READ_DEVICE_ID   EQU 0x9f  ; Address:0 Dummy:2 Num:1 to infinite

;Reset vector
org 0x00000
   ljmp main

; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR
	

$NOLIST
$include(LCD_4bit.inc)
$include(math32.inc)
$LIST

PWM_OUTPUT    equ P1.0 ; Attach an LED (with 1k resistor in series) to P1.0
DSEG at 0x30; Before the state machine!
FSM1_state:      ds 1
temp_soak:  ds 1
Time_soak:  ds 1
Temp_refl:  ds 1
Time_refl:  ds 1
Count1ms:   ds 2 ; Used to determine when half second has passed
seconds:	ds 1
sec_counter: ds 1
mins:	ds 1
temp:       ds 1
pwm_ratio:        ds 1
result:     ds  2
bcd:        ds  5
x:          ds  4
y:          ds  4
lmc:        ds  4
avg:         ds  4
sound_done: ds 1
state2: ds 1
w: ds 3

bseg
half_seconds_flag: dbit 1 ; Set to one in the ISR every time 500 ms had passed
reset_timer_flag:  dbit 1
safetycheck_flag:  dbit 1
start_flag:        dbit 1
mf: dbit 1



cseg
;LCD PINS
LCD_RS equ P3.2
LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7


Initial_Message:  db 'TS  tS  TR  tR  ', 0
time_soak_msg:    db 'SOAK TEMP:     <', 0
temp_soak_msg:    db 'SOAK TIME:     <', 0
time_reflow_msg:  db 'REFLOW TEMP:   <', 0
temp_reflow_msg:  db 'REFLOW TIME:   <', 0
current_temp:     db 'Temp:          <', 0
current_time:     db 'Time:          <', 0 
error:     		  db 'Failure:       <', 0 
error2:     	  db 'Aborting       <', 0 
state1message: 	  db 'RamptoSoak      ', 0
state2message: 	  db 'Soak 2          ', 0
state3message: 	  db 'RamptoPeak 3    ', 0
state4message: 	  db 'Reflow 4        ', 0
state5message: 	  db 'Cooling 5       ', 0
blank:            db '                ', 0
yusuf:            db 'YUSUF           ', 0
 

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
FSM2 mac
  
FSM2_0:
	mov a, seconds
	mov b, #5
	div ab
	cjne b, #0, FSM2_done
	mov state2, #1
		
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
	ljmp FSM2_0

play_200:
	mov R2, #36
	lcall Play_sound
	mov a, R1
	subb a, #200
	mov R1, a
	mov state2, #2
	ljmp FSM2_0


play_100:
	mov R2, #35
	lcall Play_sound
	mov a, R1
	subb a, #100
	mov R1, a
	mov state2, #2
	ljmp FSM2_0
	
FSM2_2:
	lcall still_playing
	mov a, state2
	cjne a, #2, FSM2_3
	mov state2, #3
	ljmp FSM2_0

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
	ljmp FSM2_0
	
FSM2_4_b1:
	ljmp FSM2_4
	
play_90:
	mov R2, #34
	lcall Play_sound
	mov a, R1
	subb a, #90
	mov R1, a
	mov state2, #4
	ljmp FSM2_0

play_80:
	mov R2, #33
	lcall Play_sound
	mov a, R1
	subb a, #80
	mov R1, a
	mov state2, #4
	ljmp FSM2_0
	
play_70:
	mov R2, #32
	lcall Play_sound
	mov a, R1
	subb a, #70
	mov R1, a
	mov state2, #4
	ljmp FSM2_0

play_60:
	mov R2, #31
	lcall Play_sound
	mov a, R1
	subb a, #60
	mov R1, a
	mov state2, #4
	ljmp FSM2_0

play_50:
	mov R2, #30
	lcall Play_sound
	mov a, R1
	subb a, #50
	mov R1, a
	mov state2, #4
	ljmp FSM2_0

play_40:
	mov R2, #29
	lcall Play_sound
	mov a, R1
	subb a, #40
	mov R1, a
	mov state2, #4
	ljmp FSM2_0

play_30:
	mov R2, #28
	lcall Play_sound
	mov a, R1
	subb a, #30
	mov R1, a
	mov state2, #4
	ljmp FSM2_0

play_20:
	mov R2, #27
	lcall Play_sound
	mov a, R1
	subb a, #20
	mov R1, a
	mov state2, #4
	ljmp FSM2_0

FSM2_0_b1:
	ljmp FSM2_0
	
FSM2_4:
	lcall still_playing
	mov a, state2
	cjne a, #4, FSM2_5
	mov state2, #5
	ljmp FSM2_0
	
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
	ljmp FSM2_0
check_18:
	mov a, R1
	cjne a, #18, check_17
	mov R2, #25	
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
		
check_17:
	mov a, R1
	cjne a, #17, check_16
	mov R2, #24
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
check_16:
	mov a, R1
	cjne a, #16, check_15
	mov R2, #23
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0

check_15:
	mov a, R1
	cjne a, #15, check_14
	mov R2, #22
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
check_14:
	mov a, R1
	cjne a, #14, check_13
	mov R2, #21
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
check_13:
	mov a, R1
	cjne a, #13, check_12
	mov R2, #20
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0

FSM2_6_b1:
	ljmp FSM2_6

check_12:
	mov a, R1
	cjne a, #12, check_11
	mov R2, #19
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
check_11:
	mov a, R1
	cjne a, #11, check_10
	mov R2, #18
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
check_10:
	mov a, R1
	cjne a, #10, check_9
	mov R2, #17
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
check_9:
	mov a, R1
	cjne a, #9, check_8
	mov R2, #16
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
check_8:
	mov a, R1
	cjne a, #8, check_7
	mov R2, #15
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
check_7:
	mov a, R1
	cjne a, #7, check_6
	mov R2, #14
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
check_6:
	mov a, R1
	cjne a, #6, check_5
	mov R2, #13
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
check_5:
	mov a, R1
	cjne a, #5, check_4
	mov R2, #12
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0

check_4:
	mov a, R1
	cjne a, #4, check_3
	mov R2, #11
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
check_3:
	mov a, R1
	cjne a, #3, check_2
	mov R2, #10
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
check_2:
	mov a, R1
	cjne a, #2, check_1
	mov R2, #9
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
check_1:
	mov a, R1
	cjne a, #1, FSM2_6
	mov R2, #8
	lcall Play_sound
	mov state2, #6
	ljmp FSM2_0
FSM2_0_b2:
	ljmp FSM2_0_b1
FSM2_6:
	mov a, state2
	cjne a, #6, FSM2_0_b2
	mov state2, #1
	lcall still_playing
	mov R2, #7
	lcall Play_sound
	lcall still_playing
FSM2_done:
endmac

Say_state mac
	lcall still_playing
say_ramp_to_soak:
	mov a, state
	cjne a, #1, say_soak
	mov R2, #1
	lcall Play_sound
	lcall done
say_soak:
	mov a, state
	cjne a, #2, say_ramp_to_peak
	mov R2, #2
	lcall Play_sound
	lcall done
say_ramp_to_peak:
	mov a, state
	cjne a, #3, say_reflow
	mov R2, #3
	lcall Play_sound
say_reflow:
	mov a, state
	cjne a, #4, say_cooling
	mov R2, #4
	lcall Play_sound
	lcall done
say_cooling:
	mov a, state
	cjne a, #5, say_finished
	mov R2, #5
	lcall Play_sound
	lcall done
say_finished:
	mov a, state
	cjne a, #6, done
	mov R2, #6
	lcall Play_sound
done:
endmac

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
	
still_playing:
	jb TR1, still_playing
	ret

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
; Timer 2 Stuff                   ;
;---------------------------------;

Timer2_Init:
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
	cjne a, #low(1000), Timer2_ISR_done ;nstruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done
	
	; 500 milliseconds have passed.  Set a flag so the main program knows
	setb half_seconds_flag ; Let the main program know half second had passed
	cpl TR0 ; Enable/disable timer/counter 0. This line creates a beep-silence-beep-silence sound.
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Increment the BCD counter
	mov a, seconds
	add a, #0x01
Timer2_ISR_da:
	da a ; Decimal adjust instruction.  Check datasheet for more details!
	mov seconds, a
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
;SPI ADC SHITANDPISS

INIT_SPI: 
     setb MY_MISO    ; Make MISO an input pin 
     clr MY_SCLK     ; For mode (0,0) SCLK is zero 
     ret 
  
DO_SPI_G: 
    push acc 
    mov R1, #0      ; Received byte stored in R1 
    mov R2, #8      ; Loop counter (8-bits) 
DO_SPI_G_LOOP: 
    mov a, R0       ; Byte to write is in R0 
    rlc a           ; Carry flag has bit to write 
    mov R0, a 
    mov MY_MOSI, c 
    setb MY_SCLK    ; Transmit 
    mov c, MY_MISO  ; Read received bit 
    mov a, R1       ; Save received bit in R1 
    rlc a 
    mov R1, a 
    clr MY_SCLK 
    djnz R2, DO_SPI_G_LOOP 
    pop acc 
    ret 

Left_blank mac
	mov a, %0
	anl a, #0xf0
	swap a
	jz Left_blank_%M_a
	ljmp %1
Left_blank_%M_a:
	Display_char(#' ')
	mov a, %0
	anl a, #0x0f
	jz Left_blank_%M_b
	ljmp %1
Left_blank_%M_b:
	Display_char(#' ')
endmac

Send_BCD mac
	push ar0
	mov r0, %0
	lcall ?Send_BCD
	pop ar0
?Send_BCD:
	push acc
	;send most significant digit
	mov a, r0
	swap a
	anl a, #0fh
	orl a, #30h
	lcall putchar
	;send least significant digit
	mov a, r0
	anl a, #0fh
	orl a, #30h
	lcall putchar
	pop acc
	ret
endmac

Display_10_digit_BCD:
	Set_Cursor(2, 7)
	Display_BCD(bcd+4)
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	; Replace all the zeros to the left with blanks
	Set_Cursor(2, 7)
	Left_blank(bcd+4, skip_blank)
	Left_blank(bcd+3, skip_blank)
	Left_blank(bcd+2, skip_blank)
	Left_blank(bcd+1, skip_blank)
	mov a, bcd+0
	anl a, #0f0h
	swap a
	jnz skip_blank
	Display_char(#' ')
skip_blank:
	ret

; Eight bit number to display passed in ?a?.
; Sends result to LCD
SendToLCD:
	mov b, #100
	div ab
	orl a, #0x30 ; Convert hundreds to ASCII
	lcall ?WriteData ; Send to LCD
	mov a, b ; Remainder is in register b
	mov b, #10
	div ab
	orl a, #0x30 ; Convert tens to ASCII
	lcall ?WriteData; Send to LCD
	mov a, b
	orl a, #0x30 ; Convert units to ASCII
	lcall ?WriteData; Send to LCD
	ret



loadbyte mac
	mov a, %0
	movx @dptr, a
	inc dptr
endmac

putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret

; Send a constant-zero-terminated string using the serial port (for the temp/putty stuff)
SendString:
    clr A
    movc A, @A+DPTR
    jz SendStringDone
    lcall putchar
    inc DPTR
    sjmp SendString
SendStringDone:
    ret


Wait10us:
	mov R0, #74
	djnz R0, $
	ret
	


read_temp:
    lcall Average_CH0
	
	mov lmc+0, x+0
	mov lmc+1, x+1
	mov lmc+2, #0
	mov lmc+3, #0
	
	lcall Average_CH1
	
	mov y+0, lmc+0
	mov y+1, lmc+1
	mov y+2, #0
	mov y+3, #0
	lcall add32 ; adds thermo and LMC355 together
	ret
	
Average_CH0:
	load_x(0)
	mov R5, #100
Sum_loop0:
	lcall Read_ADC_Channel_0
	mov y+3, #0
	mov y+2, #0
	mov y+1, avg+1
	mov y+0, avg+0
	lcall add32
	lcall Wait10us
	djnz R5, Sum_loop0
	load_y(100)
	lcall div32
	load_Y(410)
	lcall mul32
	load_Y(1023)
	lcall div32
	load_Y(273)
	lcall sub32
	ret
	
Read_ADC_Channel_0:
	clr CE_ADC
	mov R0, #00000001B ; Start bit:1
	lcall DO_SPI_G
	mov R0, #10000000B ; Single ended, read channel 0
	lcall DO_SPI_G
	mov a, R1          ; R1 contains bits 8 and 9
	anl a, #00000011B  ; We need only the two least significant bits
	mov Result+1, a    ; Save result high.
	mov R0, #55H ; It doesn't matter what we transmit...
	lcall DO_SPI_G
	mov Result, R1     ; R1 contains bits 0 to 7.  Save result low.
	setb CE_ADC
	
	
	mov avg+0, result+0 
	mov avg+1, result+1
	mov avg+2, #0
	mov avg+3, #0
	ret

Average_CH1:
	load_x(0)
	mov R5, #100
Sum_loop1:
	lcall Read_ADC_Channel_1
	mov y+3, #0
	mov y+2, #0
	mov y+1, avg+1
	mov y+0, avg+0
	lcall add32
	lcall Wait10us
	djnz R5, Sum_loop1
	load_y(100)
	lcall div32
	load_Y(319)
	lcall mul32
	load_Y(1000)
	lcall div32
	;load_Y(415)
	;lcall div32 
	;load_Y(303)
	;lcall div32
	ret
	
	
Read_ADC_Channel_1:
	clr CE_ADC
	mov R0, #00000001B ; Start bit:1
	lcall DO_SPI_G
	mov R0, #00000001B ; Single ended, read channel 1
	lcall DO_SPI_G
	mov a, R1          ; R1 contains bits 8 and 9
	anl a, #00000011B  ; We need only the two least significant bits
	mov Result+1, a    ; Save result high.
	mov R0, #55H ; It doesn't matter what we transmit...
	lcall DO_SPI_G
	mov Result, R1     ; R1 contains bits 0 to 7.  Save result low.
	setb CE_ADC
	
	
	mov avg+0, result+0 
	mov avg+1, result+1
	mov avg+2, #0
	mov avg+3, #0
	ret

    InitSerialPort:
    ; Since the reset button bounces, we need to wait a bit before
    ; sending messages, otherwise we risk displaying gibberish!
    mov R1, #222
    mov R0, #166
    djnz R0, $   ; 3 cycles->3*45.21123ns*166=22.51519us
    djnz R1, $-4 ; 22.51519us*222=4.998ms
    ; Now we can proceed with the configuration
	orl	PCON,#0x80
	mov	SCON,#0x52
	mov	BDRCON,#0x00
	mov	BRL,#BRG_VAL
	mov	BDRCON,#0x1E ; BDRCON=BRR|TBCK|RBCK|SPD;

    SendToSerialPort:
	mov b, #100
	div ab
	orl a, #0x30 ; Convert hundreds to ASCII
	lcall putchar ; Send to PuTTY/Python/Matlab
	mov a, b    ; Remainder is in register b
	mov b, #10
	div ab
	orl a, #0x30 ; Convert tens to ASCII
	lcall putchar ; Send to PuTTY/Python/Matlab
	mov a, b
	orl a, #0x30 ; Convert units to ASCII
	lcall putchar ; Send to PuTTY/Python/Matlab
	ret
	
	
    ;;; INITIAL SETUP FUNCTIONS

    Save_Configuration:
	mov FCON, #0x08 ; Page Buffer Mapping Enabled (FPS = 1)
	mov dptr, #0x7f80 ; Last page of flash memory
	; Save variables
	loadbyte(temp_soak) ; @0x7f80
	loadbyte(time_soak) ; @0x7f81
	loadbyte(temp_refl) ; @0x7f82
	loadbyte(time_refl) ; @0x7f83
	loadbyte(#0x55) ; First key value @0x7f84
	loadbyte(#0xAA) ; Second key value @0x7f85
	mov FCON, #0x00 ; Page Buffer Mapping Disabled (FPS = 0)
	orl EECON, #0b01000000 ; Enable auto-erase on next write sequence
	mov FCON, #0x50 ; Write trigger first byte
	mov FCON, #0xA0 ; Write trigger second byte
	; CPU idles until writing of flash completes.
	mov FCON, #0x00 ; Page Buffer Mapping Disabled (FPS = 0)
	anl EECON, #0b10111111 ; Disable auto-erase
	ret

getbyte mac
	clr a
	movc a, @a+dptr
	mov %0, a
	inc dptr
Endmac

Load_Configuration:
	mov dptr, #0x7f84 ; First key value location.
	getbyte(R0) ; 0x7f84 should contain 0x55
	cjne R0, #0x55, Load_Defaults
	getbyte(R0) ; 0x7f85 should contain 0xAA
	cjne R0, #0xAA, Load_Defaults
	; Keys are good. Get stored values.
	mov dptr, #0x7f80
	getbyte(temp_soak) ; 0x7f80
	getbyte(time_soak) ; 0x7f81
	getbyte(temp_refl) ; 0x7f82
	getbyte(time_refl) ; 0x7f83
	ret

; Load defaults if 'keys' are incorrect
Load_Defaults:
	
	mov temp_soak, #39
	mov time_soak, #45
	mov temp_refl, #225
	mov time_refl, #30
	ret
	
Change_8bit_Variable MAC
	jb %0, %2
	Wait_Milli_Seconds(#50) ; de-bounce
	jb %0, %2
	jnb %0, $
	jb SHIFT_PB, skip%Mb
	dec %1
	sjmp skip%Ma
	skip%Mb:
	inc %1
	skip%Ma:
ENDMAC

display_temp mac
	mov a, %0
	mov b, #100
    div	ab	
    add	a, #0x30
    Set_Cursor(2,13)
    mov	acc, a
    setb LCD_RS
    lcall LCD_byte
    mov	a, b
    mov	b, #10
    div	ab
    add	a, #0x30
    Set_Cursor(2,14)
    mov	acc, a
    setb LCD_RS
    lcall LCD_byte
    mov	a, b
    add	a, #0x30
    Set_Cursor(2,15)
    mov	acc, a
    setb LCD_RS
    lcall LCD_byte
endmac

main:
	;Initialization
	mov SP, #0x7F

	mov P0M0, #0
	mov P0M1, #0
    mov seconds, #0x00
    mov FSM1_state, #0

	lcall Load_Configuration

	lcall Timer2_Init
	setb EA ; Enable interrupts
	lcall LCD_4BIT
	lcall INIT_SPI
    lcall InitSerialPort
    setb half_seconds_flag
    clr safetycheck_flag

    Set_Cursor(1,1)
	Send_Constant_String(#Initial_Message)
	Set_Cursor(2,1)
	mov a, temp_soak
	lcall SendToLCD
	Set_Cursor(2,5)
	mov a, time_soak
	lcall SendToLCD
	Set_Cursor(2,9)
	mov a, temp_refl
	lcall SendToLCD
	Set_Cursor(2,13)
	mov a, time_refl
	lcall SendToLCD
    	; After initialization the program stays in this 'forever' loop
loop:
	Change_8bit_Variable(TEMP_SOAK_PB, temp_soak, loop_a)
	Set_Cursor(2, 1)
	mov a, temp_soak
	lcall SendToLCD
	lcall Save_Configuration
loop_a:
	Change_8bit_Variable(TIME_SOAK_PB, time_soak, loop_b)
	Set_Cursor(2, 5)
	mov a, time_soak
	lcall SendToLCD
	lcall Save_Configuration
loop_b:
	Change_8bit_Variable(TEMP_REFL_PB, temp_refl, loop_c)
	Set_Cursor(2, 9)
	mov a, temp_refl
	lcall SendToLCD
	lcall Save_Configuration
loop_c:
	Change_8bit_Variable(TIME_REFL_PB, time_refl, loop_temp)
	Set_Cursor(2, 13)
	mov a, time_refl
	lcall SendToLCD
	lcall Save_Configuration
	ljmp FSM1
	
loop_temp:
	lcall read_temp
    ljmp FSM1
	

    
;;loop_e:
;	jnb RESET_PB, loop_a
 ;   jb START_PB, FSM1_state0_done
  ;  jnb START_PB, $ ; Wait for key release
   ; mov FSM1_state, #1	
    ;ljmp loop

FSM1:
    mov a, FSM1_state 
    

FSM1_state0:
	
    cjne a, #0, FSM1_state1
    mov pwm_ratio+0, #low(0)
	mov pwm_ratio+1, #high(0)
    jb START_PB, FSM1_state0_done
    Wait_Milli_Seconds(#50) ; debouncing
	jb START_PB, FSM1_state0_done
    jnb START_PB, $
    mov FSM1_state, #1
    ljmp FSM1_state1
    Send_Constant_String(#blank)
    
FSM1_state0_done:

;	ljmp FSM1_FSM2 ; audio stuff
	ljmp loop
	
FSM1_state2a:
ljmp FSM1_state2

FSM1_state1:
cjne a, #1, FSM1_state2a
Set_Cursor(1, 1)
Send_Constant_String(#state1message)
Set_Cursor(1, 13)
Display_BCD(seconds)
Set_Cursor(2, 1)
Send_Constant_String(#temp_soak_msg)
lcall hex2bcd
Set_Cursor(2, 13)
Display_BCD(bcd)
mov pwm_ratio+0, #low(1000)
mov pwm_ratio+1, #high(1000)
jb safetycheck_flag, Safety_Passed
sjmp check_safety

;FSM1_state0_done_b1:
;	ljmp FSM1_state0_done

check_safety:
mov a, x
cjne a, #0x50, check_time
ljmp set_flag

check_time:
mov a, seconds
cjne a, #0x60, Safety_Passed
ljmp FSM1_ERROR_b

set_flag:
SETB safetycheck_flag

Safety_Passed:
mov a, temp_soak
clr c
subb a, x
jnc FSM1_state1_done
mov FSM1_state, #2
mov seconds, #0

FSM1_state1_done:
ljmp loop_temp

FSM1_ERROR_b:
ljmp FSM1_ERROR
FSM1_state3_b1:
	ljmp FSM1_state3	

FSM1_state2:
cjne a, #2, FSM1_state3_b1
Set_Cursor(1, 1)
Send_Constant_String(#state2message)
Set_Cursor(1, 13)
Display_BCD(seconds)
Set_Cursor(2, 1)
Send_Constant_String(#state2message)
display_temp(x)
mov pwm_ratio+0, #low(200)
mov pwm_ratio+1, #high(200)
mov a, time_soak
clr c
subb a, seconds
jnc FSM1_state2_done
mov FSM1_state, #3
mov seconds, #0x00

FSM1_state2_done:
	ljmp loop_temp

FSM1_state0_B:
ljmp FSM1_state0

FSM1_state3:
	cjne a, #3, FSM1_state4
	Set_Cursor(1, 1)
	Send_Constant_String(#state3message)
    mov pwm_ratio+0, #low(1000)
    mov pwm_ratio+1, #high(1000)
    mov a, temp_refl
    subb a, x
    jnc FSM1_state3_done
    mov FSM1_state, #4

FSM1_state3_done:
	ljmp loop_temp
	
FSM1_state0_C:
	ljmp FSM1_state0_B
FSM1_state4:
	cjne a, #4, FSM1_state5
	Set_Cursor(1, 1)
	Send_Constant_String(#state4message)
    cjne a, #4, FSM1_state5
    mov pwm_ratio+0, #low(200)
    mov pwm_ratio+1, #high(200)
    mov a, Time_refl
    clr c
    subb a , seconds
    jnc FSM1_state4_done
    mov FSM1_state, #5
FSM1_state4_done:
	ljmp loop_temp
	
FSM1_state5:
	cjne a, #5, FSM1_state0_C
	Set_Cursor(1, 1)
	Send_Constant_String(#state5message)
    mov pwm_ratio+0, #low(0)
    mov pwm_ratio+1, #high(0)
    Load_Y(30)
	lcall x_lt_y
	jnb mf, FSM_state5to0


FSM_state5to0:
	mov FSM1_state, #0

FSM1_state5_done:
	ljmp loop_temp
	
FSM1_ERROR:
    Set_Cursor(1,1)
  	Send_Constant_String(#error)
  	Set_Cursor(2,1)
  	Send_Constant_String(#error2)
  	sjmp FSM1_ERROR

END
