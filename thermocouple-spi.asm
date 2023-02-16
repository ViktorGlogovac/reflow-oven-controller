$NOLIST
$MODLP51RC2
$LIST

org 0000H
	ljmp MyProgram

;------- PINS --------------;
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

;--------------------------;

; -------variables---------;
DSEG at 30H
x:   ds 4
y:   ds 4
bcd: ds 5
th_temp: ds 4
am_temp: ds 4
result: ds 4
total_temp: ds 4

;---------------------------;

BSEG
mf: dbit 1

$NOLIST
$include(math32.inc)
$LIST

$NOLIST
$include(LCD_4bit.inc)
$LIST

CSEG

get_ADC:
    clr CE_ADC
	mov R0, #00000001B
	lcall DO_SPI_G
	
	mov R0, #10000000B
	lcall DO_SPI_G
	mov a, R1
	anl a, #00000011B
	mov result+1, a
	
	mov R0, #55H
	lcall DO_SPI_G
	mov result, R1
	setb CE_ADC
    Wait_Milli_Seconds(#50)
    ret

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

FindTemp:
    mov b, #1
    lcall get_ADC
    lcall solve_TH
    mov b, #0
    lcall get_ADC
    lcall solve_AM
    Set_Cursor(2,7)
    lcall add_th_am
    ljmp FindTemp


solve_TH:
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
	mov th_temp+0, x+0
	mov th_temp+1, x+1
	mov th_temp+2, x+2
	mov th_temp+3, x+3
    lcall hex2bcd
    ret

solve_AM:
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
	mov am_temp+0, x+0
	mov am_temp+1, x+1
	mov am_temp+2, x+2
	mov am_temp+3, x+3
    lcall hex2bcd
    ret

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


Test_msg:  db 'Temperature:', 0

MyProgram:
	mov sp, #07FH ; Initialize the stack pointer
	; Configure P0 in bidirectional mode
    mov P0M0, #0
    mov P0M1, #0
    lcall LCD_4BIT
	Set_Cursor(1, 1)
    Send_Constant_String(#Test_msg)

    ljmp FindTemp

END


