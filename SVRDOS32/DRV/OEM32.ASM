; OEM special hardware IO to drive SVR glasses directly.

	.386P
	.MODEL	FLAT

	INCLUDE	SVRDEF.INC	;for SVR global defs
	INCLUDE SVRDOS32.INC	;for SVRDOS32 interface
        INCLUDE BIMO32.INC
        INCLUDE LCD32.INC
        INCLUDE LCDBIOS.INC     ;for LCDBIOS interface
        INCLUDE VESA32.INC      ;for VESA interface

OEM1	EQU	1               ;Brooktree
OEM2	EQU	2               ;Rendition
OEM3	EQU	3               ;diagnostic port
OEM4	EQU	4               ;Alliance
OEM5	EQU	5               ;Alliance AT3D
OEM6    EQU     6               ;VESA 3.0 above/below stereo, NVidia NV3
OEM7    EQU     7               ;VESA 3.0 dual-address stereo

_DATA	segment dword public use32 'DATA'

_DATA	ends

_CODE	segment dword public use32 'CODE'

	assume	cs:_CODE
	assume	ds:_DATA

	public	_DetectOEM_
	public	_InitOEM_
	public	_ExitOEM_
	public	_UpdateOEM_

; Detect if OEM hardware present.

RENDNUM EQU     16               ; number of ID chars
RENDPTR db      "Rendition Verite 1000 "
RENDNM2 EQU     28
RENDPT2 db      "Creative Labs 3D Blaster PCI "
ALLINUM EQU     21
ALLIPTR db      "Alliance ProMotion AT3D "
NVIDNUM EQU     6
NVIDPTR db      "NVidia Riva 128 "

_DetectOEM_	proc near

	mov	eax,[_svr_OEM_support]	; any OEM pre specified ?
	or	eax,eax
	jnz	detoemx			; then skip auto-detect

detoem7:        ; detect VESA 3.0 stereo support
        mov     esi,dword ptr[_pVI]     ; get ptr to VESA info block
        movzx   eax,word ptr[esi+4]     ; get VESA version
        cmp     eax,0300h
        jl      detoem1

        mov     esi,dword ptr[_pMI]     ; get ptr to VESA mode info block
        movzx   eax,word ptr[esi+0]     ; get mode attributes
        test    eax,1800h               ; stereo support ?
        jz      detoem6

        mov     eax,OEM7
        mov	[_svr_OEM_support],eax
        mov     edi,dword ptr[_lp_rm_data]
        mov     dword ptr ES:[EDI+D_svr_oem],eax

        jmp     detoemx

detoem6:        ; detect VESA 3.0 above/below stereo
        test    eax,0800h               ; above/below stereo support ?
        jz      detoem1

        mov     eax,OEM6
        mov	[_svr_OEM_support],eax
        mov     edi,dword ptr[_lp_rm_data]
        mov     dword ptr ES:[EDI+D_svr_oem],eax

        jmp     detoemx

detoem1:	; detection for OEM #1 = Brooktree chipset
	mov	dx,022Ch		; point to 1st of 2 possible ports
	mov	al,01h			; send 2-byte detection command
	out	dx,al
	IODELAY
	mov	al,0E1h
	out	dx,al
	IODELAY
	IODELAY
	inc	dx 			; read status port
	inc	dx
d1a:	in	al,dx
	IODELAY
	test	al,80h			; status ready ?
	jz	d1a
	dec	dx
	dec	dx
	in	al,dx			; read 2-byte response
	IODELAY
	mov	ah,al
	in	al,dx
	cmp	ax,2233h
	jne	d1b
	mov	eax,OEM1		; flag Brooktree support
	mov	[_svr_OEM_support],eax
        mov     [_svr_lock_flip],eax
	mov     edi,dword ptr[_lp_rm_data]
        mov     dword ptr ES:[EDI+D_svr_oem],OEM1
        mov     dword ptr ES:[EDI+D_oem_port],022Ch
	jmp	detoemx
