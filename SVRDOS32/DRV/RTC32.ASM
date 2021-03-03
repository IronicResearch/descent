; Assember version of real-time clock interrupt enabler.

; Modeled after LCDBIMO.C prototype code.

	.386P
	.MODEL	FLAT

; macro for putting short IO delay inline to account for IO bus access.

IODELAY	MACRO

	jmp	$+2

	ENDM

_DATA	SEGMENT	DWORD PUBLIC USE32 'DATA'

	public	_intRateOffset

_savePIC2	db	0	; original PIC2
_saveRTCA	db	0	; original real-time clock reg A
_saveRTCB	db	0	; original real-time clock reg B
_intRateOffset	dd	0	; real-time clock interrupt rate offset

_DATA	ENDS

_CODE	SEGMENT DWORD PUBLIC USE32 'CODE'

	ASSUME	cs:_CODE
	ASSUME	ds:_DATA

	public	_InitLcdbiosTimer_
	public	_ExitLcdbiosTimer_

; Init LCDBIOS real-time clock and enable timeouts.

_InitLcdbiosTimer_	proc near

	cli
	mov	dx,0070h		; point to real-time clock ports
	mov	al,0Ah			; index +0A register
	out	dx,al
	IODELAY
	IODELAY
	inc	dx
	in	al,dx			; read original real-time clock rate
	mov	[_saveRTCA],al	        ; save for later restore
	dec	dx

	xor	ebx,ebx
        xor     ecx,ecx
	mov	bl,al
	mov	cl,al
	mov	eax,[_intRateOffset]
	or	eax,eax
	jz	irtc2			; change from default clock rate ?

	and	bl,0Fh			; clock rate in lower nibble
	sub	bl,al			; offset clock rate
	and	bl,0Fh
	mov	al,0Ah			; index clock format register
	out	dx,al
	IODELAY
	IODELAY
	inc	dx
	mov	al,bl
	and	cl,0F0h
	or	al,cl
	out	dx,al 			; write new clock rate
	dec	dx

irtc2:
	mov	al,0Bh			; index interrupt enable register
	out	dx,al
	IODELAY
	IODELAY
	inc	dx
	in	al,dx			; read old clock interrupt on/off
	mov	[_saveRTCB],al		; save for later restore
	dec	dx

	mov	bl,al
	mov	al,0Bh
	out	dx,al
	IODELAY
	inc	dx
	mov	al,bl
IF 0    ;; doesnt work on every system...
        and     al,0Fh                  ; disable any previous RTC interrupts
        out     dx,al
        IODELAY
ENDIF
	or	al,40h			; enable periodic interrupt
	out	dx,al
	dec	dx
	IODELAY
	mov	al,0Ch			; index interrupt status register
	out	dx,al
	IODELAY
	IODELAY
	inc	dx
	in	al,dx			; dummy read to clear pending interrupt
	dec	dx

	mov	dx,00A1h		; point to PIC #2 port
	in	al,dx			; read current PIC2 status
	mov	[_savePIC2],al
	IODELAY
	IODELAY
	and	al,0FEh
	out	dx,al			; enable IRQ8

	sti
	ret

_InitLcdbiosTimer_	endp

_ExitLcdbiosTimer_	proc near

	cli
	mov	dx,0070h		; point to RTC ports
	mov	al,0Ah
	out	dx,al
	IODELAY
	inc	dx
	mov	al,[_saveRTCA]		; get original RTC A port setting
	out	dx,al
	dec	dx
	IODELAY

	mov	al,0Bh
	out	dx,al
	IODELAY
	inc	dx
	mov	al,[_saveRTCB]		; get original RTC B port setting
	out	dx,al
	dec	dx
	IODELAY

	mov	dx,00A1h		; point to PIC #2 port
	mov	al,[_savePIC2]		; get original PIC2 port setting
	out	dx,al

	sti
	ret

_ExitLcdbiosTimer_	endp


_CODE	ENDS

	END
