; SVRDOS32 SimulEyes VR driver for DPMI 32-bit extender DOS/4G.
; Written by DaveM for StereoGraphics Inc.

; Video module for SVRDOS4G driver.
; (Equivalent to "modex.c" C prototype code.)
; Supports only 320x200 graphics mode-X for page-swapping.

	.386P
	.MODEL	FLAT

	INCLUDE	SVRDEF.INC
	INCLUDE	SVRDOS32.INC

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_DATA	SEGMENT PUBLIC DWORD USE32 'DATA'

	ASSUME	DS:_DATA

        ALIGN   4

; use 32-bit double-words wherever possible
; parameters are passed via registers wherever possible

	PUBLIC	_vmode
        PUBLIC  _xres
        PUBLIC  _yres
        public  _xmax, _ymax, _imax, _vmax
        public  _ileft_front, _iright_front, _ileft_back, _iright_back
        public  _vleft_front, _vright_front, _vleft_back, _vright_back

_vmode	dd	13h                     ; current video mode
_xres	dd	320                     ; X resolution
_yres	dd	200                     ; Y resolution

_xmax   dd      320                     ; max X coordinate
_ymax   dd      199                     ; max Y coordinate
_imax   dd      15920                   ; max pixel index (mode-X)
_vmax   dd      000A0000h+15920         ; max pixel address

_ileft_front    dd 0                    ; index to left front buffer
_iright_front   dd 4000h                ; index to right front buffer
_ileft_back     dd 8000h                ; index to left back buffer
_iright_back    dd 0C000h               ; index to right back buffer

_vleft_front    dd 000A0000h            ; video address to left front buffer
_vright_front   dd 000A4000h            ; video address to right front buffer
_vleft_back     dd 000A8000h            ; video address to left back buffer
_vright_back    dd 000AC000h            ; video address to right back buffer

_DATA	ENDS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_CODE	SEGMENT PUBLIC DWORD USE32 'CODE'

	ASSUME	CS:_CODE,DS:_DATA

; After immediate entry into each SVR driver function, selectors become:
;       CS <-- SVR driver code selector
;       DS <-- SVR driver data selector (local)
;       ES <-- application data selector (global)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; InitModexLocals
; Init local variables in SVR MODEX module.
; entry:
;       void
; return:
;       void

	PUBLIC	InitModexLocals_

        ALIGN   4

InitModexLocals_	PROC near

	xor	eax,eax   	;zero defaults
	mov	[_vmode],eax
	ret

InitModexLocals_	ENDP


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; GetVideoMode
; Gets VGA video mode via BIOS call.
; entry:
;       void
; return:
; 	EAX <-- video mode

	PUBLIC	xGetVideoMode_

        ALIGN   4

xGetVideoMode_	PROC near

	mov	ax,0F00h	;get mode function
	int	10h		;call video BIOS
	and	eax,000000FFh	;mode in AL
	ret

xGetVideoMode_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SetVideoMode
; Sets VGA video mode via BIOS call.
; on entry:
; 	EBX <-- video mode
; entry:
;       void
; return:
;       void


	PUBLIC	xSetVideoMode_

        ALIGN   4

xSetVideoMode_	PROC near

	mov	al,bl    	;get mode #
	mov	ah,00h		;set mode function
	int	10h		;call video BIOS
	ret

xSetVideoMode_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SetPaletteMode
; Sets palette protection with video mode sets
; entry:
;	EBX <-- protection mode
; return:
;       void


	public	xSetPaletteMode_

        ALIGN   4

xSetPaletteMode_	proc near

	mov	al,bl		;get palette protection flag
	and	al,01h		;01h = protect; 00h = reset
	mov	ah,12h		;misc option function
	mov	bl,31h		;change option sub-function
	int	10h		;call video BIOS
	ret

xSetPaletteMode_	endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SetTextMode
; Sets VGA video to text mode.
; entry:
;       void
; return:
;       void


	PUBLIC  xSetTextMode_

        ALIGN   4

xSetTextMode_	PROC near

	xor	ebx,ebx
	mov	bl,03h		;set text mode 03
	mov	[_vmode],ebx	;save text mode 03
	call	xSetVideoMode_	;set video mode
	ret

xSetTextMode_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SetGraphMode13
; Sets VGA video to graphics mode 13, 320x200 in 1 single page.
; entry:
;       void
; return:
;       void


	PUBLIC	xSetGraphMode13_

        ALIGN   4

xSetGraphMode13_	PROC near

	xor	ebx,ebx
	mov	bl,13h		;set graphics mode 13
	mov	[_vmode],ebx	;save graphics mode 13
	call	xSetVideoMode_	;set video mode
	mov	[_xres],320	;save x resolution
	mov	[_yres],200	;save y resolution
	ret

xSetGraphMode13_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SetGraphModeX
; Sets VGA video to graphics mode X, 320x200 in 4 pages.
; entry:
;       void
; return:
;       void

	PUBLIC  xSetGraphModeX_
        public  xSetGraphModeX200_

        ALIGN   4

