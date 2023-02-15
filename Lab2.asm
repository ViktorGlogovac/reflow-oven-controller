; ISR_example.asm: a) Increments/decrements a BCD variable every half second using
; an ISR for timer 2; b) Generates a 2kHz square wave at pin P1.1 using
; an ISR for timer 0; and c) in the 'main' loop it displays the variable
; incremented/decremented using the ISR for timer 2 on the LCD.  Also resets it to 
; zero if the 'BOOT' pushbutton connected to P4.5 is pressed.
$NOLIST
$MODLP51RC2
$LIST

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

SOUND_OUT     equ P1.1
TIME          equ P4.5
SEC		      equ P0.0
MIN			  equ P0.3
HOUR		  equ P0.6
ALARM		  equ P2.4

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

; In the 8051 we can define direct access variables starting at location 0x30 up to location 0x7F
dseg at 0x30
Count1ms:     ds 2 ; Used to determine when half second has passed
seconds:	  ds 1
minutes:	  ds 1
hours: 		  ds 1
alarm_min:    ds 1
alarm_hour:   ds 1

; In the 8051 we have variables that are 1-bit in size.  We can use the setb, clr, jb, and jnb
; instructions with these variables.  This is how you define a 1-bit variable:
bseg
half_seconds_flag: dbit 1 ; Set to one in the ISR every time 500 ms had passed
am_pm: dbit 1
am_pmalarm: dbit 1
alarmon: dbit 1
alarmswitch: dbit 1

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

;                 1234567890123456    <- This helps determine the location of the counter
TimeDisplay:  db 'TIME xx:xx:xx', 0
;                  1234567890123456
AlarmDisplay:  db 'ALARM xx:xx', 0

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
	cjne a, #low(1000), alarmon_flag_check ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(1000), alarmon_flag_check
	
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
	ljmp Timer2_ISR_da

Timer2_ISR_da:
	da a 
	mov seconds, a
	cjne a, #0x60, alarmon_flag_check 
	
	mov seconds, #0x00 
	clr a
	
 add_minutes:
	mov a, minutes  
	add a, #0x01
	da a
	mov minutes, a
	cjne a, #0x60, alarmon_flag_check 
	
	mov minutes, #0x00 
	clr a
	
	mov a, hours
	cjne a, #0x11, add_hours 
	cpl am_pm 
	ljmp add_hours 
	
add_hours: 	
	mov a, hours 
	add a, #0x01
	da a
	mov hours, a 
	cjne a, #0x13, alarmon_flag_check
	mov hours, #0x01 
	clr a
	ljmp alarmon_flag_check
	
alarmon_flag_check:
	jb alarmon, clock_ampm_check
	ljmp Timer2_ISR_Doff


am_pmalarm_flag_check : 
	jnb am_pmalarm,hours_check 
	ljmp Timer2_ISR_Doff

am_pm_flag_check :
	jnb am_pm, am_pmalarm_flag_check  
	ljmp Timer2_ISR_Doff	
	
alarmclock_ampm_check:
	jb am_pmalarm,hours_check
	ljmp am_pm_flag_check  
	
clock_ampm_check:
	jb am_pm,alarmclock_ampm_check 
	ljmp am_pm_flag_check 
	 
	 
hours_check:
	mov a, hours 
	cjne a, alarm_hour, Timer2_ISR_Doff 
	clr a
	ljmp minute_check   

minute_check:
	mov a, minutes 
	cjne a, alarm_min, Timer2_ISR_Doff
	clr a
	ljmp Timer2_ISR_Don

Timer2_ISR_Don:
	setb ET0
	pop psw
	pop acc
	reti
	
Timer2_ISR_Doff:
	clr ET0
	pop psw
	pop acc
	reti
;SOUND_OUT    equ P1.1
;TIME         equ P4.5
;SEC		  equ P0.0
;MIN	      equ P0.3
;HOUR		  equ P0.6
;ALARM		  equ P2.4

;seconds:	  ds 1
;minutes:	  ds 1
;hours: 		  ds 1
;alarm_min:    ds 1
;alarm_hour:   ds 1

;am_pm: dbit 1
;am_pmalarm: dbit 1
;alarmon: dbit 1

