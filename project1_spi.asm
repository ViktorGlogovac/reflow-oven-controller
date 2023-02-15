; mathtest.asm:  Examples using math32.asm routines
$NOLIST
$MODLP51RC2
$LIST

org 0000H
	ljmp MyProgram

; These register definitions needed by 'math32.inc'
DSEG at 30H
x:   ds 4
y:   ds 4
bcd: ds 5
th_temp: ds 4
am_temp: ds 4
result: ds 4

BSEG
mf: dbit 1
AMTH_flag: dbit 1

$NOLIST
$include(math32.inc)
$LIST

; These 'equ' must match the hardware wiring
; They are used by 'LCD_4bit.inc'
LCD_RS equ P3.2
; LCD_RW equ Px.x ; Always grounded
LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7
CE_ADC    EQU  P1.3 
MY_MOSI   EQU  P1.2  
MY_MISO   EQU  P1.1 
MY_SCLK   EQU  P1.0 

$NOLIST
$include(LCD_4bit.inc)
$LIST

CSEG

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
 
 
find_temp:
	;jnb AMTH_flag, Th
	Th:
	mov b, #1
	lcall convert_ADC
	lcall Thermo_temp
	;setb AMTH_flag
	;lcall find_temp
	AM: 
	mov b, #0
	lcall convert_ADC
	lcall Amb_temp
	;clr AMTH_flag
	LCD_cursor(2,7) ;NOT SURE
	lcall add_th_am
	ljmp find_temp

Th:
	mov b, #1
	lcall convert_ADC
	lcall Thermo_temp
	setb AMTH_flag
	lcall find_temp


Thermo_temp:
	mov x+0, result+0
	mov x+1, result+1
	mov x+2, #0
	mov x+3, #0
	; Multiply by 4091000
	load_Y(4091000)
	lcall mul32
	; Divide result by 1023
	load_Y(1023)
	lcall div32
	; divide 41 from result
	load_Y(41)
	lcall div32
	; divide by gain
	load_Y(383)
	lcall div32
	; The 4-bytes of x have the temperature in binary
	mov a, x+0
	da a
	mov x+0, a

	mov a, x+1
	da a
	mov x+1, a

	mov a, x+2
	da a
	mov x+2, a

	mov a, x+3
	da a
	mov x+3, a

	mov th_temp+0, x+0
	mov th_temp+1, x+1
	mov th_temp+2, x+2
	mov th_temp+3, x+3

	

	;lcall hex2bcd


Amb_temp:
	mov x+0, result+0
	mov x+1, result+1
	mov x+2, #0
	mov x+3, #0
	; Multiply by 410
	load_Y(410)
	lcall mul32
	; Divide result by 1023
	load_Y(1023)
	lcall div32
	; Subtract 273 from result
	load_Y(273)
	lcall sub32
	; The 4-bytes of x have the temperature in binary
	mov a, x+0
	da a
	mov x+0, a

	mov a, x+1
	da a
	mov x+1, a

	mov a, x+2
	da a
	mov x+2, a

	mov a, x+3
	da a
	mov x+3, a
	mov am_temp+0, x+0
	mov am_temp+1, x+1
	mov am_temp+2, x+2
	mov am_temp+3, x+3
	;lcall hex2bcd

add_th_am:
   mov x+3, am_temp+3
   mov x+2, am_temp+2
   mov x+1, am_temp+1
   mov x+0, am_temp+0
   ;-----------------
   mov y+3, th_temp+3
   mov y+2, th_temp+2
   mov y+1, th_temp+1
   mov y+0, th_temp+0 ;
   ;-----------------
   lcall add32
   ;load_y(5) ; offest can be reset
   ;lcall add32
   mov total_temp+3,  x+3
   mov total_temp+2,  x+2
   mov total_temp+1,  x+1
   mov total_temp+0,  x+0
   lcall hex2bcd
   ret

convert_ADC:
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
	ret

 
; Sends 10-digit BCD number in bcd to the LCD
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

; We can display a number any way we want.  In this case with
; four decimal places.
Display_formated_BCD:
	Set_Cursor(2, 7)
	Display_char(#' ')
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	Display_char(#'.')
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	ret

wait_for_P4_5:
	jb P4.5, $ ; loop while the button is not pressed
	Wait_Milli_Seconds(#50) ; debounce time
	jb P4.5, wait_for_P4_5 ; it was a bounce, try again
	jnb P4.5, $ ; loop while the button is pressed
	ret

Test_msg:  db 'Temperature :', 0

MyProgram:
	mov sp, #07FH ; Initialize the stack pointer
	; Configure P0 in bidirectional mode
    mov P0M0, #0
    mov P0M1, #0
    lcall LCD_4BIT
	Set_Cursor(1, 1)
    Send_Constant_String(#Test_msg)
	mov R1, #222
    mov R0, #166
    djnz R0, $   ; 3 cycles->3*45.21123ns*166=22.51519us
    djnz R1, $-4 ; 22.51519us*222=4.998ms
    ; Now we can safely proceed with the configuration
    clr	TR1
    anl	TMOD, #0x0f
    orl	TMOD, #0x20
    orl	PCON,#0x80
    mov	TH1,#T1LOAD
    mov	TL1,#T1LOAD
    setb TR1
    mov	SCON,#0x52
	lcall INIT_SPI
	ljmp find_temp
	
END
