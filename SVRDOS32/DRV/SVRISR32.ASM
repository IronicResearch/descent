; SVRDOS32 SimulEyes VR driver for DPMI 32-bit extender (like DOS4G).
; Written by DaveM for StereoGraphics Inc.

; Stereo page-swapping display module for SVRDOS4G driver.
; (Equivalent to "svrisr.c" C prototype code.)
; Supports only 320x200 graphics mode-X for page-swapping.

; NOTE: All interrupt service routines and data must be memory locked.
; This is done in advance by driver loader program.

	.386P
	.MODEL	FLAT

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	INCLUDE	SVRDEF.INC
	INCLUDE SVRDOS32.INC
	INCLUDE	MODEX32.INC

IRQ0	EQU	08h             ;IRQ0 ISR vector for PC timer interrupt
IRQ2	EQU	0Ah             ;IRQ2 ISR vector for VGA vertical retrace interrupt

TIMEBASE	EQU	1193180	;1.19 Mhz timer base frequency
TIME70		EQU	17045	;timer interval for 70 Hz
TIME71		EQU	16805	;timer interval for 71 Hz
TIME72		EQU	16571	;timer interval for 72 Hz
TIME140		EQU	TIME70/2;timer interval for 140 Hz
TIME142		EQU	TIME71/2;timer interval for 142 Hz
TIME144		EQU	TIME72/2;timer interval for 144 Hz
TIMEX1		EQU	TIME70	;for 1x timer rate
TIMEX2		EQU	TIME140	;for 2x timer rate

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_DATA	SEGMENT	DWORD PUBLIC USE32 'DATA'

	ASSUME	ds:_DATA

; read/write data:

	PUBLIC	_svr_stereomode
	PUBLIC	_svr_visiblepage

_svr_stereomode		dd	0	;stereo page-flipping active flag
_svr_visiblepage	dw	0	;visible page number (0..3)

sync0		dd	0	;vertical sync flag
counter0	dd	0	;ISR0 event counter
chainer0	dd	0	;ISR0 chain counter
chainmod	dd	4	;ISR0 chain counter modulo value

vectored0	dd	0	;IRQ0 interrupt routine replaced
vectored2	dd	0	;IRQ2 interrupt routine replaced
emulated	dd	0	;timer interval externally emulated

pvector0	df	0	;IRQ0 interrupt vector (48-bit)
pvector2	df	0	;IRQ2 interrupt vector (48-bit)

timer0		dd	0FFFFh	;PC timer 0 old interval (for 18 Hz)
timer1		dd	TIMEX2	;PC timer 0 new interval (for 140 Hz)
timer2		dd	TIMEX1	;PC timer 2 interval (for 70 Hz)

_DATA	ENDS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; macro for putting short IO delay inline to account for IO bus access.

IODELAY	MACRO

	jmp	$+2
	jmp	$+2

	ENDM

; macro for generating debug monitoring code via COM port.

IODEBUG	MACRO	option

	IF	SVR_DEBUG

	IF	option

	mov	dx,02FCh	;COM modem control port
	mov	al,03h		;handshake ON
	out	dx,al

	ELSE

	mov	dx,02FCh	;COM modem control port
	mov	al,00h		;handshake OFF
	out	dx,al

	ENDIF

	ENDIF

	ENDM

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_CODE	SEGMENT DWORD PUBLIC USE32 'CODE'

	ASSUME	cs:_CODE
	ASSUME	ds:_DATA

; NOTE: use CS: overide with these data references for LEA instruction fixups
; Also need to offset fixed-up addresses by 0100h for .COM file format.

; read-only tables:

	IF	PAGES_PACKED			;contiguous page addresses

pageaddr	dw	0,16000,32000,48000	;video page addresses
pagetable	db	1,0,3,2			;page-flipping table

	ELSE					;page-aligned addresses

pageaddr	db	0,40h,80h,0C0h		;video page addresses
pagetable	db	1,0,3,2			;page-flipping table

	ENDIF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; InitISRLocals_
; Init local variables for SVR ISR module.

	PUBLIC	InitISRLocals_

InitISRLocals_	PROC near

	xor	eax,eax		;zero all flags off
	mov	[_svr_stereomode],eax
	mov	[_svr_visiblepage],ax
	mov	[vectored0],eax
	mov	[vectored2],eax
	mov	[emulated],eax
	mov	[chainmod],4	;init chain modulo counter
	ret

InitISRLocals_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	IF	1