xSetGraphModeX_	PROC near
xSetGraphModeX200_:

	call	xSetGraphMode13_	;set graphics mode 13 (for 320x200)
	mov	[_vmode],14h	;save flag for mode X (vs mode 13)

	mov	dx,03C4h	;select VGA sequencer reg
	mov	ax,0604h	;...chain all 4 planes together
	out	dx,ax
	IODELAY

	mov	dx,03D4h	;select CRT controller registers
	mov	al,11h		;CRT protection reg
	out	dx,al
	IODELAY
	IODELAY
	inc	dx
	in	al,dx
	and	al,7Fh		;...change to write enable
	IODELAY
	IODELAY
	out	dx,al
	dec	dx
	IODELAY
	mov	ax,4109h	;CRT row reg --> double scan (for 200 lines)
	out	dx,ax
	IODELAY
	mov	ax,0014h	;CRT row reg --> single word data
	out	dx,ax
	IODELAY
	mov	ax,0E317h	;CRT mode reg --> byte access
	out	dx,ax
	IODELAY
	mov	al,11h		;CRT protection reg
	out	dx,al
	IODELAY
	IODELAY
	inc	dx
	in	al,dx
	or 	al,80h		;...back to write protected
	IODELAY
	IODELAY
	out	dx,al
	dec	dx
	IODELAY

	mov	dx,03C4h	;sequencer reg
	mov	ax,0F02h	;mask all 4 planes at once
	out	dx,ax
	IODELAY
	mov	ecx,00004000h	;for 64k in quads
	xor	eax,eax		;set blank color
	mov	edi,000A0000h	;at VGA memory location
	mov	edx,[_app_dsel]	;get default DS
	mov	es,dx		;use default DS for VGA
	cld
	rep	stosd		;blank all VGA memory in quads
	mov	dx,03C4h	;sequencer reg
	mov	ax,0102h	;leave mask set for only 1st plane
	out	dx,ax
	IODELAY
	ret

xSetGraphModeX_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SetGraphModeX400
; Sets VGA video to graphics mode X, 320x400 in 2 pages.
; entry:
;       void
; return:
;       void

	PUBLIC  xSetGraphModeX400_

        ALIGN   4

xSetGraphModeX400_	PROC near

	call	xSetGraphModeX_	;set graphics mode X for 320x200
	mov	[_vmode],15h	;change flag for mode X (vs mode 13)
        mov     [_yres],400     ;change size for 320x400 (vs 320x200)

	mov	dx,03D4h	;select CRT controller registers
	mov	ax,4009h	;CRT row reg --> single scan for 400 lines
	out	dx,ax
	IODELAY
	ret

xSetGraphModeX400_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SetGraphModeX240
; Sets VGA video to graphics mode X 320x240 in 2 pages.
; entry:
;       void
; return:
;       void

	PUBLIC  xSetGraphModeX240_

        ALIGN   4

xSetGraphModeX240_	PROC near

	call	xSetGraphMode13_	;set graphics mode 13
	mov	[_vmode],16h	;change flag for mode X (vs mode 13)
        mov     [_yres],240     ;change size for 320x240 (vs 320x200)

	mov	dx,03C4h	;select VGA sequencer reg
	mov	ax,0604h	;...chain all 4 planes together
	out	dx,ax
	IODELAY
	mov	ax,0100h	;...sequencer reset clock disable
	out	dx,ax
	IODELAY
        dec     dx
        dec     dx              ;select VGA misc reg
	mov	al,0C3h         ;...sync polarity output for 480 lines
        out	dx,al
	IODELAY
        inc     dx
        inc     dx              ;re-select VGA sequencer reg
	mov	ax,0300h	;...sequencer reset clock enable
	out	dx,ax
	IODELAY

	mov	dx,03D4h	;select CRT controller registers
	mov	al,11h		;CRT protection reg
	out	dx,al
	IODELAY
	IODELAY
	inc	dx
	in	al,dx
	and	al,7Fh		;...change to write enable
	IODELAY
	IODELAY
	out	dx,al
	dec	dx
	IODELAY
	mov	ax,0D06h        ;CRT vertical total
	out	dx,ax
	IODELAY
	mov	ax,3E07h        ;CRT vertical sync position
	out	dx,ax
	IODELAY
	mov	ax,0EA10h       ;CRT vertical sync start
	out	dx,ax
	IODELAY
	mov	ax,0AC11h       ;CRT vertical sync end
	out	dx,ax
	IODELAY
	mov	ax,0DF12h       ;CRT vertical display end
	out	dx,ax
	IODELAY
	mov	ax,0E715h       ;CRT start vertical blank
	out	dx,ax
	IODELAY
	mov	ax,0616h        ;CRT end vertical blank
	out	dx,ax
	IODELAY
	mov	ax,4109h	;CRT row reg --> double scan for 240 lines
	out	dx,ax
	IODELAY
	mov	ax,0014h	;CRT row reg --> single word data
	out	dx,ax
	IODELAY
	mov	ax,0E317h	;CRT mode reg --> byte access
	out	dx,ax
	IODELAY
	mov	al,11h		;CRT protection reg
	out	dx,al
	IODELAY
	IODELAY
	inc	dx
	in	al,dx
	or 	al,80h		;...back to write protected
	IODELAY
	IODELAY
	out	dx,al
	dec	dx
	IODELAY

	mov	dx,03C4h	;sequencer reg
	mov	ax,0F02h	;mask all 4 planes at once
	out	dx,ax
	IODELAY
	mov	ecx,00004000h	;for 64k in quads
	xor	eax,eax		;set blank color
	mov	edi,000A0000h	;at VGA memory location
	mov	edx,[_app_dsel]	;get default DS
	mov	es,dx		;use default DS for VGA
	cld
	rep	stosd		;blank all VGA memory in quads
	mov	dx,03C4h	;sequencer reg
	mov	ax,0102h	;leave mask set for only 1st plane
	out	dx,ax
	IODELAY
	ret

