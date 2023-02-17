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

MY_SCLK equ P0.0
MY_MISO equ P0.1
MY_MOSI equ P0.2
CE_ADC equ P0.3

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

Timer2_ISR_done:
	pop psw
	pop acc
	reti

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
endmac

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
	
get_temp:
	mov x+0, result+0
    mov x+1, result+1
    mov x+2, #0
    mov x+3, #0
    
    Load_Y(282)
    lcall mul32
    
    Load_Y(1000)
    lcall div32
    
    Load_Y(22)
    lcall add32
    
    lcall hex2bcd
    Send_BCD(bcd+1)
    Send_BCD(bcd)
    
    ret


read_temp mac
    lcall Read_ADC_Channel_0

    mov lmc, x+0

    lcall Read_ADC_Channel_1

    mov y+0, lmc+0
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0
    lcall add32 ; adds thermo and LMC355 together

endmac

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

	Wait_Milli_Seconds(#250)
    Wait_Milli_Seconds(#250)

    mov x+0, result+0 
    mov x+1, result+1
    mov x+2, #0
    mov x+3, #0

    load_Y(410)
    lcall mul32
    load_Y(1000)
    lcall div32
    load_Y(273) 
    lcall sub32 

    ret


Read_ADC_Channel_1:
    clr CE_ADC
    mov R0, #00000001B ; Start bit:1
    lcall DO_SPI_G
    mov R0, #10010000B ; Single ended, read channel 1
    lcall DO_SPI_G
    mov a, R1          ; R1 contains bits 8 and 9
    anl a, #00000011B  ; We need only the two least significant bits
    mov Result+1, a    ; Save result high.
    mov R0, #55H ; It doesn't matter what we transmit...
    lcall DO_SPI_G
    mov Result, R1     ; R1 contains bits 0 to 7.  Save result low.
    setb CE_ADC
    
    Wait_Milli_Seconds(#250)
    Wait_Milli_Seconds(#250)

    mov x+0, result+0 
    mov x+1, result+1
    mov x+2, #0
    mov x+3, #0

    load_Y(319)
    lcall mul32
    load_Y(1000)
    lcall div32
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
	read_temp
;	lcall get_temp
	mov a, #'\r'
	lcall putchar
	mov a, #'\n'
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
display_temp(x)
mov pwm_ratio+0, #low(1000)
mov pwm_ratio+1, #high(1000)
jb safetycheck_flag, Safety_Passed
sjmp check_safety

;FSM1_state0_done_b1:
;	ljmp FSM1_state0_done

check_safety:
mov a, x
cjne a, #50, check_time
ljmp set_flag

check_time:
mov a, seconds
cjne a, #60, Safety_Passed
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
	display_temp(x)
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