; NOTE: Uses MS-DOS interrupt handler functions for high-level compatibility.
; DOS4G provides extensions to automatically manage real-mode vectors.

; Set new interrupt vector.
;  AX <-- interrupt number
;  CX <-- interrupt vector selector
; EDX <-- interrupt vector address

xSetVector:
	push	ds		;save local DS
	mov	ds,cx		;vector in DS:EDX
	mov	ah,25h		;MS-DOS set interrupt vector
	int	21h
	pop	ds
	ret

; Get existing interrupt vector.
;  AX <-- interrupt number
;  CX --> interrupt vector selector
; EDX --> interrupt vector address

xGetVector:
	push	es		;save the locals...
	mov	ah,35h		;MS-DOS get interrupt vector
	int	21h
	mov	edx,ebx		;vector in ES:EBX
	mov	cx,es
	pop	es
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	ELSE

; NOTE: Uses DPMI protected-mode interrupt handlers to avoid A20 switching.
; (Real-mode interrupt handlers may have to be manually re-vectored.)

; Set new interrupt vector.
;  AX <-- interrupt number
;  CX <-- interrupt vector selector
; EDX <-- interrupt vector address

xSetVector:
	mov	bx,ax		;interrupt number
	mov	ax,0205h	;DPMI set protected-mode vector
	int	31h
	ret

; Get existing interrupt vector.
;  AX <-- interrupt number
;  CX --> interrupt vector selector
; EDX --> interrupt vector address

xGetVector:
	mov	bx,ax		;interrupt number
	mov	ax,0204h	;DPMI get protected-mode vector
	int	31h
	ret

	ENDIF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; EnableAutoStereo

	PUBLIC	xEnableAutoStereo_

xEnableAutoStereo_	PROC NEAR

	mov 	ax,[_svr_technique]	;use which technique ?
	cmp	ax,SVR_EMU		;externally emulated timeouts ?
	je	xEMU_Enable_
	cmp	ax,SVR_TMR		;PC hardware timer timeouts ?
	je	xTMR_Enable_
	cmp	ax,SVR_VGA		;VGA vertical retrace interrupts ?
	je	xVGA_Enable_
	jmp	xTMR_Enable_
	ret

xEnableAutoStereo_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; DisableAutoStereo

	PUBLIC	xDisableAutoStereo_

xDisableAutoStereo_	PROC NEAR

	mov 	ax,[_svr_technique]	;for which technique ?
	cmp	ax,SVR_EMU
	je	xEMU_Disable_
	cmp	ax,SVR_EMU
	je	xTMR_Disable_
	cmp	ax,SVR_VGA
	je	xVGA_Disable_
	jmp	xTMR_Disable_
	ret

xDisableAutoStereo_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; VGA vertical retrace interrupt service routine:


; VGA_ISR

	PUBLIC	xVGA_ISR_

xVGA_ISR_	PROC	NEAR

	pushad
	push	ds
	push	es

	mov	dx,03C2h	;VGA status reg 0
	in	al,dx
	test    al,80h		;vertical retrace interrupt ?
	jz	visr0

;	mov	bx,_DATA	;could be in Bumfuck Illinois...
	mov	bx,cs		;get code selector
	mov	ds,bx		;use as read-only selector
	mov	ebx,[_svr_dsel]	;get data selector
	mov	ds,bx		;use as read/write selector

	IODEBUG	1

	IF	PAGES_PACKED

	mov	ax,[_svr_visiblepage]	;get current page #
	lea	ebx,cs:pagetable	;refer to page-swap table
	xlatb
	mov	[_svr_visiblepage],ax	;put updated page #
	shl	ax,1			;use page index byte --> address index word
	mov	dx,ax
	lea	ebx,cs:pageaddr		;refer to page-address table
	xlatb
	mov	cl,al                   ;get page-address low byte
	mov	ax,dx			;re-get word index
	inc	ax			;adjust for next byte
	xlatb
	mov	ch,al			;get page-address high byte

	mov	dx,03D4h		;CRT controller reg
	mov	al,0Ch			;start address high
	out	dx,al
	IODELAY
	inc	dx
	mov	al,ch
	out	dx,al
	IODELAY
	dec	dx
	mov	al,0Dh			;start address low
	out	dx,al
	IODELAY
	inc	dx
	mov	al,cl
	out	dx,al
	IODELAY

	ELSE

	mov	ax,[_svr_visiblepage]	;get current page #
	lea	ebx,cs:pagetable	;refer to page-swap table
	xlatb
	mov	[_svr_visiblepage],ax	;put updated page #
	lea	ebx,cs:pageaddr		;refer to page-address table
	xlatb
	mov	ch,al			;get page-address high byte

	mov	dx,03D4h		;CRT controller reg
	mov	al,0Ch			;start address high (only)
	out	dx,al
	IODELAY
	inc	dx
	mov	al,ch
	out	dx,al
	IODELAY

	ENDIF

	mov	dx,03D4h		;CRT controller reg
	mov	al,11h
        out     dx,al
        IODELAY
        IODELAY
        inc     dx
	in	al,dx                   ;get register state
	IODELAY
	and	al,0CFh                 ;mask off interrupt bits
	or	al,20h			;clear interrupt
	out	dx,al
	IODELAY
	or	al,10h			;re-enable interrupt
	out	dx,al
	IODELAY
        dec     dx

	mov	dx,0020h		;priority controller reg
	mov	al,20h			;End-of-Interrupt signal
	out	dx,al
	IODELAY

	IODEBUG	0