d1b:
	mov	dx,024Ch		; point to 2nd of 2 possible ports
	mov	al,01h			; send 2-byte detection command
	out	dx,al
	IODELAY
	mov	al,0E1h
	out	dx,al
	IODELAY
	IODELAY
	inc	dx 			; read status port
	inc	dx
d1c:	in	al,dx
	IODELAY
	test	al,80h			; status ready ?
	jz	d1c
	dec	dx
	dec	dx
	in	al,dx			; read 2-byte response
	IODELAY
	mov	ah,al
	in	al,dx
	cmp	ax,2233h
	jne	detoem2
	mov	eax,OEM1		; flag Brooktree support
	mov	[_svr_OEM_support],eax
	mov     [_svr_lock_flip],1
        mov     edi,dword ptr[_lp_rm_data]
        mov     dword ptr ES:[EDI+D_svr_oem],eax
        mov     dword ptr ES:[EDI+D_oem_port],024Ch
	jmp	detoemx

detoem2:        ; detection for OEM chipset #2 = Rendition
        mov     edi,dword ptr[_pVI]     ; get ptr to VESA info block
        mov     ebx,dword ptr[edi+6]    ; get OemStringPtr
        mov     edi,ebx
        and     edi, 0000FFFFh          ; convert from real-mode ptr
        and     ebx,0FFFF0000h
        shr     ebx,12
        or      edi,ebx
        mov     ebx,edi

        lea     esi,cs:RENDPTR          ; search for Rendition string
        mov     ecx,RENDNUM
        cld
        rep     cmpsb
        je      @cmp2

        mov     edi,ebx
        lea     esi,cs:RENDPT2          ; search for 3D Blaster string
        mov     ecx,RENDNM2
        rep     cmpsb
        je      @cmp2
        jmp     detoem3

@cmp2:  mov	eax,OEM2		; flag Rendition support
	mov	[_svr_OEM_support],eax
        mov     edi,dword ptr[_lp_rm_data]
        mov     dword ptr ES:[EDI+D_svr_oem],eax
        jmp     detoemx

detoem3:        ; detection for OEM chipset #3 = diagnostic port
        mov     edx,[_SVR_debug_port]
        or      edx,edx
        jz      detoem4

        mov	eax,OEM3		; flag diagnostic port support
	mov	[_svr_OEM_support],eax
        mov     edi,dword ptr[_lp_rm_data]
        mov     dword ptr ES:[EDI+D_svr_oem],eax
        mov     dword ptr ES:[EDI+D_oem_port],edx
	jmp     detoemx

detoem4:        ; detection for OEM chipset #4 = Alliance
        mov     dx,03C4h
        movzx   edx,dx
        mov     al,1Eh
        out     dx,al
        IODELAY
        IODELAY
        inc     edx
        in      al,dx
        mov     bl,al
        dec     edx
        IODELAY
        IODELAY
        mov     al,1Fh
        out     dx,al
        IODELAY
        IODELAY
        inc     edx
        in      al,dx
        mov     bh,al
        dec     edx
        IODELAY
        IODELAY
        movzx   ebx,bx
        mov     edi,dword ptr[_lp_rm_data]
        mov     dword ptr ES:[EDI+D_oem_port],ebx
        mov     al,1Dh
        out     dx,al
        IODELAY
        IODELAY
        inc     edx
        mov     al,60h
        out     dx,al
        dec     edx
        IODELAY
        mov     edx,ebx
        in      al,dx
        mov     bl,al
        IODELAY
        inc     edx
        in      al,dx
        mov     bh,al
        IODELAY
        inc     edx
        in      al,dx
        mov     cl,al
        IODELAY
        inc     edx
        in      al,dx
        mov     ch,al
        shl     ecx,16
        mov     cx,bx
        cmp     ecx,64241142h
        jne     detoem5
        mov     [_svr_oem_support],OEM4 ; Alliance AT24
        mov     [_svr_fast_intr],0      ; 1024 Hz sampling

	jmp	detoemx