;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;    
main:
	mov SP, #0x7F
	
    lcall Timer0_Init
    lcall Timer2_Init
    
    mov P0M0, #0
    mov P0M1, #0
    
    setb EA
    setb am_pm
	setb am_pmalarm
	setb alarmon
	
    lcall LCD_4BIT
    
    Set_Cursor(1,1)
    Send_Constant_String(#TimeDisplay)
    Set_Cursor(2,1)
    Send_Constant_String(#AlarmDisplay)

    setb half_seconds_flag
    
    mov seconds, #0x00
    mov minutes, #0x00
    mov hours, #0x12
    mov alarm_min, #0x00
    mov alarm_hour, #0x00
    
clockloop:
	
AlarmOnOff:
	jb ALARM, clock_sec
	Wait_Milli_Seconds(#50) 
	jb ALARM,  clock_sec
	jnb ALARM, $
	
	cpl alarmon
	ljmp clockloop

clock_sec:
	jb SEC, clock_min
	Wait_Milli_Seconds(#50) 
	jb SEC, clock_min 
	jnb SEC, $
	jb alarmswitch, updateLCD1
	
	mov a, seconds
	add a, #0x01
	da a
	mov seconds, a
	cjne a, #0x60, updateLCD1
	mov seconds, #0x00 
	clr a
	ljmp updateLCD1
	
clock_min:
	jb MIN, clock_hour
	Wait_Milli_Seconds(#50) 
	jb MIN, clock_hour 
	jnb MIN, $
	jb alarmswitch, alarm_min_LCD 
	
	mov a, minutes
	add a, #0x01
	da a
	mov minutes, a
	cjne a, #0x60, updateLCD1
	mov minutes, #0x00 
	clr a
	ljmp updateLCD1
	
alarm_min_LCD:
	mov a, alarm_min
	add a, #0x01
	da a
	mov alarm_min, a
	cjne a, #0x60, updateLCDA1
	mov alarm_min, #0x00 
	clr a
	ljmp updateLCDA1
	
clock_hour:
    jb HOUR, OnOffSwitch1
	Wait_Milli_Seconds(#50) 
	jb HOUR, OnOffSwitch1 
	jnb HOUR, $
	jb alarmswitch, alarm_hour_LCD
	
	mov a, hours
	cjne a, #0x11, clock_hour_inc
	cpl am_pm
	ljmp clock_hour_inc 

clock_hour_inc:
	mov a, hours
	add a, #0x01
	da a
	mov hours, a
	cjne a, #0x13, updateLCD
	mov hours, #0x01 
	clr a
	ljmp updateLCD
	
updateLCD1:
	ljmp updateLCD
alarm_hour_button:
	jb HOUR, OnOffswitch1
	Wait_Milli_Seconds(#50) 
	jb HOUR, OnOffswitch1
	jnb HOUR, $
	jb alarmon, alarm_hour_LCD
	
	mov a, hours
	cjne a, #0x11, alarm_hour_LCD
	cpl am_pm
	ljmp alarm_hour_LCD
	
alarm_hour_LCD:	
	mov a, alarm_hour
	cjne a, #0x11, alarm_hour_inc
	cpl am_pmalarm
	ljmp alarm_hour_inc
	
alarm_hour_inc:
	mov a, alarm_hour
	add a, #0x01
	da a
	mov alarm_hour, a
	cjne a, #0x13, updateLCDA
	mov alarm_hour, #0x01 
	clr a
	ljmp updateLCDA
	
updateLCDA1:
	ljmp updateLCDA
	
OnOffSwitch1:
	ljmp OnOffSwitch
	
updateLCD:
	clr half_seconds_flag
	Set_Cursor(1, 12)     
	Display_BCD(seconds)
	Set_Cursor(1, 9)
	Display_BCD(minutes)
	Set_Cursor(1, 6)
	Display_BCD(hours)
	ljmp AlarmisOn
	
updateLCDA:
	clr half_seconds_flag
	Set_Cursor(2, 10)     
	Display_BCD(alarm_min)
	Set_Cursor(2, 7)
	Display_BCD(alarm_hour)
	ljmp AlarmisAM

OnOffswitch:
	jb TIME, updateLCD 
	Wait_Milli_Seconds(#50)
	jb TIME, updateLCD 
	jnb TIME, $
	
	cpl alarmswitch
	
	jb alarmswitch, AlarmisOn 
	
	ljmp AlarmisOff
	
AlarmisAm:
	jb am_pmalarm, AlarmisPM
	Set_Cursor(2,12)
	Display_Char(#'A')
	ljmp updateLCD
	
AlarmisPM:
	Set_Cursor(2,12)
	Display_Char(#'P')
	ljmp updateLCD

AlarmisOn:
	jnb alarmon, AlarmisOff
	Set_Cursor(2,14)
	Display_Char(#'O')
	Set_Cursor(2,15)
	Display_Char(#'N')
	Set_Cursor(2,16)
	Display_Char(#' ')
	ljmp clockisAM
	
AlarmisOff:
	Set_Cursor(2,14)
	Display_Char(#'O')
	Set_Cursor(2,15)
	Display_Char(#'F')
	Set_Cursor(2,16)
	Display_Char(#'F')
	ljmp clockisAM
	
clockisAM:
	jb am_pm, clockisPM
	Set_Cursor(1,15)
	Display_Char(#'A')
	Set_Cursor(1,16)
	Display_Char(#'M')
	ljmp clockloop
	
clockisPM:
	Set_Cursor(1,15)
	Display_Char(#'P')
	Set_Cursor(1,16)
	Display_Char(#'M')
	ljmp clockloop

END