visr0:
	pushfd				;as if actual interrupt
	call	FWORD PTR[pvector2]	;call original ISR for IRQ2

visr9:
	pop	es
	pop	ds
	popad
	iretd

xVGA_ISR_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; VGA_Enable

	PUBLIC	xVGA_Enable_

xVGA_Enable_	PROC NEAR

	mov	eax,[vectored2]	;already replaced ISR vector ?
	or	eax,eax
	jnz	ve9

	cli
	call	xWaitVSync_
	mov	ax,IRQ2		;interrupt number
	call	xGetVector	;get DOS ISR vector for IRQ2
	mov	DWORD PTR[pvector2],edx	;old address
	mov	WORD PTR[pvector2+4],cx	;+ selector
	mov	ax,IRQ2
	lea	edx,cs:xVGA_ISR_	;new address
	mov	cx,cs		;+ selector
	call	xSetVector	;load in replacement ISR vector
	mov	dx,03D4h	;VGA CRT controller reg
	mov	al,11h		;protection reg
	out	dx,al
	IODELAY
	inc	dx
	in	al,dx
	IODELAY
	IODELAY
	and	al,0CFh		;write enable
	or	al,10h		;enable vertical sync interrupt
	out	dx,al
	IODELAY
	sti
	mov	[vectored2],1	;flag replacement ISR active

ve9:	mov	[_svr_stereomode],1	;flag auto-stereo active
	ret

xVGA_Enable_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; VGA_Disable

	PUBLIC	xVGA_Disable_

xVGA_Disable_	PROC NEAR

	mov	eax,[vectored2]	;already replaced ISR vector ?
	or	eax,eax
	jz	vd9

	cli
	mov	dx,03D4h	;VGA CRT controller reg
	mov	al,11h		;protection reg
	out	dx,al
	IODELAY
	inc	dx
	in	al,dx
	IODELAY
	and	al,0CFh		;write enable
	or	al,30h		;disable vertical sync interrupt
	out	dx,al
	IODELAY
	or	al,20h		;clear last vertical sync interrupt
	out	dx,al
	IODELAY
	or	al,0F0h		;re-enable write protection
	out	dx,al
	IODELAY
	mov	ax,IRQ2		;interrupt number
	mov	edx,DWORD PTR[pvector2]	;get vector address
	mov	cx,WORD PTR[pvector2+4]	;+ selector
	call	xSetVector	;restore original ISR vector
	sti
	mov	[vectored2],0	;flag replacement ISR inactive

vd9:	mov	[_svr_stereomode],0	;flag auto-stereo inactive
	ret

xVGA_Disable_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; PC hardware timer interrupt service routine:

; TMR_ISR
; NOTE: "cli" and "sti" instructions may take a long time to execute
; because of low-privelege-level emulation by CPU.

	PUBLIC	xTMR_ISR_

xTMR_ISR_	PROC	NEAR

	pushad
	push	ds
	push	es

	mov	dx,03DAh	;check vertical sync status immediately
	in	al,dx
	and	al,08h

	mov	bx,cs		;get code selector
	mov	ds,bx		;use as read-only selector
	mov	ebx,[_svr_dsel]	;get data selector
	mov	ds,bx		;use as read/write selector
	mov	es,bx

	movzx	eax,al		;buffer sync status for further use
	mov	[sync0],eax
	mov	ebx,eax

	inc	[counter0]	;update ISR counter

	mov	eax,[_svr_stereomode]	;flipping stereo pages ?
	or	eax,eax
	jz      tisr7

	IODEBUG	1		;output debug signal active

	or	ebx,ebx		;sync already detected ?
	jnz	tisr2

	mov	dx,03DAh	;VGA status reg 1