xSetGraphModeX240_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SetGraphModeX480
; Sets VGA video to graphics mode X 320x480, which fits only in 1 page.
; entry:
;       void
; return:
;       void

	PUBLIC  xSetGraphModeX480_

        ALIGN   4

xSetGraphModeX480_	PROC near

	call	xSetGraphModeX240_	;set graphics mode X for 320x240
	mov	[_vmode],17h	;change flag for mode X (vs mode 13)
        mov     [_yres],480     ;change size for 320x480 (vs 320x200)

	mov	dx,03D4h	;select CRT controller registers
	mov	ax,4009h	;CRT row reg --> single scan for 480 lines
	out	dx,ax
	IODELAY
	ret

xSetGraphModeX480_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SetPaletteColor
; Sets VGA palette register to selected RGB color values.
; entry:
; 	BL <-- palette color index
; 	BH <-- red
; 	CL <-- green
; 	CH <-- blue
; return:
;       void

	PUBLIC	xSetPaletteColor_

        ALIGN   4

xSetPaletteColor_	PROC near

	mov	dx,03C8h	;VGA palette select reg
	mov	al,bl		;palette #
	out	dx,al
	IODELAY
	mov	dx,03C9h	;VGA palette write reg
	mov	al,bh		;red value
	out	dx,al
	IODELAY
	mov	al,cl		;green value
	out	dx,al
	IODELAY
	mov	al,ch		;blue value
	out	dx,al
	IODELAY
	ret

xSetPaletteColor_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; PlotPixel
; Plots pixel directly into video memory.
; Note magic number trick in 320x200 mode:
; index = 320*y + x = (64 + 256)*y + x.
; entry:
; 	EBX <-- pixel X
; 	ECX <-- pixel Y
; 	EDX <-- pixel color
;        ES <-- application data selector (global)
; return:
;       void

	PUBLIC  xPlotPixel_

        ALIGN   4

xPlotPixel_	PROC near

	mov	eax,[_vmode]	;check graphics mode
	cmp	al,13h		;vanilla mode 13 ?
	jne	xPlotPixelX_	;or mode X ?

xPlotPixel0_:			;plot linear for vanilla mode 13

	shl	ecx,6		;y * 64
	add	ebx,ecx         ;... + x
	shl	ecx,2		;y * 256
	add	ebx,ecx		;... index = x + y*64 + y*256
        mov	edi,000A0000h	;VGA address
	add	edi,ebx
	mov	es:[edi],dl     ;plot pixel DL
	ret

        ALIGN   4

xPlotPixelX_:			;plot modulo-4 for mode X

	mov     esi,edx		;save color
	shl	ecx,6		;y * 64
	add	ebx,ecx         ;... + x
	shl	ecx,2		;y * 256
	add	ebx,ecx		;... index = x + y*64 + y*256

	mov	ecx,ebx         ;save index (EBX)
	and	cl,03h		;modulo 4 index
	mov	al,01h		;init VGA memory plane bit 1
	shl	al,cl		;compute VGA memory plane bit 1,2,3, or 4
	mov	dx,03C4h	;select VGA sequencer register
	mov     ah,al           ;...memory plane # (data)
	mov	al,02h		;...select memory plane register (index)
        out	dx,ax
	IODELAY

        shr	ebx,2		;divide index by 4 for mode X packing
	mov	edi,000A0000h	;VGA address
	add	edi,ebx
	mov     edx,esi		;get color
	mov	es:[edi],dl     ;output pixel to video mem
	ret

xPlotPixel_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; PlotPixelPageX
; Plots pixels directly into mode-x video memory.
; Optimized in case of repetitive calls.
; entry:
; 	EAX <-- page #
; 	EBX <-- pixel X
; 	ECX <-- pixel Y
; 	EDX <-- pixel color
;        ES <-- application data selector (global)
; return:
;       void
; Note magic number trick in 320x200 mode:
; index = 320*y + x = (64 + 256)*y + x.

	PUBLIC  xPlotPixelPageX_

        ALIGN   4

xPlotPixelPageX_	PROC near

	mov     esi,edx		;save color
	shl	ecx,6		;y * 64
	add	ebx,ecx         ;... + x
	shl	ecx,2		;y * 256
	add	ebx,ecx		;... index = x + y*64 + y*256

	mov	ecx,ebx         ;save index (EBX)
        shr	ecx,2		;divide index by 4 for mode X packing
	mov	edi,000A0000h	;VGA address
	add	edi,ecx         ;... + mode-x offset

	or	eax,eax		;page #0 ?
	jz	fpp1
        and	al,3		;limit to page #0,1,2,3
	movzx   ecx,al
	shl     ecx,2           ;DWORD index addressing
        lea     edx,[_ileft_front+ECX]  ;index table of page indexes
        mov     eax,dword ptr[EDX]      ;get video page index
        add	edi,eax		;mem <-- mem base + offset
fpp1:
	mov	ecx,ebx         ;restore index (EBX)
	and	cl,03h		;modulo 4 index
	mov	al,01h		;init VGA memory plane bit 1
	shl	al,cl		;compute VGA memory plane bit 1,2,3, or 4
	mov	dx,03C4h	;select VGA sequencer register
	mov     ah,al           ;...memory plane # (data)
	mov	al,02h		;...select memory plane register (index)
        out	dx,ax
	IODELAY

	mov     edx,esi		;get color pixel
	mov	byte ptr es:[edi],dl     ;output pixel to video mem
	ret

