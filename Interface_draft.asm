

; standard library
$NOLIST
$MODLP52
$LIST
$include(macros.inc)
$include(math32.inc)
$include(LCD_4bit.inc)

CLK         equ     22118400
BAUD        equ     115200
T0_RELOAD   equ     (65536-(CLK/4096))
T1_RELOAD   equ     (0x100-CLK/(16*BAUD))
T2_RELOAD   equ     (65536-(CLK/1000))
TIME_RATE   equ     1000

; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR


shift_PB   equ P0.5
TEMP_SOAK_PB equ P0.4
TIME_SOAK_PB equ P0.3
TEMP_REFL_PB equ P0.2
TIME_REFL_PB equ P0.1
RESET_PB equ P0.0
START_PB equ P0.6
RETURN_PB equ P0.7

RESET_STATE     equ     0
RAMP_TO_SOAK	equ     1
PREHEAT_SOAK	equ     2
RAMP_TO_PEAK	equ     3
REFLOW			equ     4
COOLING			equ     5


DSEG ; Before the state machine!
state:      ds 1
temp_soak:  ds 1
Time_soak:  ds 1
Temp_refl:  ds 1
Time_refl:  ds 1
Count1ms:   ds 2 ; Used to determine when half second has passed
seconds:	ds 1
sec_counter: ds 1
mins:	ds 1
temp:       ds 1
pwm:        ds 1
result:     ds  2
bcd:        ds  5
x:          ds  4
y:          ds  4

bseg
half_seconds_flag: dbit 1 ; Set to one in the ISR every time 500 ms had passed
reset_timer_flag: dbit 1

Initial_Message:  db 'TS  tS  TR  tR', 0
time_soak_msg:    db 'SOAK TEMP:     <', 0
temp_soak_msg:    db 'SOAK TIME:     <', 0
time_reflow_msg:  db 'REFLOW TEMP:   <', 0
temp_reflow_msg:  db 'REFLOW TIME:   <', 0
current_temp:     db 'Temp:   <', 0
current_time:     db 'Time:   <', 0    



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

Timer2_Init:
	mov r0, #0x00 ;am/pm alarm
	mov r1, #0x00 ;min
	mov r2, #0x00 ;hour
	mov r3, #0x00 ;am/pm
	mov r4, #0x00 ;alarmsec
	mov r5, #0x00 ;alarmmin
	mov r6, #0x00 ;alarmhour
	mov r7, #0x00 ;pause
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
	mov a, sec_counter
	add a, #0x01

Inc_Done_PWM:
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

Timer2_ISR_da:
	da a ; Decimal adjust instruction.  Check datasheet for more details!
	cjne a, #0x05, sec ;check if 5 sec have passed
;	lcall Play_sound
	mov a, #0x00
sec:
	mov sec_counter, a

Timer2_ISR_seconds:
    jnb seconds_flag, Timer2_ISR_done
    mov a, seconds
    add a, #0x01
    da a 
    jb reset_timer_flag, Reset_seconds

Reset_seconds:
clr seconds

    
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti



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

main:

    mov SP, #0x7F
    mov P0M0, #0
    mov P0M1, #0
    mov sec_counter, #0x00
    mov seconds, #0x00
    mov state, #0
    lcall Timer2_Init
    setb EA
    setb half_seconds_flag
    ;initialize

    lcall LCD_4BIT


Update_LCD:
    ; update main screen values
    LCD_cursor(2, 12)
    LCD_printBCD(seconds)
    lcall SendVoltage
    Display_formated_BCD(Oven_temp, 1, 12)
    LCD_cursor(1, 16)
    LCD_printChar(#'C')
    ljmp 	main_button_start

FSM1:
    mov a, FSM1_state
    mov segBCD+1, mins
    mov segBCD+0, seconds

FSM1_ERROR:
    LCD_cursor(1,1)
  	LCD_print(#error)
  	LCD_cursor(2,1)
  	LCD_print(#error2)
    Wait_Milli_Seconds(#500)
    ljmp FSM1_state0

FSM1_Return_state0:


FSM1_state0:

    jb START_PB, START_PRESSED
    cjne a, #0, FSM1_state1
    mov pwm, #0
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
    ;jump to state 1
    jb START_PB, FSM1_state0_done
    jnb START_PB, $ ; Wait for key release
    mov FSM1_state, #1	
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

START_PRESSED:
mov FSM1_state, #1


FSM1_state0_done:
ljmp FSM2

FSM1_state1:
cjne a, #1, FSM1_state2
mov pwm, #100
mov a, #60d
subb a, seconds
jz FSM1_ERROR
mov a, temp_soak
clr c
subb a, temp
jnc FSM1_state1_done
mov FSM1_state, #2
setb reset_timer_flag
clr reset_timer_flag

FSM1_state1_done:
ljmp FSM2

FSM1_state2:
cjne a, #2, FSM1_state3
mov pwm, #20
mov a, time_soak
clr c
subb a, sec
jnc FSM1_state2_done
mov FSM1_state, #3
setb reset_timer_flag
clr reset_timer_flag

FSM1_state2_done:
ljmp FSM2

FSM1_state3:
cjne a, #3, FSM1_state4
mov pwm, #100
mov a, reflow_temp
clr c
subb a, oven_temp
jnc FSM1_state3_done
setb reset_timer_flag
clr reset_timer_flag
mov FSM1_state, #4

FSM1_state3_done:
ljmp FSM2

FSM1_state4: 
cjne a, #4, FSM1_state5
mov pwm, #20
mov a, Time_refl
clr c,
subb a , Time_soak
jnc FSM1_state4_done
mov FSM1_state, #5

FSM1_state4_done:
ljmp FSM2

FSM1_state5:
cjne a, #5,  
mov pwm, #0
mov a, #60
clr c
subb a, reflow temp
jnc FSM_state5_done
mov state, #0

FSM1_state5_done:
ljmp FSM2