tisr1:	in	al,dx
	IODELAY
	and	al,08h		;vertical retrace ?
	jz      tisr1		;wait until sync...
tisr2:

IF RED_HACK
	mov	ax,[_svr_visiblepage]	;get current page #
	and     al,01h			;odd or even page # ?
	shl	al,1
	mov	ah,al
	mov	dx,0061h		;PC speaker port
	in	al,dx
	IODELAY
	IODELAY
	and	al,0FCh
	or	al,ah
	out	dx,al
	IODELAY
ENDIF

IF GREEN_HACK
	mov	ax,[_svr_visiblepage]	;get current page #
	and     al,01h			;odd or even page # ?
	or	al,04h
	mov	dx,022Ch		;BROOKTREE IO port
	out	dx,al
	IODELAY
	mov	dx,024Ch		;BROOKTREE IO port
	out	dx,al
	IODELAY
ENDIF

IF CYAN_HACK
	mov	ax,[_svr_visiblepage]	;get current page #
	and     al,01h			;odd or even page # ?
	mov	dx,02FCh		;modem control port
	out	dx,al
ENDIF

	IF	PAGES_PACKED

	mov	ax,[_svr_visiblepage]	;get current page #
	lea	ebx,cs:pagetable	;refer to page-swap table
	xlatb
	mov	[_svr_visiblepage],ax	;put updated page #
	shl	ax,1			;use page index byte --> address index word
	mov	dx,ax
	lea	ebx,cs:pageaddr		;refer to page-address table
	xlatb
	mov	cl,al                   ;get page-address low byte
	mov	ax,dx			;re-get word index
	inc	ax			;adjust for next byte
	xlatb
	mov	ch,al			;get page-address high byte

	mov	dx,03D4h		;CRT controller reg
	mov	al,0Ch			;start address high
	out	dx,al
	IODELAY
	inc	dx
	mov	al,ch
	out	dx,al
	IODELAY
	dec	dx
	mov	al,0Dh			;start address low
	out	dx,al
	IODELAY
	inc	dx
	mov	al,cl
	out	dx,al
	IODELAY

	ELSE

	mov	ax,[_svr_visiblepage]	;get current page #
	lea	ebx,cs:pagetable	;refer to page-swap table
	xlatb
	mov	[_svr_visiblepage],ax	;put updated page #
	lea	ebx,cs:pageaddr		;refer to page-address table
	xlatb
	mov	ch,al			;get page-address high byte

	mov	dx,03D4h		;CRT controller reg
	mov	al,0Ch			;start address high (only)
	out	dx,al
	IODELAY
	inc	dx
	mov	al,ch
	out	dx,al
	IODELAY

	ENDIF

tisr5:
	mov	eax,[sync0]	;sync detected on entry to ISR ?
	or	eax,eax
	jnz	tisr7

	mov	dx,0043h	;PC timer control reg
	mov	al,34h		;timer 0 rate divider
	out	dx,al
	IODELAY
	mov	dx,0040h	;PC timer 0
	mov	eax,[timer1]	;re-load timer divider
	out	dx,al
	IODELAY
	mov	al,ah
	out	dx,al
	IODELAY

	IODEBUG	0		;output debug signal inactive

tisr7:
	mov	dx,0020h	;priority controller reg
	mov	al,20h		;End-of-Interrupt signal
	out	dx,al
	IODELAY

	sti			;re-enable interrupts

	dec	[chainer0]	;update chain modulo counter
	jnz	tisrexit	;time to chain to previous ISR ?
	mov	eax,[chainmod]
	mov	[chainer0],eax	;re-load chain counter

	pushfd				;as if actual interrupt
	call	FWORD PTR[pvector0]	;call original ISR for IRQ0

tisrexit:
	pop	es
	pop	ds
	popad
	iretd

xTMR_ISR_	ENDP

; PC hardware timer interrupt service routine with run-time options:

; TMR_ISR_Option

	PUBLIC	xTMR_ISR_Option_