detoem5:        ; additionally detect Alliance AT3D
        cmp     ecx,643D1142h
        jne     detoemx
        mov     [_svr_oem_support],OEM5 ; Alliance AT3D
        mov     [_svr_fast_intr],0      ; 1024 Hz sampling
	jmp	detoemx

detoemx:
	ret

_DetectOEM_	endp

; Init OEM hardware IO for stereo page-flipping support.
; return: non-0 if hardware auto-flipping support available.

_InitOEM_	proc near

	mov	eax,[_svr_OEM_support]	; any OEM specified ?
	or	eax,eax
	jz	initoemx

	cmp	al,OEM1
	je	initoem1
	cmp	al,OEM2
	je	initoem2
	cmp	al,OEM3
	je	initoem3
	cmp	al,OEM4
	je	initoem4
	cmp	al,OEM5
	je	initoem5
	cmp	al,OEM6
	je	initoem6
	cmp	al,OEM7
	je	initoem7
        xor     eax,eax
	jmp	initoemx

initoem1:	; enable OEM 1 = Brooktree
        mov     edi,dword ptr[_lp_rm_data]
        mov     edx,dword ptr ES:[EDI+D_oem_port]       ; Brooktree port
	mov	al,02h		; program left/right control
	out	dx,al
        IODELAY
        mov     al,04h          ; Brooktree left poke
        movzx   eax,al
        mov     dword ptr ES:[EDI+D_oem_dataL],eax
        mov     al,05h          ; Brooktree right poke
        mov     dword ptr ES:[EDI+D_oem_dataR],eax
        xor     eax,eax         ; uses ISR
	jmp	initoemx

initoem2:	; enable OEM 2 = Rendition
        mov     eax,1580h
        mov     ebx,0001h       ; BIOS call for Verite enable
        int     10h
	mov     edi,dword ptr[_lp_rm_data]
        mov     ecx,dword ptr ES:[EDI+D_startLeftX]
        mov     edx,dword ptr ES:[EDI+D_startRightX]
        mov     eax,1589h       ; BIOS call to load Verite regs
        mov     edi,edx         ; (index already in bytes, not bytes / 4)
        mov     edx,ecx
        shr     edx,16
        mov     ebx,edi
        shr     ebx,16
        int     10h
        mov     eax,OEM2        ; does not use ISR
        or      eax,eax
	jmp	initoemx

initoem3:	; enable OEM 3 = diagnostic port
	mov     edi,dword ptr[_lp_rm_data]
        mov     edx,dword ptr ES:[EDI+D_oem_port]       ; diagnostic port
        cmp     edx,0061h       ; PC speaker port ?
        je      initspkr

        xor     eax,eax         ; LPT/COM = 0 = right eye
        mov     dword ptr ES:[EDI+D_oem_dataR],eax
        inc     eax             ; LPT/COM = 1 = left eye
        mov     dword ptr ES:[EDI+D_oem_dataL],eax
        out     dx,al
        xor     eax,eax         ; uses ISR
        jmp     initoemx

initspkr:
	mov	dx,0061h	;PC timer 2 gate enable
	in	al,dx
	IODELAY
	IODELAY
	and	al,0FCh		;disable speaker output
	or	al,01h		;enable timer 2 gate
	out	dx,al
	IODELAY
        movzx   eax,al          ; PC speaker high = left
        mov     dword ptr ES:[EDI+D_oem_dataL],eax
	or      al,02h          ; PC speaker low = right
        mov     dword ptr ES:[EDI+D_oem_dataR],eax
	xor     eax,eax         ; uses ISR
        jmp	initoemx

initoem4:	; enable OEM 4 = Alliance AT24
        mov     dx,03C4h
        movzx   edx,dx
        mov     al,1Dh
        out     dx,al
        IODELAY
        inc     edx
        mov     al,33h
        out     dx,al
        IODELAY
        mov     edi,dword ptr[_lp_rm_data]
        mov     edx,dword ptr ES:[EDI+D_oem_port]
        mov     al,80h
        out     dx,al
        IODELAY
        inc     edx
        mov     al,01h
        out     dx,al
	xor     eax,eax         ; uses ISR
        jmp	initoemx

