; ISR_example.asm: a) Increments/decrements a BCD variable every half second using
; an ISR for timer 2; b) Generates a 2kHz square wave at pin P1.1 using
; an ISR for timer 0; and c) in the 'main' loop it displays the variable
; incremented/decremented using the ISR for timer 2 on the LCD.  Also resets it to 
; zero if the 'BOOT' pushbutton connected to P4.5 is pressed.
$NOLIST
$MODLP51RC2
$LIST

shift_PB   equ P2.4
TEMP_SOAK_PB equ P4.5
TIME_SOAK_PB equ P0.6
TEMP_REFL_PB equ P0.3
TIME_REFL_PB equ P0.0

CE_ADC    EQU  P2.0 
MY_MOSI   EQU  P2.1  
MY_MISO   EQU  P2.2 
MY_SCLK   EQU  P2.3 

dseg at 0x30
dseg at 0x30

Result:     ds 2
x:			ds 4
y:			ds 4
BCD:		ds 5

state: ds 1
temp_soak: ds 1
Time_soak: ds 1
Temp_refl: ds 1
Time_refl: ds 1
temp_Cooling: ds 1
Oven_Power: ds 1
seconds: ds 1
minutes: ds 1
count_ms: ds 2
Count1ms:	ds 2 ; Used to determine when half second has passed
BCD_counter:	ds 1 ; The BCD counter incrememted in the ISR and displayed in the main loop
hours: 		ds 1
alarm_min:	ds 1
alarm_hour:	ds 1

freq: ds 1
speaker_time: ds 1

    ljmp main

cseg
; These 'equ' must match the hardware wiring
LCD_RS equ P3.2

LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7
;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 ; 11110000 Clear the bits for timer 0
	orl a, #0x01 ; 00000001 Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Set autoreload value
	mov RH0, #high(TIMER0_RELOAD)
	mov RL0, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
    setb ET0  ; Enable timer 0 interrupt
    setb TR0  ; Start timer 0
	ret

;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P1.1 ;
;---------------------------------;
Timer0_ISR:
	;clr TF0  ; According to the data sheet this is done for us already.
	cpl SOUND_OUT ; Connect speaker to P1.1!
	reti

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
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

Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in ISR

	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit one mili second counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	; Do the PWM thing
	; Check if Count1ms > pwm_ratio (this is a 16-bit compare)
	clr c
	mov a, pwm_ratio+0
	subb a, Count1ms+0
	mov a, pwm_ratio+1
	subb a, Count1ms+1
	; if Count1ms > pwm_ratio  the carry is set.  Just copy the carry to the pwm output pin:
	mov PWM_OUTPUT, c

	; Check if a second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Timer2_ISR_done
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done
	
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	
	; Increment binary variable 'seconds'
	inc seconds
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti

DO_SPI_G:
mov R1, #0 ; Received byte stored in R1
mov R2, #8            ; Loop counter (8-bits)
DO_SPI_G_LOOP:
mov a, R0             ; Byte to write is in R0
rlc a                 ; Carry flag has bit to write
mov R0, a
mov MY_MOSI, c
setb MY_SCLK          ; Transmit
mov c, MY_MISO        ; Read received bit
mov a, R1             ; Save received bit in R1
rlc a
mov R1, a
clr MY_SCLK
djnz R2, DO_SPI_G_LOOP
ret
;                     1234567890123456    <- This helps determine the location of the counter
Initial_Message:  db 'TS  tS  TR  tR', 0

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

getbyte mac
clr a
movc a, @a+dptr
mov %0, a
inc dptr
Endmac

loadbyte mac
mov a, %0
movx @dptr, a
inc dptr
endmac

SendToLCD:
mov b, #100
div ab
orl a, #0x30 ; Convert hundreds to ASCII
lcall ?WriteData ; Send to LCD
mov a, b    ; Remainder is in register b
mov b, #10
div ab
orl a, #0x30 ; Convert tens to ASCII
lcall ?WriteData; Send to LCD
mov a, b
orl a, #0x30 ; Convert units to ASCII
lcall ?WriteData; Send to LCD
ret

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

Load_Configuration:
mov dptr, #0x7f84 ; First key value location.
getbyte(R0) ; 0x7f84 should contain 0x55
cjne R0, #0x55, Load_Defaults
getbyte(R0) ; 0x7f85 should contain 0xAA
cjne R0, #0xAA, Load_Defaults
; Keys are good.  Get stored values.
mov dptr, #0x7f80
getbyte(temp_soak) ; 0x7f80
getbyte(time_soak) ; 0x7f81
getbyte(temp_refl) ; 0x7f82
getbyte(time_refl) ; 0x7f83
ret

Load_Defaults:
mov temp_soak, #150
mov time_soak, #45
mov temp_refl, #225
mov time_refl, #30
ret

;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;
main:
	; Initialization
    mov SP, #0x7F
    mov P0M0, #0
    mov P0M1, #0
    lcall LCD_4BIT
    ; For convenience a few handy macros are included in 'LCD_4bit.inc':
    lcall Load_Configuration
	Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message)
    Set_Cursor(2, 1)
    mov a, temp_soak
	lcall SendToLCD
	Set_Cursor(2, 5)
    mov a, time_soak
	lcall SendToLCD
	Set_Cursor(2, 9)
    mov a, temp_refl
	lcall SendToLCD
	Set_Cursor(2, 13)
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
	Change_8bit_Variable(TIME_REFL_PB, time_refl, loop_d)
	Set_Cursor(2, 13)
	mov a, time_refl
	lcall SendToLCD
	lcall Save_Configuration	



loop_d:



    ljmp loop

Forever:
clr CE_ADC
mov R0, #00000001B
lcall DO_SPI_G

mov R0, a
lcall DO_SPI_G
mov a, R1
anl a, #00000011B
mov result+1, a

mov R0, #55H
lcall DO_SPI_G
mov result, R1
setb CE_ADC

lcall find_temp

Wait_Milli_Seconds(#100)
Wait_Milli_Seconds(#100)
Wait_Milli_Seconds(#100)
Wait_Milli_Seconds(#100)

ljmp Forever

ENDs
