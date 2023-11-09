;   LCDBIOS -- LCD glasses driver with partial emulation of 3D-BIOS
;
;   version 1.20x
;   written by Donald Sawdai, 10/95
;   copyright 1995 Donald Sawdai
;
; This source code, or any modification of it, may *only* be distributed by
; Donald Sawdai (the author) or a source code sublicenser directly authorized
; by Donald Sawdai.  For any other user, this source code must be kept
; internal and confidential by the user or the user's company.  Any licensed
; user of this source code may freely distribute any compiled executibles
; incoporating part or whole of this source code to end users.  Any
; modification of this source code must include the copyright notice and
; this licensing paragraph.
;

;** Modified for use with SVRDOS4G protected-mode driver.
;** Modified 1/96 by DaveM for StereoGraphics.
;** Refer to LCDBIOS32.ASM for complete v1.20 modification history.

;** LCDBIOS v1.21.d3 for bi-modal real- and protected-mode drivers;
;** Data references must use numerical offset aliases for relocatable code;
;** Use EDI for base of relocatable data addresses, ie [EDI+D_boostRefresh];

;** LCDBIOS v1.21.d4 for minimal ISR functionality.
;** Only INT 70 real-time clock ISR is used.
;** INT 10 video extension and INT 1C DOS ticker double-checker are not used.

;** LCDBIOS v1.21.d5 for OEM custom chipset support.

;** LCDBIOS v1.21.d9 optimzed for 32-bit data access.
;** Converted all WORD data to DWORD size;
;** Referenced all flag and mode data items as BYTE PTR type;


USE_LCDBIOS16	EQU	0	;1 = original 16-bit code; 0 = 32-bit code

USE_VIDEO_BIOS	EQU	0	;use INT 10 video BIOS for LCD enable ?
USE_DOS_TICKER	EQU	0	;use INT 1C DOS ticker for watchdog ?

USE_DATA_SYMBOL	EQU	0	;use original symbol references for data

DATA_START	EQU	0800h	;offset for locating start of relocatable data

USE_ISR         EQU     1       ;use code in ISR
USE_ISR_DEBUG   EQU     0       ;use debug code for PC speaker in ISR
USE_ISR_TRACE   EQU     0       ;use debug trace log in ISR

USE_PM_JMPTBL   EQU     1       ;use indexed jump table in ISR
USE_RM_JMPTBL   EQU     0       ;use indexed jump table in real-mode ISR

USE_OEM         EQU     1       ;use OEM hardware code in ISR

USE_TICK_ADJUST EQU     0       ;use flip tick counter adjustment

USE_LEAN_MEAN   EQU     0       ;use immediate page-flip upon sync detection

USE_VESA_BIOS   EQU     1       ;use VESA 2.0 protected-mode interface

USE_ROM_BASIC   EQU     0       ;steal an unused auto-passup interrupt vector

INTR_VESA2      EQU     2Ch     ;unused auto-passup vector for VESA 2.0 call
INTR_BASIC      EQU     18h     ;unused auto-passup vector for re-load call

USE_NEAR_CALLBACK EQU   1       ;use near callback shell for external driver


	.386P
	.MODEL	FLAT

	INCLUDE SVRDEF.INC	;SVRDOS32 loadable driver global defs
	INCLUDE SVRDOS32.INC	;SVRDOS32 interface
	INCLUDE LCDBIOS.INC	;LCDBIOS global symbol and data alias defs
        INCLUDE MODEX32.INC     ;MODEX32 interface
	INCLUDE	OEM32.INC	;OEM32 interface


; Macro RTC_CLEAR:
;   Clears any pending interrupt of the RTC by reading CMOS register C.
;   Destroys the contents of AX and DX.
RTC_CLEAR MACRO
	LOCAL @rtc1
	mov     dx,CMOS_ADDR
	mov     al,0ch
	out     dx,al
	inc     dx
	IODELAY
        IODELAY
	in      al,dx
ENDM


; Macro VERT_RETRACE_CLEAR:
;   Clears the vertical retrace interrupt bit of the VGA.  After clearing,
;    it also re-enalbes the vertical retrace interrupt.  Note that the IRQ
;    is not enabled, so it does not fire.  However, upon vertical retrace,
;    the retrace bit is set, and it can only be cleared by the code below.
;   Destroys the contents of AX, BL, and DX.
VERT_RETRACE_CLEAR MACRO
	mov     dx,CRTC_ADDR
	in      al,dx           ; save old CRTC index
	mov     bl,al

	mov     ax,word ptr [EDI+D_clearVertInt]
	out     dx,ax           ; clear vertical interrupt

	mov     ax,word ptr [EDI+D_setVertInt]
	out     dx,ax           ; turn on vertical interrupt for next retrace

	mov     al,bl
	out     dx,al           ; reset old CRTC Index
ENDM

VERT_RETRACE_CLEAR_16	MACRO
	mov     dx,CRTC_ADDR
	in      al,dx           ; save old CRTC index
	mov     bl,al

	mov     ax,word ptr [DI+D_clearVertInt]
	out     dx,ax           ; clear vertical interrupt

	mov     ax,word ptr [DI+D_setVertInt]
	out     dx,ax           ; turn on vertical interrupt for next retrace

	mov     al,bl
	out     dx,al           ; reset old CRTC Index
ENDM


;;** Data from SVRDOS32 loadable driver used by LCDBIOS
;;** to distinguish real- and protected-mode ISRs.
;;** Both ISRs use same data block in real-mode memory.

_DATA segment dword public use32 'DATA'

	extrn	_lp_rm_isr:FWORD
	extrn	_lp_rm_data:FWORD

_DATA ends


_CODE	segment dword public use32 'CODE'

	assume	nothing
	assume  cs:_CODE

;;** Add data selector variables within code segment for CS/DS management;
;;** Selectors available as read-only data in code segment;
;;** but alias selector allows read-write data (presto-changeo);

;;** Dont forget the 0100h COM file offset between code and data addresses!
;;** (SVRDOS32 loadable driver is generated in COM file format.)

_codesel:	dw	?	;code selector (just because)
_aliasel:	dw	?	;code selector alias
_datasel:	dw	?	;data selector for ISR
_dataoff:	dd	?	;data offset for ISR

;;** Add initialization routine to set up CS/DS management;
;;** Install LCDBIOS ISR selector info for external set-up;

	public	_InitLcdbios32_
	public	_ExitLcdbios32_

_InitLcdbios32_	proc	near

	assume  cs:_CODE
	assume	ds:_DATA	;loadable driver DS
	assume	es:_CODE	;local data within CS code space

	mov	ax,000Ah	;DPMI alias selector function
	mov	bx,cs		;present code selector
	int	31h		;presto changeo...
	jc	initerr

	; make a read/write selector alias to plant data in code space
	push	ds
	mov	dx,ds           ;save caller DS
	push	es
	mov	es,ax		;allow read/write DS within CS
	mov	word ptr es:[_aliasel],ax
        mov     cx,word ptr ds:[_lp_rm_isr+4]   ;get flat CS
        mov	word ptr es:[_codesel],cx
	mov	dx,word ptr ds:[_lp_rm_data+4]	;get flat DS
	mov	word ptr es:[_datasel],dx
	mov	eax,DWORD ptr ds:[_lp_rm_data]	;get real-mode data offset
	mov	dword ptr es:[_dataoff],eax
	pop	es
	pop	ds

	; make read-only selector again
	mov	ax,0001h	;DPMI free selector function
	mov	bx,cs:word ptr[_aliasel]
	int	31h

        ; set up external callback function, if any
        call    _InitCallback32_

	ret

initerr:
	ret

_InitLcdbios32_	endp

;;** Add exit routine for external shut-down;
;;** (Nothing to do.)

_ExitLcdbios32_	proc	near

        call    _ExitCallback32_        ; remove exteranl callback function
	ret

_ExitLcdbios32_	endp

;;** Add external callback hooks for real- and protected-mode handlers.
;;** Use unused auto-passup interrupt for real-mode service.

	public	_InitCallback32_
	public	_ExitCallback32_
        public  _ExternalCallback32_
	public	_InitPassup32_
	public	_ExitPassup32_

_InitCallback32_	proc	near

	assume nothing
	assume cs:_CODE

        push    ds
        lea     ebx,_ExternalCallback32_        ; point to external function
        mov     ds,word ptr cs:[_datasel]
        mov     edi,dword ptr cs:[_dataoff]
        mov     dword ptr [EDI+D_pm_setxy],ebx

        call    _InitPassup32_                  ; set auto-passup interrupt
        pop     ds

IF USE_NEAR_CALLBACK
        assume  ds:_DATA

        push    es
        mov     es, word ptr ds:[_lp_rm_data+4] ; data selector for transfer
        mov     eax, dword ptr ds:[_lp_rm_isr]  ; code offset in ISR buffer
        add     eax, DATA_START-0100h           ; locate callback routine
        mov     edi, eax
        lea     esi, _ExternalCallback48_
        lea     ecx, _ExternalCallback48end_
        sub     ecx, esi
        rep     movsb                           ; copy into real-mode ISR buffer
        pop     es
ENDIF

        ret

_InitCallback32_	endp

_ExitCallback32_	proc	near

	assume nothing
	assume cs:_CODE

        push    ds
        xor     ebx,ebx                         ; no external function
        mov     ds,word ptr cs:[_datasel]
        mov     edi,dword ptr cs:[_dataoff]
        mov     dword ptr [EDI+D_pm_setxy],ebx

        call    _ExitPassup32_                  ; restore auto-passup
        pop     ds

        ret

_ExitCallback32_	endp

_ExternalCallback32_	proc	far

	assume nothing
	assume cs:_CODE

        pushad
        push    ds
        push    es
        push    fs
        push    gs

IF USE_NEAR_CALLBACK
        mov     DS,word ptr CS:[_datasel]	; get data selector DS
	mov	EDI,dword ptr CS:[_dataoff]	; get data offset

        mov     ax,cs
        movzx   eax,ax
        push    eax                             ; return CS
        lea     eax,retback
        push    eax                             ; return offset

        mov     ax,word ptr CS:[_codesel]
        movzx   eax,ax
        push    eax                             ; call CS
        mov     eax, edi
        sub     eax, 0100h
        push    eax                             ; call offset
        retf                                    ; call far ...
retback:
ELSE
        mov     DS,word ptr CS:[_datasel]	; get data selector DS
	mov	EDI,dword ptr CS:[_dataoff]	; get data offset

        call    fword ptr [EDI+D_pm_external]   ; call far external function
ENDIF
        pop     gs
        pop     fs
        pop     es
        pop     ds
        popad
        iretd

_ExternalCallback32_    endp

_ExternalCallback48_	proc	far

	assume nothing

        call    dword ptr [EDI+D_pm_external]   ; call near external function
        retf                                    ; return far

_ExternalCallback48end_:dd      0

_ExternalCallback48_    endp

_InitPassup32_	proc	near

	assume nothing
	assume cs:_CODE

	; save old interrupt vector for unused auto-passup interrupt
        push    es
        push    edi
	mov	al,INTR_VESA2
	mov	ah,35h
	int	21h
        pop     edi
	mov     dword ptr [EDI+D_old_passup+0],ebx
	mov     word ptr [EDI+D_old_passup+4],es
        pop     es

	; set new interrupt vector for auto-passup interrupt
	push 	ds
	lea	edx,_ExternalCallback32_
	mov	bx,cs
	mov	ds,bx
	mov	al,INTR_VESA2
	mov	ah,25h
	int	21h
	pop	ds

        ret

_InitPassup32_	endp