initoem5:	; enable OEM 5 = Alliance AT3D
        mov     dx,03C4h
        movzx   edx,dx
        mov     al,1Dh
        out     dx,al
        IODELAY
        inc     edx
        mov     al,33h
        out     dx,al
        IODELAY
        mov     edi,dword ptr[_lp_rm_data]
        mov     edx,dword ptr ES:[EDI+D_oem_port]
        mov     al,20h          ; GPO pin overide
        out     dx,al
        IODELAY
        inc     edx
        mov     al,20h          ; left/right eye overide
        out     dx,al
        IODELAY
        inc     edx
        mov     al,00h          ; left eye select
        out     dx,al
	xor     eax,eax         ; uses ISR ???
        jmp	initoemx

initoem6:	; enable OEM 6 = VESA 3.0 above/below stereo
	mov     edi,dword ptr[_lp_rm_data]
        mov     ecx,dword ptr ES:[EDI+D_startLeftX]
        mov     eax,4F07h       ; set display page
        mov     ebx,0002h       ; update single page
        int     10h
	mov     eax,4F07h
        mov     ebx,0005h       ; enable stereo for above/below
        int     10h
        mov     eax,OEM6        ; auto-flipping
        or      eax,eax         ; does not use ISR
	jmp	initoemx

initoem7:	; enable OEM 7 = VESA 3.0 dual-address stereo
	mov     edi,dword ptr[_lp_rm_data]
        mov     ecx,dword ptr ES:[EDI+D_startLeftX]
        mov     edx,dword ptr ES:[EDI+D_startRightX]
        mov     eax,4F07h       ; set display page
        mov     ebx,0003h       ; update dual pages
        int     10h
	mov     eax,4F07h
        mov     ebx,0005h       ; enable stereo
        int     10h
	mov     edi,dword ptr[_lp_rm_data]
        mov     ecx,dword ptr ES:[EDI+D_startLeftX]
        mov     edx,dword ptr ES:[EDI+D_startRightX]
        mov     eax,4F07h
        mov     ebx,0083h       ; update on sync
        int     10h
	mov     eax,OEM7        ; auto-flipping
        or      eax,eax         ; does not use ISR
	jmp	initoemx

initoemx:
	ret

_InitOEM_	endp

; Exit OEM hardware IO.

_ExitOEM_	proc near

	mov	eax,[_svr_OEM_support]  ; any OEM at all ?
        or      eax,eax
        jz      exitoemx
	cmp	al,OEM1
	je	exitoem1
	cmp	al,OEM2
	je	exitoem2
	cmp	al,OEM3
	je	exitoem3
	cmp	al,OEM4
	je	exitoem4
	cmp	al,OEM5
	je	exitoem5
	cmp	al,OEM6
	je	exitoem6
	cmp	al,OEM7
	je	exitoem7
        jmp	exitoemx

exitoem1:
	jmp	exitoemx

exitoem2:       ; disable OEM 2 = Rendition
	mov     eax,1580h
        mov     ebx,0000h       ; BIOS call for Verite disable
        int     10h
	jmp	exitoemx

exitoem3:       ; disable OEM 3 = diagnostic port
	mov     edi,dword ptr[_lp_rm_data]
        mov     edx,dword ptr ES:[EDI+D_oem_port]; diagnostic port
        cmp     edx,0061h       ; PC speaker port ?
        je      exitspkr
        mov     eax,dword ptr ES:[EDI+D_oem_dataL]
        out     dx,al           ; leave port on left eye
        jmp     exitoemx

exitspkr:
	mov	dx,0061h	;PC timer 2 gate enable
	in	al,dx
	IODELAY
	IODELAY
	and	al,0FCh		;disable speaker output
	out	dx,al
	IODELAY
	jmp	exitoemx