xTMR_ISR_Option_	PROC	NEAR

	pushad
	push	ds
	push	es

	mov	dx,03DAh	;check vertical sync status immediately
	in	al,dx
	and	al,08h

	mov	bx,cs		;get code selector
	mov	ds,bx		;use as read-only selector
	mov	ebx,[_svr_dsel]	;get data selector
	mov	ds,bx		;use as read/write selector
	mov	es,bx

	movzx	eax,al		;buffer sync status for further use
	mov	[sync0],eax

	inc	[counter0]	;update ISR counter

	mov	eax,[_svr_timer_chan2]	;option to use timer 2 timeout ?
	or	eax,eax
	jz	tisochk1
	mov	dx,0061h	;time-out signal from timer 2 ?
	in	al,dx
	and	al,20h
	jz	tiso5		;...if not, then skip this time around
	jmp	tisochk2	;...else check for auto page-flipping

tisochk1:
	mov 	eax,[_svr_double_rate]	;option for timeout at double rate ?
	or	eax,eax
	jz	tisochk2
	mov	eax,[counter0]	;ISR counter on odd value ?
	bt	eax,0
	jc	tiso5		;...then skip this time around

tisochk2:
	mov	eax,[_svr_stereomode]	;flipping stereo pages ?
	or	eax,eax
	jz      tiso5		;...if not, then nothing to do

	mov	eax,[_svr_debug_port]	;output debugging signal ?
	or	eax,eax
	jz	tiso0
	mov	edx,eax		;output debugging signal entry
	xor	eax,eax
	inc	eax
	out	dx,al

tiso0:
	mov	eax,[sync0]	;sync already detected on entry to ISR ?
	or	eax,eax
	jnz	tiso2

	mov	dx,03DAh	;VGA status reg 1
tiso1:	in	al,dx
	IODELAY
	and	al,08h		;vertical retrace ?
	jz      tiso1		;wait until sync...
tiso2:

	IF	PAGES_PACKED

	mov	ax,[_svr_visiblepage]	;get current page #
	lea	ebx,cs:pagetable	;refer to page-swap table
	xlatb
	mov	[_svr_visiblepage],ax	;put updated page #
	shl	ax,1			;use page index byte --> address index word
	mov	dx,ax
	lea	ebx,cs:pageaddr		;refer to page-address table
	xlatb
	mov	cl,al                   ;get page-address low byte
	mov	ax,dx			;re-get word index
	inc	ax			;adjust for next byte
	xlatb
	mov	ch,al			;get page-address high byte

	mov	dx,03D4h		;CRT controller reg
	mov	al,0Ch			;start address high
	out	dx,al
	IODELAY
	inc	dx
	mov	al,ch
	out	dx,al
	IODELAY
	dec	dx
	mov	al,0Dh			;start address low
	out	dx,al
	IODELAY
	inc	dx
	mov	al,cl
	out	dx,al
	IODELAY

	ELSE

	mov	ax,[_svr_visiblepage]	;get current page #
	lea	ebx,cs:pagetable	;refer to page-swap table
	xlatb
	mov	[_svr_visiblepage],ax	;put updated page #
	lea	ebx,cs:pageaddr		;refer to page-address table
	xlatb
	mov	ch,al			;get page-address high byte

	mov	dx,03D4h		;CRT controller reg
	mov	al,0Ch			;start address high (only)
	out	dx,al
	IODELAY
	inc	dx
	mov	al,ch
	out	dx,al
	IODELAY

	ENDIF

tiso3:
	mov	eax,[_svr_timer_reload]	;option to re-load timer ?
	or	eax,eax
	jz	tiso4
	mov	dx,0043h	;PC timer control reg
	mov	al,34h		;timer 0 rate divider
	out	dx,al
	IODELAY
	mov	dx,0040h	;PC timer 0
	mov	eax,[timer1]	;re-load timer divider
	out	dx,al
	IODELAY
	mov	al,ah
	out	dx,al
	IODELAY

	mov	eax,[_svr_timer_chan2]	;option to use timer 2 ?
	or	eax,eax
	jz	tiso4
	mov	dx,0043h	;PC timer control reg
	mov	al,0B0h		;timer 2 one-shot time-out
	out	dx,al
	IODELAY
	mov	dx,0042h	;PC timer 2
	mov	eax,[timer2]	;re-load timer 2 time-out
	out	dx,al
	IODELAY
	mov	al,ah
	out	dx,al
	IODELAY

tiso4:
	mov	eax,[_svr_debug_port]	;output debugging signal ?
	or	eax,eax
	jz	tiso5
	mov	edx,eax		;output debugging signal exit
	xor	eax,eax
	out	dx,al

tiso5:
	mov	eax,[_svr_PIC_reset]	;option to reset PIC ?
	or	eax,eax
	jz	tiso6
	mov	dx,0020h	;priority controller reg
	mov	al,20h		;End-of-Interrupt signal
	out	dx,al
	IODELAY