xPlotPixelPageX_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; FillPixel4
; Fills pixels 4 at a time directly into mode-x video memory.
; entry:
; 	EAX <-- page #
; 	EBX <-- mode-x video memory address index
; 	ECX <-- mode-x count
; 	EDX <-- pixel color
;        ES <-- application data selector (global)
; return:
;       void

	PUBLIC  xFillPixel4_

        ALIGN   4

xFillPixel4_	PROC near

	mov	edi,000A0000h	;init video memory destination
	add	edi,ebx		;adjust destination address by index
	mov	ebx,edx		;save pixel color to copy
	mov	dx,03C4h	;select VGA sequencer register
	mov	ax,0F02h	;select all 4 memory planes at once
	out	dx,ax
	IODELAY
	mov	eax,ebx		;re-transfer pixel color to copy
	mov	ah,al		;duplicate pixel byte
	shl	eax,16
	mov	al,bl		;duplicate 2x more
	mov	ah,al
	shr	ecx,2		;count by quads
	cld
	rep	stosd		;copy pixel in quads to all 4 planes at a time
	ret

xFillPixel4_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; MixMod4
; Mixes a block of linear pixel data into modulo-4 mode X format.
; on entry:
; 	DS:ESI <-- source pointer to linear buffer
; 	ES:EDI <-- destination pointer to modulo-4 buffer
;    	ECX <-- modulo-4 block size counter
; during operation:
;    	EBX <-- copy of source base pointer
;    	EAX <-- modulo-4 index for source pointer
;    	EDX <-- incrementing index for destination pointer
;	ECX <-- decrementing byte counter
; return:
;       void

	PUBLIC  xMixMod4_

        ALIGN   4

xMixMod4_	PROC near

	mov	ebx,esi		;copy source pointer
	cld
	push 	ecx		;save modulo-4 counter for other 3 blocks
	xor 	edx,edx		;init destination index
mix1:   mov 	eax,edx		;construct source index
	shl 	eax,2		;scale up by 4
	add 	eax,ebx		;+ source base address
	mov 	esi,eax		;...for 0th, 4th, 8th, 12th...
	movsb
	inc 	edx		;update running index
	LOOPM	mix1		;repeat for 1st mod-4 block
	pop 	ecx

	push 	ecx
	xor 	edx,edx
mix2:   mov 	eax,edx
	shl 	eax,2		;scale up by 4
	inc 	eax		;+ 1
	add 	eax,ebx		;+ source base
	mov 	esi,eax		;...for 1st, 5th, 9th, 13th...
	movsb
	inc 	edx
	LOOPM	mix2		;repeat for 2nd mod-4 block
	pop 	ecx

	push 	ecx
	xor 	edx,edx
mix3:   mov 	eax,edx
	shl 	eax,2		;scale up by 4
	inc 	eax
	inc 	eax		;+ 2
	add 	eax,ebx		;+ source base
	mov 	esi,eax		;...for 2nd, 6th, 10th, 14th...
	movsb
	inc 	edx
	LOOPM	mix3		;repeat for 3rd mod-4 block
	pop 	ecx

	xor 	edx,edx
mix4:   mov 	eax,edx
	shl 	eax,2		;scale up by 4
	inc 	eax
	inc 	eax
	inc 	eax		;+ 3
	add 	eax,ebx		;+ source base
	mov 	esi,eax		;...for 3rd, 7th, 11th, 15th...
	movsb
	inc 	edx
	LOOPM	mix4            ;repeat for 4th mod-4 block

	ret

xMixMod4_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; UnMixMod4
; Un-Mixes a block of modulo-4 mode X pixel data into linear order.
; on entry:
; 	DS:ESI <-- source pointer to modulo-4 buffer
; 	ES:EDI <-- destination pointer to linear buffer
;    	ECX <-- modulo-4 block size counter
; during operation:
;    	EBX <-- copy of destination base pointer
;    	EAX <-- modulo-4 index for destination pointer
;    	EDX <-- incrementing index for source pointer
;    	ECX <-- decrementing byte counter
; return:
;       void

	PUBLIC  xUnMixMod4_

        ALIGN   4

xUnMixMod4_	PROC near

	mov	ebx,edi		;copy destination pointer
	cld
	push 	ecx		;save modulo-4 counter for other 3 blocks
	xor 	edx,edx		;init source index
unmix1: mov 	eax,edx		;construct destination index
	shl 	eax,2		;scale up by 4
	add 	eax,ebx		;+ destination base address
	mov 	edi,eax		;...for 0th, 4th, 8th, 12th...
	movsb
	inc 	edx		;update running index
	LOOPM	unmix1		;repeat for 1st mod-4 block
	pop 	ecx

	push 	ecx
	xor 	edx,edx
unmix2: mov 	eax,edx
	shl 	eax,2		;scale up by 4
	inc 	eax		;+ 1
	add 	eax,ebx		;+ base
	mov 	edi,eax		;...for 1st, 5th, 9th, 13th...
	movsb
	inc 	edx
	LOOPM	unmix2		;repeat for 2nd mod-4 block
	pop 	ecx

	push 	ecx
	xor 	edx,edx
unmix3: mov 	eax,edx
	shl 	eax,2		;scale up by 4
	inc 	eax
	inc 	eax		;+ 2
	add 	eax,ebx		;+ base
	mov 	edi,eax		;...for 2nd, 6th, 10th, 14th...
	movsb
	inc 	edx
	LOOPM	unmix3		;repeat for 3rd mod-4 block
	pop 	ecx

	xor 	edx,edx
