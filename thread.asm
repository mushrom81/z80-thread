	DEVICE ZXSPECTRUM48

	org $F000
START equ $



main:
	call int_install

	call ROM_CLS


; Character streams
	ld de, $F800
	ld bc, put_c
	ld a, "A"
	call new_thread

	ld de, $F900
	ld bc, put_c
	ld a, "B"
	call new_thread

	ld de, $FA00
	ld bc, put_c
	ld a, "C"
	call new_thread


; Dueling threads
	ld de, $FB00
	ld bc, inc_mut
	call new_thread

	ld de, $FC00
	ld bc, dec_mut
	call new_thread


.wait_for_completed:
	call queue_empty
	jr z, .empty
	call yield
	jr .wait_for_completed
.empty:

	ld a, "H"
MUT_CHAR equ $ - 1
	rst $10


; Moving objects
	ld de, $F500
	ld bc, screen_draw
	push de
	exx
	ld hl, $4800
	push hl
	exx
	call new_thread
	exx
	ld b, 6
.spawn:
	pop hl
	inc h
	exx
	pop de
	ld a, e
	add $20
	ld e, a
	push de
	exx
	push hl
	exx
	call new_thread
	exx
	djnz .spawn

.wait_for_completed2:
	call queue_empty
	jr z, .empty2
	call yield
	jr .wait_for_completed2
.empty2:

	call int_uninstall
	ret







inc_mut:
	ld hl, MUT_CHAR
	ld bc, 1000
.loop:
	inc (hl)
	dec bc ; doesn't update the flags
	ld a, c
	or b
	jp nz, .loop
	ret


dec_mut:
	ld hl, MUT_CHAR
	ld bc, 1000
.loop:
	dec (hl)
	dec bc
	ld a, b
	or c
	jp nz, .loop
	ret


; Just spits out char a 50 times
put_c:
	ld c, a
	ld b, 50
.loop:
	ld a, c
	di
	rst $10
	ei

	ld d, 255
.waste
	dec d
	jr nz, .waste
	;call yield

	djnz .loop
	ret


screen_draw:
	exx
.loop:

	ld de, $4000
.wait
	dec de
	ld a, d
	or e
	jp nz, .wait

	ld (hl), $00
	ld a, l
	inc a
	and 00011111b
	ld l, a
	ld (hl), $FF
	jp .loop ; ?????







ROM_CLS equ $0DAF
ROM_PRINT equ $203C










; Decrement semaphore and sleep if >= 0
; Inputs: hl: address to 1-byte semaphore
; Outputs: none
; Clobbers: nothing
seme_p:
	dec (hl)
	bit 7, (hl)
	jr nz, .sleep
	ret
.sleep
	call yield
	bit 7, (hl)
	jr nz, .sleep
	ret


; Increment semaphore
; Inputs: hl: address to 1-byte semaphore
; Outputs: none
; Clobbers:
seme_v:
	inc (hl)
	ret




















; Loader for all of the interrupt stuff
; Inputs: none
; Outputs: none
; Clobbers: a, hl
int_install:
	di
; Set the interrupt to get its address from the table full of $FFFF
	ld a, $39
	ld i, a
	im 2
; $FFFF jumps back to $FFF4
	ld hl, $FFFF
	ld (hl), $18
; Now we just go to the subroutine
	ld l, $F4 ; hl = $FFF4
	ld (hl), $C3
	ld hl, interrupt
	ld ($FFF5), hl
	ei
	ret


; Uninstall the interrupt
; Inputs: none
; Outputs: none
; Clobbers: nothing
int_uninstall:
	im 1
	ret



; Create a new thread to be run
; Inputs: de: sp of the new thread
;         bc: pc of the new thread
; Outputs: none
; Clobbers: hl, de
new_thread:
	di
; Save current SP and swap out the new one
	ld hl, 0
	add hl, sp
	ex hl, de
	ld sp, hl
; Populate new stack with process information
	ld hl, next_thread
	push hl ; End-of-thread handler
	push bc ; PC

; Registers
	push af
	push bc
	push de
	push hl
	exx
	ex af, af'
	push af
	push bc
	push de
	push hl
	push ix
	push iy
	exx
	ex af, af'

; Restore old stack
	ld hl, 0
	add hl, sp
	call queue_push
	ex hl, de
	ld sp, hl
	ei
	ret



; Append to the FIFO queue at $FE00-FF
; Inputs: hl: value to append to the queue
; Outputs: none
; Clobbers: hl
queue_push:
	ld ($FE00), hl
QUEUE_TAIL equ $ - 2
	ld hl, QUEUE_TAIL
	inc (hl)
	inc (hl)
	ret


; Pop from the FIFO queue at $FE00-FF
; Inputs: none
; Outputs hl: holds the return value
; Clobbers: de
queue_pop:
	ld hl, ($FE00)
QUEUE_HEAD equ $ - 2
	ex hl, de
	ld hl, QUEUE_HEAD
	inc (hl)
	inc (hl)
	ex hl, de
	ret


; Check if the FIFO queue at $FE00-FF is empty
; Inputs: none
; Outputs: z: is the queue empty
; Clobbers, a, b
queue_empty:
	ld a, (QUEUE_HEAD)
	ld b, a
	ld a, (QUEUE_TAIL)
	sub b
	ret



; The actual subroutine that runs when the interrupt is called
; Inputs: none
; Outputs: none
; Clobbers: nothing, not even the flags!
yield: ; di ???
	di
interrupt:
; Push everything onto stack
	push af
	push bc
	push de
	push hl
	exx
	ex af, af'
	push af
	push bc
	push de
	push hl
	push ix
	push iy

; Save stack
	ld hl, 0
	add hl, sp
	call queue_push

next_thread: ; di ???
	di
; Get next thread to run from the stack
	call queue_pop
	ld sp, hl

; Pop all the registers back off again
	pop iy
	pop ix
	pop hl
	pop de
	pop bc
	pop af
	ex af, af'
	exx
	pop hl
	pop de
	pop bc
	pop af

	jp $0038 ; ret



; Deployment
LENGTH equ $ - START
	; Option 1: tape
	include TapLib.asm
	MakeTape ZXSPECTRUM48, "thread.tap", "thread", START, LENGTH, START
	; Option 2: snapshot
	SAVESNA "thread.sna", START
