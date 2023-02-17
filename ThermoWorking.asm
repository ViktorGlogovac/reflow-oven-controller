$MODLP51RC2
org 0000H
   ljmp MainProgram

$include(LCD_4bit.inc)
$include(math32.inc)

CLK  EQU 22118400
BAUD equ 115200
BRG_VAL equ (0x100-(CLK/(16*BAUD)))
CE_ADC    EQU  P0.3 
MY_MOSI   EQU  P0.2  
MY_MISO   EQU  P0.1 
MY_SCLK   EQU  P0.0
LCD_RS equ P3.2
LCD_E  equ P3.3
LCD_D4 equ P3.4
LCD_D5 equ P3.5
LCD_D6 equ P3.6
LCD_D7 equ P3.7 

DSEG at 30H
x:   ds 4
y:   ds 4
avg: ds 4
lmc: ds 4
bcd: ds 5
result: ds 4 
temp: ds 1
mode: ds 1

BSEG
mf: dbit 1

CSEG
temperature:  db 'Temperature', 0

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

Wait10us:
	mov R0, #74
	djnz R0, $
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
	load_Y(40920000)
	lcall mul32
	load_Y(1023)
	lcall div32
	load_Y(415)
	lcall div32 
	load_Y(303)
	lcall div32
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
	
; Send a character using the serial port
putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret
	
MainProgram:
	 mov SP, #7FH ; Set the stack pointer to the begining of idata
	 setb CE_ADC
	 lcall INIT_SPI
	 lcall InitSerialPort
	 mov P0M0, #0
	 mov P0M1, #0
	 lcall LCD_4BIT
	 Set_Cursor(1, 1)
	 Send_Constant_String(#temperature)

loop: 
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
	
	lcall hex2bcd 
	lcall Display_10_digit_BCD
		
	ljmp loop	
END