unmix4: mov 	eax,edx
	shl 	eax,2		;scale up by 4
	inc 	eax
	inc 	eax
	inc 	eax		;+ 3
	add 	eax,ebx		;+ base
	mov 	edi,eax		;...for 3rd, 7th, 11th, 15th...
	movsb
	inc 	edx
	LOOPM	unmix4		;repeat for 4th mod-4 block

	ret

xUnMixMod4_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; MovePixelPage
; Move a 64000-byte block of pixels to video memory page.
; on entry:
; 	EBX <-- page
; 	ECX <-- screenbuf address
;  	 DX <-- screenbuf selector
;  	 DS <-- SVR driver data selector (local)
;        ES <-- application data selector (global)
; during operation:
; 	DS:ESI <-- source address
; 	ES:EDI <-- destination address
; 	EBX <-- start source address per block
; 	ECX <-- block counter
; return:
;       void

	PUBLIC  xMovePixelPage_

        ALIGN   4

xMovePixelPage_	PROC near

	mov	eax,[_vmode]	;check graphics mode
	cmp	al,13h		;vanilla mode 13 ?
	jne	xMovePixelPageX_	;or mode X ?

xMovePixelPage0_:		;move pixels for linear mode 13

	mov	edi,000A0000h	;set destination address (only 1 page)
	mov	esi,ecx		;get source address <-- screenbuf
	push	ds		;save local DS
	mov	ds,dx		;get source selector
	mov	ecx,16000	;all pixels in quads
	cld
	rep	movsd		;transfer entire block in quads
	pop	ds		;restore local DS
	ret

        ALIGN   4

xMovePixelPageX_:		;move pixels for modulo-4 mode X

	push	edx		;save source selector
	mov	edx,000A0000h	;VGA mem base
	mov	eax,ebx    	;get page #0..3
	push	ecx		;save screenbuf source address

	or	eax,eax		;page #0 ?
	jz	mpp1
        and     al,3            ;limit to pages #0,1,2,3
        movzx   ecx,al
	shl     ecx,2           ;DWORD index addressing
        lea     ebx,[_ileft_front+ECX]  ;index table of page indexes
        mov     eax,dword ptr[EBX]      ;get video page index
mpp1:
	add	eax,edx		;mem <-- mem base + offset
	mov	edi,eax		;set destination address
	pop	eax		;restore screenbuf source address
	mov	esi,eax		;set source address
	pop	edx		;restore source selector

	push	ds		;save local DS
	mov	ds,dx		;set source selector

	mov	ebx,eax		;init source to 1st 1/4 block address
	mov	dx,03C4h	;sequencer reg
	mov	ax,0102h	;map mask for plane #1
	out	dx,ax
	IODELAY
	cld
	mov	ecx,4000	;1/4 pixels in quads
	rep	movsd		;transfer 1st block in quads

	mov	dx,03C4h	;sequencer reg
	mov	ax,0202h	;map mask for plane #2
	out	dx,ax
	IODELAY
	mov	eax,edi
	sub	eax,16000	;reset VGA mod-4 destination for next block
	mov	edi,eax
	add	ebx,16000	;advance source pointer to next 1/4 block
	mov     esi,ebx
	mov	ecx,4000	;1/4 pixels in quads
	rep	movsd		;transfer 2nd block in quads

	mov	dx,03C4h	;sequencer reg
	mov	ax,0402h	;map mask for plane #3
	out	dx,ax
	IODELAY
	mov	eax,edi
	sub	eax,16000	;reset VGA mod-4 destination for next block
	mov	edi,eax
	add	ebx,16000	;advance source to next block
	mov     esi,ebx
	mov	ecx,4000	;1/4 pixels in quads
	rep	movsd		;transfer 3rd block in quads

	mov	dx,03C4h	;sequencer reg
	mov	ax,0802h	;map mask for plane #4
	out	dx,ax
	IODELAY
	mov	eax,edi
	sub	eax,16000	;reset VGA mod-4 destination for next block
	mov	edi,eax
	add	ebx,16000	;advance source to next block
	mov     esi,ebx
	mov	ecx,4000	;1/4 pixels in quads
	rep	movsd		;transfer 4th block in quads

	pop	ds		;restore local DS
	ret

xMovePixelPage_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; MovePixelClip
; Move a clipped block of pixels to video memory page.
; on entry:
; 	EAX <-- page
; 	ESI <-- screenbuf address
;  	 DX <-- screenbuf selector
;  	 DS <-- SVR driver data selector (local)
;        ES <-- application data selector (global)
; 	EBX <-- x0,y0 (packed)
; 	ECX <-- xd,yd (packed)
; during operation:
; 	DS:ESI <-- source address in screen buffer
; 	ES:EDI <-- destination address in video memory
; 	ECX <-- block counter
; return:
;       void

	PUBLIC  xMovePixelClip_

        ALIGN   4

xMovePixelClip_	PROC near

	push	eax		;(convert EBX,ECX)
	push	edx

	movzx	eax,bx		;unpack x0
	shr	ebx,16		;unpack y0
	shl	ebx,6		;y0*64
	add	eax,ebx
	shl	ebx,2		;y0*256
	add	eax,ebx		;offset = x0 + y0*64 + y0*256
	mov	ebx,eax		;xy offset --> EBX

	movzx	eax,cx		;unpack xd
	shr	ecx,16		;unpack yd
	cmp	ecx,200		;insure yd < 200 to prevent over-write
	jc	ydok
	mov	ecx,199         ;max yd
