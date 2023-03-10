; ISR_example.asm: a) Increments/decrements a BCD variable every half second using
; an ISR for timer 2; b) Generates a 2kHz square wave at pin P1.1 using
; an ISR for timer 0; and c) in the 'main' loop it displays the variable
; incremented/decremented using the ISR for timer 2 on the LCD.  Also resets it to 
; zero if the 'BOOT' pushbutton connected to P4.5 is pressed.
$NOLIST
$MODLP51RC2
$LIST


shift_PB   equ P0.5
TEMP_SOAK_PB equ P0.4
TIME_SOAK_PB equ P0.3
TEMP_REFL_PB equ P0.2
TIME_REFL_PB equ P0.1
RESET_PB equ P0.0

dseg at 0x30
temp_soak: ds 1
time_soak: ds 1
temp_refl: ds 1
time_refl: ds 1

    ljmp main

cseg
; These 'equ' must match the hardware wiring
LCD_RS equ P3.2

LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

;                     1234567890123456    <- This helps determine the location of the counter
Initial_Message:  db 'TS  tS  TR  tR', 0

Change_8bit_Variable MAC
jb %0, %2
Wait_Milli_Seconds(#50) ; de-bounce
jb %0, %2
jnb %0, $
jb SHIFT_PB, skip%Mb
;jb RESET_PB, reset%Mb
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

loop_a:
	Change_8bit_Variable(TEMP_SOAK_PB, temp_soak, loop_b)
;	Change_8bit_Variable(RESET_PB, temp_soak, loop_a)
	Set_Cursor(2, 1)
	mov a, temp_soak
	lcall SendToLCD
	lcall Save_Configuration
loop_b:
	Change_8bit_Variable(TIME_SOAK_PB, time_soak, loop_c)
;	Change_8bit_Variable(RESET_PB, time_soak, loop_b)
	Set_Cursor(2, 5)
	mov a, time_soak
	lcall SendToLCD
	lcall Save_Configuration	
loop_c:
	Change_8bit_Variable(TEMP_REFL_PB, temp_refl, loop_d)
;	Change_8bit_Variable(RESET_PB, temp_refl, loop_c)
	Set_Cursor(2, 9)
	mov a, temp_refl
	lcall SendToLCD
	lcall Save_Configuration	

loop_d:
	Change_8bit_Variable(TIME_REFL_PB, time_refl, loop_e)
;	Change_8bit_Variable(RESET_PB, time_refl, loop_d)
	Set_Cursor(2, 13)
	mov a, time_refl
	lcall SendToLCD
	lcall Save_Configuration	

loop_e:
	jnb RESET_PB, loop_1	
    ljmp loop
   
loop_1:
	lcall Load_Defaults
	Set_Cursor(2, 1)
	mov a, temp_soak
	lcall SendToLCD
	Set_Cursor(2, 5)
	lcall SendToLCD
	mov a, time_soak
	Set_Cursor(2, 9)
	mov a, temp_refl
	lcall SendToLCD
	Set_Cursor(2, 13)
	mov a, time_refl
	lcall SendToLCD
	lcall Save_Configuration
	ljmp loop
END