_ExitPassup32_	proc	near

	assume nothing
	assume cs:_CODE

	; restore original interrupt vector for auto-passup interrupt
	mov	edx,dword ptr [EDI+D_old_passup+0]
	mov	bx,word ptr [EDI+D_old_passup+4]
	push	ds
	mov	ds,bx
	mov	al,INTR_VESA2
	mov	ah,25h
	int	21h
	pop	ds

        ret

_ExitPassup32_	endp

;;** Add direct access routines to enable and disable stereo flipping;
;;** That is, there is no need to use calls to video BIOS extensions;

	public	_EnableLcdbios32_
	public	_DisableLcdbios32_

_EnableLcdbios32_	proc	near

	assume nothing
	assume cs:_CODE
        assume ES:_DATA

	push	ds
	push	es
	mov	dx,ds
	mov	es,dx
	mov	EDI,cs:dword ptr[_dataoff]	;get data offset
	mov	DS,cs:word ptr[_datasel]	;+ selector

        ; determine if line-alternate or half-resolution format
        ; line-alt format has precedence over half-res only format
        cmp     BYTE ptr ES:[svr_halfed],0             ; half-res mode ?
        je      enalt
        mov     BYTE ptr [EDI+D_stereoMode],4          ; half-res only

enalt:	cmp     BYTE ptr ES:[_svr_line_alternate],0    ; line-alt mode ?
        je      enfull
        mov     BYTE ptr [EDI+D_stereoMode],3          ; line-alt half-res
enfull:

	; cut-n-paste from...
	; @LCDBl01: ; BL = 01h : enter 3D mode
	cmp     BYTE ptr [EDI+D_mode],0
	jne	enerr			; fail: LCDBios already on

        ; okay to turn on LCDBIOS 3D mode
	cli                             ; disable interrupts

	mov     dx,CRTC_ADDR
	in      al,dx                   ; save old CRTC index
	mov     byte ptr [EDI+D_saveCRTCIndex],al

        cmp     BYTE ptr [EDI+D_stereoMode],0          ; line-alt / half-res ?
        je      enon

	call	_halfToFullScreen	; yes, so cut vert. resolution by 2

        cmp     BYTE ptr [EDI+D_stereoMode],4          ; half-res only ?
        je      enon

	call	_alternateToSolid       ; set up line-alternate addressing

enon:	call	_on3D                   ; turn on page-flipping

	mov     dx,CRTC_ADDR
	mov     al,byte ptr [EDI+D_saveCRTCIndex]
	out     dx,al		; restore saved CRTC index

	sti                             ; re-enable interrupts

IF USE_OEM
	; setup(s) for special LCD hardware IO
	mov	eax,ES:[_svr_OEM_support]	;transfer OEM code
	mov	dword ptr [EDI+D_svr_oem],eax
ENDIF

enexit:
	pop	es
	pop	ds
	ret
enerr:
	pop	es
	pop	ds
	ret

_EnableLcdbios32_	endp

;;** Disable stereo page-flipping.

_DisableLcdbios32_	proc	near

	assume nothing
	assume cs:_CODE

	push	ds
	mov	EDI,cs:dword ptr[_dataoff]	;get data offset
	mov	DS,cs:word ptr[_datasel]	;+ selector

	; cut-n-paste from...
	; @LCDBl02: ; BL = 02h : exit 3D mode
	cmp     BYTE ptr [EDI+D_mode],0
	je      disexit                 ; fail: LCDBios already off

	; okay to turn LCDBios 3D mode off
	cli

	mov     dx,CRTC_ADDR
	in      al,dx				; save CRTC index
	mov     byte ptr [EDI+D_saveCRTCIndex],al

	call	_off3D                  ; turn off page-flipping

        cmp     BYTE ptr [EDI+D_stereoMode],0        ; line-alt / half-res ?
        je      disoff

        cmp     BYTE ptr [EDI+D_stereoMode],4        ; half-res only ?
        je      disalt

	call	_solidToAlternate       ; restore contiguous display
disalt:

	call	_fullToHalfScreen	; restore vert. resolution

        mov     BYTE ptr [EDI+D_stereoMode],0        ; not anymore

disoff:
	mov     dx,CRTC_ADDR
	mov     al,byte ptr [EDI+D_saveCRTCIndex]
	out     dx,al				; restore CRTC index

	RTC_CLEAR                       ; clear any RTC pending interrupt
	sti

disexit:
	pop	ds
	ret

diserr:
	pop	ds
	ret

_DisableLcdbios32_	endp

;;** Add direct access routines for switching low- and high-page pairs.

	public _LowPageLcdbios32_
	public _HighPageLcdbios32_

;;** Select VGA low-page address pair at 0000h & 4000h.
;;** Select VGA low-page address at 0000h for line-alternate mode.
;;** Page addresses are pre-buffered for flexible display format.
;;** VGA Mode-X indexes account for bytes / 4 planes.
;;** VESA indexes remain in bytes (not bytes / 4).

_LowPageLcdbios32_	proc near

	assume nothing
	assume cs:_CODE
        assume ES:_DATA

	push	ds
	push	es
	mov	dx,ds
	mov	es,dx
	mov	EDI,cs:dword ptr[_dataoff]	;get data offset
	mov	DS,cs:word ptr[_datasel]	;+ selector

	cli
        mov     eax,dword ptr ES:[_ileft_front] ; get front buffer pointers
        mov     ebx,dword ptr ES:[_iright_front]
	mov	dword ptr [EDI+D_startLeftX],eax
	mov	dword ptr [EDI+D_startRightX],ebx
        shr     eax,16
        shr     ebx,16
        mov     dword ptr [EDI+D_startLeftY],eax
        mov     dword ptr [EDI+D_startRightY],ebx
	sti

        pop     es
        pop     ds
	ret

_LowPageLcdbios32_	endp

;;** Select VGA high-page address pair at 8000h & C000h.
;;** Select VGA high-page address at 8000h for line-alternate mode.

_HighPageLcdbios32_	proc near

	assume nothing
	assume cs:_CODE
        assume ES:_DATA

        push    ds
	push	es
        mov     dx,ds
        mov     es,dx
	mov	EDI,cs:dword ptr[_dataoff]	;get data offset
	mov	DS,cs:word ptr[_datasel]	;+ selector

	cli
        mov     eax,dword ptr ES:[_ileft_back]  ; get back buffer pointers
        mov     ebx,dword ptr ES:[_iright_back]
	mov	dword ptr [EDI+D_startLeftX],eax
	mov	dword ptr [EDI+D_startRightX],ebx
	shr     eax,16
        shr     ebx,16
        mov     dword ptr [EDI+D_startLeftY],eax
        mov     dword ptr [EDI+D_startRightY],ebx
	sti

        pop     es
        pop     ds
	ret

_HighPageLcdbios32_	endp

;;** Original LCDBIOS routines follow...

	assume nothing
	assume cs:_CODE

_alternateToSolid	proc    near
; This procedure changes the screen from a line-alternate format to a full-
;   screen by doubling the width of the virtual screen buffer.  It does
;   not change the physical resolution of the screen in any way.  It then
;   stores the start addresses for both pages in the start* variables.
; Variables set: saveOffset (VGA only), screenWidth,
;   startLeftX, startLeftY (VESA only), startRightX, startRightY (VESA only)
; Registers altered: Offset (VGA only)
; VESA set calls: setWidth (VESA only)
; Note:  changes contents of CRTC index register
;	 interrupts should be disabled

	; check if we should set the screen for VESA or for VGA
	cmp     BYTE ptr [EDI+D_vesaMode],0   ; in vga mode?
	je      @altSolVGA
	jmp     @altSolVESA