ydok:	imul	ecx		;count = xd * yd
	mov	ecx,eax		;xy count --> ECX

	pop	edx
	pop	eax

	cmp	[_vmode],13h		;vanilla mode 13 ?
	jne	xMovePixelClipX_	;or mode X ?

xMovePixelClip0_:		;move pixels for linear mode 13

	mov	edi,000A0000h	;set destination address (only 1 page)
	add	edi,ebx		;+ xy offset
	push	ds		;save local DS
	mov	ds,dx		;get source selector
	cld
	shr	ecx,2		;count ECX pixels in quads
	rep	movsd		;transfer entire block in quads
	pop	ds		;restore local DS
	ret

        ALIGN   4

xMovePixelClipX_:		;move pixels for modulo-4 mode X

	push	edx		;save source selector (DX)
	push	ecx		;save count (ECX)
	mov	edi,000A0000h	;VGA mem base
	shr	ebx,2		;scale down xy offset for mod-4 addressing
	add	edi,ebx		;adjust VGA base by xy offset

	or	eax,eax		;page #0 ?
	jz	mpc1
        and     al,3            ;limit to pages #0,1,2,3
        movzx   ecx,al
	shl     ecx,2           ;DWORD index addressing
        lea     ebx,[_ileft_front+ECX]  ;index table of page indexes
        mov     eax,dword ptr[EBX]      ;get video page index
mpc1:
	add	edi,eax		;mem <-- mem base + offset
	pop	ecx		;re-load xy count
	pop	edx		;re-load source selector

	push	ds		;save local DS
	mov	ds,dx		;set source selector

        push edi                ;save video mem dest per block
	shr	ecx,2		;scale down xy count for mod-4 addressing
	mov     ebx,ecx		;save mod-4 xy count for next 3 blocks
	mov	dx,03C4h	;sequencer reg
	mov	ax,0102h	;map mask for plane #1
	out	dx,ax
	IODELAY
	cld
	shr	ecx,2		;1/4 pixels in quads
	rep	movsd		;transfer 1st block in quads
        movzx   ecx,bl
        and     cl,3            ;plus 1, 2, 3 bytes more
        jz      skp1
        rep     movsb
skp1:	pop     edi

	mov	dx,03C4h	;sequencer reg
	mov	ax,0202h	;map mask for plane #2
	out	dx,ax
	IODELAY
        push    edi             ;re-save video dest
	mov     ecx,ebx
	shr	ecx,2		;1/4 pixels in quads
	rep	movsd		;transfer 2nd block in quads
        movzx   ecx,bl
        and     cl,3            ;plus 1, 2, 3 bytes more
        jz      skp2
        rep     movsb
skp2:   pop     edi

	mov	dx,03C4h	;sequencer reg
	mov	ax,0402h	;map mask for plane #3
	out	dx,ax
	IODELAY
        push    edi
	mov     ecx,ebx
	shr	ecx,2		;1/4 pixels in quads
	rep	movsd		;transfer 3rd block in quads
        movzx   ecx,bl
        and     cl,3            ;plus 1, 2, 3 bytes more
        jz      skp3
        rep     movsb
skp3:	pop     edi

	mov	dx,03C4h	;sequencer reg
	mov	ax,0802h	;map mask for plane #4
	out	dx,ax
	IODELAY
	mov     ecx,ebx
	shr	ecx,2		;1/4 pixels in quads
	rep	movsd		;transfer 4th block in quads
        movzx   ecx,bl
        and     cl,3            ;plus 1, 2, 3 bytes more
        jz      skp4
        rep     movsb
skp4:
	pop	ds		;restore local DS
	ret

xMovePixelClip_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ReadPixelClip
; Read a clipped block of pixels from video memory page.
; on entry:
; 	EAX <-- page
; 	EDI <-- screenbuf address
;  	 DX <-- screenbuf selector
;  	 DS <-- SVR driver data selector (local)
;        ES <-- application data selector (global)
; 	EBX <-- x0,y0 (packed)
; 	ECX <-- xd,yd (packed)
; during operation:
; 	DS:ESI <-- source address in video memory
; 	ES:EDI <-- destination address in screen buffer
; 	ECX <-- block counter
; return:
;       void

	PUBLIC  xReadPixelClip_

        ALIGN   4

xReadPixelClip_	PROC near

	push	eax		;(convert EBX,ECX)
	push	edx

	movzx	eax,bx		;unpack x0
	shr	ebx,16		;unpack y0
	shl	ebx,6		;y0*64
	add	eax,ebx
	shl	ebx,2		;y0*256
	add	eax,ebx		;offset = x+ y*256 + y*64
	mov	ebx,eax		;xy offset --> EBX

	movzx	eax,cx		;unpack xd
	shr	ecx,16		;unpack yd
	cmp	ecx,200		;insure yd < 200 to prevent over-write
	jc	ydok2
	mov	ecx,199         ;max yd
ydok2:	imul	ecx		;count = xd * yd
	mov	ecx,eax		;xy count --> ECX

	pop	edx
	pop	eax

	push	eax		;save page parameter
	mov	eax,[_vmode]	;check graphics mode
	cmp	al,13h		;vanilla mode 13 ?
	pop	eax		;restore page parameter
	jne	xReadPixelClipX_	;or mode X ?