tiso6:
	mov	eax,[_svr_STI_reset]	;option to re-enable interrupts ?
	or	eax,eax
	jz	tiso7
	sti			;re-enable interrupts
tiso7:
	mov	eax,[_svr_HZ18_chain]	;option to chain to previous ISR ?
	or	eax,eax
	jz	tiso9		;if not, then chain immediately
tiso8:
	dec	[chainer0]	;update chain call counter
	jnz	tisoexit	;time to chain to previous ISR ?
	mov	eax,[chainmod]
	mov	[chainer0],eax	;re-load chain call counter
tiso9:
	pushfd				;as if actual interrupt
	call	FWORD PTR[pvector0]	;call original ISR for IRQ0

tisoexit:
	pop	es
	pop	ds
	popad
	iretd

xTMR_ISR_Option_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; TMR_Adjust

	PUBLIC	xTMR_Adjust_

xTMR_Adjust_	PROC NEAR

	movzx	eax,[_svr_timerate]	;what timer rate range ?
	cmp	eax,140		;rate < 140 ?
	mov	eax,4		;...then 4x countdown to chain calls
	jc	ta0
	mov	eax,8		;...else 8x countdown to chain calls
ta0:	mov	[chainmod],eax	;save chain call mod counter

	mov	eax,[_svr_HZ18_chain]	;option for chain call counter ?
	or	eax,eax
	jz	ta1
	mov	[chainmod],eax		;if so, then use countdown provided
ta1:
	mov	eax,TIMEX2	;set default timer interval
	mov	[timer2],eax	;save default timer interval
	mov	eax,TIMEX1	;set default timer interval
	mov	[timer0],eax	;save default timer interval

	movzx	ebx,[_svr_timerate]	;get timer rate
	or	ebx,ebx		;insure timer rate != 0 ?
	jz      ta2
	mov	eax,TIMEBASE	;compute timer interval
	xor	edx,edx
	idiv	ebx		;... = TIMEBASE clock HZ / timer rate HZ
ta2:
	mov	[timer0],eax	;save default timer interval
	mov	[timer1],eax	;save effective timer interval
	mov	ebx,[_svr_ticks_adjust]
	sub	eax,ebx		;shorten by timer ticks adjustment
	mov	[timer1],eax	;save effective timer interval
	ret

xTMR_Adjust_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; TMR_Init

	PUBLIC	xTMR_Init_

xTMR_Init_	PROC NEAR

	mov	eax,[vectored0]	;already replaced ISR vector ?
	or	eax,eax
	jnz	ti9

	call	xTMR_Adjust_	;compute timer interval

	call	xWaitVSync_     ;wait for next video sync
	cli

	mov	dx,0043h	;PC timer control reg
	mov	al,34h		;timer 0 rate divider
	out	dx,al
	IODELAY
	mov	dx,0040h	;PC timer 0
	mov	eax,[timer0]	;load new timer divider (un-adjusted)
	out	dx,al
	IODELAY
	mov	al,ah
	out	dx,al
	IODELAY

	mov	dx,0043h	;PC timer control reg
	mov	al,0B0h		;timer 2 one-shot time-out
	out	dx,al
	IODELAY
	mov	dx,0042h	;PC timer 2
	mov	eax,[timer2]	;load timer 2 time-out
	out	dx,al
	IODELAY
	mov	al,ah
	out	dx,al
	IODELAY
	mov	dx,0061h	;PC timer 2 gate enable
	in	al,dx
	IODELAY
	IODELAY
	and	al,0FCh		;disable speaker output
	or	al,01h		;enable timer 2 gate
	out	dx,al
	IODELAY

	mov	ax,IRQ0		;interrupt number
	call	xGetVector	;get DOS ISR vector for IRQ0
	mov	DWORD PTR[pvector0],edx	;old address
	mov	WORD PTR[pvector0+4],cx	;+ selector
	mov	ax,IRQ0
	lea	edx,cs:xTMR_ISR_	;new address
	mov	cx,cs		;+ selector
	mov	eax,[_svr_ISR_options]	;use ISR with run-time options ?
	or	eax,eax
	jz	ti8
	lea	edx,cs:xTMR_ISR_Option_
ti8:	mov	ax,IRQ0
	call	xSetVector	;load replacement ISR vector

	xor	eax,eax		;zero event counter
	mov	[counter0],eax
	mov	eax,[chainmod]	;init modulo chain counter
	mov	[chainer0],eax

	mov	[vectored0],1	;flag replacement ISR active
	sti