@altSolVGA:
	; Double the virtual screen width, so that we have 2 side-by-side
	;  screens instead of one line-alternate screen.  To do this,
	;  double the value in the Offset register
	mov     dx,CRTC_ADDR
	mov     al,OFFR
	out     dx,al
	inc	dx
	in      al,dx			; save old Offset register
	mov     byte ptr [EDI+D_saveOffset],al

	; Note: Page width (CPU bytes) = (# CPU bytes/line)
	;            = Offset Register * K
	;	  K = 2 for EGA/VGA screen modes (byte addressing)
	;	  K = 4 for CGA emulation modes (word addressing)
	;	K is found from bit 6 (word/byte mode) of
	;	  CTRC register 17h (Mode Control Register)
	;	We could care less about CGA modes, and K=2 for VGA mode
	;	  13h (320x200x256, but word addressing is on), so just
	;	  assume K=2 always.
	mov	ah,0
	shl     ax,1			; x2 -> new Offset register value
	mov     word ptr [EDI+D_screenWidth],ax	; save page width (in bytes)

	mov	ah,al
	mov	al,OFFR
	mov     dx,CRTC_ADDR
	out     dx,ax			; write new Offset register

	; Calculate new start addresses for left/right pages
	; Note:  Right eye start address = end of first line of left eye
	;	     = Left eye start address + page width (CPU bytes)
	mov     dx,CRTC_ADDR
	mov     al,SAHR
	out     dx,al
	inc	dx
	in      al,dx                   ; get Start Address high byte
	mov     ah,al

	mov     dx,CRTC_ADDR
	mov     al,SALR
	out     dx,al
	inc	dx
	in      al,dx			; get Start Address low byte

	mov     word ptr [EDI+D_startLeftX],ax	;left eye start address
	add     ax,word ptr [EDI+D_screenWidth]	;calculate right eye start
	mov     word ptr [EDI+D_startRightX],ax	;right eye start address

	ret

@altSolVESA:
	; Double the virtual screen width, so that we have 2 side-by-side
	;  screens instead of one line-alternate screen.  To do this,
	;  use VESA BIOS call AX=4f06h (get/set screen width)
	mov     ax, 4f06h
	mov     bx, 0001h       ; VESA get screen width
IF USE_VIDEO_BIOS
	pushf
	call    FWORD ptr [EDI+D_oldhandlerBIOS]
ELSE
        int     10h
ENDIF
	mov     word ptr [EDI+D_screenWidth], cx ; save VESA screen width

	mov     ax, 4f06h
	mov     bx, 0h          ; VESA set virtual screen width
	shl     cx, 1           ; double current screen width
IF USE_VIDEO_BIOS
	pushf
	call    FWORD ptr [EDI+D_oldhandlerBIOS]
ELSE
        int     10h
ENDIF

	; Calculate new start addresses for left/right pages
	; Note:  Right eye start address = end of first line of left eye
	;	     = Left eye start address + page width (CPU bytes)
	mov     ax, 4f07h
	mov     bx, 0001h       ; VESA get display start address
IF USE_VIDEO_BIOS
	pushf
	call    FWORD ptr [EDI+D_oldhandlerBIOS]
ELSE
        int     10h
ENDIF

	mov     word ptr [EDI+D_startLeftX], cx	; save left X start address
	mov     word ptr [EDI+D_startLeftY], dx	; save left Y start address
	add     cx, word ptr [EDI+D_screenWidth]
	mov     word ptr [EDI+D_startRightX], cx	; save right X start address
	mov     word ptr [EDI+D_startRightY], dx	; save right Y start address

	ret
_alternateToSolid	endp

_solidToAlternate	proc    near
; This procedure changes the screen from a full-screen format to line-
;   alternate by halving the width of the virtual screen buffer.  It does
;   not change the physical resolution of the screen in any way.
; Registers altered: Offset (VGA only)
; VESA set calls: setWidth (VESA only)
; Note:  changes contents of CRTC index register
;	 interrupts should be disabled

	cmp     BYTE ptr [EDI+D_vesaMode],0   	; are we in a vga mode?
	jne     @solAltVESA			; no

	; restore VGA-specific registers
	mov     dx,CRTC_ADDR
	mov     ah,byte ptr [EDI+D_saveOffset]
	mov	al,OFFR
	out     dx,ax			    	; restore Offset register

	ret

@solAltVESA: ; restore VESA screen mode
	mov     ax, 4f06h		; VESA set virtual screen width
	mov     bx, 0h
	mov     cx, word ptr [EDI+D_screenWidth]	; restore VESA screen width
IF USE_VIDEO_BIOS
	pushf
	call    FWORD ptr [EDI+D_oldhandlerBIOS]
ELSE
        int     10h
ENDIF

	ret
_solidToAlternate	endp

_halfToFullScreen	proc    near
; This procedure reduces the vertical resolution of the screen to 1/2 present
;   size by doubling the number of physical scan lines per pixel.
;   I.e., alter the Max Scan Line bits (4:0) in the MSL register
;	    new MSL(4:0) = oldMSL(4:0) * 2 + 1
;	    new MSL(7:5) must not be altered!!!
;   This may not work in VESA modes on some cards with some BIOS.
; Variables set: saveMSL
; Registers altered: MaxScanLine
; Note:  changes contents of CRTC index register
;	 interrupts should be disabled

	mov     dx,CRTC_ADDR
	mov     al,MSLR
	out     dx,al
	inc	dx
	in      al,dx			; save old Max Scan Line register
	mov     byte ptr [EDI+D_saveMSL],al

	mov	dl, al			; save MSL in dl for bits (7:5)
	and     ax,000fh		; start with MSL(3:0) (drop bit 4)
	shl     ax,1			; * 2
	inc     ax			; + 1
	and     dx,00e0h
	or      ax,dx			; restore old MSL(7:5)

	mov	ah,al
	mov	al,MSLR
	mov     dx,CRTC_ADDR
	out     dx,ax			; write new MSL

	ret
_halfToFullScreen	endp

_fullToHalfScreen	proc    near
; This procedure restores the screen to its full vertical resolution after
;   it has been reduced by halfToFullScreen.
; Registers altered: MaxScanLine
; Note:  changes contents of CRTC index register
;	 interrupts should be disabled

	mov     dx,CRTC_ADDR
	mov     ah,byte ptr [EDI+D_saveMSL]
	mov	al,MSLR
	out     dx,ax				; restore old MSL register

	ret
_fullToHalfScreen	endp

_on3D	proc    near
; This procedure turns on 3D operation.  It assumes that the screen is in
;   the proper video mode and that the start* variables are set to point
;   to the left and right video buffers.
; Note:  changes contents of CRTC index register
;	 interrupts should be disabled

	mov     BYTE ptr [EDI+D_hookVesa],1   ; capture VESA start addr calls

	mov     BYTE ptr [EDI+D_countVertRet],0
	mov     BYTE ptr [EDI+D_page],0          ; page = 0
	mov     BYTE ptr [EDI+D_mode],1 ; mode = 1 (initialize retrace/RTC)
	mov     BYTE ptr [EDI+D_timerCheckRTC], 0 ; tell DOS timer that RTC is on
	mov     BYTE ptr [EDI+D_pageAdvanced], 2	 ; tell apps we are calibrating

	mov     dx, MISC_READ_ADDR
	in      al, dx                  ; save Misc. Output register
	mov     byte ptr [EDI+D_saveMiscOut], al

	mov     dx,CRTC_ADDR
	mov     al,VRER
	out     dx,al
	inc	dx
	in      al,dx			; save the old VertRet End Register
	mov     byte ptr [EDI+D_saveVRER],al

	; calculate value used to clear the vertical retrace interrupt bit
	;   = (oldVRER << 8) & 0xcf00 | VRER | 0x2000
	mov     ah,al
	and     ax, 0CF00h
	or      ax, 2000h OR VRER
	mov     word ptr [EDI+D_clearVertInt],ax

	; calculate value used to reset the vertical retrace interrupt bit
	;   = clearVertInt & 0xcfff | 0x1000
	and     ax, 0CFFFh
	or      ax, 1000h
	mov     word ptr [EDI+D_setVertInt],ax

	VERT_RETRACE_CLEAR      ; clear any pending vertical retrace
				; interrupt and reset for next retrace

	RTC_CLEAR               ; clear RTC pending interrupt

	ret

_on3D	endp

_off3D	proc    near
; This procedure turns off 3D operation.  It assumes that the screen is in
;   the proper video mode and that the start* variables are set to point
;   to the left and right video buffers.
; Note:  changes contents of CRTC index register
;	 interrupts should be disabled

	mov	al, BYTE ptr  [EDI+D_mode]
	mov	BYTE ptr [EDI+D_exitMode], al	; save mode at exit for debug
	mov     BYTE ptr [EDI+D_mode],0		; turn off RTC routine

	mov     BYTE ptr [EDI+D_countTick],0	; clear countTick*
	mov     BYTE ptr [EDI+D_countTickEye],0

	mov     BYTE ptr [EDI+D_hookVesa],0	; ignore VESA calls
	mov     BYTE ptr [EDI+D_timerCheckRTC], 2 ; ignore DOS timer

	; turn off 3D glasses manually here, if necessary

	cmp     BYTE ptr [EDI+D_boostRefresh], 0 ; did we change refresh rate
	je      @Off3DSkipRefresh		; no, so skip ahead

	mov     dx, MISC_WRITE_ADDR
	mov     al, byte ptr [EDI+D_saveMiscOut]
	out     dx, al                  	;restore Misc. Output register

@Off3DSkipRefresh:
	mov     dx,CRTC_ADDR
	mov     ah,byte ptr [EDI+D_saveVRER]
	mov	al,VRER
	out     dx,ax				; restore VRER register

	cmp     BYTE ptr [EDI+D_vesaMode],0   	; are we in a vga mode?
	jne     @off3DVESA			; no

	; restore VGA-specific left eye
	mov     dx,CRTC_ADDR
	mov     ah,byte ptr [EDI+D_startLeftX+1]
	mov	al,SAHR
	out     dx,ax				; show left eye (high byte)
	mov     ah,byte ptr [EDI+D_startLeftX]
	mov	al,SALR
	out     dx,ax				; show left eye (low byte)

	ret

@off3DVESA: ; restore VESA screen to left eye
	mov     ax, 4f07h               	; VESA set start address
	mov     bx, 0000h
	mov     cx, word ptr [EDI+D_startLeftX] 	; display left eye
	mov     dx, word ptr [EDI+D_startLeftY]
IF USE_VIDEO_BIOS
	pushf
	call    FWORD ptr [EDI+D_oldhandlerBIOS]
ELSE
        int     10h
ENDIF

	ret

_off3D	endp

;;******************** TIMER interrupt code **********************


; vertRet:   The interrupt handler for the Real-Time Clock (RTC)
;
; This is an interrupt service routine for the RTC.  It is called 1024 times
; per second (unless reprogrammed to different rate).  Its purpose is to
; watch for vertical retrace.  At that time, it flips the glasses and the
; current buffer (left <--> right eyes).
;
; The actions of vertRet depends upon the global variable
; "word ptr [EDI+D_mode]".  The modes are as follows:
; _mode = 0 : Routine inactive.  Correctly handle RTC interrupt and then
;             return.  Do not affect video or glasses.  Routine will stay
;             in this mode until an external routine changes _mode to 1.
;         1 : Synchronize to vertical retrace.  Since an external routine
;             can change _mode from 0 (inactive) to 1 (initialize 3D mode)
;             at any time, the routine needs to find the next closest retrace.
;             This mode waits for the third occurance of vertical retrace.
;             Then it immediately switches to _mode 2.  Therefore the routine
;             never stays long in this _mode, and it enters _mode 2 on a
;             vertical retrace.
;         2 : Calibrate screen refresh rate.  The routine stays in this _mode
;             for CAL_LENGTH successive vertical retraces.  It counts the
;             number of RTC ticks which occur during this period.  After
;             CAL_LENGTH retraces, it averages the number of ticks between
;             retraces (rounding down) and sets the calibrated timing
;             variables (*Tick).  Then it immediately switches to _mode 3.
;             Therefore, the routine never stays long in this _mode, and it
;             enters _mode 3 on a vertical retrace.
;         3 : 3D mode.  This is the workhorse _mode.  Every retrace, it
;             flips the visible eyes and the current buffer (left <--> right).
;             Since this routine is called 1024 times/sec, it sets a countTick
;             to 0 after each retrace.  It then increments countTick after
;             each call.  It flips the screen and the eyes on ticks specified
;             by _mode 2.  After resyncCheckTick, it starts to check the
;             vertical interrupt bit for retrace.  On retrace, it resets the
;             countTick.  After resyncMissTick passes without the bit set, it
;             assumes that retrace was missed and subtracts one retrace from
;             countTick.  The routine will stay in this mode until an external
;             routine changes _mode to 0.
;         4 : Resync mode.  If the program gets out of sync with the vertical
;             retrace, any external procedure can set _mode to 4.  In this
;             mode, the routine will wait for vertical retrace by polling the
;             retrace bit on each call.  When it finds a vertical retrace,
;             it resyncs all counters and switches back to mode 3.  This mode
;             should only be entered while the routine is already in mode 3.

;;************************ PROTECTED MODE ISR ***************************

	assume	nothing
	assume  cs:_CODE

	public	_PMvertRet32_
	public	_PMvertRet32end_

_PMvertRet32_        proc    far

	pushad                  ; Ensure that we do not mess up *any*
        push    ds

;-----  DEBUG CODE BEGIN
IF USE_ISR_DEBUG
	mov     dx, 61h         ; Cause PC speaker to buzz when interrupt
	in      al, dx          ; fires.  By listening, we can tell if the
	and     al, 0feh        ; interrupt is not firing at all (no buzz),
	xor     al, 02h         ; or if the interrupt misses once (click
	out     dx, al          ; heard in buzz).  Buzz pitch indicates
ENDIF			        ; interrupt rate (1024/sec = 512 Hz ~ high C)
;-----  DEBUG CODE END

IF USE_ISR      ;; protected-mode ISR code for actual vertical retrace

; point to data area in real-mode 1M memory
	mov     DS,word ptr CS:[_datasel]	; get data selector DS
	mov	EDI,dword ptr CS:[_dataoff]	; init EDI to point to data variables

IF USE_ISR_TRACE
	inc	dword ptr [EDI+D_pm_isr_count]	; log protected-mode event
	inc	dword ptr [EDI+D_interruptCount]; increase tick count
ENDIF

; switch (mode) { ...  : jump to address in @PMtimerModeTable based on _mode

	mov     bl,BYTE ptr [EDI+D_mode]
	cmp     bl,4
	jbe 	@PM@5           ; check if _mode is out of table range ( > 4 )
IF USE_LEAN_MEAN
        cmp     bl,5            ; additional mode 5 ?
        je      @PMtimerMode5
ENDIF
	jmp     @PMtimerModeBreak
@PM@5:
IF USE_PM_JMPTBL 	;; invalid jump table if relocatable code
	shl     bl,2            ; 4-byte DWORD jump per table to @PMtimerMode*
        movzx   ebx,bl
	jmp     DWORD ptr CS:@PMtimerModeTable[ebx]
ELSE	;; jump the old-fashioned way
	cmp	bl,3
	je	@PMtimerMode3
	cmp	bl,4
	je	@PMtimerMode4
	cmp	bl,0
	je	@PMtimerMode0
	cmp	bl,1
	je	@PMtimerMode1
	cmp	bl,2
	je	@PMtimerMode2
ENDIF   ; USE_PM_JMPTBL

@PMtimerMode0:    ; Mode 0 : Routine inactive

	jmp     @PMtimerModeBreak       ; Do nothing

@PMtimerMode1:    ; Mode 1 : Synchronize to vertical retrace
	mov     dx,STA0_ADDR            ; check if in vertical interrupt
	in      al, dx
	test    al, 80h
	je      @PMtimerMode1Cont       ; if not, do not count it as a retrace!

	; vertical interrupt has occurred
	inc     BYTE ptr [EDI+D_countVertRet]    ; count it
IF USE_DOS_TICKER
	mov     BYTE ptr [EDI+D_timerCheckRTC],0 ;tell DOS timer that RTC is on
ENDIF

	VERT_RETRACE_CLEAR      ; clear vert. intr. and reset for next retrace

	; check if finished waiting (3rd vertical retrace)
	cmp     BYTE ptr [EDI+D_countVertRet],2
	jle     @PMtimerMode1Cont    	; not there yet, so wait longer

	; start calibration on next tick (mode 2)

	mov     BYTE ptr [EDI+D_mode],2         ; switch to mode 2

        xor     eax,eax
	mov     DWORD ptr [EDI+D_sumTick],eax     ; clear calibration sum
	mov     DWORD ptr [EDI+D_countTick],eax   ; clear # ticks since retrace
	mov     DWORD ptr [EDI+D_countVertRet],eax; clear # retraces

	cmp     BYTE ptr [EDI+D_boostRefresh],0 ; should we boost refresh rate?
	je      @PMtimerMode1Cont

	; increase refresh rate by setting bit 2 of Misc. register
	mov     al, byte ptr [EDI+D_saveMiscOut]
        and     al,0F3h                         ; mask off SVGA clock (DaveM)
	or      al, 04h
	mov     dx, MISC_WRITE_ADDR
	out     dx, al

@PMtimerMode1Cont:
IF USE_LEAN_MEAN
        cmp     byte ptr [EDI+D_flipEyeOffset],99      ; special tick offset ?
        jne     @PMtimerModeBreak
        mov     byte ptr [EDI+D_mode],5         ; use immediate page-flip mode
ENDIF
	jmp     @PMtimerModeBreak               ; end of mode 1 code

@PMtimerMode2:    ; Mode 2 : Calibrate screen refresh rate.
	inc     BYTE ptr [EDI+D_countTick]      ; update # ticks since retrace

	mov     dx,STA0_ADDR    ; check if in vertical interrupt
	in      al, dx
	test    al, 80h
	je      @PM2@338    ; if not, do not count it as a retrace!

	; vertical interrupt has occurred
	inc     BYTE ptr [EDI+D_countVertRet]   ; count it
IF USE_DOS_TICKER
	mov     BYTE ptr [EDI+D_timerCheckRTC], 0  ;tell DOS timer that RTC is on
ENDIF
	mov     al,BYTE ptr [EDI+D_countTick]
        movzx   eax,al
	add     DWORD ptr [EDI+D_sumTick],eax   ; add in number of ticks for avg

	mov     BYTE ptr [EDI+D_countTick],0    ; clear # ticks since retrace

	VERT_RETRACE_CLEAR      ; clear vert. intr. and reset for next retrace

@PM2@338: ; check if finished gathering cal. data
	cmp     BYTE ptr [EDI+D_countVertRet],CAL_LENGTH
	jl      @PM2@394    ; nope, wait some more

	; Determine tick number to flip screens on.
	; Note:  We want the eyes to flip close to the vert. retrace.
	;        The screens can be flipped earlier, since changing the
	;        Start Address does not take affect until the next screen
	;        starts to draw.  However, if we flip the Start Adress too
	;        early and multifple buffering is used, we will see the wrong
	;        buffer more often (whenever the buffer is told to change
	;        through a function call between flipScreenTick and the
	;        actual start of the next vertical scan).

	;             retraceCount = (sumTick/countVertRet);
	mov     eax,DWORD ptr [EDI+D_sumTick]   ; calculate average number of
	                                        ;  ticks (rounded down)
	idiv    BYTE ptr [EDI+D_countVertRet]   ;  between retraces

	mov     BYTE ptr [EDI+D_retraceCount],al; retrace is at this count

	dec     al                              ; retraceCount - 1
	mov     BYTE ptr [EDI+D_resyncCheckTick],al ; check resync at this count

	add     al, 4                           ; retraceCount + 3
	mov     BYTE ptr [EDI+D_resyncMissTick],al ; force resync at this count

	mov     al, BYTE ptr [EDI+D_retraceCount]
    IF USE_TICK_ADJUST OR USE_LEAN_MEAN
    ELSE
	add     al, BYTE ptr [EDI+D_flipEyeOffset] ; retraceCount+flipEyeOffset
    ENDIF
	mov     BYTE ptr [EDI+D_flipEyeTick],al ; flip eyes at this count

	mov     al, BYTE ptr [EDI+D_retraceCount]
	mov     bl, al
	shr     bl, 3
	sub     al, bl
	dec     al                              ; (7/8)*retraceCount - 1
    IF USE_TICK_ADJUST
	add     al, BYTE ptr [EDI+D_flipEyeOffset] ; +flipEyeOffset adjust
    ENDIF
	mov     BYTE ptr [EDI+D_flipScreenTick],al ;flip screens at this count

	mov     BYTE ptr [EDI+D_mode],3         ; switch to mode 3

	mov     BYTE ptr [EDI+D_countTick],0    ; clear # ticks since retrace
	mov     BYTE ptr [EDI+D_countTickEye],0 ; clear # ticks since retrace

	mov     BYTE ptr [EDI+D_flippedEyes],0  ; reset flipped eyes status

@PM2@394:
	jmp     @PMtimerModeBreak               ; end of mode 2 code

@PMtimerMode3:    ; Mode 3: 3D mode

	inc     BYTE ptr [EDI+D_countTick]      ; update # ticks since retrace
	inc     BYTE ptr [EDI+D_countTickEye]   ; update # ticks since retrace

	; Is it time to flip screen pages?
	mov     al,BYTE ptr [EDI+D_countTick]
	cmp     al,BYTE ptr [EDI+D_flipScreenTick]
	je      @PMtimerCheckVesa
	jmp     @PMtimerEndFlipScreen           ; nope

@PMtimerCheckVesa: ; Check if we should flip the screen by VESA or by VGA
	cmp     BYTE ptr [EDI+D_vesaMode],0     ; in vga mode?
	jne     @PMtimerVesaFlip

@PMtimerVgaFlip:
	mov     dx,CRTC_ADDR
	in      al,dx                   ; save old CRTC index
	mov     bl,al

	cmp     BYTE ptr [EDI+D_page],0 ; which page to show?
	jne     @PM2@506                ; if we are on 1, jump to show 0

	; show right eye (we are on left eye)
	mov     ah,byte ptr [EDI+D_startRightX+1]
	mov	al,SAHR
	out     dx,ax
	mov     ah,byte ptr [EDI+D_startRightX]
	mov	al,SALR
	out     dx,ax

	jmp     @PM2@534

@PM2@506:
	; show left eye (we are on right eye)
	mov     ah,byte ptr [EDI+D_startLeftX+1]
	mov	al,SAHR
	out     dx,ax
	mov     ah,byte ptr [EDI+D_startLeftX]
	mov	al,SALR
	out     dx,ax

@PM2@534:
	mov     al,bl
	out     dx,al                   ; restore old CRTC index

	jmp     @PMtimerEndFlipScreen   ; continue (jump past Vesa page code)

@PMtimerVesaFlip:
	mov     ax, 4f07h               ; VESA set start address function
	mov     bx, 0000h               ;  bx = 0 --> set function

	cmp     BYTE ptr [EDI+D_page],0 ; which page to show?
	jne     @PMtimerVesa1

	mov     ecx, DWORD ptr [EDI+D_startRightX]      ; we are on 0, so show 1 (right)
	mov     edx, DWORD ptr [EDI+D_startRightY]      ;  dx = Y start address
	jmp     @PMtimerVesa2

@PMtimerVesa1:
	mov     ecx, DWORD ptr [EDI+D_startLeftX]	; we are on 1, show 0 (left)
	mov     edx, DWORD ptr [EDI+D_startLeftY]	;  dx = Y start address

@PMtimerVesa2:
        push    DS
        push    EDI
IF USE_VIDEO_BIOS
        pushfd
        call    FWORD ptr [EDI+D_oldhandlerBIOS] ; call old INT 10h (VESA)
ELSE
    IF  USE_VESA_BIOS
        cmp     DWORD ptr [EDI+D_pm_setxy],0    ; valid VESA 2.0 pointer ?
        jne     @PMvesa20

        int     10h                     ; call video BIOS for VESA 1.2
        jmp     @PMvesa12

@PMvesa20:
        mov     al, byte ptr [EDI+D_page]
        movzx   esi,al
        pushfd                          ; interrupt call
        mov     ax,cs
        movzx   eax,ax
        push    eax
        call    dword ptr [EDI+D_pm_setxy]      ; call VESA 2.0 fn directly

@PMvesa12:
    ELSE
        int     10h
    ENDIF       ;; USE_VESA_BIOS
ENDIF           ;; USE_VIDEO_BIOS
        pop     EDI
        pop     DS

@PMtimerEndFlipScreen:  ; Is it time to flip eye (glasses) visible pages?
	mov     al,BYTE ptr [EDI+D_countTickEye]
	cmp     al,BYTE ptr [EDI+D_flipEyeTick]
	jl      @PMtimerEndFlipEyes             ; no, it is not time yet

	cmp     BYTE ptr [EDI+D_flippedEyes],0  ; have we already flipped them?
	jne     @PMtimerEndFlipEyes             ; yep, so skip this part

	; flip eyes (left <--> right)

	cmp     al,BYTE ptr [EDI+D_countTick]   ; did vert. retrace occur yet?
	jne     @PMtimerFlipEyeAfterRetrace     ; yep -- special handler

	; flip eyes before retrace is detected
	cmp     BYTE ptr [EDI+D_nailRetrace], 0 ; wait for exactly retrace?
	je      @PMtimerNoNail
	mov     dx,STA0_ADDR                    ; read retrace bit
@PMtimerNail:
        in      al,dx
	test    al,80h
	je      @PMtimerNail                    ; loop back if not at retrace
	inc	DWORD ptr [EDI+D_delayCount]	; notify apps of delay
@PMtimerNoNail:
	inc     BYTE ptr [EDI+D_flippedEyes]    ; mark eyes as flipped
		; Note:  retrace will reset this flag and countTickEye
	jmp     @PMtimerFlipEyesCont

@PMtimerFlipEyeAfterRetrace:      ; flip eyes after retrace was detected
	mov     al,BYTE ptr [EDI+D_countTick]
	mov     BYTE ptr [EDI+D_countTickEye],al ; reset countTickEye by
						 ;  the previous retrace

@PMtimerFlipEyesCont:
	cmp     BYTE ptr [EDI+D_page],0 	; are we on left eye now?
	jne     @PM2@646                        ; no

	; we are on left eye
	; flip glasses to right eye manually, if necessary
IF USE_OEM
_PMupdateOemRight_:
	mov	eax,dword ptr [EDI+D_svr_oem]   ; which OEM ?
        or      al,al
        jz      @PMrightx
	cmp	al,OEM1
	je	@PMright1
	cmp	al,OEM2
	je	@PMright2
	cmp	al,OEM3
	je	@PMright3
	cmp	al,OEM4
	je	@PMright4
	cmp	al,OEM5
	je	@PMright5
	jmp	@PMrightx

@PMright1:      ; update Brooktree port
@PMright3:      ; update diagnostic port
        mov     edx,dword ptr[EDI+D_oem_port]   ; OEM port
        mov     al,byte ptr[EDI+D_oem_dataR]    ; right eye poke (ouch)
	out	dx,al
	jmp	@PMrightx

@PMright4:      ; update Alliance port
        mov     dx,03C4h
        movzx   edx,dx
        in      al,dx
        mov     bl,al
        IODELAY
        IODELAY
        mov     ax,331Dh
        out     dx,ax
        IODELAY
        mov     edx,dword ptr[EDI+D_oem_port]   ; Alliance port
        mov     ax,0180h
        out     dx,ax
        IODELAY
        mov     dx,03C4h
        mov     al,bl
        out     dx,al
	jmp	@PMrightx

@PMright5:
        mov     dx,03C4h
        movzx   edx,dx
        in      al,dx
        mov     bl,al
        IODELAY
        IODELAY
        mov     ax,331Dh
        out     dx,ax
        IODELAY
        mov     edx,dword ptr[EDI+D_oem_port]   ; Alliance port
        mov     ax,2020h
        out     dx,ax
        IODELAY
        mov     al,20h
        out     dx,al
        IODELAY
        mov     dx,03C4h
        mov     al,bl
        out     dx,al
	jmp	@PMrightx

@PMright2:      ; Rendition is auto-flipping
@PMrightx:
ENDIF   ;; USE_OEM

	mov     BYTE ptr [EDI+D_page],1 ; tell ptr we are now on right eye
	jmp     @PMtimerEndFlipEyes

@PM2@646: ; we are on right eye
	; flip glasses to left eye manually, if necessary
IF USE_OEM
_PMupdateOemLeft_:
	mov	eax,dword ptr [EDI+D_svr_oem]
        or      al,al
        jz      @PMleftx
	cmp	al,OEM1
	je	@PMleft1
	cmp	al,OEM2
	je	@PMleft2
	cmp	al,OEM3
	je	@PMleft3
	cmp	al,OEM4
	je	@PMleft4
	cmp	al,OEM5
	je	@PMleft5
	jmp	@PMleftx

@PMleft1:       ; update Brooktree port
@PMleft3:       ; update diagnostic port
        mov     edx,dword ptr[EDI+D_oem_port]   ; OEM port
        mov     al,byte ptr[EDI+D_oem_dataL]    ; left eye poke (eek)
	jmp	@PMleftx

@PMleft4:       ; update Alliance port
        mov     dx,03C4h
        movzx   edx,dx
        in      al,dx
        mov     bl,al
        IODELAY
        IODELAY
        mov     ax,331Dh
        out     dx,ax
        IODELAY
        mov     edx,dword ptr[EDI+D_oem_port]   ; Alliance port
        mov     ax,0080h
        out     dx,ax
        IODELAY
        mov     dx,03C4h
        mov     al,bl
        out     dx,al
	jmp	@PMleftx

@PMleft5:
        mov     dx,03C4h
        movzx   edx,dx
        in      al,dx
        mov     bl,al
        IODELAY
        IODELAY
        mov     ax,331Dh
        out     dx,ax
        IODELAY
        mov     edx,dword ptr[EDI+D_oem_port]   ; Alliance port
        mov     ax,2020h
        out     dx,ax
        IODELAY
        mov     al,00h
        out     dx,al
        IODELAY
        mov     dx,03C4h
        mov     al,bl
        out     dx,al
	jmp	@PMleftx

@PMleft2:       ; Rendition is auto-flipping
@PMleftx:
ENDIF   ;; USE_OEM

	mov     BYTE ptr [EDI+D_page],0 ; tell ptr we are now on left eye

@PMtimerEndFlipEyes: ; Is it time to start checking the vertical interrupt bit?
	mov     al,BYTE ptr [EDI+D_countTick]
	cmp     al,BYTE ptr [EDI+D_resyncCheckTick]
	je 	@@PM6                   ; check: countTick = resyncCheckTick
	jg 	@@PM6a                  ; check: countTick > resyncCheckTick
	jmp     @PMtimerEndResync       ; do not check yet

@@PM6:    ; did the vertical interrupt bit go off?
	mov     dx,STA0_ADDR
	in      al,dx
	test    al,80h
	je      @PMtimerNoVertInt       ; nope

	; yes -- we checked, and the vertical interrupt bit was set, so
	; vertical retrace has started (or maybe even past).  However, we
	; just started checking on this tick.  We may be way off.  Therefore,
	; we must start watching earlier (decrease *Tick).  Especially start
	; checking earlier for the next immediate retrace (reset countTick
	; to 1).

	dec     BYTE ptr [EDI+D_resyncCheckTick]        ; check earlier
	jg      @@PM6b                                  ; is it <= 0?
	mov     BYTE ptr [EDI+D_resyncCheckTick],1      ; Yes.  1 = min value

@@PM6b:
        mov     BYTE ptr [EDI+D_countTick],1  ; clear # ticks since retrace

	jmp 	@PMtimerRecalibrateCont


@@PM6a:   ; did the vertical interrupt bit go off?
	mov     dx,STA0_ADDR
	in      al,dx
	test    al,80h
	je      @PMtimerNoVertInt               ; nope

	; yes -- we checked, and the vertical interrupt bit was set, so
	; vertical retrace has started (or maybe even past)

	mov     BYTE ptr [EDI+D_countTick],0    ; clear # ticks since retrace

@PMtimerRecalibrateCont:
IF USE_DOS_TICKER
	mov     BYTE ptr [EDI+D_timerCheckRTC],0 ;tell DOS timer that RTC is on
ENDIF
	mov     BYTE ptr [EDI+D_pageAdvanced],1	; inform all that retrace came

	cmp     BYTE ptr [EDI+D_flippedEyes],0  ; eyes flipped before retrace?
	je      @PMtimerClearNoEyeFlipA         ; nope

	; Eye flipped before retrace
	mov     BYTE ptr [EDI+D_flippedEyes],0  ; reset flipped eyes status
	mov     BYTE ptr [EDI+D_countTickEye],0 ; reset eye count

@PMtimerClearNoEyeFlipA:
	VERT_RETRACE_CLEAR      ; clear vert. intr. and reset for next retrace

	jmp     @PMtimerEndResync

@PMtimerNoVertInt: ; did we completely miss the vertical retrace?
	; assume we did if (countTick >= resyncMissTick)
	mov     al,BYTE ptr [EDI+D_resyncMissTick]
	cmp     al,BYTE ptr [EDI+D_countTick]
	jg      @PMtimerEndResync   ; no, countTick did not get there yet

	; Somehow the vert. ret. signal was missed (it is 3 ticks overdue).
	; Estimate time using retraceCount and resync on next retrace...
IF USE_ISR_TRACE
	inc     word ptr [EDI+D_countMisses]    ; mark the miss for debug
ENDIF

	mov     al,BYTE ptr [EDI+D_retraceCount]
	sub     BYTE ptr [EDI+D_countTick],al   ; subtract off 1 retrace time

IF USE_DOS_TICKER
	mov     BYTE ptr [EDI+D_timerCheckRTC],0 ;tell DOS timer that RTC is on
ENDIF
	mov     BYTE ptr [EDI+D_pageAdvanced],1	; inform all that retrace came

	cmp     BYTE ptr [EDI+D_flippedEyes],0  ; eyes flipped before retrace?
	je      @PMtimerClearNoEyeFlipB         ; nope

	; Eye flipped before retrace
	mov     BYTE ptr [EDI+D_flippedEyes],0  ; reset flipped eyes status
	mov     al, BYTE ptr [EDI+D_countTick]
	mov     BYTE ptr [EDI+D_countTickEye],al ; reset eye count

@PMtimerClearNoEyeFlipB:
	VERT_RETRACE_CLEAR      ; clear vert. intr. and reset for next retrace

@PMtimerEndResync:
	jmp     @PMtimerModeBreak       ; end of mode 3 code

@PMtimerMode4:    ; Mode 4: Resync mode

	; did the vertical interrupt bit go off?
	mov     dx,STA0_ADDR
	in      al,dx
	test    al,80h
	je      @PMtimerModeBreak       ; nope -- exit routine

	; vertical interrupt bit fired, so resync all timers
	VERT_RETRACE_CLEAR      ; clear vert. intr. and reset for next retrace
IF USE_DOS_TICKER
	mov     BYTE ptr [EDI+D_timerCheckRTC], 0  ;tell DOS timer that RTC is on
ENDIF

	mov     BYTE ptr [EDI+D_countTick],0    ; clear # ticks since retrace
	mov     BYTE ptr [EDI+D_countTickEye],0 ; clear # ticks since retrace

	mov     BYTE ptr [EDI+D_flippedEyes],0  ; reset flipped eyes status

	mov     BYTE ptr [EDI+D_mode],3         ; switch to mode 3

	jmp     @PMtimerModeBreak ; end of mode 4 code

IF USE_LEAN_MEAN
@PMtimerMode5:  ; Mode 5: lean-n-mean immediate page-flip mode

	; Is it time to flip screen pages?
	; did the vertical interrupt bit go off?
	mov     dx,STA0_ADDR
	in      al,dx
	test    al,80h
	jz      @PMtimerModeBreak       ; nope -- exit routine

        ; make sure retrace is over
        mov     dx,STA1_ADDR
@PMtail:in      al,dx
        test    al,08h                  ; poll sync
        jnz     @PMtail

	VERT_RETRACE_CLEAR      ; clear vert. intr. and reset for next retrace

@PMtimerCheckVesa5: ; Check if we should flip the screen by VESA or by VGA
	cmp     BYTE ptr [EDI+D_vesaMode],0     ; in vga mode?
	jne     @PMtimerVesaFlip5

@PMtimerVgaFlip5:
	mov     dx,CRTC_ADDR
	in      al,dx                   ; save old CRTC index
	mov     bl,al

	cmp     BYTE ptr [EDI+D_page],0 ; which page to show?
	jne     @PM2@5065               ; if we are on 1, jump to show 0
        mov     byte ptr [EDI+D_page],1 ; else toggle page index to 1

	; show right eye (we are on left eye)
	mov     ah,byte ptr [EDI+D_startRightX+1]
	mov	al,SAHR
	out     dx,ax
	mov     ah,byte ptr [EDI+D_startRightX]
	mov	al,SALR
	out     dx,ax

	jmp     @PM2@5345

@PM2@5065:
        mov     byte ptr [EDI+D_page],0 ; or toggle page index to 0
	; show left eye (we are on right eye)
	mov     ah,byte ptr [EDI+D_startLeftX+1]
	mov	al,SAHR
	out     dx,ax
	mov     ah,byte ptr [EDI+D_startLeftX]
	mov	al,SALR
	out     dx,ax

@PM2@5345:
	mov     al,bl
	out     dx,al                   ; restore old CRTC index

	jmp     @PMtimerEndFlipScreen5  ; continue (jump past Vesa page code)

@PMtimerVesaFlip5:
	mov     ax, 4f07h               ; VESA set start address function
	mov     bx, 0000h               ;  bx = 0 --> set function

	cmp     BYTE ptr [EDI+D_page],0 ; which page to show?
	jne     @PMtimerVesa15
        mov     byte ptr [EDI+D_page],1 ; else toggle page index to 1

	mov     ecx, DWORD ptr [EDI+D_startRightX]      ; we are on 0, so show 1 (right)
	mov     edx, DWORD ptr [EDI+D_startRightY]      ;  dx = Y start address
	jmp     @PMtimerVesa25

@PMtimerVesa15:
        mov     byte ptr [EDI+D_page],0 ; or toggle page index to 0
	mov     ecx, DWORD ptr [EDI+D_startLeftX]	; we are on 1, show 0 (left)
	mov     edx, DWORD ptr [EDI+D_startLeftY]	;  dx = Y start address

@PMtimerVesa25:
        push    DS
        push    EDI
IF USE_VIDEO_BIOS
        pushfd
        call    FWORD ptr [EDI+D_oldhandlerBIOS] ; call old INT 10h (VESA)
ELSE
    IF  USE_VESA_BIOS
        cmp     DWORD ptr [EDI+D_pm_setxy],0    ; valid VESA 2.0 pointer ?
        jne     @PMvesa205

        int     10h                     ; call video BIOS for VESA 1.2
        jmp     @PMvesa125

@PMvesa205:
        mov     al, byte ptr [EDI+D_page]
        movzx   esi,al
        pushfd                          ; interrupt call
        mov     ax,cs
        movzx   eax,ax
        push    eax
        call    dword ptr [EDI+D_pm_setxy]      ; call VESA 2.0 fn directly

@PMvesa125:
    ELSE
        int     10h
    ENDIF       ;; USE_VESA_BIOS
ENDIF           ;; USE_VIDEO_BIOS
        pop     EDI
        pop     DS

@PMtimerEndFlipScreen5:
        jmp     @PMtimerModeBreak
ENDIF   ;; USE_LEAN_MEAN

@PMtimerModeBreak:
; Note:  We must tell the RTC and the PICs that we have handled the interrupt
;        request.  There are 3 ways to do this: (A) let BIOS do it, but keep
;        the BIOS wait count high so that it does not turn the timer off;
;        (B) let BIOS do it, and re-enable RTC interrupts afterwords if they
;        were disabled by BIOS; and (C) tell them directly and skip BIOS.
;        I am using method (C).  It is the safest, as long as the BIOS
;        RTC routines are not needed.
;--------------------------------
; RTC handler method (A):
;    Call old (BIOS) handler for the interrupt.  It will take care of the
;    PICs and the RTC.  We will make sure that DOS never decides to turn off
;    the periodic interrupt by keeping the DOS timer counter >> 0.
; Problem:  No other program can use the RTC timer (wait: INT 15h AH=83h, 85h)
;    functions, since we alter its value.  RTC alarm can be used, and any
;    other things that BIOS/TSRs do during IRQ 8 are also enabled.
;
;       mov     dx,0040h
;       mov     es,dx         ;BIOS data area = 0040:xxxx
;       mov     di,009eh      ;offset of wait count (high byte, in 1/1024 sec)
;       mov     dx,1000h
;       mov     es:[di],dx    ;put a large number there
;
;       pushf
;       call    dword ptr DGROUP:_oldhandler
;
;--------------------------------
; RTC handler method (B):
;    Call old (BIOS) handler for the interrupt.  It will take care of the
;    PICs and the RTC.  Just make sure periodic interrupt is on after DOS
;    (maybe) turns it off.
; Problem:  None!!!  Except for some reason, it does not work on all
;    machines.  Give me a machine that it does not work on (I have not been
;    able to verify it personally), and I'll find out why!!!  Maybe the
;    PIC is being disabled...  -D.S.
;
;       pushf
;       call    dword ptr DGROUP:_oldhandler
;       cli
;
;       mov     dx,CMOS_ADDR
;       mov     al,CMOS_B
;       out     dx,al           ;select CMOS register B (enable interrupts)
;       inc     dx
;
;       mov     ax,5            ;delay for slow clock chips
;@PM2@842a: dec   ax
;       jg      @PM2@842a
;
;       in      al,dx           ;read register B
;       test    al,40h          ;check if periodic interrupt is on
;       jne     @PM2@842c
;
;       or      al,40h          ;enable periodic interrupt
;       mov     bl,al           ;save new register B
;
;       mov     dx,CMOS_ADDR
;       mov     al,CMOS_B
;       out     dx,al           ;select CMOS register B (enable interrupts)
;       inc     dx
;
;       mov     ax,10           ;delay for slow clock chips
;@PM2@842b: dec   ax
;       jg      @PM2@842b
;
;       mov     al,bl           ;new register B to write
;       out     dx,al           ;write new CMOS register B
;
;@PM2@842c:
;--------------------------------

; RTC handler method (C):
;           We can use the code below *instead* of calling DOS's old handler
; Problem:  The timer and alarm functions (INT 1h; INT 15h AH=83h, 85h) will
;           not work
;

ENDIF   ;; USE_ISR

	RTC_CLEAR               ; clear pending interrupt from RTC

	mov     al,20h
	out     0a0h,al         ; clear pending interrupt from PIC 2
	out     020h,al         ; clear pending interrupt from PIC 1

	pop     ds
	popad

	iretd

_PMvertRet32_        endp


IF USE_PM_JMPTBL 	;; jump table only for relocatable code
@PMtimerModeTable label   DWORD		; 32-bit jump table for RTC timer Mode
	dd      @PMtimerMode0
	dd      @PMtimerMode1
	dd      @PMtimerMode2
	dd      @PMtimerMode3
	dd      @PMtimerMode4
ENDIF   ; USE_PM_JMPTBL

_PMvertRet32end_	dd 0

;;** protected-mode ISR code for vertical retrace

_CODE	ends


;;*********************** REAL MODE TIMER ISR ************************

	.286	; .386 code is not efficient here
        JUMPS   ; inverted logic if short conditional JMP detected

_CODE16 segment byte public use16 'CODE'

	assume  nothing
	assume 	cs:_CODE16

	public	_RMvertRet16_
	public	_RMvertRet16end_

_RMvertRet16_        proc    far

	pusha                   ; Ensure that we do not mess up *any*
        push    ds

;-----  DEBUG CODE BEGIN
IF USE_ISR_DEBUG
        mov     dx, 61h         ; Cause PC speaker to buzz when interrupt
        in      al, dx          ; fires.  By listening, we can tell if the
        and     al, 0feh        ; interrupt is not firing at all (no buzz),
        xor     al, 02h         ; or if the interrupt misses once (click
        out     dx, al          ; heard in buzz).  Buzz pitch indicates
ENDIF
;-----  DEBUG CODE END


IF USE_ISR      ;; real-mode ISR code for actual vertical retrace

; point to data area in real-mode memory
	mov     dx,CS		; assign real-mode DS <-- CS
	mov     DS,dx           ; Point DS to DGROUP so we can access data
	mov	DI,DATA_START	; init DI to point to data variables

IF USE_ISR_TRACE
	inc	word ptr [DI+D_rm_isr_count]	; log real-mode event
	inc	word ptr [DI+D_interruptCount] ; increase tick count
ENDIF

; switch (mode) { ...  : jump to address in @timerModeTable based on _mode

	mov     bl,BYTE ptr [DI+D_mode]
	cmp     bl,4
	jbe 	@@RM5     ; check if _mode is out of table range ( > 4 )
IF USE_LEAN_MEAN
        cmp     bl,5            ; additional mode 5 ?
        je      @RMtimerMode5
ENDIF
	jmp     @RMtimerModeBreak
@@RM5:
IF USE_RM_JMPTBL	;; no jump table for relocatable code
	shl     bl,1            ; 2-byte WORD jump per table to @timerMode*
        xor     bh,bh
	jmp     word ptr CS:@RMtimerModeTable[bx]
ELSE	;; jump the old-fashioned way...
	cmp	bl,3
	jne	@RMskip3
	jmp	@RMtimerMode3   ; long jump
@RMskip3:
	cmp	bl,4
	jne	@RMskip4
	jmp	@RMtimerMode4   ; long jump
@RMskip4:
	cmp	bl,0
	je	@RMtimerMode0
	cmp	bl,1
	je	@RMtimerMode1
	cmp	bl,2
	je	@RMtimerMode2
ENDIF   ; USE_RM_JMPTBL

@RMtimerMode0:    ; Mode 0 : Routine inactive

	jmp     @RMtimerModeBreak       ; Do nothing

@RMtimerMode1:    ; Mode 1 : Synchronize to vertical retrace
	mov     dx,STA0_ADDR            ; check if in vertical interrupt
	in      al, dx
	test    al, 80h
	je      @RMtimerMode1Cont       ; if not, do not count it as a retrace!

	; vertical interrupt has occurred
	inc     BYTE ptr [DI+D_countVertRet]    ; count it
IF USE_DOS_TICKER
	mov     BYTE ptr [DI+D_timerCheckRTC],0 ;tell DOS timer that RTC is on
ENDIF
	VERT_RETRACE_CLEAR_16           ; clear vert. intr. and reset for next retrace

	; check if finished waiting (3rd vertical retrace)
	cmp     BYTE ptr [DI+D_countVertRet],2
	jle     @RMtimerMode1Cont    	; not there yet, so wait longer

	; start calibration on next tick (mode 2)

	mov     BYTE ptr [DI+D_mode],2  ; switch to mode 2

        xor     ax,ax
	mov     word ptr [DI+D_sumTick],ax      ; clear calibration sum
	mov     word ptr [DI+D_countTick],ax    ; clear # ticks since retrace
	mov     word ptr [DI+D_countVertRet],ax ; clear # retraces

	cmp     BYTE ptr [DI+D_boostRefresh], 0 ; should we boost refresh rate?
	je      @RMtimerMode1Cont

	; increase refresh rate by setting bit 2 of Misc. register
	mov     al, byte ptr [DI+D_saveMiscOut]
        and     al,0F3h                 ; mask off SVGA clock
	or      al, 04h                 ; select faster VGA clock
	mov     dx, MISC_WRITE_ADDR
	out     dx, al

@RMtimerMode1Cont:
IF USE_LEAN_MEAN
        cmp     byte ptr [DI+D_flipEyeOffset],99      ; special tick offset ?
        jne     @RMtimerModeBreak
        mov     byte ptr [DI+D_mode],5         ; use immediate page-flip mode
ENDIF
	jmp     @RMtimerModeBreak       ; end of mode 1 code

@RMtimerMode2:    ; Mode 2 : Calibrate screen refresh rate.
	inc     BYTE ptr [DI+D_countTick]       ; update # ticks since retrace

	mov     dx,STA0_ADDR    ; check if in vertical interrupt
	in      al, dx
	test    al, 80h
	je      @RM2@338    ; if not, do not count it as a retrace!

	; vertical interrupt has occurred
	inc     BYTE ptr [DI+D_countVertRet]    ; count it
IF USE_DOS_TICKER
	mov     BYTE ptr [DI+D_timerCheckRTC],0 ;tell DOS timer that RTC is on
ENDIF

	mov     al,BYTE ptr [DI+D_countTick]
        xor     ah,ah
	add     word ptr [DI+D_sumTick],ax      ; add in number of ticks for avg

	mov     BYTE ptr [DI+D_countTick],0     ; clear # ticks since retrace

	VERT_RETRACE_CLEAR_16           ; clear vert. intr. and reset for next retrace

@RM2@338: ; check if finished gathering cal. data
	cmp     BYTE ptr [DI+D_countVertRet],CAL_LENGTH
	jl      @RM2@394                ; nope, wait some more

	; Determine tick number to flip screens on.
	; Note:  We want the eyes to flip close to the vert. retrace.
	;        The screens can be flipped earlier, since changing the
	;        Start Address does not take affect until the next screen
	;        starts to draw.  However, if we flip the Start Adress too
	;        early and multifple buffering is used, we will see the wrong
	;        buffer more often (whenever the buffer is told to change
	;        through a function call between flipScreenTick and the
	;        actual start of the next vertical scan).

	;             retraceCount = (sumTick/countVertRet);
	mov     ax,word ptr [DI+D_sumTick]      ; calculate average number of
	                                        ;  ticks (rounded down)
	idiv    BYTE ptr [DI+D_countVertRet]    ;  between retraces

	mov     BYTE ptr [DI+D_retraceCount],al ; retrace is at this count

	dec     al                              ; retraceCount - 1
	mov     BYTE ptr [DI+D_resyncCheckTick],al      ; check resync at this count

	add     al, 4                           ; retraceCount + 3
	mov     BYTE ptr [DI+D_resyncMissTick],al       ; force resync at this count

	mov     al, BYTE ptr [DI+D_retraceCount]
    IF USE_TICK_ADJUST OR USE_LEAN_MEAN
    ELSE
	add     al, BYTE ptr [DI+D_flipEyeOffset]       ; retraceCount+flipEyeOffset
    ENDIF
	mov     BYTE ptr [DI+D_flipEyeTick],al          ; flip eyes at this count

	mov     al, BYTE ptr [DI+D_retraceCount]
	mov     bl, al
        shr     bl, 3
	sub     al, bl
	dec     al                              ; (7/8)*retraceCount - 1
    IF USE_TICK_ADJUST
	add     al, BYTE ptr [DI+D_flipEyeOffset] ; +flipEyeOffset adjust
    ENDIF
	mov     BYTE ptr [DI+D_flipScreenTick],al       ;flip screens at this count

	mov     BYTE ptr [DI+D_mode],3          ; switch to mode 3

	mov     BYTE ptr [DI+D_countTick],0     ; clear # ticks since retrace
	mov     BYTE ptr [DI+D_countTickEye],0  ; clear # ticks since retrace

	mov     BYTE ptr [DI+D_flippedEyes],0   ; reset flipped eyes status

@RM2@394:
	jmp     @RMtimerModeBreak               ; end of mode 2 code

@RMtimerMode3:    ; Mode 3: 3D mode

	inc     BYTE ptr [DI+D_countTick]       ; update # ticks since retrace
	inc     BYTE ptr [DI+D_countTickEye]    ; update # ticks since retrace

	; Is it time to flip screen pages?
	mov     al,BYTE ptr [DI+D_countTick]
	cmp     al,BYTE ptr [DI+D_flipScreenTick]
	je      @RMtimerCheckVesa
	jmp     @RMtimerEndFlipScreen           ; nope

@RMtimerCheckVesa: ; Check if we should flip the screen by VESA or by VGA
	cmp     BYTE ptr [DI+D_vesaMode],0 ; in vga mode?
	jne     @RMtimerVesaFlip

@RMtimerVgaFlip:
	mov     dx,CRTC_ADDR
	in      al,dx                   ; save old CRTC index
	mov     bl,al

	cmp     BYTE ptr [DI+D_page],0  ; which page to show?
	jne     @RM2@506                ; if we are on 1, jump to show 0

	; show right eye (we are on left eye)
	mov     ah,byte ptr [DI+D_startRightX+1]
	mov	al,SAHR
	out     dx,ax
	mov     ah,byte ptr [DI+D_startRightX]
	mov	al,SALR
	out     dx,ax
	jmp     @RM2@534

@RM2@506:
	; show left eye (we are on right eye)
	mov     ah,byte ptr [DI+D_startLeftX+1]
	mov	al,SAHR
	out     dx,ax
	mov     ah,byte ptr [DI+D_startLeftX]
	mov	al,SALR
	out     dx,ax

@RM2@534:
	mov     al,bl
	out     dx,al                   ; restore old CRTC index

	jmp     @RMtimerEndFlipScreen   ; continue (jump past Vesa page code)

@RMtimerVesaFlip:
	mov     ax, 4f07h               ; VESA set start address function
	mov     bx, 0000h               ;  bx = 0 --> set function

	cmp     BYTE ptr [DI+D_page],0  ; which page to show?
	jne     @RMtimerVesa1

	mov     cx, word ptr [DI+D_startRightX] ; we are on 0, so show 1 (right)
	mov     dx, word ptr [DI+D_startRightY] ;  dx = Y start address
	jmp     @RMtimerVesa2

@RMtimerVesa1:
	mov     cx, word ptr [DI+D_startLeftX]	; we are on 1, show 0 (left)
	mov     dx, word ptr [DI+D_startLeftY]	;  dx = Y start address

@RMtimerVesa2:
        push    DS
        push    DI
IF USE_VIDEO_BIOS
        pushf
        call    DWORD ptr [DI+D_rm_old10]       ; call old INT 10h (VESA)
ELSE
    IF  USE_VESA_BIOS
        cmp     WORD ptr [DI+D_pm_setxy],bx     ; valid VESA 2.0 pointer ?
        jne     @RMvesa20
        cmp     WORD ptr [DI+D_pm_setxy+2],bx
        jne     @RMvesa20

        int     10h                     ; call video BIOS for VESA 1.2
        jmp     @RMvesa12

@RMvesa20:
        mov     si, word ptr [DI+D_page]
        int     INTR_VESA2              ; call video BIOS for VESA 2.0

@RMvesa12:
    ELSE
        int     10h                     ; call video BIOS service
    ENDIF       ;; USE_VESA_BIOS
ENDIF           ;; USE_VIDEO_BIOS
        pop     DI
        pop     DS

@RMtimerEndFlipScreen:  ; Is it time to flip eye (glasses) visible pages?
	mov     al,BYTE ptr [DI+D_countTickEye]
	cmp     al,BYTE ptr [DI+D_flipEyeTick]
        jl      @RMtimerEndFlipEyes             ; no, it is not time yet
@RMskip111:

	cmp     BYTE ptr [DI+D_flippedEyes],0   ; have we already flipped them?
	jne     @RMtimerEndFlipEyes             ; yep, so skip this part
@RMskip222:

	; flip eyes (left <--> right)

	cmp     al,BYTE ptr [DI+D_countTick]    ; did vert. retrace occur yet?
	jne     @RMtimerFlipEyeAfterRetrace     ; yep -- special handler

	; flip eyes before retrace is detected
	cmp     BYTE ptr [DI+D_nailRetrace], 0  ; wait for exactly retrace?
	je      @RMtimerNoNail
	mov     dx,STA0_ADDR                    ; read retrace bit
@RMtimerNail:
        in      al,dx
	test    al,80h
	je      @RMtimerNail                    ; loop back if not at retrace
	inc	BYTE ptr [DI+D_delayCount]	; notify apps of delay
@RMtimerNoNail:
	inc     BYTE ptr [DI+D_flippedEyes]     ; mark eyes as flipped
		; Note:  retrace will reset this flag and countTickEye
	jmp     @RMtimerFlipEyesCont

@RMtimerFlipEyeAfterRetrace:      ; flip eyes after retrace was detected
	mov     al,BYTE ptr [DI+D_countTick]
	mov     BYTE ptr [DI+D_countTickEye],al ; reset countTickEye by
						;  the previous retrace
@RMtimerFlipEyesCont:
	cmp     BYTE ptr [DI+D_page],0 	        ; are we on left eye now?
	jne     @RM2@646                        ; no

	; we are on left eye
	; flip glasses to right eye manually, if necessary
IF USE_OEM
_RMupdateOemRight_:
	push	ax
	push	dx
	mov	al,byte ptr [DI+D_svr_oem]
        or      al,al
        jz      @RMrightx
	cmp	al,OEM1
	je	@RMright1
	cmp	al,OEM2
	je	@RMright2
	cmp	al,OEM3
	je	@RMright3
	cmp	al,OEM4
	je	@RMright4
	cmp	al,OEM5
	je	@RMright5
	jmp	@RMrightx

@RMright1:      ; update Brooktree port
@RMright3:      ; update diagnostic port
        mov     dx,word ptr[DI+D_oem_port]   ; OEM port
        mov     al,byte ptr[DI+D_oem_dataR]  ; OEM right eye poke
        out     dx,al
	jmp	@RMrightx

@RMright4:      ; update Alliance port
        mov     dx,03C4h
        in      al,dx
        mov     bl,al
        IODELAY
        IODELAY
        mov     ax,331Dh
        out     dx,ax
        IODELAY
        mov     dx,word ptr[DI+D_oem_port]   ; Alliance port
        mov     ax,0180h
        out     dx,ax
        IODELAY
        mov     dx,03C4h
        mov     al,bl
        out     dx,al
	jmp	@RMrightx

@RMright5:
        mov     dx,03C4h
        in      al,dx
        mov     bl,al
        IODELAY
        IODELAY
        mov     ax,331Dh
        out     dx,ax
        IODELAY
        mov     dx,word ptr[DI+D_oem_port]   ; Alliance port
        mov     ax,2020h
        out     dx,ax
        IODELAY
        mov     al,20h
        out     dx,al
        IODELAY
        mov     dx,03C4h
        mov     al,bl
        out     dx,al
	jmp	@RMrightx

@RMright2:      ; Rendition is auto-flipping
@RMrightx:
	pop	dx
	pop	ax
ENDIF   ;; USE_OEM

	mov     BYTE ptr [DI+D_page],1  ; tell ptr we are now on right eye
	jmp     @RMtimerEndFlipEyes

@RM2@646: ; we are on right eye
	; flip glasses to left eye manually, if necessary
IF USE_OEM
_RMupdateOemLeft_:

	push	ax
	push	dx
	mov	al,byte ptr [DI+D_svr_oem]
        or      al,al
        jz      @RMleftx
	cmp	al,OEM1
	je	@RMleft1
	cmp	al,OEM2
	je	@RMleft2
	cmp	al,OEM3
	je	@RMleft3
	cmp	al,OEM4
	je	@RMleft4
	cmp	al,OEM5
	je	@RMleft5
	jmp	@RMleftx

@RMleft1:       ; update Brooktree port
@RMleft3:       ; update diagnostic port
        mov     dx,word ptr[DI+D_oem_port]   ; OEM port
        mov     al,byte ptr[DI+D_oem_dataL]  ; OEM left eye poke
        out     dx,al
	jmp	@RMleftx

@RMleft4:       ; update Alliance port
        mov     dx,03C4h
        in      al,dx
        mov     bl,al
        IODELAY
        IODELAY
        mov     ax,331Dh
        out     dx,ax
        IODELAY
        mov     dx,word ptr[DI+D_oem_port]   ; Alliance port
        mov     ax,0080h
        out     dx,ax
        IODELAY
        mov     dx,03C4h
        mov     al,bl
        out     dx,al
	jmp	@RMleftx

@RMleft5:
        mov     dx,03C4h
        in      al,dx
        mov     bl,al
        IODELAY
        IODELAY
        mov     ax,331Dh
        out     dx,ax
        IODELAY
        mov     dx,word ptr[DI+D_oem_port]   ; Alliance port
        mov     ax,2020h
        out     dx,ax
        IODELAY
        mov     al,00h
        out     dx,al
        IODELAY
        mov     dx,03C4h
        mov     al,bl
        out     dx,al
	jmp	@RMleftx

@RMleft2:       ; Rendition is auto-flipping
@RMleftx:
	pop	dx
	pop	ax
ENDIF   ;; USE_OEM

	mov     BYTE ptr [DI+D_page],0  ; tell ptr we are now on left eye

@RMtimerEndFlipEyes: ; Is it time to start checking the vertical interrupt bit?
	mov     al,BYTE ptr [DI+D_countTick]
	cmp     al,BYTE ptr [DI+D_resyncCheckTick]
	je 	@@RM6                   ; check: countTick = resyncCheckTick
	jg 	@@RM6a                  ; check: countTick > resyncCheckTick
	jmp     @RMtimerEndResync       ; do not check yet

@@RM6:    ; did the vertical interrupt bit go off?
	mov     dx,STA0_ADDR
	in      al,dx
	test    al,80h
	je      @RMtimerNoVertInt       ; nope

	; yes -- we checked, and the vertical interrupt bit was set, so
	; vertical retrace has started (or maybe even past).  However, we
	; just started checking on this tick.  We may be way off.  Therefore,
	; we must start watching earlier (decrease *Tick).  Especially start
	; checking earlier for the next immediate retrace (reset countTick
	; to 1).

	dec     BYTE ptr [DI+D_resyncCheckTick] ; check earlier
	jg      @@RM6b                          ; is it <= 0?
	mov     BYTE ptr [DI+D_resyncCheckTick],1      ; Yes.  1 = min value

@@RM6b:
        mov     BYTE ptr [DI+D_countTick],1   ; clear # ticks since retrace

	jmp 	@RMtimerRecalibrateCont


@@RM6a:   ; did the vertical interrupt bit go off?
	mov     dx,STA0_ADDR
	in      al,dx
	test    al,80h
	je      @RMtimerNoVertInt       ; nope

	; yes -- we checked, and the vertical interrupt bit was set, so
	; vertical retrace has started (or maybe even past)

	mov     BYTE ptr [DI+D_countTick],0     ; clear # ticks since retrace

@RMtimerRecalibrateCont:
IF USE_DOS_TICKER
	mov     BYTE ptr [DI+D_timerCheckRTC], 0 ;tell DOS timer that RTC is on
ENDIF
	mov     BYTE ptr [DI+D_pageAdvanced], 1	; inform all that retrace came

	cmp     BYTE ptr [DI+D_flippedEyes],0   ; eyes flipped before retrace?
	je      @RMtimerClearNoEyeFlipA         ; nope

	; Eye flipped before retrace
	mov     BYTE ptr [DI+D_flippedEyes],0   ; reset flipped eyes status
	mov     BYTE ptr [DI+D_countTickEye],0  ; reset eye count

@RMtimerClearNoEyeFlipA:
	VERT_RETRACE_CLEAR_16           ; clear vert. intr. and reset for next retrace

	jmp     @RMtimerEndResync

@RMtimerNoVertInt: ; did we completely miss the vertical retrace?
	; assume we did if (countTick >= resyncMissTick)
	mov     al,BYTE ptr [DI+D_resyncMissTick]
	cmp     al,BYTE ptr [DI+D_countTick]
	jg      @RMtimerEndResync       ; no, countTick did not get there yet

	; Somehow the vert. ret. signal was missed (it is 3 ticks overdue).
	; Estimate time using retraceCount and resync on next retrace...
IF USE_ISR_TRACE
	inc     word ptr [DI+D_countMisses]     ; mark the miss for debug
ENDIF
        mov     al,BYTE ptr [DI+D_retraceCount]
	sub     BYTE ptr [DI+D_countTick],al    ; subtract off 1 retrace time

IF USE_DOS_TICKER
	mov     BYTE ptr [DI+D_timerCheckRTC], 0 ;tell DOS timer that RTC is on
ENDIF
	mov     BYTE ptr [DI+D_pageAdvanced], 1	; inform all that retrace came

	cmp     BYTE ptr [DI+D_flippedEyes],0   ; eyes flipped before retrace?
	je      @RMtimerClearNoEyeFlipB         ; nope

	; Eye flipped before retrace
	mov     BYTE ptr [DI+D_flippedEyes],0   ; reset flipped eyes status
	mov     al, BYTE ptr [DI+D_countTick]
	mov     BYTE ptr [DI+D_countTickEye],al ; reset eye count

@RMtimerClearNoEyeFlipB:
	VERT_RETRACE_CLEAR_16           ; clear vert. intr. and reset for next retrace

@RMtimerEndResync:
	jmp     @RMtimerModeBreak       ; end of mode 3 code

@RMtimerMode4:    ; Mode 4: Resync mode

	; did the vertical interrupt bit go off?
	mov     dx,STA0_ADDR
	in      al,dx
	test    al,80h
	je      @RMtimerModeBreak       ; nope -- exit routine

	; vertical interrupt bit fired, so resync all timers
	VERT_RETRACE_CLEAR_16           ; clear vert. intr. and reset for next retrace
IF USE_DOS_TICKER
	mov     BYTE ptr [DI+D_timerCheckRTC],0 ;tell DOS timer that RTC is on
ENDIF
	mov     BYTE ptr [DI+D_countTick],0     ; clear # ticks since retrace
	mov     BYTE ptr [DI+D_countTickEye],0  ; clear # ticks since retrace

	mov     BYTE ptr [DI+D_flippedEyes],0   ; reset flipped eyes status

	mov     BYTE ptr [DI+D_mode],3          ; switch to mode 3

	jmp     @RMtimerModeBreak               ; end of mode 4 code

IF USE_LEAN_MEAN
@RMtimerMode5:  ; Mode 5: lean-n-mean immediate page-flip mode

	; Is it time to flip screen pages?
	; did the vertical interrupt bit go off?
	mov     dx,STA0_ADDR
	in      al,dx
	test    al,80h
	jz      @RMtimerModeBreak       ; nope -- exit routine

        ; make sure retrace is over
        mov     dx,STA1_ADDR
@RMtail:in      al,dx
        test    al,08h                  ; poll sync
        jnz     @RMtail

	VERT_RETRACE_CLEAR_16      ; clear vert. intr. and reset for next retrace

@RMtimerCheckVesa5: ; Check if we should flip the screen by VESA or by VGA
	cmp     BYTE ptr [DI+D_vesaMode],0     ; in vga mode?
	jne     @RMtimerVesaFlip5

@RMtimerVgaFlip5:
	mov     dx,CRTC_ADDR
	in      al,dx                   ; save old CRTC index
	mov     bl,al

	cmp     BYTE ptr [DI+D_page],0  ; which page to show?
	jne     @RM2@5065               ; if we are on 1, jump to show 0
        mov     byte ptr [DI+D_page],1  ; else toggle page index to 1

	; show right eye (we are on left eye)
	mov     ah,byte ptr [DI+D_startRightX+1]
	mov	al,SAHR
	out     dx,ax
	mov     ah,byte ptr [DI+D_startRightX]
	mov	al,SALR
	out     dx,ax

	jmp     @RM2@5345

@RM2@5065:
        mov     byte ptr [DI+D_page],0  ; or toggle page index to 0
	; show left eye (we are on right eye)
	mov     ah,byte ptr [DI+D_startLeftX+1]
	mov	al,SAHR
	out     dx,ax
	mov     ah,byte ptr [DI+D_startLeftX]
	mov	al,SALR
	out     dx,ax

@RM2@5345:
	mov     al,bl
	out     dx,al                   ; restore old CRTC index

	jmp     @RMtimerEndFlipScreen5  ; continue (jump past Vesa page code)

@RMtimerVesaFlip5:
	mov     ax, 4f07h               ; VESA set start address function
	mov     bx, 0000h               ;  bx = 0 --> set function

	cmp     BYTE ptr [DI+D_page],0  ; which page to show?
	jne     @RMtimerVesa15
        mov     byte ptr [DI+D_page],1  ;  else toggle page index to 1

	mov     cx, WORD ptr [DI+D_startRightX]      ; we are on 0, so show 1 (right)
	mov     dx, WORD ptr [DI+D_startRightY]      ;  dx = Y start address
	jmp     @RMtimerVesa25

@RMtimerVesa15:
        mov     byte ptr [DI+D_page],0  ; or toggle page index to 0
	mov     cx, WORD ptr [DI+D_startLeftX]	; we are on 1, show 0 (left)
	mov     dx, WORD ptr [DI+D_startLeftY]	;  dx = Y start address

@RMtimerVesa25:
        push    DS
        push    DI
IF USE_VIDEO_BIOS
        pushf
        call    dword ptr [DI+D_rm_old10]       ; call old real-mode INT 10h (VESA)
ELSE
    IF  USE_VESA_BIOS
        cmp     WORD ptr [DI+D_pm_setxy],bx     ; valid VESA 2.0 pointer ?
        jne     @RMvesa205
        cmp     WORD ptr [DI+D_pm_setxy+2],bx
        jne     @RMvesa205

        int     10h                     ; call video BIOS for VESA 1.2
        jmp     @RMvesa125

@RMvesa205:
        mov     si, word ptr [DI+D_page]
        int     INTR_VESA2              ; call video BIOS for VESA 2.0

@RMvesa125:
    ELSE
        int     10h                     ; call video BIOS service
    ENDIF       ;; USE_VESA_BIOS
ENDIF           ;; USE_VIDEO_BIOS
        pop     DI
        pop     DS

@RMtimerEndFlipScreen5:
        jmp     @RMtimerModeBreak
ENDIF   ;; USE_LEAN_MEAN

@RMtimerModeBreak:
; Note:  We must tell the RTC and the PICs that we have handled the interrupt
;        request.  There are 3 ways to do this: (A) let BIOS do it, but keep
;        the BIOS wait count high so that it does not turn the timer off;
;        (B) let BIOS do it, and re-enable RTC interrupts afterwords if they
;        were disabled by BIOS; and (C) tell them directly and skip BIOS.
;        I am using method (C).  It is the safest, as long as the BIOS
;        RTC routines are not needed.
;--------------------------------
; RTC handler method (A):
;    Call old (BIOS) handler for the interrupt.  It will take care of the
;    PICs and the RTC.  We will make sure that DOS never decides to turn off
;    the periodic interrupt by keeping the DOS timer counter >> 0.
; Problem:  No other program can use the RTC timer (wait: INT 15h AH=83h, 85h)
;    functions, since we alter its value.  RTC alarm can be used, and any
;    other things that BIOS/TSRs do during IRQ 8 are also enabled.
;
;       mov     dx,0040h
;       mov     es,dx         ;BIOS data area = 0040:xxxx
;       mov     di,009eh      ;offset of wait count (high byte, in 1/1024 sec)
;       mov     dx,1000h
;       mov     es:[di],dx    ;put a large number there
;
;       pushf
;       call    dword ptr DGROUP:_oldhandler
;
;--------------------------------
; RTC handler method (B):
;    Call old (BIOS) handler for the interrupt.  It will take care of the
;    PICs and the RTC.  Just make sure periodic interrupt is on after DOS
;    (maybe) turns it off.
; Problem:  None!!!  Except for some reason, it does not work on all
;    machines.  Give me a machine that it does not work on (I have not been
;    able to verify it personally), and I'll find out why!!!  Maybe the
;    PIC is being disabled...  -D.S.
;
;       pushf
;       call    dword ptr DGROUP:_oldhandler
;       cli
;
;       mov     dx,CMOS_ADDR
;       mov     al,CMOS_B
;       out     dx,al           ;select CMOS register B (enable interrupts)
;       inc     dx
;
;       mov     ax,5            ;delay for slow clock chips
;@RM2@842a: dec   ax
;       jg      @RM2@842a
;
;       in      al,dx           ;read register B
;       test    al,40h          ;check if periodic interrupt is on
;       jne     @RM2@842c
;
;       or      al,40h          ;enable periodic interrupt
;       mov     bl,al           ;save new register B
;
;       mov     dx,CMOS_ADDR
;       mov     al,CMOS_B
;       out     dx,al           ;select CMOS register B (enable interrupts)
;       inc     dx
;
;       mov     ax,10           ;delay for slow clock chips
;@RM2@842b: dec   ax
;       jg      @RM2@842b
;
;       mov     al,bl           ;new register B to write
;       out     dx,al           ;write new CMOS register B
;
;@RM2@842c:
;--------------------------------

; RTC handler method (C):
;           We can use the code below *instead* of calling DOS's old handler
; Problem:  The timer and alarm functions (INT 1h; INT 15h AH=83h, 85h) will
;           not work
;

ENDIF   ;; USE_ISR

	RTC_CLEAR               ; clear pending interrupt from RTC

	mov     al,20h
	out     0a0h,al         ; clear pending interrupt from PIC 2
	out     020h,al         ; clear pending interrupt from PIC 1

	pop     ds
	popa

	iret			;16-bit stack frame return

_RMvertRet16_        endp

IF USE_RM_JMPTBL	;; no jump table for relocatable code (DaveM)
@RMtimerModeTable label   word		; 16-bit jump table for RTC timer Mode
	dw      @RMtimerMode0
	dw      @RMtimerMode1
	dw      @RMtimerMode2
	dw      @RMtimerMode3
	dw      @RMtimerMode4
ENDIF   ; USE_RM_JMPTBL

_RMvertRet16end_	dd 0

_CODE16	ends


	END