xReadPixelClip0_:		;move pixels for linear mode 13

	push	es		;save for return
	mov	es,dx		;use supplied destination selector
	mov	esi,000A0000h	;set source address (only 1 page)
	add	esi,ebx		;+ xy offset
	mov	eax,[_app_dsel]	;get default DS
	push	ds		;save local DS
	mov	ds,ax		;use default source selector
	cld
	shr	ecx,2		;xy count in quads
	rep	movsd		;transfer entire block in quads
	pop	ds		;restore local DS
	pop	es
	ret

        ALIGN   4

xReadPixelClipX_:		;move pixels for modulo-4 mode X

	push	edx		;save destination selector (DX)
	push	ecx		;save xy count (ECX)
	mov	esi,000A0000h	;source <-- VGA mem base
	shr	ebx,2		;scale down xy offset for mod-4 addressing
	add	esi,ebx		;adjust VGA base by xy offset
	or	eax,eax		;page #0 ?
	jz	rpc1

        and     al,3            ;limit to pages #0,1,2,3
        movzx   ecx,al
	shl     ecx,2           ;DWORD index addressing
        lea     ebx,[_ileft_front+ECX]  ;index table of page indexes
        mov     eax,dword ptr[EBX]      ;get video page index
rpc1:
	add	esi,eax		;mem <-- mem base + offset
	pop	ecx		;re-load xy count
	pop	edx		;re-load dest selector

	push	es              ;save for return
	mov	es,dx		;use supplied selector for dest
	mov	eax,[_app_dsel]	;get default DS
	push	ds		;save local DS
	mov	ds,ax		;use default selector for source

        push    esi             ;save video mem source per block
	shr	ecx,2		;scale down xy count for mod-4 addressing
	mov     ebx,ecx		;save mod-4 xy count for other 3 blocks
	mov	dx,03CEh	;read map mask reg
	mov	ax,0004h	;map mask for plane #1
	out	dx,ax
	IODELAY
	cld
	shr	ecx,2		;1/4 xy count in quads
	rep	movsd		;transfer 1st block in quads
        movzx   ecx,bl
        and     cl,3            ;plus 1, 2, 3 bytes more
        jz      skp5
        rep     movsb
skp5:	pop     esi

	mov	dx,03CEh	;read map mask reg
	mov	ax,0104h	;map mask for plane #2
	out	dx,ax
	IODELAY
        push    esi
        mov     ecx,ebx
	shr	ecx,2		;1/4 xy count in quads
	rep	movsd		;transfer 2nd block in quads
        movzx   ecx,bl
        and     cl,3            ;plus 1, 2, 3 bytes more
        jz      skp6
        rep     movsb
skp6:	pop     esi

	mov	dx,03CEh	;read map mask reg
	mov	ax,0204h	;map mask for plane #3
	out	dx,ax
	IODELAY
        push    esi
        mov     ecx,ebx
	shr	ecx,2		;1/4 xy count in quads
	rep	movsd		;transfer 3rd block in quads
        movzx   ecx,bl
        and     cl,3            ;plus 1, 2, 3 bytes more
        jz      skp7
        rep     movsb
skp7:	pop     esi

	mov	dx,03CEh	;read map mask reg
	mov	ax,0304h	;map mask for plane #4
	out	dx,ax
	IODELAY
        mov     ecx,ebx
	shr	ecx,2		;1/4 xy count in quads
	rep	movsd		;transfer 4th block in quads
        movzx   ecx,bl
        and     cl,3            ;plus 1, 2, 3 bytes more
        jz      skp8
        rep     movsb
skp8:
	pop	ds		;restore local DS
	pop	es
	ret

xReadPixelClip_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; VSync
; Returns vertical retrace signal from video status register.
; entry:
;       void
; return:
; 	EAX --> sync status

	PUBLIC	xVSync_

        ALIGN   4

xVSync_	PROC near

	xor	eax,eax
	mov	dx,03DAh	;VGA input status reg
	in	al,dx
	and	al,08h		;vertical retrace bit ?
	ret

xVSync_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; WaitVSync
; Wait until next complete vertical sync interval.
; entry:
;       void
; return:
; 	void

	PUBLIC  xWaitVSync_

        ALIGN   4

xWaitVSync_	PROC near

	xor	eax,eax
	mov	dx,03DAh	;VGA input status reg
wvs1:	in	al,dx
	and	al,08h		;vertical retrace bit ?
	jnz	wvs1		;already vertical sync ?
        IODELAY
wvs2:	in	al,dx
	and	al,08h		;vertical retrace bit ?
	jz	wvs2		;wait until next vertical sync
	ret

xWaitVSync_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SelectDisplayMem
; Select internal pixel starting address for visible display memory.
; entry:
; 	EBX <-- video address
; return:
;       void

	PUBLIC	xSelectDisplayMem_

        ALIGN   4

xSelectDisplayMem_	PROC near

	mov	dx,03D4h	;CRT controller reg
	mov	al,0Ch		;start address high
	out	dx,al
	IODELAY
	inc	dx
	mov	al,bh		;get address high
	out	dx,al
	IODELAY
	dec	dx
	mov	al,0Dh		;start address low
	out	dx,al
	IODELAY
	inc	dx
	mov	al,bl		;get address low
	out	dx,al
	IODELAY
	ret

xSelectDisplayMem_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SelectDisplayPage
; Select 1 of 4 mode-X pages for visible display.
; entry:
; 	EBX <-- video page
; return:
;       void

	PUBLIC	xSelectDisplayPage_

        ALIGN   4