ti9:
	ret

xTMR_Init_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; TMR_Exit

	PUBLIC	xTMR_Exit_

xTMR_Exit_	PROC NEAR

	mov	eax,[vectored0]	;already replaced ISR vector ?
	or	eax,eax
	jz	tx9

	cli
	mov	dx,0043h	;PC timer control reg
	mov	al,34h		;timer 0 rate divider
	out	dx,al
	IODELAY
	mov	dx,0040h	;PC timer 0
	mov	ax,0FFFFh	;slowest time interval for 18 Hz
	out	dx,al
	IODELAY
	mov	al,ah
	out	dx,al
	IODELAY

	mov	ax,IRQ0		;interrupt number
	mov	edx,DWORD PTR[pvector0]	;get original address
	mov	cx,WORD PTR[pvector0+4]	;+ selector
	call	xSetVector	;restore original ISR vector

	mov	[vectored0],0	;flag replacement ISR inactive
	sti
tx9:
	ret

xTMR_Exit_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; TMR_Enable

	PUBLIC	xTMR_Enable_

xTMR_Enable_	PROC NEAR

	mov	eax,[vectored0]	;ISR vector installed ?
	or	eax,eax
	jnz	te2
te1:
	call	xTMR_Init_	;if not, install timer handler now...
te2:
	call	xTMR_Adjust_	;compute latest timer data

	call	xWaitVSync_	;re-load timer on sync
	cli
	mov	dx,0043h	;PC timer control reg
	mov	al,34h		;timer 0 rate divider
	out	dx,al
	IODELAY
	mov	dx,0040h	;PC timer 0
	mov	eax,[timer1]	;re-load new timer divider (adjusted)
	out	dx,al
	IODELAY
	mov	al,ah
	out	dx,al
	IODELAY
	mov	dx,0043h	;PC timer control reg
	mov	al,0B0h		;timer 2 one-shot time-out
	out	dx,al
	IODELAY
	mov	dx,0042h	;PC timer 2
	mov	eax,[timer2]	;re-load timer 2 time-out
	out	dx,al
	IODELAY
	mov	al,ah
	out	dx,al
	IODELAY

IF RED_HACK
	mov	dx,0061h	;PC timer 2 gate enable
	in	al,dx
	IODELAY
	IODELAY
	and	al,0FCh		;disable speaker output
	or	al,01h		;enable timer 2 gate
	out	dx,al
	IODELAY
ENDIF

IF GREEN_HACK
	mov	dx,022Ch	;BROOKTREE IO port
	mov	al,02h
	out	dx,al
	IODELAY
	mov	dx,024Ch	;BROOKTREE IO port
	mov	al,02h
	out	dx,al
	IODELAY
ENDIF

	xor	eax,eax		;re-zero event counter
	mov	[counter0],eax
	mov	eax,[chainmod]	;re-init modulo chain counter
	mov	[chainer0],eax

te9:	mov	[_svr_stereomode],1	;flag auto-stereo active
	sti
	ret

xTMR_Enable_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; TMR_Disable

	PUBLIC	xTMR_Disable_

xTMR_Disable_	PROC NEAR

	cli
	mov	dx,0043h	;PC timer control reg
	mov	al,34h		;timer 0 rate divider
	out	dx,al
	IODELAY
	mov	dx,0040h	;PC timer 0
	mov	eax,[timer0]	;re-load timer divider (un-adjusted)
	out	dx,al
	IODELAY
	mov	al,ah
	out	dx,al
	IODELAY

td9:	mov	[_svr_stereomode],0	;flag auto-stereo inactive
	sti
	ret

xTMR_Disable_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Externally emulated timeout callback routine:

; EMU_ISR

	PUBLIC	xEMU_ISR_

xEMU_ISR_	PROC	NEAR
 IF 1
	push	eax
	push	edx

	mov	dx,0061h	;timer 2 status reg
	in	al,dx
	and	al,20h		;timer 2 timeout ?
	pop	edx
	pop	eax
	jnz	ei0
	ret
ei0:
	pushad
	IODEBUG	1

	mov	dx,03DAh	;VGA input status reg