exitoem4:       ; disable OEM 4 = Alliance AT24
        mov     dx,03C4h
        movzx   edx,dx
        mov     al,1Dh
        out     dx,al
        IODELAY
        inc     edx
        mov     al,33h
        out     dx,al
        IODELAY
        mov     edi,dword ptr[_lp_rm_data]
        mov     edx,dword ptr ES:[EDI+D_oem_port]
        mov     al,80h
        out     dx,al
        IODELAY
        inc     edx
        mov     al,00h
        out     dx,al
	jmp	exitoemx

exitoem5:       ; disable OEM 5 = Alliance AT3D
        mov     dx,03C4h
        movzx   edx,dx
        mov     al,1Dh
        out     dx,al
        IODELAY
        inc     edx
        mov     al,33h
        out     dx,al
        IODELAY
        mov     edi,dword ptr[_lp_rm_data]
        mov     edx,dword ptr ES:[EDI+D_oem_port]
        mov     al,00h          ; GPO pin default
        out     dx,al
        IODELAY
        inc     edx
        mov     al,00h          ; left/right pin default
        out     dx,al
	IODELAY
        inc     edx
        mov     al,00h          ; left select
        out     dx,al
	jmp	exitoemx

exitoem6:       ; disable VESA 3.0 above/below stereo
        mov     eax,4F07h
        mov     ebx,0006h       ; disable stereo
        int     10h
	jmp	exitoemx

exitoem7:       ; disable VESA 3.0 dual-address stereo
        mov     eax,4F07h
        mov     ebx,0006h       ; disable stereo
        int     10h
	jmp	exitoemx

exitoemx:
	ret

_ExitOEM_	endp

; Update OEM hardware IO during run-time.
; Real-time update routines have to be included with bi-modal ISR code.
; Hardware page-flipping chipsets are updated here instead.

_UpdateOEM_	proc near

	mov	eax,[_svr_OEM_support]  ; any OEM at all ?
        or      eax,eax
        jz      updtoemx
	cmp	al,OEM1
	je	updtoem1
	cmp	al,OEM2
	je	updtoem2
	cmp	al,OEM3
	je	updtoem3
	cmp	al,OEM4
	je	updtoem4
	cmp	al,OEM5
	je	updtoem5
	cmp	al,OEM6
	je	updtoem6
	cmp	al,OEM7
	je	updtoem7
	jmp	updtoemx

updtoem1:
	jmp	updtoemx

updtoem2:       ; update OEM 2 = Rendition
	mov     edi,dword ptr[_lp_rm_data]
        mov     ecx,dword ptr ES:[EDI+D_startLeftX]
        mov     edx,dword ptr ES:[EDI+D_startRightX]
        mov     eax,1589h       ; BIOS call to update Verite regs
        mov     edi,edx         ; (index already in bytes, not bytes / 4)
        mov     edx,ecx
        shr     edx,16
        mov     ebx,edi
        shr     ebx,16
        int     10h
	jmp	updtoemx

updtoem3:
	jmp	updtoemx

updtoem4:
	jmp	updtoemx

updtoem5:
	jmp	updtoemx

updtoem6:       ; update VESA 3.0 above/below stereo
	mov     edi,dword ptr[_lp_rm_data]
        mov     ecx,dword ptr ES:[EDI+D_startLeftX]
        mov     eax,4F07h
        mov     ebx,0082h       ; update single page on sync
        int     10h
	jmp	updtoemx

updtoem7:       ; update VESA 3.0 dual-address stereo
	mov     edi,dword ptr[_lp_rm_data]
        mov     ecx,dword ptr ES:[EDI+D_startLeftX]
        mov     edx,dword ptr ES:[EDI+D_startRightX]
        mov     eax,4F07h
        mov     ebx,0083h       ; update dual pages on sync
        int     10h
	jmp	updtoemx

updtoemx:
	ret

_UpdateOEM_	endp

_CODE	ends

	END