xSelectDisplayPage_	PROC near

	mov	eax,ebx    	;get page #0..3
	or	eax,eax		;page #0 ?
	jz	sdp1

        and     al,3            ;limit to pages #0,1,2,3
        movzx   ecx,al
	shl     ecx,2           ;DWORD index addressing
        lea     ebx,[_ileft_front+ECX]  ;index table of page indexes
        mov     eax,dword ptr[EBX]      ;get video page index
sdp1:
	mov	ebx,eax		;set up address for start memory
	call	xSelectDisplayMem_
	ret

xSelectDisplayPage_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SetGraphLimits
; Sets pixel X,Y and index limits for selected resolution and format.
; entry:
;       void
; return:
;       void

        public  xSetGraphLimits_

        ALIGN   4

xSetGraphLimits_        proc near

        mov     eax,[_svr_line_alternate]       ; line-alt format ?
        or      eax,eax
        jnz     sgl2

        mov     eax,[svr_halfed]                ; half-res format ?
        or      eax,eax
        jnz     sgl1

sgl0:   ; full-resolution format
        mov     eax,[_xres]     ; max x = x resolution
        mov     [_xmax],eax
        mov     ebx,[_yres]     ; max y = y resolution - 1
        dec     ebx
        mov     [_ymax],ebx
        xor     edx,edx         ; max index = max x * max y
        imul    ebx
        shr     eax,2           ; ... /4 for mode-X addressing
        mov     [_imax],eax
        add     eax,000A0000h   ; max video address
        mov     [_vmax],eax
        ret

        ALIGN   4

sgl1:   ; half-resolution format
        mov     eax,[_xres]     ; max x = x resolution
        mov     [_xmax],eax
        mov     ebx,[_yres]     ; max y = (y resolution /2) - 1
        shr     ebx,1
        dec     ebx
        mov     [_ymax],ebx
        xor     edx,edx         ; max index = max x * max y
        imul    ebx
        shr     eax,2           ; ... /4 for mode-X addressing
        mov     [_imax],eax
        add     eax,000A0000h   ; max video address
        mov     [_vmax],eax
        ret

        ALIGN   4

sgl2:   ; line-alternate format
        mov     eax,[_xres]     ; max x = x resolution
        mov     [_xmax],eax
        mov     ebx,[_yres]     ; max y = y resolution - 2
        dec     ebx
        dec     ebx
        mov     [_ymax],ebx
        xor     edx,edx         ; max index = max x * max y
        imul    ebx
        shr     eax,2           ; ... /4 for mode-X addressing
        mov     [_imax],eax
        add     eax,000A0000h   ; max video address
        mov     [_vmax],eax
        ret

xSetGraphLimits_        endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SetGraphPages
; Sets video page addresses for selected resolution and format.
; entry:
;       void
; return:
;       void

        public  xSetGraphPages_

        ALIGN   4

xSetGraphPages_        proc near

        mov     eax,[_svr_line_alternate]       ; line-alt format ?
        or      eax,eax
        jnz     sgp2

        mov     eax,[svr_halfed]                ; half-res format ?
        or      eax,eax
        jnz     sgp1

sgp0:   ; full-resolution format on 4 pages -- for 320x200 only
        xor     eax,eax
        mov     ebx,00004000h
        mov     edx,000A0000h
        mov     [_ileft_front],eax      ; set page 0 index
        mov     [_vleft_front],edx      ; + video address
        add     eax,ebx
        add     edx,ebx
        mov     [_iright_front],eax     ; set page 1 index
        mov     [_vright_front],edx     ; + video address
        add     eax,ebx
        add     edx,ebx
        mov     [_ileft_back],eax       ; set page 2 index
        mov     [_vleft_back],edx       ; + video address
        add     eax,ebx
        add     edx,ebx
        mov     [_iright_back],eax      ; set page 3 index
        mov     [_vright_back],edx      ; + video address
        ret

        ALIGN   4

sgp1:   ; half-resolution format on 2 pages
        xor     eax,eax
        mov     ebx,[_imax]             ; get half-res max index
        add     ebx,80                  ; adjust past bottom reg line
        mov     edx,000A0000h
        mov     [_ileft_front],eax      ; set page 0 index
        mov     [_vleft_front],edx      ; + video address
        add     eax,ebx
        add     edx,ebx
        mov     [_iright_front],eax     ; set page 1 index on bottom half
        mov     [_vright_front],edx     ; + video address
        mov     eax,00008000h
        mov     edx,000A8000h
        mov     [_ileft_back],eax       ; set page 2 index at mid video mem
        mov     [_vleft_back],edx       ; + video address
        add     eax,ebx
        add     edx,ebx
        mov     [_iright_back],eax      ; set page 3 index on bottom half
        mov     [_vright_back],edx      ; + video address
        ret

        ALIGN   4

sgp2:   ; line-alternate format on 2 pages
        xor     eax,eax
        mov     ebx,80                  ; difference between alternate lines
        mov     edx,000A0000h
        mov     [_ileft_front],eax      ; set page 0 index
        mov     [_vleft_front],edx      ; + video address
        add     eax,ebx
        add     edx,ebx
        mov     [_iright_front],eax     ; set page 1 index on same video page
        mov     [_vright_front],edx     ; + video address
        mov     eax,00008000h
        mov     edx,000A8000h
        mov     [_ileft_back],eax       ; set page 2 index at mid video mem
        mov     [_vleft_back],edx       ; + video address
        add     eax,ebx
        add     edx,ebx
        mov     [_iright_back],eax      ; set page 3 index on same video page
        mov     [_vright_back],edx      ; + video address
        ret

xSetGraphPages_        endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_CODE	ENDS

	END

