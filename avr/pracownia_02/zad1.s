.org 0x0000
	jmp start		; Reset handler
.org 0x0040
	jmp timer0_ovf_irq 	; Timer0 Overflow Handler

.include "include/atmega328p.s"
.include "include/macros.s"
; 7 segment controller mc74hc595
; SDI - portb 0 ; SHIFT CLK - portd 7 ; LATCH CLK - portd 4
.set timer_cycles_per_half_second, 31250

.section .data
screen_data: 		;2
	.space 2

screen_bit:			;1	;przy ujemnej oblicza nowy wyswietlacz zamiast przerywac
	.space 1

shift_clk:			;1	;zbocza
	.space 1

stopwatch_value:	;2
	.space 2

stopwatch_seconds:	;1
	.space 1

segments_digit:		;1
	.space 1

segments_data:		;2	;wartosc obu wyswietlaczy
	.space 2
;
.section .text
; Interrupt handlers
timer0_ovf_irq:		;Timer0 Overflow Interrupt handler
	call stopwatch_refresh
	call segments_refresh
	reti

; Reset Interrupt handler
start:
	load_register_16 SPH, SPL, _stack_top

	lds r16, DDRB
	sbr r16, 0x21
	sts DDRB, r16

	lds r16, DDRD
	sbr r16, 0x90
	sts DDRD, r16

	load_register_8 TCCR0B, 0x01
	load_register_8 TIMSK0, 0x01
	load_register_8 TCNT0, 0x00

	load_register_Z shift_clk		;zbocza
	ldi r16, 0xFF
	st Z, r16

	load_register_Z segments_digit
	ldi r16, 0x00
	st Z, r16

	load_register_Z segments_data	;wartosc obu wyswietlaczy
	ldi r16, 0x00
	st Z+, r16
	st Z+, r16

	load_register_Z screen_bit		;przy ujemnej oblicza nowy wyswietlacz zamiast przerywac
	ldi r16, -1
	st Z, r16

	; load_register_Z stopwatch_seconds
	; ldi r16, 0
	; st Z, r16

	call stopwatch_reset

	sei
sleep:
	sleep
	jmp sleep
;
;; Functions
; Toggle shift clock
; Clobbers: r16, r17, Z
segments_toggle_shift_clk:
	load_register_Z shift_clk
	ld r16, Z
	com r16
	st Z, r16
	lds r17, PORTD
	andi r17, 0x7F
	andi r16, 0x80
	or r17, r16
	sts PORTD, r17
	ret
;
; Put correct data on sdi pin
; Clobbers: r16, r17, r18, Z
segments_put_sdi:					;odswieza wyswietlacze stale w 33 cyklach
	; Rotate screen data, oldest bit in r18
	load_register_Z screen_data
	ld r16, Z+
	ld r17, Z+
	clr r18
	clc
	rol r16
	rol r17
	rol r18
	st -Z, r17
	st -Z, r16

	; Put correct data on sdi
	lds r16, PORTB
	sbrc r18, 0
	sbr r16, 0x01
	sbrs r18, 0
	cbr r16, 0x01
	sts PORTB, r16

	ret
;
; Put correct data on sdi pin
; Clobbers: r16, r17, r18, Z
segments_next_seg:
	load_register_X segments_data
	load_register_Y segments_digit
	load_register_Z patterns

	; Shift r16 to select correct digit
	ld r17, Y
	ldi r16, 0x00
	ldi r18, 4
	sub r18, r17
	sec							;set C flag
segments_next_seg_loop:
	rol r16
	dec r18
	brne segments_next_seg_loop

	; Calculate currect digit address
	ld r17, Y
	clc
	add r26, r17
	ldi r17, 0x00
	adc r27, r17				;add + C flag

	; Calculate currect digit pattern
	ld r17, X
	clc
	add r30, r17
	ldi r17, 0x00
	adc r31, r17

	lpm r17, Z
	call segments_update

	; Increment current digit
	ld r16, Y
	inc r16
	cpi r16, 4	; l wysw
	brne segments_next_seg_not_last_digit
	ldi r16, 0
segments_next_seg_not_last_digit:
	st Y, r16
	ret

; Refresh (send next bit) to the mc74hc device
; Clobbers: r16, r17, r18, Y, Z
segments_refresh:
	; Check screen_bit if -1, all bits has been sent
	; Load next digit
	load_register_Z screen_bit
	ld r16, Z
	tst r16
	brmi segments_refresh_next_segments_next_seg

	; Check screen_bit if 0, skip, but rise latch_clk
	dec r16
	st Z, r16
	brmi segments_refresh_one_latch_clk

	call segments_toggle_shift_clk

	; Update sdi only on falling edge
	tst r16
	brne segments_refresh_end

	call segments_put_sdi

	jmp segments_refresh_end
segments_refresh_next_segments_next_seg:
	call segments_next_seg
	jmp segments_refresh_zero_latch_clk
segments_refresh_one_latch_clk:
	lds r16, PORTD
	sbr r16, 0x10
	sts PORTD, r16
segments_refresh_zero_latch_clk:
	lds r16, PORTD
	cbr r16, 0x10
	sts PORTD, r16
segments_refresh_end:
	ret
;
; Update value on segment digit
; Parameters: r16 - segment selection, r17 - segments pattern
; Clobbers: r16, Z
segments_update:
	load_register_Z screen_data
	st Z+, r16
	st Z+, r17
	load_register_Z screen_bit
	ldi r16, 33
	st Z, r16

	ret

; Refresh stop watch, triggers every 1 second
; Clobbers: r16, Z
stopwatch_reset:
	load_register_Z stopwatch_value
	ldi r16, lo8(timer_cycles_per_half_second)
	st Z+, r16
	ldi r16, hi8(timer_cycles_per_half_second)
	st Z, r16

; Refresh stop watch, triggers every 1 second
; Clobbers: r26, r27, Z
stopwatch_refresh:
	load_register_Z stopwatch_value
	ld r26, Z+
	ld r27, Z+
	sbiw r26, 1
	st -Z, r27
	st -Z, r26
	brne stopwatch_refresh_exit
	call stopwatch_reset
	call stopwatch_next
stopwatch_refresh_exit:
	ret

; Refresh stop watch, triggers every 1 second
; Clobbers: r16, r17, Z
stopwatch_next:
	; Toggle led
	lds r16, PORTB
	ldi r17, 0x20
	eor r16, r17
	sts PORTB, r16

	; If led is zero, wait next 500ms
	sbrc r16, 5
	jmp stopwatch_next_end

	; Increment current seconds count (wrap at 4)
	load_register_Z stopwatch_seconds
	ld r16, Z
	inc r16
	cpi r16, 4
	brne stopwatch_next_less_than_four
	ldi r16, 0
stopwatch_next_less_than_four:
	st Z, r16
	load_register_Z segments_data ; Update display data
	st Z, 16
stopwatch_next_end:
	ret

patterns:
	.byte 0xC0, 0xF9, 0xA4, 0xB0
