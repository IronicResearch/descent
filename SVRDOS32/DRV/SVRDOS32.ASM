; SVRDOS32 SimulEyes VR driver for DPMI 32-bit extender (like DOS/4G).
; Written by DaveM for StereoGraphics Inc.

; Outline for 32-bit loadable driver.
; Driver gets loaded from file into allocated and locked memory area.
; Code and Data Selectors are distinct from rest of environment.
; (That is, we're on our own once the DPMI host program has loaded us...)

; Basic theory of operation:
; (1) External loader program creates separate memory area for driver;
; (2) Loader program loads driver with pre-defined code and data offsets;
; (3) Jump table at head of code section accomodates driver function calls;
; (4) 1st call should be to 1st function to initialize local driver environment;
; (5) subsequent calls use local code and data selectors;

; For getting binary image of driver code:
; 	tasm svrdos32.asm /l /m2 /p /s
;	tlink svrdos32.obj /3 /m /s /t
; makes .COM format file with code starting immediately at head of file;

; To account for 0100h COM file offset of code and data addresses:
; (a) Pad SVRDOS32.DRV file with 256-byte header (YES);
; 	copy svrhdr32.com,svrdos32.com svrdos32.drv
; (b) Let file loader load at equivalent 0100h offset from selector base (NO);
; Otherwise all run-time addresses need to account for offset (done that, hated it);

; SVRDOS32.ASM modeled after SVRDOS4G.C prototype code.
; Version numbers correspond by functionality.

; v1.xx: IRQ0 timer functions with polled video sync.

; v2.0x: Adapt LCDBIOS code for IRQ8 timeouts with IRQ9 latched video sync.

; v2.1x: Extend SVR API with separate ShowImages() and ClearImages() functions.

; v2.2x: Use half-resolution line-alternate formats for mode-X 320x240, 320x400.

; v2.3x: Use VESA 2.0 protected-mode interface for 640x400, 640x480.

; v2.4x: Extend SVR API with separate SetFlip() and UpdateFlip() functions.

; v2.5x: Extend SVR API with SetCallback() function.

; v2.6x: Updated VESA 2.0 support, including VESA 320x200 alternative.

; v2.65: Option for not using IRQ9 sync for non-VGA chipsets.

; v2.7x: VESA 3.0 support for stereo-ready chipsets.


	.386P
	.MODEL	FLAT

	INCLUDE SVRDEF.INC	;for SVR common definitions
	INCLUDE	MODEX32.INC	;for MODEX32.ASM graphics functions
        INCLUDE VESA32.INC      ;for VESA32.ASM graphics functions
	INCLUDE SVRISR32.INC	;for SVRISR32.ASM interrupt routines
	INCLUDE LCD32.INC	;for LCD32.ASM interrupt routines
        INCLUDE LCDBIOS.INC     ;for LCD32.ASM data indexes
	INCLUDE BIMO32.INC	;for BIMO32.ASM installer functions
	INCLUDE OEM32.INC	;for OEM32.ASM extensions


SVR_VER	        EQU 271h        ;SVR driver version 2.71

USE_LCDBIOS	EQU 1           ;use LCDBIOS driver

USE_OEMCODE     EQU 1           ;use OEM custom driver extensions
USE_OEMONLY     EQU 0           ;use OEM stereo sync instead of white-line code

USE_BLUELINE    EQU 0           ;use blue-line registration code (prototype glasses)

BLUE_R	        EQU 0           ;RGB code for blue (or cyan or magenta)
BLUE_G	        EQU 0
BLUE_B	        EQU 63

USE_MIXBUF      EQU 0           ;use mixing buffer for mode-x transfers (obsolete)

USE_VESA        EQU 1           ;use VESA video modes
USE_VESA_320    EQU 1           ;use VESA 320-wide modes instead of mode-X

USE_NO_IRQ9     EQU 0           ;do not use IRQ9 status reg


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_CODE	SEGMENT DWORD PUBLIC USE32 'CODE'
	ASSUME	CS:_CODE, DS:_CODE

; read-only header has to be associated with code here for start of file

	ORG	OBIN+OHDR
MAIN:

header:	db	"****SVRDOS32****"
hname:	db	"SimulEyes VR Driver for 32-bit DOS Extender "
hver:	db	"Version 2.71 "
hcopy:	db	"Copyright 1995-97 StereoGraphics Corp. "
IF USE_LCDBIOS
        db      "Portions of LCDBIOS used under license from Don Sawdai, "
        db      "Copyright 1995. "
ENDIF
        db      "Dedicated to those who use this for the benefit of all..."

_CODE	ENDS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_DATA	SEGMENT DWORD PUBLIC USE32 'DATA'
        ASSUME DS:_DATA

; read-write data gets put into its own segment (somewhere):

	ORG	OBIN+ODAT

; code and data selectors must be filled in by driver loader;
; (Note that code selector is an alias for data selector.)

	PUBLIC	_app_csel
	PUBLIC	_app_dsel
	PUBLIC	_svr_csel
	PUBLIC	_svr_dsel

_app_csel	dd	?	;host application code selector
_app_dsel	dd	?	;host application data selector
_svr_csel	dd	?	;SVR driver code selector
_svr_dsel	dd	?	;SVR driver data selector
; SVR ISR global data parameters:

	PUBLIC	_svr_technique
	PUBLIC	_svr_timerate
	PUBLIC	_svr_pcallin
	PUBLIC	_svr_pcallout

_svr_technique	dd	?	;stereo interrupt routine technique
_svr_timerate	dd	?	;interrupt update timer rate
_svr_pcallin 	df	?	;interrupt update callback function pointer
_svr_pcallout 	df	?	;interrupt update callback function pointer

; SVR constant assignments:

SVR_OK		EQU	1	;SVR function call result OK
SVR_ERROR	EQU	0	;SVR function call result ERROR

SVR_MODE03	EQU	03h	;SVR text mode 03
SVR_MODE13	EQU	13h	;SVR graphics mode 13
SVR_MODEX	EQU	14h	;SVR graphics mode X
SVR_MODEX_200   EQU     14h     ;SVR graphics mode X 320x200 (default)
SVR_MODEX_400   EQU     15h     ;SVR graphics mode X 320x400
SVR_MODEX_240   EQU     16h     ;SVR graphics mode X 320x240
SVR_MODEX_480   EQU     17h     ;SVR graphics mode X 320x480
SVR_MODE100     EQU     100h    ;SVR graphics mode VESA 640x400
SVR_MODE101     EQU     101h    ;SVR graphics mode VESA 640x480

SVR_MODE_ORG	EQU	0FFFFh	;original video mode
SVR_MODE_PREV	EQU	0FFFEh	;previous video mode

SVR_LINE_ALT    EQU     8000h   ;line-alternate option
SVR_HALF_RES    EQU     4000h   ;half-resolution option

; SVR driver activity flags and variables:

        public  svr_active
        public  svr_halfed

svr_mode	dd	-1	;SVR video graphics mode
svr_enabled	dd	0	;SVR driver enabled for calls
svr_active	dd	0	;page-flipping mode active for stereo
svr_black	dd	0	;palette entry for black color
svr_white	dd	15	;palette entry for white color
svr_page	dd	0	;current page # for page-flipping mode
svr_readpage    dd      0       ;current page # to read
svr_softimer	dd	0	;timer emulation usage flag
svr_orgmode	dd	-1	;original video mode prior to SVR Init
svr_premode	dd	-1	;previous video mode prior to SVR Enable
svr_halfed      dd      0       ;half-resolution stereo format
svr_quarter     dd      20      ;quarter scan line (in DWORDs)
svr_3quarter    dd      60      ;3-quarter scan line (in DWORDs)
svr_4quarter    dd      80      ;total scan line width (in DWORDs)

; SVR ISR run-time options:

IF	SVR_VER	GE	0200h

SVR_NUM_OPTIONS	EQU	11	;number of DWORD options (for C struct)
SVR_PTR_OPTIONS EQU	_svr_calls_far	;pointer to 1st option (for C struct)

ELSE

SVR_NUM_OPTIONS	EQU	14	;number of DWORD options (for C struct)
SVR_PTR_OPTIONS EQU	_svr_ISR_options	;pointer to 1st option (for C struct)

ENDIF

	public	_svr_calls_far
	public	_svr_pixels_modex
	public	_svr_pixels_width
	public	_svr_debug_port
	public	_svr_pal_protect
	public	_svr_line_alternate
	public	_svr_high_refresh
	public	_svr_lock_flip
	public	_svr_delay_flip
	public	_svr_fast_intr
	public	_svr_OEM_support

; Note: the following order is equivalent to SVRDos32Options C struct v2.0
_svr_calls_far		dd 0;	// SVR function calls near or far ?
_svr_pixels_modex	dd 0;   // pixel data ordering linear or mode-X ?
_svr_pixels_width	dd 0;   // pixel data width gaps in pixel buffer ?
_svr_debug_port		dd 0;   // port for debugging ISR activity
_svr_pal_protect	dd 0;   // protect palette during video mode set ?
_svr_line_alternate	dd 0;	// pixel data linear or line-alternate ?
_svr_high_refresh	dd 0;   // standard video refresh rate or higher ?
_svr_lock_flip		dd 0;   // SVR ISR polls for vertical retrace ?
_svr_delay_flip		dd 0;   // SVR ISR flip delay after vertical retrace
_svr_fast_intr		dd 0;   // SVR ISR interrupt rate doubler
_svr_OEM_support	dd 0;   // support for special OEM chipset

	PUBLIC	_svr_ISR_options
	PUBLIC	_svr_sync_edge
	PUBLIC	_svr_PIC_reset
	PUBLIC	_svr_STI_reset
	PUBLIC	_svr_HZ18_chain
	PUBLIC	_svr_timer_reload
	PUBLIC	_svr_timer_oneshot
	PUBLIC	_svr_ticks_adjust
	PUBLIC	_svr_double_rate
	PUBLIC	_svr_timer_chan2
	PUBLIC	_svr_debug_port
	PUBLIC	_svr_pixels_modex
	PUBLIC	_svr_pixels_width
	PUBLIC	_svr_calls_far

; Note: the following order is equivalent to SVRDos32Options C struct v1.0
_svr_ISR_options	dd 0;	;SVR uses fast ISR or ISR with options ?
_svr_sync_edge		dd 0;	;sync on leading or trailing edge ?
_svr_PIC_reset		dd 0;	;SVR resets priority interrupt controller ?
_svr_STI_reset		dd 0;	;SVR re-enables interrupts ?
_svr_HZ18_chain		dd 0;	;SVR chains to DOS clock INT at 18 Hz ?
_svr_timer_reload 	dd 0;	;timer free-running or re-loaded on sync ?
_svr_timer_oneshot	dd 0;	;timer continuous or one-shot operation ?
_svr_ticks_adjust 	dd 0;	;timer ticks adjustment shortener
_svr_double_rate	dd 0;	;SVR running at double timeout rate ?
_svr_timer_chan2  	dd 0;	;use hardware timer 2 for double-check ?
IF SVR_VER LE 01FFh
_svr_debug_port		dd 0;	;use port for debugging ISR activity ?
_svr_pixels_modex 	dd 0;	;pixel data ordering linear or mode-X ?
_svr_pixels_width 	dd 0;	;pixel data width gaps in pixel buffer ?
_svr_calls_far		dd 0;	;SVR function calls near or far ?
ENDIF

; SVR local allocated buffer parameters:

IF      USE_MIXBUF

        public  _svr_pbuf

_svr_pbuf	df	?	;SVR mixing buffer pointer

pbuf_addrl	dw	0	;buffer linear address
pbuf_addrh	dw	0
pbuf_handl	dw	0	;buffer alloc handle
pbuf_handh	dw	0
pbuf_dsel	dw	0	;buffer data selector

ENDIF   ; USE_MIXBUF

_DATA	ENDS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_CODE	SEGMENT DWORD PUBLIC USE32 'CODE'
	ASSUME	CS:_CODE, DS:_DATA

; Upon entry into SVR driver, selectors default to:
;       CS <-- SVR driver code selector
;       DS <-- application data selector
;       ES <-- application data selector
; After immediate entry into each SVR driver function, selectors become:
;       CS <-- SVR driver code selector
;       DS <-- SVR driver data selector (local)
;       ES <-- application data selector (global)

; Jump table to driver functions.
; All jumps should be far 32-bit relative JMPs (5 bytes each).
; Accomodate jumps for 32 functions.

	ORG	OBIN+OJMP-OBIN

	PUBLIC	fn0_
	PUBLIC	fn1_
	PUBLIC	fn2_
	PUBLIC	fn3_
	PUBLIC	fn4_
	PUBLIC	fn5_
	PUBLIC	fn6_
	PUBLIC	fn7_
	PUBLIC	fn8_
	PUBLIC	fn9_
	PUBLIC	fn10_
	PUBLIC	fn11_
	PUBLIC	fn12_
	PUBLIC	fn13_
	PUBLIC	fn14_
	PUBLIC	fn15_
	PUBLIC	fn16_
	PUBLIC	fn17_
	PUBLIC	fn18_
	PUBLIC	fn19_
	PUBLIC	fn20_
	PUBLIC	fn21_
	PUBLIC	fn22_
	PUBLIC	fn23_
	PUBLIC	fn24_
	PUBLIC	fn25_
	PUBLIC	fn26_
	PUBLIC	fn27_
	PUBLIC	fn28_
	PUBLIC	fn29_
	PUBLIC	fn30_
	PUBLIC	fn31_

fn0_:	jmp     far ptr	fn0
fn1_:	jmp     far ptr	fn1
fn2_:	jmp     far ptr	fn2
fn3_:	jmp     far ptr	fn3
fn4_:	jmp     far ptr	fn4
fn5_:	jmp     far ptr	fn5
fn6_:	jmp     far ptr	fn6
fn7_:	jmp     far ptr	fn7
fn8_:	jmp     far ptr	fn8
fn9_:	jmp     far ptr	fn9
fn10_:	jmp     far ptr	fn10
fn11_:	jmp     far ptr	fn11
fn12_:	jmp     far ptr	fn12
fn13_:	jmp     far ptr	fn13
fn14_:	jmp     far ptr	fn14
fn15_:	jmp     far ptr	fn15
fn16_:	jmp     far ptr	fn16
fn17_:	jmp     far ptr	fn17
fn18_:	jmp     far ptr	fn18
fn19_:	jmp     far ptr	fn19
fn20_:	jmp     far ptr	fn20
fn21_:	jmp     far ptr	fn21
fn22_:	jmp     far ptr	fn22
fn23_:	jmp     far ptr	fn23
fn24_:	jmp     far ptr	fn24
fn25_:	jmp     far ptr	fn25
fn26_:	jmp     far ptr	fn26
fn27_:	jmp     far ptr	fn27
fn28_:	jmp     far ptr	fn28
fn29_:	jmp     far ptr	fn29
fn30_:	jmp     far ptr	fn30
fn31_:	jmp     far ptr	fn31

        mov     eax,SVR_ERROR           ;never supposed to get here
        retf

; Alternate jump table.
; SVR API entry points on 8-byte alignments.

        ORG	OBIN+OJMP2-OBIN

        NOWARN  ALN                     ;for explicit ALIGN 8

xfn0_:	jmp     fn0
        ALIGN   8
xfn1_:	jmp     fn1
        ALIGN   8
xfn2_:	jmp     fn2
        ALIGN   8
xfn3_:	jmp     fn3
        ALIGN   8
xfn4_:	jmp     fn4
        ALIGN   8
xfn5_:	jmp     fn5
        ALIGN   8
xfn6_:	jmp     fn6
        ALIGN   8
xfn7_:	jmp     fn7
        ALIGN   8
xfn8_:	jmp     fn8
        ALIGN   8
xfn9_:	jmp     fn9
        ALIGN   8
xfn10_:	jmp     fn10
        ALIGN   8
xfn11_:	jmp     fn11
        ALIGN   8
xfn12_:	jmp     fn12
        ALIGN   8
xfn13_:	jmp     fn13
        ALIGN   8
xfn14_:	jmp     fn14
        ALIGN   8
xfn15_:	jmp     fn15
        ALIGN   8
xfn16_:	jmp     fn16
        ALIGN   8
xfn17_:	jmp     fn17
        ALIGN   8
xfn18_:	jmp     fn18
        ALIGN   8
xfn19_:	jmp     fn19
        ALIGN   8
xfn20_:	jmp     fn20
        ALIGN   8
xfn21_:	jmp     fn21
        ALIGN   8
xfn22_:	jmp     fn22
        ALIGN   8
xfn23_:	jmp     fn23
        ALIGN   8
xfn24_:	jmp     fn24
        ALIGN   8
xfn25_:	jmp     fn25
        ALIGN   8
xfn26_:	jmp     fn26
        ALIGN   8
xfn27_:	jmp     fn27
        ALIGN   8
xfn28_:	jmp     fn28
        ALIGN   8
xfn29_:	jmp     fn29
        ALIGN   8
xfn30_:	jmp     fn30
        ALIGN   8
xfn31_:	jmp     fn31
        ALIGN   8

        WARN    ALN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Separate location for actual code.
; All subroutines must explicitly return far.
; Parameters are passed via registers, as designated.
; Return values are passed back in register EAX.
; Use of local data variables requires switching DS data selectors.

	ORG	OBIN+OCOD-OBIN

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Init SVRDOS32 local variables to default values.

InitSVRLocals:
	xor	eax,eax			;zero flags
	mov	[svr_enabled],eax
	mov	[svr_active],eax
	mov	[svr_softimer],eax
	mov	[svr_page],eax
        mov     [svr_readpage],eax
	mov	[svr_black],eax		;default black
	mov	[svr_white],15		;default white
	mov	ebx,SVR_MODE_ORG	;default original video mode
	mov	[svr_mode],ebx
	mov	[svr_orgmode],ebx
	mov	[svr_premode],ebx
	push	es
	mov	dx,ds
	mov	es,dx
	lea	edi,SVR_PTR_OPTIONS	;zero options
	mov	ecx,SVR_NUM_OPTIONS
	xor	eax,eax
        cld
	rep	stosd
	pop	es
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; FillPixels shell for calling either VGA mode-X or VESA FillPixels routine

FillPixels      proc near

        cmp     [_VESA_active],0        ;VESA mode active ?
        je      xFillPixel4_            ;if not, call mode-X Fill
        jmp     xFillVesaPixels_        ;else call VESA Fill

FillPixels      endp

; FillPixels macro for VGA or VESA code

FILL_PIXELS4    MACRO

IF USE_VESA
	call	FillPixels              ;VESA / VGA pixel fill
ELSE
	call	xFillPixel4_            ;VGA mode-X pixel fill
ENDIF

        ENDM

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; MovePixels shell for calling either VGA mode-X or VESA MovePixels routine

MovePixels      proc near

        cmp     [_VESA_active],0        ;VESA mode active ?
        je      xMovePixelClip_         ;if not, call mode-X Move
        jmp     xMoveVesaPixels_        ;else call VESA Move

MovePixels      endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; PlotPixels shell for calling either VGA mode-X or VESA PlotPixels routine

PlotPixel       proc near

        cmp     [_VESA_active],0        ;VESA mode active ?
        je      xPlotPixelPageX_        ;if not, call mode-X Plot
        jmp     xPlotVesaPixel_         ;else call VESA Plot

PlotPixel       endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #0
; int xSVRDos32Init (void);
;	parm	[]	\
;	value	[eax]	\

        ALIGN   4

fn0:
	push	ds			;save caller DS
	xor	eax,eax
	xor	ebx,ebx
        mov     bx,ds                   ;insure caller ES = DS
        mov     es,bx                   ;(fixes v2.0 driver loader bug)
	mov	bx,cs			;get code selector for driver
	mov	ds,bx			;use for read-only data selector
	mov	eax,[svr_enabled]	;already initialized ?
	or	eax,eax
	jnz	err0

	mov	ax,000Ah		;DPMI data selector alias fn
	int	31h
	jc	err0			;DPMI error ?
	mov	ds,ax			;use local data selector for driver
	movzx	ebx,ax
	mov	[_svr_dsel],ebx         ;save data selector for driver
	xor	ebx,ebx
	mov	bx,cs			;save code selector for driver
	mov	[_svr_csel],ebx

	pop	eax			;re-load caller DS (32-bit pop)
	mov	[_app_dsel],eax		;save as application DS for future ref
	mov	ecx,ss:[esp+4]		;copy caller CS from return stack
	mov	[_app_csel],ecx		;save as application CS for future ref
	push	eax                     ;re-save caller DS (32-bit push)

IF USE_MIXBUF
	; use DPMI to create local 64K buffer for mixing modulo-4 pixels
	xor 	eax,eax
	mov	ax,0501h		;DPMI alloc fn #501
	mov	bx,0001h		;alloc size --> BX:CX
	mov 	cx,0000h
	int	31h
	jc	err0
	mov	[pbuf_addrh],bx		;linear address <-- BX:CX
	mov	[pbuf_addrl],cx
	mov	[pbuf_handh],si		;alloc handle <-- SI:DI
	mov	[pbuf_handl],di

	mov	ax,0600h		;DPMI lock fn #600
	mov 	bx,[pbuf_addrh]		;linear address --> BX:CX
	mov	cx,[pbuf_addrl]
	mov	si,0001h		;lock size --> SI:DI
	mov	di,0000h
	int	31h
	jc	err0

	mov	ax,0000h		;DPMI alloc LDT descriptor fn #0
	mov 	cx,1			;number of descriptors --> CX
	int	31h
	jc	err0
	mov	[pbuf_dsel],ax		;base selector <-- AX

	mov	ax,0007h		;DPMI set segment base fn #7
	mov 	bx,[pbuf_dsel]		;selector --> BX
	mov	cx,[pbuf_addrh]		;linear address --> CX:DX
	mov	dx,[pbuf_addrl]
	int	31h
	jc	err0

	mov	ax,0008h		;DPMI set segment limit fn #8
	mov	bx,[pbuf_dsel]		;selector --> BX
	mov 	cx,0001h		;limit --> CX:DX
	mov 	dx,0000h
	int	31h
	jc	err0

	mov	ax,[pbuf_dsel]		;get buffer selector
	mov	WORD PTR[_svr_pbuf+4],ax	;save as complete far pointer
	xor	ebx,ebx
	mov	DWORD PTR[_svr_pbuf],ebx	;zero default offset
ENDIF   ; USE_MIXBUF

	; init SVR local variables
	call	InitSVRLocals		;init local vars in SVRDOS32
	call	InitISRLocals_		;init local vars in SVRISR32
	call	InitModexLocals_	;init local vars in MODEX32
        call    InitVesaLocals_         ;init local vars in VESA32

IF USE_VESA
        ; detect and init VESA BIOS Extensions
        call    xInitVesa_              ;init VESA interface
ENDIF

	; determine current video mode prior to SVR activation
	call	xGetVideoMode_		;get current video mode
	mov	[svr_orgmode],eax	;save as the "original" video mode

	; init SVR driver operation parameters
IF USE_LCDBIOS
	mov	[_svr_technique],SVR_LCD32      ;init ISR technique

	mov     [_svr_high_refresh],1   ;init high refesh rate (for Lenny)
        mov     [_svr_lock_flip],0      ;no lock flip
        mov     [_svr_delay_flip],0     ;flip at default timeout tick #
        mov     [_svr_fast_intr],-2     ;interrupt rate at 256 Hz
        mov     [_svr_fast_intr],-1     ;interrupt rate at 512 Hz
   IF USE_NO_IRQ9
        mov     [_svr_lock_flip],1      ;must lock flip if no IRQ9
   ENDIF

	call	_InitLcdbios_		;init LCDBIOS ISR
	call	_SetLcdbiosOptions_     ;init LCDBIOS run-time options

   IF USE_NO_IRQ9
        push    es
        mov     ES,word ptr[_lp_rm_data+4]      ;get ISR data selector
	mov	EDI,dword ptr[_lp_rm_data]	;get ISR data offset
        mov     eax,6                           ;512Hz/78Hz pre-calibration
        mov     dword ptr ES:[EDI+D_retraceCount],eax    ;set retrace count
        pop     es
   ENDIF

   IF USE_OEMCODE
	call	_DetectOEM_		;detect OEM hardware
	call	_SetLcdbiosOptions_     ;re-init LCDBIOS run-time options for OEM
   ENDIF
ELSE
	mov	[_svr_technique],SVR_TMR;init ISR technique
	mov	[_svr_timerate],70      ;init timer rate
	mov	[_svr_ticks_adjust],200
	lea	ebx,xTMR_ISR_		;init ISR address
	mov	cx,cs
	mov	DWORD PTR[_svr_pcallin],ebx
	mov	WORD  PTR[_svr_pcallin+4],cx
ENDIF

exit0:
	xor	eax,eax
	not	eax
	mov	[svr_enabled],eax	;flag SVR enabled
	mov	eax,SVR_OK
	pop	ds			;restore caller DS
	retf
err0:
	mov	eax,SVR_ERROR		;exit error with SVR disabled
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #1
; int xSVRDos32Exit (void);
;	parm	[]	\
;	value	[eax]	\

        ALIGN   4

fn1:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	mov	eax,[svr_enabled]	;is SVR driver enabled ?
	or	eax,eax
	jz	err1

IF USE_LCDBIOS
   IF USE_OEMCODE
	call	_ExitOEM_		;exit OEM hardware support
   ENDIF
	call	_ExitLcdbios_		;remove LCDBIOS handlers
ELSE
	mov	eax,[_svr_technique]	;which technique used ?
	cmp	eax,SVR_TMR		;timer ISR ?
	jne	exit1
	call	xTMR_Exit_		;remove timer handler now...
ENDIF

exit1:
	mov	ebx,[svr_orgmode]	;get the "original" video mode
	call	xSetVideoMode_		;set as exit video mode

IF USE_VESA
        call    xExitVesa_              ;exit VESA interface
ENDIF

IF USE_MIXBUF
	; use DPMI to release previously allocated 64K mixing buffer
	mov 	ax,0601h		;DPMI unlock fn #601
	mov	bx,[pbuf_addrh]		;alloc linear address --> BX:CX
	mov	cx,[pbuf_addrl]
	mov 	si,0001h		;alloc size --> SI:DI
	mov 	di,0000h
	int	31h

	mov	ax,0502h		;DPMI free fn #502
	mov	si,[pbuf_handh]		;alloc buffer handle --> SI:DI
	mov	di,[pbuf_handl]
	int	31h

	mov	ax,0001h		;DPMI free LDT descriptor fn #1
	mov 	bx,[pbuf_dsel]		;alloc selector --> BX
	int	31h
ENDIF

	xor	eax,eax
	mov	[svr_active],eax	;flag SVR inactive
	mov	[svr_enabled],eax	;flag SVR disabled

	mov	ebx,[_svr_dsel]		;get local DS one last time
	mov	[_svr_dsel],eax		;no longer available to be used
	mov	ax,0001h		;DPMI free selector fn #1
	int	31h

	mov	eax,SVR_OK		;notify SVR driver deactivated
	pop	ds                      ;restore caller DS
	retf
err1:
	mov	eax,SVR_ERROR		;notify SVR call error
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #2
; int xSVRDos32SetMode (WORD usermode);
;	parm	[ax]	\
;	value	[eax]	\

        ALIGN   4

fn2:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	movzx	eax,ax			;get 16-bit user mode
	mov	[svr_mode],eax		;save current SVR graphics mode

        mov     eax,[svr_active]        ;page-flipping active ?
        or      eax,eax
        jz      di2
IF USE_LCDBIOS
	call	_DisableLcdbios32_	;disable auto-flipping ISR
ELSE
	call	xDisableAutoStereo_	;disable auto-stereo ISR
ENDIF
        xor     eax,eax
        mov     [svr_active],eax        ;flag page-flipping disabled
di2:
	call	xGetVideoMode_		;get current video mode
	mov	[svr_premode],eax	;save as the "previous" video mode

	mov	eax,[svr_mode]		;re-load SVR graphics mode
        xor     ebx,ebx
        test    eax,SVR_LINE_ALT        ;line-alternate format ?
        jz      la2
        not     ebx                     ;flag true
        and     eax,NOT SVR_LINE_ALT    ;mask off option bit
la2:    mov     [_svr_line_alternate],ebx

        xor     ebx,ebx
        test    eax,SVR_HALF_RES        ;otherwise half-resolution format ?
        jz      hr2
        not     ebx                     ;flag true
        and     eax,NOT SVR_HALF_RES    ;mask off option bit
hr2:    mov     [svr_halfed],ebx

	cmp	eax,SVR_MODE13          ;vanilla mode 13 ?
	jne	fn2a
	mov	[svr_mode],eax		;save current SVR graphics mode
	mov     [svr_premode],eax       ;save as previous SVR graphics mode
	mov	ebx,[_svr_pal_protect]	;get palette protection option
	call	xSetPaletteMode_	;set palette protection
	call	xSetGraphMode13_	;set graphics mode 13
        call    xSetGraphLimits_        ;set graphics XY limits
        call    xSetGraphPages_         ;set graphics page addresses
	xor	ebx,ebx
	call	XSetPaletteMode_	;back to default palette option
	jmp	exit2

fn2a:   ; set VGA mode-X video modes
IF USE_VESA AND USE_VESA_320
        cmp     dword ptr[_VESA_detected],2     ;VESA interface active ?
        jge     fn2v                            ;use VESA modes instead
ENDIF
	cmp	eax,SVR_MODEX           ;graphics mode X 320x200 ?
	jne	fn2a1
	mov	[svr_mode],eax		;save current SVR graphics mode
	mov     [svr_premode],eax       ;save as previous SVR graphics mode
fn2x0:  mov	ebx,[_svr_pal_protect]	;get palette protection option
	call	xSetPaletteMode_	;set palette protection
	call	xSetGraphModeX_		;set graphics mode X default
	call    xSetGraphLimits_        ;set graphics XY limits
        call    xSetGraphPages_         ;set graphics page addresses
	xor	ebx,ebx
	call	XSetPaletteMode_	;back to default palette option
        jmp     fn2x
fn2a1:
        cmp	eax,SVR_MODEX_400       ;graphics mode X 320x400 ?
	jne	fn2a2
	mov	[svr_mode],eax		;save current SVR graphics mode
	mov     [svr_premode],eax       ;save as previous SVR graphics mode
fn2x1:	mov	ebx,[_svr_pal_protect]	;get palette protection option
	call	xSetPaletteMode_	;set palette protection
	call	xSetGraphModeX400_      ;set graphics mode X 320x400
	call    xSetGraphLimits_        ;set graphics XY limits
        call    xSetGraphPages_         ;set graphics page addresses
	xor	ebx,ebx
	call	XSetPaletteMode_	;back to default palette option
        jmp     fn2x
fn2a2:
        cmp	eax,SVR_MODEX_240       ;graphics mode X 320x240 ?
	jne	fn2a4
	mov	[svr_mode],eax		;save current SVR graphics mode
	mov     [svr_premode],eax       ;save as previous SVR graphics mode
fn2x2:	mov	ebx,[_svr_pal_protect]	;get palette protection option
	call	xSetPaletteMode_	;set palette protection
	call	xSetGraphModeX240_      ;set graphics mode X 320x240
	call    xSetGraphLimits_        ;set graphics XY limits
        call    xSetGraphPages_         ;set graphics page addresses
	xor	ebx,ebx
	call	XSetPaletteMode_	;back to default palette option
        jmp     fn2x
fn2a4:
        cmp	eax,SVR_MODEX_480       ;graphics mode X 320x480 ?
	jne	fn2a9
	mov	[svr_mode],eax		;save current SVR graphics mode
	mov     [svr_premode],eax       ;save as previous SVR graphics mode
fn2x4:	mov	ebx,[_svr_pal_protect]	;get palette protection option
	call	xSetPaletteMode_	;set palette protection
	call	xSetGraphModeX480_      ;set graphics mode X 320x480
	call    xSetGraphLimits_        ;set graphics XY limits
        call    xSetGraphPages_         ;set graphics page addresses
	xor	ebx,ebx
	call	XSetPaletteMode_	;back to default palette option
fn2a9:
IF USE_VESA     ; set VESA video modes
fn2v:
	cmp	eax,SVR_MODEX           ;graphics mode 320x200 ?
	jne	fn2v1
	mov	[svr_mode],eax		;save current SVR graphics mode
	mov     [svr_premode],eax       ;save as previous SVR graphics mode
        mov     ebx,0153h
        call    xSetVesaMode_           ;set VESA mode 320x200
        or      ebx,ebx
        jz      fn2x0                   ;else set VGA mode X 320x200
        call    xSetVesaGraphLimits_    ;set graphics XY limits
        call    xSetVesaGraphPages_     ;set graphics page addresses
        xor     ebx,ebx
        call    xDisplayVesaPage_       ;set VESA page, index, XY data
        jmp     fn2x
fn2v1:
        cmp	eax,SVR_MODEX_400       ;graphics mode 320x400 ?
	jne	fn2v2
	mov	[svr_mode],eax		;save current SVR graphics mode
	mov     [svr_premode],eax       ;save as previous SVR graphics mode
        mov     ebx,0155h
        call    xSetVesaMode_           ;set VESA mode 320x400
        or      ebx,ebx
        jz      fn2x1                   ;else set VGA mode X 320x400
        call    xSetVesaGraphLimits_    ;set graphics XY limits
        call    xSetVesaGraphPages_     ;set graphics page addresses
        xor     ebx,ebx
        call    xDisplayVesaPage_       ;set VESA page, index, XY data
        jmp     fn2x
fn2v2:
        cmp	eax,SVR_MODEX_240       ;graphics mode 320x240 ?
	jne	fn2v4
	mov	[svr_mode],eax		;save current SVR graphics mode
	mov     [svr_premode],eax       ;save as previous SVR graphics mode
        mov     ebx,0154h
        call    xSetVesaMode_           ;set VESA mode 320x240
        or      ebx,ebx
        jz      fn2x2                   ;else set VGA mode X 320x240
        call    xSetVesaGraphLimits_    ;set graphics XY limits
        call    xSetVesaGraphPages_     ;set graphics page addresses
        xor     ebx,ebx
        call    xDisplayVesaPage_       ;set VESA page, index, XY data
        jmp     fn2x
fn2v4:
        cmp	eax,SVR_MODEX_480       ;graphics mode 320x480 ?
	jne	fn2v6
	mov	[svr_mode],eax		;save current SVR graphics mode
	mov     [svr_premode],eax       ;save as previous SVR graphics mode
        mov     ebx,0156h
        call    xSetVesaMode_           ;set VESA mode 320x480
        or      ebx,ebx
        jz      fn2x4                   ;else set VGA mode X 320x480
        call    xSetVesaGraphLimits_    ;set graphics XY limits
        call    xSetVesaGraphPages_     ;set graphics page addresses
        xor     ebx,ebx
        call    xDisplayVesaPage_       ;set VESA page, index, XY data
        jmp     fn2x
fn2v6:
        cmp     eax,SVR_MODE100         ;VESA mode 640x400 ?
        jne     fn2v8
        mov	[svr_mode],eax		;save current SVR graphics mode
	mov     [svr_premode],eax       ;save as previous SVR graphics mode
        mov     ebx,0100h
        call    xSetVesaMode_           ;set VESA mode 640x400
        call    xSetVesaGraphLimits_    ;set graphics XY limits
        call    xSetVesaGraphPages_     ;set graphics page addresses
        xor     ebx,ebx
        call    xDisplayVesaPage_       ;set VESA page, index, XY data
        jmp     fn2x
fn2v8:
        cmp     eax,SVR_MODE101         ;VESA mode 640x480 ?
        jne     fn2v9
        mov	[svr_mode],eax		;save current SVR graphics mode
	mov     [svr_premode],eax       ;save as previous SVR graphics mode
        mov     ebx,0101h
        call    xSetVesaMode_           ;set VESA mode 640x480
        call    xSetVesaGraphLimits_    ;set graphics XY limits
        call    xSetVesaGraphPages_     ;set graphics page addresses
        xor     ebx,ebx
        call    xDisplayVesaPage_       ;set VESA page, index, XY data
        jmp     fn2x
fn2v9:
        jmp     fn2b                    ;check other modes

ENDIF   ; USE_VESA

fn2x:   ; set video page variables to initial page-flipping state
        xor     eax,eax
        mov     [_svr_visiblepage],ax   ;init visible page = 0
        mov     al,2
        mov     [svr_page],eax          ;init non-visible page = 2
IF USE_LCDBIOS
        call    _LowPageLcdbios32_      ;select low page pair in ISR
ENDIF

IF USE_VESA     ; set VESA mode vars
        cmp     [_VESA_active],0        ;VESA mode ?
        je      fn2x9

        mov     eax,[_VESA_vmode]       ;transfer VESA video info
        mov     [_vmode],eax
        mov     eax,[_VESA_xres]
        mov     [_xres],eax
        mov     eax,[_VESA_yres]
        mov     [_yres],eax

        push    es
        mov     ES,word ptr[_lp_rm_data+4]      ;get ISR data selector
	mov	EDI,dword ptr[_lp_rm_data]	;get ISR data offset
        mov     ecx,[_VESA_detected]            ;get VESA version
        mov     dword ptr ES:[EDI+D_vesaMode],ecx      ;set VESA mode
        mov     edx,dword ptr[_pSetStartFn]
;;;;    mov     dword ptr ES:[EDI+D_pm_setxy],edx      ;set SetXY fn ptr
        mov     dword ptr ES:[EDI+D_pm_external],edx   ;set SetXY fn ptr
        mov     cx,cs
        mov     word ptr ES:[EDI+D_pm_external+4],cx
        pop     es
        jmp     exit2
fn2x9:
ENDIF
        ; set visible video page
        xor     ebx,ebx
        call    xSelectDisplayPage_     ;select video page 0

	; init SVR black and white colors
	mov	eax,[svr_white]		;save white palette entry
IF USE_BLUELINE
	mov	bl,0
	mov	bh,BLUE_R		;set red
	mov	cl,BLUE_G		;green
	mov	ch,BLUE_B		;blue
ELSE
	mov	bx,3F00h		;set max red
	mov	cx,3F3Fh		;set max green + blue
ENDIF
	mov	bl,al			;set palette index
	call	xSetPaletteColor_	;set the palette color to white
	jmp	exit2

fn2b:   ; check for other display modes...
	cmp	eax,SVR_MODE03          ;text mode ?
	jne	fn2c
	mov	[svr_mode],eax		;save current SVR graphics mode
	mov     [svr_premode],eax       ;save as previous SVR graphics mode
	call	xSetTextMode_		;set text mode 03
	jmp	exit2
fn2c:
	cmp	eax,SVR_MODE_ORG        ;original mode ?
	jne	fn2d
        mov     eax,[svr_orgmode]       ;get original mode
	mov	[svr_mode],eax		;save current SVR graphics mode
        mov     [svr_premode],eax       ;save as previous SVR graphics mode
        mov     ebx,eax
	call	xSetVideoMode_		;set original video mode
	jmp	exit2
fn2d:
	cmp	eax,SVR_MODE_PREV       ;previous mode ?
	jne	fn2e
	mov     eax,[svr_premode]       ;get previous mode
	mov	[svr_mode],eax		;save current SVR graphics mode
        mov     ebx,eax
	call	xSetVideoMode_		;set previous video mode
	jmp	exit2
fn2e:
err2:   ; if we fell through to here, we don't have your display mode...
	mov	eax,SVR_ERROR		;exit error if mode not valid
	mov	[svr_mode],eax		;save current SVR graphics mode
	pop	ds                      ;restore caller DS
	retf
exit2:
	mov	eax,SVR_OK		;exit OK if mode valid
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #3
; int xSVRDos32GetMode (void);
;	parm	[]	\
;	value	[eax]	\

        ALIGN   4

fn3:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	mov	eax,[svr_mode]		;get current SVR graphics mode
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #4
; int xSVRDos32GetInfo (SVRDos32Info_t FAR * _SVR_info);
;	parm	[cx ebx]\
;	value	[eax]	\

        ALIGN   4

fn4:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	push	es
	mov	es,cx			;use caller selector
	mov	eax,' VGA'
IF USE_VESA
        mov     edx,[_VESA_detected]    ;VESA ?
        or      edx,edx
        jz      fn4a
        dec     edx                     ;VESA 1.x or 2.x ?
        mov     eax,'VESA'
        jz      fn4a
        mov     eax,'VBE2'
        dec     edx                     ;VESA 2.0 or 3.0 ?
        jz      fn4a
        mov     eax,'VBE3'
fn4a:
ENDIF
	mov	es:[ebx],eax		;DWORD hwVersion
	mov	eax,SVR_VER
	mov	es:[ebx+4],eax		;DWORD tsrVersion
	mov	eax,[_vmode]
	mov	es:[ebx+8],eax		;DWORD gfxMode
	pop	es

	mov	eax,SVR_OK		;_SVR_info struct filled in
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #5
; int xSVRDos32SetImage (BOOL eye, WORD x0, WORD y0, WORD xd, WORD yd, LPBYTE buf);
;	parm	[eax][ebx][ecx][dx esi]	\
;	value	[eax]	\

        ALIGN   4

fn5:
	push	ds			;save caller DS
	push	edx			;save parameter EDX
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS
	pop	edx			;restore parameter EDX

	; determine which page to effectively update with pixel data
	or	eax,eax			;update which eye ?
	jnz	right5
	mov	ax,[_svr_visiblepage]	;page flipping on which pair ?
	cmp	al,0
	je	left5
	cmp	al,1
	je	left5
	mov	al,0			;if 2 or 3, select left page 0
	jmp	page5
left5:  mov	al,2			;if 0 or 1, select left page 2
	jmp	page5
right5:
	mov	ax,[_svr_visiblepage]	;page flipping on which pair ?
	cmp	al,0
	je	right05
	cmp	al,1
	je	right05
	mov	al,1			;if 2 or 3, select right page 1
	jmp	page5
right05:mov	al,3			;if 0 or 1, select right page 3
page5:
	movzx	eax,al
	mov	[svr_page],eax          ;save as the next effective page

        ; insure xd and yd are valid
	mov     eax,ecx
	or      eax,eax                 ;xd, yd = 0 ?
	jz      err5
	or      ax,ax                   ;xd = 0 ?
	jz      err5
	shr     eax,16
	or      eax,eax                 ;yd = 0 ?
        jz      err5
        or      esi,esi                 ;buf = NULL ?
        jz      err5
        or      dx,dx                   ;selector = 0 ?
        jz      err5

	; insure xd and yd within 320 x 200 limits
	mov	eax,ecx
	shr	eax,16			;unpack yd
	cmp	eax,[_ymax]             ;insure <= 199 ?
	jbe     yd5
	mov     eax,[_ymax]
yd5:	shl	eax,16
	mov	ax,cx			;unpack xd
	cmp	ax,word ptr [_xmax]     ;insure <= 320
	jbe     xd5
	mov	ax,word ptr [_xmax]
xd5:	mov	ecx,eax			;re-pack xd and yd

	; insure y0+yd do not obscure last line
	xor	ax,ax    		;mask out xd in low word
	add	eax,ebx			;add y0 + yd in high words
	shr	eax,16
	cmp	eax,[_ymax]             ;insure y0+yd <= 199 ?
	jbe     y0yd5
        push    edx
        mov     edx,ebx
        xor     dx,dx
	mov	eax,[_ymax]             ;limit yd = 199 - y0
	shl	eax,16
	sub	eax,edx			;subtract 199 - y0 in high words
        mov	ax,cx  			;repack xd with yd
	mov	ecx,eax
        pop     edx
        jbe     err5                    ;adjusted yd <= 0 ?
y0yd5:

        ; determine display mode format for blitting
IF USE_VESA
        cmp     [_VESA_active],0        ;VESA mode ?
        jne     vesa5                   ;...then copy as-is linear
ENDIF

	; determine if pixel data requires modulo-4 ordering for mode X
	mov	eax,[_svr_pixels_modex] ;user pixels supplied as mode X ?
	or	eax,eax
	jnz	modex5			;...then copy as-is

	mov	eax,[_vmode]		;linear mode 13 or modulo-4 mode X ?
	cmp	al,13h			;if mode 13
	je   	xfer5			;...then copy as-is (linear)

        ; determine if pixel data has to be copied line by line
        mov     eax,[_svr_line_alternate]       ;line-alternate format ?
        or      eax,eax
        jnz     alt5                    ;...then copy alternate lines

	cmp	cx,320			;xd = 320 full width ?
	jne	line5			;if not, then copy line by line

        ; copy full-width bitmap directly in mode-X modulo-4 order

	shr	ecx,16			;unpack yd
        xor     eax,eax
        shl     ecx,6                   ;yd * 64
        add     eax,ecx
        shl     ecx,2                   ;yd * 256
        add     eax,ecx                 ;... = yd * 320
	mov	ecx,eax                 ;total byte count ECX

        mov     edi,[svr_page]          ;get video page #0..3
        shl     edi,2                   ;scale up for DWORD index
        lea     eax,[_vleft_front+EDI]  ;index table of page addresses
        mov     edi,dword ptr[EAX]      ;get video page address

        movzx   eax,bx                  ;unpack x0
        shr     ebx,16                  ;unpack y0
        shl     ebx,6                   ;y0 * 64
        add     eax,ebx                 ;x0 + y0 * 64
        shl     ebx,2                   ;y0 * 256
        add     eax,ebx                 ;x0 + y0 * 64 + y0 * 256
        shr     eax,2                   ;scale down for mod-4 packing
        add     edi,eax                 ;= VGA index x0 + y0 * 320

        push    ds                      ;save local DS
        mov     ds,dx                   ;transfer source DS
        mov     ebx,3                   ;mod-4 incrementer
        shr	ecx,2			;scale down for mod-4 4x counting
        cld                             ;auto-increment ESI, EDI

	mov	dx,03C4h	        ;VGA sequencer reg
        mov     al,02h                  ;map mask index
        out     dx,al
        inc     edx
        mov     al,01h                  ;select VGA plane #1
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        ALIGN   4
xf15:   movsb                           ;transfer
        add     esi,ebx                 ;source +=4
        dec     ecx
        jnz     xf15
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,02h                  ;select VGA plane #2
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        inc     esi                     ;adjust source for 1,5,9,...
        ALIGN   4
xf25:   movsb                           ;transfer
        add     esi,ebx                 ;source +=4
        dec     ecx
        jnz     xf25
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,04h                  ;select VGA plane #3
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        inc     esi                     ;adjust source for 2,6,10,...
        inc     esi
        ALIGN   4
xf35:   movsb                           ;transfer
        add     esi,ebx                 ;source +=4
        dec     ecx
        jnz     xf35
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,08h                  ;select VGA plane #4
        out     dx,al

        inc     esi                     ;adjust source for 3,7,11,...
        inc     esi
        inc     esi
        ALIGN   4
xf45:   movsb                           ;transfer
        add     esi,ebx                 ;source +=4
        dec     ecx
        jnz     xf45

        pop     ds                      ;restore local DS
        jmp     swap5

        ALIGN   4

xfer5:  ; copy mode-X format pixel data as-is to effective video page

	mov	eax,[svr_page]		;select video page number
	call	xMovePixelClip_		;move block of pixels to video page
	jmp	swap5


        ALIGN   4

line5:  ; copy pixel data line by line directly in mode-X modulo-4 order

	cmp	cx,16			;very small xd width ?
	jle	pixel5			;then output pixel by pixel

        mov     edi,[svr_page]          ;get video page #0..3
        shl     edi,2                   ;scale up for DWORD index
        lea     eax,[_vleft_front+EDI]  ;index table of page addresses
        mov     edi,dword ptr[EAX]      ;get video page address

        movzx   eax,bx                  ;unpack x0
        shr     ebx,16                  ;unpack y0
        shl     ebx,6                   ;y0 * 64
        add     eax,ebx                 ;x0 + y0 * 64
        shl     ebx,2                   ;y0 * 256
        add     eax,ebx                 ;x0 + y0 * 64 + y0 * 256
        shr     eax,2                   ;scale down for mod-4 packing
        add     edi,eax                 ;= VGA mode-x index x0 + y0 * 320

        ASSUME  FS:_DATA

        push    ds                      ;save local DS
        push    fs                      ;save FS
        mov     ax,ds
        mov     fs,ax                   ;use FS for local data selector
        mov     ds,dx                   ;transfer source DS
        cld                             ;auto-increment ESI, EDI
        mov     ebx,3                   ;mod-4 incrementer

	mov	dx,03C4h	        ;VGA sequencer reg
        mov     al,02h                  ;map mask index
        out     dx,al
        inc     edx                     ;map mask data port

        mov	eax,ecx
	shr	eax,16			;unpack yd for number of lines
	movzx	ecx,cx			;unpack xd for size of lines

        ALIGN   4

lloop5: push	eax			;save yd line counter
	push 	ecx			;save xd block size counter per line
        push	esi			;save source pointer per line
	push    edi                     ;save destination pointer per line

        shr	ecx,2			;scale down for mod-4 4x counting

	mov     al,01h                  ;select VGA plane #1
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        ALIGN   4
lxf15:  movsb                           ;transfer
        add     esi,ebx                 ;source +=4
        dec     ecx
        jnz     lxf15
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,02h                  ;select VGA plane #2
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        inc     esi                     ;adjust source for 1,5,9,...
        ALIGN   4
lxf25:  movsb                           ;transfer
        add     esi,ebx                 ;source +=4
        dec     ecx
        jnz     lxf25
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,04h                  ;select VGA plane #3
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        inc     esi                     ;adjust source for 2,6,10,...
        inc     esi
        ALIGN   4
lxf35:  movsb                           ;transfer
        add     esi,ebx                 ;source +=4
        dec     ecx
        jnz     lxf35
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,08h                  ;select VGA plane #4
        out     dx,al

        inc     esi                     ;adjust source for 3,7,11,...
        inc     esi
        inc     esi
        ALIGN   4
lxf45:  movsb                           ;transfer
        add     esi,ebx                 ;source +=4
        dec     ecx
        jnz     lxf45

        pop     edi                     ;restore destination pointer
        pop	esi                     ;restore source pointer
	pop     ecx                     ;restore linear xd
	mov	eax,fs:[_svr_pixels_width]	;non-contiguous pixels ?
	or	eax,eax
	jnz	addx5                   ;non-contiguous pixels width ?
	mov	eax,ecx                 ;contiguous xd width
addx5:	add	esi,eax			;update source address by xd or 320
        add     edi,80                  ;update destination by mod-4 320
	pop	eax			;restore line counter
	dec	eax			;update line count
	jnz	lloop5			;repeat for all lines

        pop     fs                      ;restore FS
        pop     ds                      ;restore local DS
        jmp     swap5

        ASSUME  FS:nothing

        ALIGN   4

alt5:   ; copy pixel data by alternate lines directly in mode-X modulo-4 order

	cmp	cx,16			;very small xd width ?
	jle	pixel5			;then output pixel by pixel

        mov     edi,[svr_page]          ;get video page #0..3
        shl     edi,2                   ;scale up for DWORD index
        lea     eax,[_vleft_front+EDI]  ;index table of page addresses
        mov     edi,dword ptr[EAX]      ;get video page address

        mov     eax,edi                 ;start address
        add     eax,[_imax]             ;+ max index
        mov     [_vmax],eax             ;= max video address

        movzx   eax,bx                  ;unpack x0
        shr     ebx,16                  ;unpack y0
        shl     ebx,1                   ;scale up y0 by 2 for alternate lines

        push    eax                     ;x0
        push    edx
        mov     eax,[_xres]             ;320
        imul    ebx                     ;320 * (2*y0)
        pop     edx
        pop     ebx                     ;x0
        add     eax,ebx                 ;x0 + 320 * (2*y0)

        test    byte ptr[svr_page],01h  ;0 = left, 1 = right
        jz      even5                   ;320 * (2*y0)
        inc     eax                     ;320 * (2*y0) + 1
even5:
        shr     eax,2                   ;scale down for mode-X packing
        add     edi,eax                 ;video memory alternate line index

        cmp     edi,[_vmax]             ;video address within range ?
        jae     exit5

        ASSUME  FS:_DATA

        push    ds                      ;save local DS
        push    fs                      ;save FS
        mov     ax,ds
        mov     fs,ax                   ;use FS for local data selector
        mov     ds,dx                   ;transfer source DS
        cld                             ;auto-increment ESI, EDI
        mov     ebx,3                   ;mod-4 incrementer

	mov	dx,03C4h	        ;VGA sequencer reg
        mov     al,02h                  ;map mask index
        out     dx,al
        inc     edx                     ;map mask data port

        mov	eax,ecx
	shr	eax,16			;unpack yd for number of lines
	movzx	ecx,cx			;unpack xd for size of lines

        ALIGN   4

aloop5: push	eax			;save yd line counter
	push 	ecx			;save xd block size counter per line
        push	esi			;save source pointer per line
	push    edi                     ;save destination pointer per line

        shr	ecx,2			;scale down for mod-4 4x counting

	mov     al,01h                  ;select VGA plane #1
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        ALIGN   4
axf15:  movsb                           ;transfer
        add     esi,ebx                 ;source +=4
        dec     ecx
        jnz     axf15
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,02h                  ;select VGA plane #2
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        inc     esi                     ;adjust source for 1,5,9,...
        ALIGN   4
axf25:  movsb                           ;transfer
        add     esi,ebx                 ;source +=4
        dec     ecx
        jnz     axf25
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,04h                  ;select VGA plane #3
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        inc     esi                     ;adjust source for 2,6,10,...
        inc     esi
        ALIGN   4
axf35:  movsb                           ;transfer
        add     esi,ebx                 ;source +=4
        dec     ecx
        jnz     axf35
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,08h                  ;select VGA plane #4
        out     dx,al

        inc     esi                     ;adjust source for 3,7,11,...
        inc     esi
        inc     esi
        ALIGN   4
axf45:  movsb                           ;transfer
        add     esi,ebx                 ;source +=4
        dec     ecx
        jnz     axf45

        pop     edi                     ;restore destination pointer
        pop	esi                     ;restore source pointer
	pop     ecx                     ;restore linear xd
	mov	eax,fs:[_svr_pixels_width]	;non-contiguous pixels ?
	or	eax,eax
	jnz	addx5a                  ;non-contiguous pixels width ?
	mov	eax,ecx                 ;contiguous xd width
addx5a:	add	esi,eax			;update source address by xd or 320
        add     edi,160                 ;update destination by mod-4 320 2x
	pop	eax			;restore line counter

        cmp     edi,fs:[_vmax]          ;video address still within range ?
        jae     aexit5
	dec	eax			;update line count
	jnz	aloop5			;repeat for all lines

aexit5:
        pop     fs                      ;restore FS
        pop     ds                      ;restore local DS
        jmp     swap5

        ASSUME  FS:nothing

        ALIGN   4

pixel5: ; copy image pixel by pixel

	push	es
        mov     es,[_app_dsel]          ;init default selector for PlotPixelX
        push    fs
	mov	fs,dx			;init source buffer selector

	mov	eax,ebx
	shr	eax,16                  ;unpack y0
	movzx	ebx,bx			;unpack x0
	mov     edi,eax			;EDI <-- y = y0

	mov	eax,ecx
	shr	eax,16			;unpack yd count
	movzx	ecx,cx			;unpack xd count

        ALIGN   4

loopy5:	push	eax			;EAX <-- yd count
	push	ebx			;EBX <-- x0 index
	push	ecx			;ECX <-- xd count
	mov	eax,ecx			;re-init xd count per y line
	mov	ecx,edi			;incremental y

        ALIGN   4

loopx5:	push	eax                     ;EAX <-- xd
        push    ebx                     ;EBX <-- x
        push    ecx                     ;ECX <-- y
	push	esi
	push	edi
	mov	eax,[svr_page]
        movzx	edx,byte ptr fs:[esi]   ;EDX <-- get pixel from source buffer
IF USE_VESA
	call	PlotPixel               ;plot pixel in VESA or VGA mode-x
ELSE
	call	xPlotPixelPageX_        ;plot pixel in mode-x
ENDIF
	pop	edi
	pop	esi
        pop     ecx
        pop     ebx
	pop	eax
	inc	esi			;update source ptr
	inc	ebx			;update x
	dec	eax			;update xd counter
	jnz	loopx5                  ;repeat for each x

	inc	edi			;update y
	pop	ecx                     ;restore xd count
	pop	ebx			;restore x0 index
	pop	eax
	dec	eax			;update yd counter
	jnz	loopy5                  ;repeat for each y

        pop     fs
	pop	es
	jmp	swap5


        ALIGN   4

modex5: ; copy pixel data already prepared for mode x
	cmp	cx,320			;xd = 320 ?
	jne	linex5			;if not, then copy line by line
        jmp     xfer5                   ;else copy mode-x block as-is


        ALIGN   4

linex5: ; copy pixel data line by line already prepared for mode x
	cmp	cx,16 			;very small xd width ?
	jle	pixel5			;then output pixel by pixel

	mov	eax,ecx
	shr	eax,16			;EAX <-- unpack yd for number of lines
	movzx	ecx,cx			;ECX <-- unpack xd for size of lines

        ALIGN   4

lloop5x:
	push	eax			;save yd line counter
        push    edx                     ;save source selector
	push	esi			;save esi source pointer

	push	ecx
	or	ecx,00010000h		;load xd,yd for 1 line
	push	ebx

	mov	eax,[svr_page]          ;load video page #
IF USE_VESA
        call    MovePixels              ;copy line at x0,y0+y
ELSE
	call	xMovePixelClip_		;copy line at x0,y0+y
ENDIF
	pop	ebx			;restore x0,y0
	mov	edx,ebx
	shr	edx,16
	inc	dx			;update y0 only
	shl	edx,16
	mov	dx,bx
	mov	ebx,edx
	pop	ecx			;restore xd block size counter

	pop	esi                     ;restore source pointer
	mov	edx,ecx
	mov	eax,[_svr_pixels_width]	;non-contiguous pixels ?
	or	eax,eax
	jz	addx5x
	mov	edx,eax
addx5x:	add	esi,edx			;update source address by xd or 320
        pop     edx                     ;restore source selector
	pop	eax			;restore line counter
	dec	eax			;update line count
	jnz	lloop5x			;repeat for all lines

	jmp	swap5

IF USE_VESA

        ALIGN   4

vesa5:  ; blit pixels in VESA linear display format

        cmp     cx,word ptr[_VESA_xgap] ;xd == xgap ?
        jne     linex5                  ;if not, then move line by line

	mov	eax,[svr_page]		;select video page number
	call	xMoveVesaPixels_	;move block of pixels to video page
        jmp     swap5

ENDIF   ; USE_VESA


        ALIGN   4

swap5:	; switch visible/non-visible pair of left/right flipping pages
        ; performed separately with call to SVRDos32ShowImages

exit5:
	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

err5:
	mov	eax,SVR_ERROR
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #6
; int xSVRDos32GetImage (BOOL eye, WORD x0, WORD y0, WORD xd, WORD yd, LPBYTE buf);
;	parm	[eax][ebx][ecx][dx edi]	\
;	value	[eax]	\

        ALIGN   4

fn6:
	push	ds			;save caller DS
	push	edx			;save parameter EDX
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS
	pop	edx			;restore parameter EDX

	; determine which page to read pixel data from
	or	eax,eax			;update which eye ?
	jnz	right6
	mov	ax,[_svr_visiblepage]	;page flipping on which pair ?
	cmp	al,0
	je	left6
	cmp	al,1
	je	left6
	mov	al,2			;if 2 or 3, select left page 2
	jmp	page6
left6:  mov	al,0			;if 0 or 1, select left page 0
	jmp	page6
right6:
	mov	ax,[_svr_visiblepage]	;page flipping on which pair ?
	cmp	al,0
	je	right06
	cmp	al,1
	je	right06
	mov	al,3			;if 2 or 3, select right page 3
	jmp	page6
right06:mov	al,1			;if 0 or 1, select right page 1
page6:
	movzx	eax,al
	mov	[svr_readpage],eax          ;save as the effective page

        ; insure xd and yd are valid
        mov     eax,ecx
        or      eax,eax                 ;xd, yd = 0 ?
        jz      err6
        or      ax,ax                   ;xd = 0 ?
        jz      err6
        shr     eax,16
        or      ax,ax                   ;yd = 0 ?
        jz      err6
        or      edi,edi                 ;buf = NULL ?
        jz      err6
        or      dx,dx                   ;selector = 0 ?
        jz      err6

	; insure xd and yd within 320 x 200 limits
	mov	eax,ecx
	shr	eax,16			;unpack yd
	cmp	eax,[_ymax]             ;insure <= 199 ?
	jbe     yd6
	mov     eax,[_ymax]
yd6:	shl	eax,16
	mov	ax,cx			;unpack xd
	cmp	ax,word ptr [_xmax]     ;insure <= 320
	jbe     xd6
	mov	ax,word ptr [_xmax]
xd6:	mov	ecx,eax			;re-pack xd and yd

	; insure y0+yd do not obscure last line
	xor	ax,ax    		;mask out xd in low word
	add	eax,ebx			;add y0 + yd in high words
	shr	eax,16
	cmp	eax,[_ymax]             ;insure y0+yd <= 199 ?
	jbe     y0yd6
        push    edx
        mov     edx,ebx
        xor     dx,dx
	mov	eax,[_ymax]             ;limit yd = 199 - y0
	shl	eax,16
	sub	eax,edx			;subtract 199 - y0 in high words
        mov	ax,cx  			;repack xd with yd
	mov	ecx,eax
        pop     edx
        jbe     err6                    ;adjusted yd <= 0 ?
y0yd6:
	; determine if pixel data has to read line by line
	cmp	cx,320			;xd = 320 ?
	jne	line6			;if not, then read line by line

	; determine if pixel data requires modulo-4 de-ordering for mode X
	mov	eax,[_vmode]		;linear mode 13 or modulo-4 mode X ?
	cmp	al,13h			;if mode 13
	je   	asis6			;...then copy as-is (linear)

        ; read pixel data directly in modulo-4 mode-X format

	shr	ecx,16			;unpack yd
        xor     eax,eax
        shl     ecx,6                   ;yd * 64
        add     eax,ecx
        shl     ecx,2                   ;yd * 256
        add     eax,ecx                 ;... = yd * 320
	mov	ecx,eax                 ;total byte count ECX

        mov     esi,[svr_readpage]      ;get video page #0..3
        shl     esi,2                   ;scale up for DWORD index
        lea     eax,[_vleft_front+ESI]  ;index table of page addresses
        mov     esi,dword ptr[EAX]      ;get video page address

        movzx   eax,bx                  ;unpack x0
        shr     ebx,16                  ;unpack y0
        shl     ebx,6                   ;y0 * 64
        add     eax,ebx                 ;x0 + y0 * 64
        shl     ebx,2                   ;y0 * 256
        add     eax,ebx                 ;x0 + y0 * 64 + y0 * 256
        shr     eax,2                   ;scale down for mod-4 packing
        add     esi,eax                 ;= VGA index x0 + y0 * 320

        push    ds                      ;save local DS
        push    es                      ;save global ES
        mov     ax,es
        mov     es,dx                   ;transfer destination ES
        mov     ds,ax                   ;global video source DS

        mov     ebx,3                   ;mod-4 incrementer
        shr	ecx,2			;scale down for mod-4 4x counting
        cld                             ;auto-increment ESI, EDI

        mov	dx,03CEh	        ;VGA read map mask reg
	mov	al,04h                  ;map mask index
        out     dx,al
        inc     edx
        mov     al,00h                  ;select VGA plane #1
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        ALIGN   4
xf16:   movsb                           ;transfer
        add     edi,ebx                 ;destination +=4
        dec     ecx
        jnz     xf16
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,01h                  ;select VGA plane #2
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        inc     edi                     ;adjust destination for 1,5,9,...
        ALIGN   4
xf26:   movsb                           ;transfer
        add     edi,ebx                 ;destination +=4
        dec     ecx
        jnz     xf26
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,02h                  ;select VGA plane #3
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        inc     edi                     ;adjust destination for 2,6,10,...
        inc     edi
        ALIGN   4
xf36:   movsb                           ;transfer
        add     edi,ebx                 ;destination +=4
        dec     ecx
        jnz     xf36
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,03h                  ;select VGA plane #4
        out     dx,al

        inc     edi                     ;adjust destination for 3,7,11,...
        inc     edi
        inc     edi
        ALIGN   4
xf46:   movsb                           ;transfer
        add     edi,ebx                 ;destination +=4
        dec     ecx
        jnz     xf46

        pop     es                      ;restore global ES
        pop     ds                      ;restore local DS
        jmp     exit6

        ALIGN   4

asis6:  ; read mode-X pixel data as-is
	mov	eax,[svr_readpage]      ;get video page number
	call	xReadPixelClip_		;read block of pixels from video page
	jmp	exit6

        ALIGN   4

line6:  ; read pixel data line by line directly in mode-X format
        mov     esi,[svr_readpage]      ;get video page #0..3
        shl     esi,2                   ;scale up for DWORD index
        lea     eax,[_vleft_front+ESI]  ;index table of page addresses
        mov     esi,dword ptr[EAX]      ;get video page address

        movzx   eax,bx                  ;unpack x0
        shr     ebx,16                  ;unpack y0
        shl     ebx,6                   ;y0 * 64
        add     eax,ebx                 ;x0 + y0 * 64
        shl     ebx,2                   ;y0 * 256
        add     eax,ebx                 ;x0 + y0 * 64 + y0 * 256
        shr     eax,2                   ;scale down for mod-4 packing
        add     esi,eax                 ;= VGA mode-x index x0 + y0 * 320

        ASSUME  FS:_DATA

        push    ds                      ;save local DS
        push    es                      ;save global ES
        push    fs                      ;save FS
        mov     ax,ds
        mov     fs,ax                   ;use FS for local data selector
        mov     ax,es
        mov     es,dx                   ;transfer destination ES
        mov     ds,ax                   ;set global video source DS
        cld                             ;auto-increment ESI, EDI
        mov     ebx,3                   ;mod-4 incrementer

        mov	dx,03CEh	        ;VGA read map mask reg
	mov	al,04h                  ;map mask index
        out     dx,al
        inc     edx

	mov	eax,ecx
	shr	eax,16			;unpack yd for number of lines
	movzx	ecx,cx			;unpack xd for size of lines

        ALIGN   4

lloop6: push	eax			;save yd line counter
	push 	ecx			;save xd block size counter per line
        push	esi			;save source pointer per line
	push    edi                     ;save destination pointer per line

        shr	ecx,2			;scale down for mod-4 4x counting

        mov     al,00h                  ;select VGA plane #1
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        ALIGN   4
lxf16:  movsb                           ;transfer
        add     edi,ebx                 ;destination +=4
        dec     ecx
        jnz     lxf16
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,01h                  ;select VGA plane #2
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        inc     edi                     ;adjust destination for 1,5,9,...
        ALIGN   4
lxf26:  movsb                           ;transfer
        add     edi,ebx                 ;destination +=4
        dec     ecx
        jnz     lxf26
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,02h                  ;select VGA plane #3
        out     dx,al

        push    esi                     ;save source address
        push    edi                     ;save destination address
        push    ecx                     ;save mode-x byte counter
        inc     edi                     ;adjust destination for 2,6,10,...
        inc     edi
        ALIGN   4
lxf36:  movsb                           ;transfer
        add     edi,ebx                 ;destination +=4
        dec     ecx
        jnz     lxf36
        pop     ecx                     ;restore counter
        pop     edi                     ;restore destination
        pop     esi                     ;restore source

        mov     al,03h                  ;select VGA plane #4
        out     dx,al

        inc     edi                     ;adjust destination for 3,7,11,...
        inc     edi
        inc     edi
        ALIGN   4
lxf46:  movsb                           ;transfer
        add     edi,ebx                 ;destination +=4
        dec     ecx
        jnz     lxf46

        pop     edi                     ;restore destination pointer
        pop	esi                     ;restore source pointer
	pop     ecx                     ;restore linear xd
	mov	eax,fs:[_svr_pixels_width]	;non-contiguous pixels ?
	or	eax,eax
        jnz	addx6                   ;non-contiguous pixels width ?
	mov	eax,ecx                 ;contiguous xd width
addx6:	add	edi,eax			;update destination by xd or 320
        add     esi,80                  ;update video source by mod-4 320
	pop	eax			;restore line counter
	dec	eax			;update line count
	jnz	lloop6			;repeat for all lines

        pop     fs                      ;restore FS
        pop     es                      ;restore global ES
        pop     ds                      ;restore local DS
        jmp     exit6

        ASSUME  FS:nothing

        ALIGN   4

exit6:
	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

err6:
	mov	eax,SVR_ERROR
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #7
; int xSVRDos32GetRegistration (void);
;	parm	[]	\
;	value	[eax]	\

        ALIGN   4

fn7:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	mov	eax,[svr_active]	;get page-flipping active flag
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #8
; int xSVRDos32SetRegistration (BOOL active);
;	parm	[eax]	\
;	value	[eax]	\

        ALIGN   4

fn8:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	cmp	eax,[svr_active]	;redundant call ?
	je	err8

	mov	[svr_active],eax	;set page-flipping active flag
	or	eax,eax			;turn page-flipping on ?
	jz	dis8
en8:
IF USE_OEMCODE AND USE_OEMONLY
	mov     eax,[_svr_OEM_support]	;any OEM chipset IO ?
	or	eax,eax
	jnz	go8			;then no registration lines
ENDIF

IF USE_VESA
        mov     ebx,dword ptr [_pVI]    ;get ptr to VESA info block
        mov     eax,dword ptr [ebx+10]  ;get VESA Capabilities field
        test    eax,0008h               ;board has stereo sync signal output ?
        jnz     go8                     ;then no registration lines
ENDIF

        mov     eax,[_svr_line_alternate]       ;line-alternate mode ?
        or      eax,eax
        jnz     alt8

	; draw black and white registration code lines in all 4 video pages
        mov     eax,[_xres]             ;get visible scan line width
IF USE_VESA
        cmp     [_VESA_active],0        ;VESA mode ?
        jne     @en8a
ENDIF
        shr     eax,2                   ;save as mode-X quads
@en8a:  mov     [svr_4quarter],eax
        shr     eax,2                   ;quarter it
        mov     [svr_quarter],eax
        mov     ebx,eax
        add     eax,ebx                 ;+ quarter
        add     eax,ebx                 ;+ quarter
        mov     [svr_3quarter],eax      ;= 3 quarters

	mov	eax,0			;1st page
        mov     ebx,[_imax]             ;index last line
	mov	ecx,[svr_quarter]       ;1st quarter line
	mov	edx,[svr_white]		;white
	FILL_PIXELS4
	mov	eax,0			;1st page
	mov     ebx,[_imax]             ;index last line
        add     ebx,[svr_quarter]
        mov     ecx,[svr_3quarter]      ;2nd 3 quarters line
	mov	edx,[svr_black]		;black
	FILL_PIXELS4

	mov	eax,1			;2nd page
        mov     ebx,[_iright_front]     ;index 2nd page
	add     ebx,[_imax]             ;index last line
        mov	ecx,[svr_3quarter]      ;1st 3 quarters line
	mov	edx,[svr_white]		;white
	FILL_PIXELS4
	mov	eax,1			;2nd page
	mov     ebx,[_iright_front]     ;index 2nd page
	add     ebx,[_imax]             ;index last line
        add     ebx,[svr_3quarter]
        mov	ecx,[svr_quarter]	;4th quarter line
	mov	edx,[svr_black]		;black
	FILL_PIXELS4

	mov	eax,2			;3rd page
	mov     ebx,[_ileft_back]       ;index 3rd page
	add     ebx,[_imax]             ;index last line
        mov	ecx,[svr_quarter]	;1st quarter line
	mov	edx,[svr_white]		;white
	FILL_PIXELS4
	mov	eax,2			;3rd page
	mov     ebx,[_ileft_back]       ;index 3rd page
	add     ebx,[_imax]             ;index last line
        add     ebx,[svr_quarter]
        mov	ecx,[svr_3quarter]	;2nd 3 quarters line
	mov	edx,[svr_black]		;black
	FILL_PIXELS4

	mov	eax,3			;4th page
	mov     ebx,[_iright_back]      ;index 4th page
	add     ebx,[_imax]             ;index last line
        mov	ecx,[svr_3quarter]	;1st 3 quarters line
	mov	edx,[svr_white]		;white
	FILL_PIXELS4
	mov	eax,3			;4th page
	mov     ebx,[_iright_back]      ;index 4th page
	add     ebx,[_imax]             ;index last line
        add     ebx,[svr_3quarter]
        mov	ecx,[svr_quarter]	;4th quarter line
	mov	edx,[svr_black]		;black
	FILL_PIXELS4
        jmp     go8

alt8:	; draw black and white registration code lines for line-alt video pages
	mov	eax,0			;1st page
	mov     ebx,[_imax]             ;index last line
	mov	ecx,[svr_quarter]	;1st quarter line
	mov	edx,[svr_white]		;white
	FILL_PIXELS4
	mov	eax,0			;1st page
	mov     ebx,[_imax]             ;index last line
        add     ebx,[svr_quarter]
        mov	ecx,[svr_3quarter]	;2nd 3 quarters line
	mov	edx,[svr_black]		;black
	FILL_PIXELS4

	mov	eax,0			;1st page
	mov     ebx,[_imax]             ;index last line
        add     ebx,[svr_4quarter]      ;past reg line
	mov	ecx,[svr_3quarter]	;1st 3 quarters line
	mov	edx,[svr_white]		;white
	FILL_PIXELS4
	mov	eax,0			;1st page
	mov     ebx,[_imax]             ;index last line
        add     ebx,[svr_4quarter]      ;past reg line
        add     ebx,[svr_3quarter]
	mov	ecx,[svr_quarter]	;4th quarter line
	mov	edx,[svr_black]		;black
	FILL_PIXELS4

	mov	eax,2			;3rd page
	mov     ebx,[_ileft_back]       ;index 3rd page
	add     ebx,[_imax]             ;index last left line
        mov	ecx,[svr_quarter]	;1st quarter line
	mov	edx,[svr_white]		;white
	FILL_PIXELS4
	mov	eax,2			;3rd page
	mov     ebx,[_ileft_back]       ;index 3rd page
	add     ebx,[_imax]             ;index last left line
        add     ebx,[svr_quarter]
        mov	ecx,[svr_3quarter]	;2nd 3 quarters line
	mov	edx,[svr_black]		;black
	FILL_PIXELS4

	mov	eax,2			;3rd page
	mov     ebx,[_ileft_back]       ;index 3rd page
	add     ebx,[_imax]             ;index last line
        add     ebx,[svr_4quarter]      ;index last right line
        mov	ecx,[svr_3quarter]	;1st 3 quarters line
	mov	edx,[svr_white]		;white
	FILL_PIXELS4
	mov	eax,2			;3rd page
	mov     ebx,[_ileft_back]       ;index 3rd page
	add     ebx,[_imax]             ;index last line
        add     ebx,[svr_4quarter]      ;index last right line
        add     ebx,[svr_3quarter]
        mov	ecx,[svr_quarter]	;4th quarter line
	mov	edx,[svr_black]		;black
	FILL_PIXELS4

go8:
IF USE_OEMCODE
        call    _InitOEM_               ;enable auto-flipping OEM
        jnz     exit8                   ;auto-flipping hardware ?
ENDIF
IF USE_LCDBIOS
	call	_EnableLcdbios32_	;enable auto-flipping ISR
ELSE
	call	xEnableAutoStereo_	;enable auto-stereo ISR
ENDIF

	jmp	exit8
dis8:
IF USE_LCDBIOS
	call	_DisableLcdbios32_	;disable auto-flipping ISR
ELSE
	call	xDisableAutoStereo_	;disable auto-stereo ISR
ENDIF
IF USE_OEMCODE
        call    _ExitOEM_               ;disable auto-flipping OEM
ENDIF

exit8:
	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

err8:
	mov	eax,SVR_ERROR
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #9
; int xSVRDos32SetBlackCode (BYTE color);
;	parm	[al]	\
;	value	[eax]	\

        ALIGN   4

fn9:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	movzx	eax,al			;get 8-bit black color
	mov	[svr_black],eax		;save black palette entry
	mov	bx,0000h		;set min red
	mov	cx,0000h		;set min green + blue
	mov	bl,al			;set palette index
	call	xSetPaletteColor_	;set the palette color to black

	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #10
; int xSVRDos32SetWhiteCode (BYTE color);
;	parm	[al]	\
;	value	[eax]	\

        ALIGN   4

fn10:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	movzx	eax,al			;get 8-bit white color
	mov	[svr_white],eax		;save white palette entry
IF USE_BLUELINE
	mov	bl,0
	mov	bh,BLUE_R		;set red
	mov	cl,BLUE_G		;set green
	mov	ch,BLUE_B		;set blue
ELSE
	mov	bx,3F00h		;set max red
	mov	cx,3F3Fh		;set max green + blue
ENDIF
	mov	bl,al			;set palette index
	call	xSetPaletteColor_	;set the palette color to white

	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #11
; int xSVRDos32Sync(void);
;	parm	[]	\
;	value	[eax]	\

        ALIGN   4

fn11:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	call	xWaitVSync_		;wait for vertical sync
	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #12
; int xSVRDos32SetTimerEmulation (BOOL active);
;	parm	[eax]	\
;	value	[eax]	\

        ALIGN   4

fn12:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	mov	[svr_softimer],eax	;save timer emulation state

	mov	eax,[svr_softimer]	;real or emulated timeouts ?
	or	eax,eax
	jz	tmr12
emu12:
	mov	eax,SVR_EMU		;set emulated timeout technique
	mov	[_svr_technique],eax
	jmp	set12
tmr12:
	mov	eax,SVR_TMR		;set real timeout technique
	mov	[_svr_technique],eax
	call	xTMR_Init_		;install timer ISR now...
set12:
	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #13
; int xSVRDos32GetTimerRate (void);
;	parm	[]	\
;	value	[eax]	\

        ALIGN   4

fn13:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	mov	eax,[_svr_timerate]	;get timer rate
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #14
; int xSVRDos32SetTimerRate (int rate);
;	parm	[eax]	\
;	value	[eax]	\

        ALIGN   4

fn14:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	mov	[_svr_timerate],eax	;save timer rate
	call	xTMR_Adjust_		;adjust timer rate now...

	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #15
; int xSVRDos32GetTimerCallbackIn (void far * *callbackfn);
;	parm	[cx ebx]\
;	value	[eax]	\

        ALIGN   4

fn15:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	mov	eax,[svr_softimer]	;real or emulated timeouts ?
	or	eax,eax
	jz	tmr15
emu15:
	lea	eax,xEMU_ISR_		;set ISR address for emulated timeouts
	mov	dx,cs
	mov	DWORD PTR[_svr_pcallin],eax
	mov	WORD  PTR[_svr_pcallin+4],dx
	jmp	get15
tmr15:
	lea	eax,xTMR_ISR_		;set ISR address for real timeouts
	mov	dx,cs
	mov	DWORD PTR[_svr_pcallin],eax
	mov	WORD  PTR[_svr_pcallin+4],dx
get15:
	mov	eax,DWORD PTR[_svr_pcallin]	;get callback input pointer
	mov	dx,WORD PTR[_svr_pcallin+4]	;+ selector
	push	es
	mov	es,cx			;use destination selector
	mov	es:[ebx],eax		;transfer pointer offset
	mov	es:[ebx+4],dx		;transfer pointer selector
	pop	es

	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #16
; int xSVRDos32SetTimerCallbackOut (void far * callbackfn);
;	parm	[cx ebx]\
;	value	[eax]	\

        ALIGN   4

fn16:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	mov	DWORD PTR[_svr_pcallout],ebx	;save callback output pointer
	mov	WORD PTR[_svr_pcallout+4],cx	;+ selector
	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #17
; int xSVRDos32SetOptions (SVRDos32Option_t FAR * _SVR_option);
;	parm	[cx ebx]\
;	value	[eax]	\
;	modify	[eax ebx ecx edx esi edi];

        ALIGN   4

fn17:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	push	es			;save local DS
	push	ds
	lea	edi,SVR_PTR_OPTIONS	;init destn address pointer at 1st option
	mov	dx,ds
	mov	es,dx			;use local selector
	mov	esi,ebx			;load caller address source
	mov	ds,cx			;load caller selector
	mov	ecx,SVR_NUM_OPTIONS	;number of options
        cld
	rep	movsd			;copy options from caller
	pop	ds			;restore local DS
	pop	es

        call    xSetGraphLimits_        ;re-size limits if format change
        call    xSetGraphPages_         ;re-configure video pages too

IF USE_LCDBIOS
	call	_SetLcdbiosOptions_	;set LCDBIOS options
ELSE
	call	xTMR_Adjust_		;update timer data now...
ENDIF

	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #18
; int xSVRDos32GetOptions (SVRDos32Option_t FAR * _SVR_option);
; 	parm	[cx ebx]\
;	value	[eax]	\
;	modify	[eax ebx ecx edx esi edi];

        ALIGN   4

fn18:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

IF USE_LCDBIOS
	pusha
	call	_GetLcdbiosOptions_	;get LCDBIOS run-time options
	popa
ENDIF

	push	es
	mov	edi,ebx			;load caller address destination
	mov	es,cx			;load caller selector
	lea	esi,SVR_PTR_OPTIONS	;init source address pointer at 1st option
	mov	ecx,SVR_NUM_OPTIONS	;number of options
	rep	movsd			;copy options from SVR
        cld
	pop	es

	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #19
; int xSVRDos32ShowImages(void);
;	parm	[]	\
;	value	[eax]	\

        ALIGN   4

fn19:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	;switch visible/non-visible pair of left/right flipping pages
	mov	eax,[svr_page]		;get effective page number
	cmp	al,2			;low pages 0 or 1 ?
	jnc     hi19                    ;high pages 2 or 3 ?
lo19:	mov	[_svr_visiblepage],ax	;switch to lower active page pair
IF USE_LCDBIOS
	call	_LowPageLcdbios32_	;switch to low visible page pair in ISR
ENDIF
IF USE_OEMCODE
        call    _UpdateOEM_             ;update OEM page-flipping
ENDIF
        mov     al,2                    ;switch to high non-visible page too
        movzx   eax,al
        mov     [svr_page],eax

	jmp	vis19

        ALIGN   4

hi19:   mov	[_svr_visiblepage],ax	;switch to higher active page pair
IF USE_LCDBIOS
	call	_HighPageLcdbios32_	;switch to high visible page pair in ISR
ENDIF
IF USE_OEMCODE
        call    _UpdateOEM_             ;update OEM page-flipping
ENDIF
        mov     al,0                    ;switch to low non-visible page too
        movzx   eax,al
        mov     [svr_page],eax

        ALIGN   4
vis19:
        mov     eax,[svr_active]        ;page-flipping active ?
        or      eax,eax
        jnz     exit19

        mov     bx,[_svr_visiblepage]
        and     bl,02h                  ;default to left page 0 or 2
IF USE_VESA
        cmp     [_VESA_active],0        ;VESA mode ?
        je      vis19x
        call    xDisplayVesaPage_       ;if not flipping, display VESA page now
        jmp     exit19
vis19x:
ENDIF
        call    xSelectDisplayPage_     ;if not flipping, display mode-X page now

        ALIGN   4

exit19:
	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #20
; int xSVRDos32ClearImages(void);
;	parm	[]	\
;	value	[eax]	\

        ALIGN   4

fn20:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

        mov     eax,[_svr_line_alternate]       ;line-alternate format ?
        or      eax,eax
        jnz     alt20

        mov     eax,[svr_halfed]                ;half-resolution format ?
        or      eax,eax
        jnz     half20

        cmp     [_svr_visiblepage],2    ;low pages 0 or 1 visible ?
        jc      hi20                    ;then clear high pages 2 and 3

lo20:   mov	eax,0			;1st page
	mov	ebx,[_ileft_front]      ;1st line
	mov     ecx,[_imax]             ;index last line
	mov	edx,[svr_black]		;black
        FILL_PIXELS4

	mov	eax,1			;2nd page
	mov	ebx,[_iright_front]     ;1st line
	mov     ecx,[_imax]             ;index last line
	mov	edx,[svr_black]		;black
        FILL_PIXELS4
        jmp     exit20

        ALIGN   4

hi20:   mov	eax,2			;3rd page
        mov	ebx,[_ileft_back]       ;1st line
	mov     ecx,[_imax]             ;index last line
	mov	edx,[svr_black]		;black
        FILL_PIXELS4

	mov	eax,3			;4th page
	mov	ebx,[_iright_back]      ;1st line
	mov     ecx,[_imax]             ;index last line
	mov	edx,[svr_black]		;black
        FILL_PIXELS4
        jmp     exit20

        ALIGN   4

half20: ; clear half-sized image areas on same full-sized page
        cmp     [_svr_visiblepage],2    ;low pages 0 or 1 visible ?
        jc      hhi20                   ;then clear high pages 2 and 3

hlo20:  mov	eax,0			;1st page
	mov	ebx,[_ileft_front]      ;1st line
	mov     ecx,[_imax]             ;index last line
	mov	edx,[svr_black]		;black
        FILL_PIXELS4

	mov	eax,0			;1st page too
	mov	ebx,[_iright_front]     ;1st right line
	mov     ecx,[_imax]             ;index last line
	mov	edx,[svr_black]		;black
        FILL_PIXELS4
        jmp     exit20

        ALIGN   4

hhi20:  mov	eax,2			;3rd page
        mov	ebx,[_ileft_back]       ;1st line
	mov     ecx,[_imax]             ;index last line
	mov	edx,[svr_black]		;black
        FILL_PIXELS4

	mov	eax,2			;3rd page too
	mov	ebx,[_iright_back]      ;1st right line
	mov     ecx,[_imax]             ;index last line
	mov	edx,[svr_black]		;black
        FILL_PIXELS4
        jmp     exit20

        ALIGN   4

alt20:  ; clear pages in line-alternate mode excluding last 2 lines
        cmp     [_svr_visiblepage],2    ;low pages 0 or 1 visible ?
        jc      ahi20                   ;then clear high pages 2 and 3

alo20:  mov	eax,0			;1st page
	mov	ebx,[_ileft_front]      ;1st line
	mov     ecx,[_imax]             ;index last composite line
	mov	edx,[svr_black]		;black
        FILL_PIXELS4
        jmp     exit20

        ALIGN   4

ahi20:  mov	eax,2			;3rd page
	mov	ebx,[_ileft_back]       ;1st line
	mov     ecx,[_imax]             ;index last composite line
	mov	edx,[svr_black]		;black
        FILL_PIXELS4
        jmp     exit20

        ALIGN   4

exit20:
	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #21
; extern int xSVRDos32SetFlip (BOOL active, BOOL mode);
;	parm	[ebx] [ecx]	\
;	value	[eax]	\
;	modify	[eax ebx ecx edx esi edi];


        ALIGN   4

fn21:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

        mov     eax,ebx
	cmp	eax,[svr_active]	;redundant call ?
	je	err21

	mov	[svr_active],eax	;set page-flipping active flag
	or	eax,eax			;turn page-flipping on ?
	jz	dis21
en21:
IF USE_OEMCODE
        call    _InitOEM_               ;enable auto-flipping OEM
        jnz     exit21                  ;auto-flipping hardware ?
ENDIF
	push    es
        mov     ES,word ptr[_lp_rm_data+4]      ;get ISR data selector
	mov	EDI,dword ptr[_lp_rm_data]	;get ISR data offset
        mov     dword ptr ES:[EDI+D_vesaMode],ecx      ;set VGA / VESA mode
	call	_EnableLcdbios32_	;enable auto-flipping ISR
        pop     es

	jmp	exit21

dis21:
	call	_DisableLcdbios32_	;disable auto-flipping ISR
IF USE_OEMCODE
        call    _ExitOEM_               ;disable auto-flipping OEM
ENDIF

exit21:
	mov	eax,SVR_OK
	pop	ds                      ;restore caller DS
	retf

err21:
	mov	eax,SVR_ERROR
	pop	ds                      ;restore caller DS
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #22

; extern int xSVRDos32UpdateFlip (PBYTE left, PBYTE right);
; 	parm	[ebx] [ecx]	\
;	value	[eax]	\
;	modify	[eax ebx ecx edx esi edi];

        ALIGN   4

fn22:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

	push    es
        mov     ES,word ptr[_lp_rm_data+4]
	mov	EDI,dword ptr[_lp_rm_data]	;get data offset
	cli                                     ;transfer display pointers
	mov	dword ptr ES:[EDI+D_startLeftX],ebx
	mov	dword ptr ES:[EDI+D_startRightX],ecx
	sti
        pop     es

IF USE_OEMCODE
        call    _UpdateOEM_             ;update OEM page-flipping
ENDIF

	mov	eax,SVR_OK
        pop     ds
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #23


; extern int xSVRDos32SetCallback (VOID FAR * lpCallback);
; 	parm	[cx ebx]\
; 	value	[eax]	\
; 	modify	[eax ebx ecx edx esi edi];

        ALIGN   4

fn23:
	push	ds			;save caller DS
	mov	dx,cs			;get driver CS
	mov	ds,dx			;use as read-only DS
	mov	edx,[_svr_dsel]		;get driver DS
	mov	ds,dx			;use as read/write DS

        push    es
        mov     ES,word ptr[_lp_rm_data+4]
	mov	EDI,dword ptr[_lp_rm_data]	;get data offset
	cli                                     ;transfer external callback
	mov	dword ptr ES:[EDI+D_pm_external],ebx
	mov	word ptr ES:[EDI+D_pm_external+4],cx
	sti
        pop     es

	mov	eax,SVR_OK
        pop     ds
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #24

        ALIGN   4

fn24:
	mov	eax,SVR_ERROR		;not supported
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #25

        ALIGN   4

fn25:
	mov	eax,SVR_ERROR		;not supported
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #26

        ALIGN   4

fn26:
	mov	eax,SVR_ERROR		;not supported
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #27

        ALIGN   4

fn27:
	mov	eax,SVR_ERROR		;not supported
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #28

        ALIGN   4

fn28:
	mov	eax,SVR_ERROR		;not supported
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #29

        ALIGN   4

fn29:
	mov	eax,SVR_ERROR		;not supported
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #30

        ALIGN   4

fn30:
	mov	eax,SVR_ERROR		;not supported
	retf

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; function #31

        ALIGN   4

fn31:
	mov	eax,SVR_ERROR		;not supported
	retf

_CODE	ENDS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	END	MAIN