ei1:	in	al,dx
	and	al,08h		;vertical retrace sync ?
	IODELAY
	jz	ei1

	IF	PAGES_PACKED

	mov	ax,[_svr_visiblepage]	;get current page #
	lea	ebx,cs:pagetable	;refer to page-swap table
	xlatb
	mov	[_svr_visiblepage],ax	;put updated page #
	shl	ax,1			;use page index byte --> address index word
	mov	dx,ax
	lea	ebx,cs:pageaddr		;refer to page-address table
	xlatb
	mov	cl,al                   ;get page-address low byte
	mov	ax,dx			;re-get word index
	inc	ax			;adjust for next byte
	xlatb
	mov	ch,al			;get page-address high byte

	mov	dx,03D4h		;CRT controller reg
	mov	al,0Dh			;start address low
	out	dx,al
	IODELAY
	inc	dx
	mov	al,cl
	out	dx,al
	IODELAY
	dec	dx
	mov	al,0Ch			;start address high
	out	dx,al
	IODELAY
	inc	dx
	mov	al,ch
	out	dx,al
	IODELAY

	ELSE

	mov	ax,[_svr_visiblepage]	;get current page #
	lea	ebx,cs:pagetable	;refer to page-swap table
	xlatb
	mov	[_svr_visiblepage],ax	;put updated page #
	lea	ebx,cs:pageaddr		;refer to page-address table
	xlatb
	mov	ch,al			;get page-address high byte

	mov	dx,03D4h		;CRT controller reg
	mov	al,0Ch			;start address high (only)
	out	dx,al
	IODELAY
	inc	dx
	mov	al,ch
	out	dx,al
	IODELAY

	ENDIF

	mov	dx,0043h	;PC timer control reg
	mov	al,34h		;timer 2 one-shot
	out	dx,al
	IODELAY
	mov	dx,0040h	;re-load PC timer 0
	mov	eax,[timer1]
	out	dx,al
	IODELAY
	mov	al,ah
	out	dx,al
	IODELAY
	mov	dx,0043h	;PC timer control reg
	mov	al,0B0h		;timer 2 one-shot
	out	dx,al
	IODELAY
	mov	dx,0042h	;re-load PC timer 2
	mov	eax,[timer2]
	out	dx,al
	IODELAY
	mov	al,ah
	out	dx,al
	IODELAY

	IODEBUG	0

	popad
	ret

 ENDIF
xEMU_ISR_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; EMU_Enable

	PUBLIC	xEMU_Enable_

xEMU_Enable_	PROC NEAR

	mov     eax,[emulated]	;emulation already active ?
	or	eax,eax
	jnz	ee9

;	mov	eax,OFFSET xEMU_ISR_	;point to emulation ISR
	lea	eax,cs:xEMU_ISR_	;point to emulation ISR
	mov	DWORD PTR[_svr_pcallin],eax	;address
	mov	WORD PTR[_svr_pcallin+4],cs	;+ selector
	mov	eax,TIMEX2 	;main timer 0 interval
	mov	[timer1],eax
	mov	eax,TIMEX1	;aux timer 2 interval
	mov	[timer2],eax

	call	xWaitVSync_
	mov	dx,0043h	;PC timer control reg
	mov	al,34h		;timer 0 rate divider
	out	dx,al
	IODELAY
	mov	dx,0040h	;PC timer 0
	mov	eax,[timer1]
	out	dx,al
	IODELAY
	mov	al,ah
	out	dx,al
	IODELAY
	mov	dx,0043h	;PC timer control reg
	mov	al,0B0h		;timer 2 one-shot
	out	dx,al
	IODELAY
	mov	dx,0042h	;PC timer 2
	mov	eax,[timer2]
	out	dx,al
	IODELAY
	mov	al,ah
	out	dx,al
	IODELAY
	mov	dx,0061h	;PC timer 2 gate reg
	in	al,dx
	IODELAY
	or	al,01h		;enable timer 2
	out	dx,al
	IODELAY

	mov	[emulated],1	;flag emulation ISR active

ee9:	mov	[_svr_stereomode],1	;flag auto-stereo active
	ret

xEMU_Enable_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; EMU_Disable

	PUBLIC	xEMU_Disable_

xEMU_Disable_	PROC NEAR

	mov	eax,[emulated]	;emulation already relieved ?
	or	eax,eax
	jz	ed9

	mov	dx,0061h	;timer 2 gate reg
	in	al,dx
	IODELAY
	and	al,0FCh		;disable timer 2
	out	dx,al
	IODELAY

	mov	[emulated],0	;flag emulation handle inactive

ed9:	mov	[_svr_stereomode],0	;flag auto-stereo inactive
	ret

xEMU_Disable_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_CODE	ENDS

	END


