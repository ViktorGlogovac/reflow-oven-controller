$MODLP51RC2
org 0000H
   ljmp MainProgram

CLK  EQU 22118400
BAUD equ 115200
BRG_VAL equ (0x100-(CLK/(16*BAUD)))
$include(math32.inc)
$include(LCD_4bit.inc)


;added stuff
CE_ADC EQU P2.0 ;enable for adc
MY_MOSI EQU P2.1 ;connected to Din(SPI port serial data input pin, used to load	channel configuration data)
MY_MISO EQU P2.2 ;connected to Dout (The SPI serial data output pin is used to shift out the results of the A/D conversion. Data will always change	on the falling edge of each clock as the conversion takes place)
MY_SCLK EQU P2.3
LCD_RS equ P3.2
; LCD_RW equ Px.x ; Always grounded
LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7

dseg at 0x30
Result:     ds 2
x:			ds 4
y:			ds 4
BCD:		ds 5

BSEG
mf:			dbit 1

CSEG

Initial_Message:  db 'Temperature:', 0

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
; Configure the serial port and baud rate
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
    ret

INIT_SPI:
	setb MY_MISO ; Make MISO an input pin
	clr MY_SCLK ; For mode (0,0) SCLK is zero
	ret
 
 
; Send a character using the serial port
changechar:
    jnb TI, changechar
    clr TI
    mov SBUF, a
    ret

; Send a constant-zero-terminated string using the serial port
SendString:
    clr A
    movc A, @A+DPTR
    jz SendStringDone
    lcall changechar
    inc DPTR
    sjmp SendString
SendStringDone:
    ret
 
;Hello_World:
    ;DB  'Hello, World!', '\r', '\n', 0

WaitHalfSec:
    mov R6, #89
L9: mov R5, #250
L8: mov R4, #166
L7: djnz R4, L7 ; 3 cycles->3*45.21123ns*166=22.51519us
    djnz R5, L8 ; 22.51519us*250=5.629ms
    djnz R6, L9 ; 5.629ms*89=0.5s (approximately)
    ret

DO_SPI_G:
	push acc
	mov R1, #0 ; Received byte stored in R1
	mov R2, #8 ; Loop counter (8-bits)
DO_SPI_G_LOOP:
	mov a, R0 ; Byte to write is in R0
	rlc a ; Carry flag has bit to write
	mov R0, a
	mov MY_MOSI, c
	setb MY_SCLK ; Transmit
	mov c, MY_MISO ; Read received bit
	mov a, R1 ; Save received bit in R1
	rlc a
	mov R1, a
	clr MY_SCLK
	djnz R2, DO_SPI_G_LOOP
	pop acc
	ret

Display_10_digit_BCD:
	Set_Cursor(2,7)
	Display_BCD(bcd+4)
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	Display_BCD(bcd+1)
	Display_BCD(bcd+0)
	
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

	;lcall wait_for_P4_5


MainProgram:
    mov SP, #7FH ; Set the stack pointer to the begining of idata
    
    setb CE_ADC
    lcall INIT_SPI
    ;my code
    lcall InitSerialPort
    mov P0M0, #0
    mov P0M1, #0
    lcall LCD_4BIT
	Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message)
    Set_Cursor(1, 16)
	Display_char(#0b00101010)

    ;mov DPTR, #Hello_World
    ;lcall SendString
loop:    
    clr CE_ADC
    mov R0, #0b00000001
    lcall DO_SPI_G
    
    mov R0, #0b10000000
    lcall DO_SPI_G
    mov a, R1
    anl a, #0b00000011
    mov Result+1, a
    
    mov R0, #55H
    lcall DO_SPI_G
    mov Result+0, R1
    setb CE_ADC

    
    lcall WaitHalfSec

	 
	mov x+0, Result+0
	mov x+1, Result+1
	mov x+2, #0
	mov x+3, #0
	load_Y(410)
	lcall mul32
	load_Y(1023)
	lcall div32
	load_Y(273)
	lcall sub32
	
	lcall hex2bcd
	lcall Display_10_digit_BCD
	
	
	mov a, BCD+1
	anl a, #0xf0
	swap a
	orl a, #'0'
	lcall changechar
	
	mov a, BCD+1
	anl a, #0x0f
	orl a, #'0'
	lcall changechar

	mov a, BCD+0
	anl a, #0xf0
	swap a
	orl a, #'0'
	lcall changechar
	
	mov a, BCD+0
	anl a, #0x0f
	orl a, #'0'
	lcall changechar
		
	mov a, #'\r'
	lcall changechar
	   
	mov a, #'\n'
	lcall changechar

    ljmp loop 
   
	 
END

