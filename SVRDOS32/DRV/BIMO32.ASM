; Assember version of DPMI interrupt handler installation.
; Written by DaveM for StereoGraphics.

; Modeled after LCDBIMO.C prototype code.

	.386P
	.MODEL	FLAT

	INCLUDE	SVRDEF.INC	;for SVR global defs
	INCLUDE SVRDOS32.INC	;for SVRDOS32 interface
	INCLUDE LCDBIOS.INC	;for LCDBIOS32 global defs
	INCLUDE LCD32.INC	;for LCDBIOS32 interface
        INCLUDE RTC32.INC       ;for RTC32 interface

INT_NO		EQU	70h	; INT 70 real-time clock interrupt
ISR_SIZE	EQU	1000h	; size if ISR to fit in real-mode mem
ISR_DATA	EQU	0800h	; ISR offset to locate data

_DATA	SEGMENT	DWORD PUBLIC USE32 'DATA'

	public	_lp_rm_data
        public	_lp_rm_isr


_rm_int_off	dw	0	; original real-mode ISR offset & segment
_rm_int_seg	dw	0	;
_pm_int_off	dd	0	; original protected-mode ISR offset & selector
_pm_int_sel	dw	0	;
_alloc_off	dw	0	; allocated real-mode mem offset & segment
_alloc_seg	dw	0	;
_alloc_sel	dw	0	; ... DPMI alloc selector
_lp_rm_isr	df	0	; protected-mode pointer to real-mode ISR address
_lp_rm_data	df	0	; ... real-mode data
_lp_pm_isr	df	0	; pointer to protected-mode ISR

_DATA	ENDS

_CODE	SEGMENT DWORD PUBLIC USE32 'CODE'

	ASSUME	cs:_CODE
	ASSUME	ds:_DATA

; NOTE: use CS: overide with these data references for LEA instruction fixups
; Also need to offset fixed-up addresses by 0100h for .COM file format.

	public	_InitLcdbios_
	public	_ExitLcdbios_
	public	_InitLcdbiosDpmi_
	public	_ExitLcdbiosDpmi_
	public	_SetLcdbiosOptions_
	public	_GetLcdbiosOptions_

; Init LCDBIOS ISRs by installing interrupt handlers using DPMI.
; Installs dual real-mode and protected-mode handlers for same interrupt.
; (1) Gets original real- and protected-mode ISR vectors.
; (2) Allocates DOS real-mode memory for real-mode ISR and data.
; (3) Copies real-mode ISR into real-mode memory.
; (4) Initializes real-mode data (to be shared by both ISRs).
; (5) Provide pointers to real-mode data for protected-mode ISR.
; (6) Locks both real- and protected- ISRs in memory in case of VMM.
; (7) Installs new real- and protected- ISR vectors.

_InitLcdbiosDpmi_	proc near

	push	ds
	push	es

	xor	eax,eax
	mov	ax,0200h	; DPMI get real-mode vector
	mov	bx,INT_NO
	int	31h
	mov	word ptr [_rm_int_off],dx
	mov	word ptr [_rm_int_seg],cx

	mov	ax,0204h	; DPMI get protected-mode vector
	mov	bx,INT_NO
	int	31h
	mov	dword ptr [_pm_int_off],edx
	mov	word ptr [_pm_int_sel],cx

	mov	ax,0100h	; DPMI alloc real-mode mem
	mov	bx,ISR_SIZE
	shr	bx,4
	int	31h
	mov	word ptr [_alloc_sel],dx	; DX --> alloc selector
	mov	word ptr [_alloc_seg],ax	; AX --> real-mode segment
	mov	word ptr [_alloc_off],0

	movzx	eax,ax
	shl	eax,4		; convert segment to flat address
	mov	dword ptr [_lp_rm_isr],eax	; flat address for rm_isr
	mov	bx,word ptr [_app_csel]		; default code selector
	mov	word ptr [_lp_rm_isr+4],bx

        mov	es,word ptr [_app_dsel]		; default data selector
        mov     ebx,eax
	mov	edi,eax		                ; memset rm_isr code
	xor	eax,eax
	mov	ecx,ISR_SIZE
	shr	ecx,4
	rep	stosd
        mov     eax,ebx

	lea	esi,cs:_RMvertRet16_		; memcopy rm_isr code
	mov	edi,eax
	lea	ecx,cs:_RMvertRet16end_		; compute rm_isr size
	lea	edx,cs:_RMvertRet16_
	sub	ecx,edx                         ; ISR end - ISR begin
	add	ecx,4
	shr	ecx,2
	cld
	rep	movsd

	mov	eax,dword ptr [_lp_rm_isr]
	add	eax,ISR_DATA			; locate offset to data area
	mov	bx,word ptr [_app_dsel]		; default data selector
	mov	dword ptr [_lp_rm_data],eax	; flat data address
	mov	word ptr [_lp_rm_data+4],bx

	mov	edi,eax		                ; memset rm_isr data
	xor	eax,eax
	mov	ecx,ISR_SIZE-ISR_DATA
	shr	ecx,4
	rep	stosd

	lea	eax,cs:_PMvertRet32_		; locate protected-mode ISR
	mov	bx,cs				; in local code selector
	mov	dword ptr [_lp_pm_isr],eax 	; flat address for pm_isr
	mov	word ptr [_lp_pm_isr+4],bx

IF 0	; loadable driver is residing within its own selector
	; and has already by locked in its entirity....
	mov	ax,0600h	; DPMI lock mem
	lea	edx,cs:_PMvertRet32_		; lock protected-mode ISR
	mov	ebx,edx
	shr	ebx,16		; BX:CX <-- linear address **** NOT ****
	movzx	ecx,dx
	xor	esi,esi
	lea	edi,cs:_PMvertRet32end_
	lea	esi,cs:_PMvertRet32_
	sub	edi,esi
	add	edi,4
	xor	esi,esi
	int	31h
ENDIF

	mov	ax,0600h	; DPMI lock mem
	mov	edx,dword ptr [_lp_rm_isr]	; lock real-mode ISR
	mov	ebx,edx
	shr	ebx,16		; BX:CX <-- linear address
	movzx	ecx,dx
	xor	esi,esi
	mov	edi,ISR_SIZE
	int	31h

	cli
	mov	ax,0205h	; DPMI set protected-mode vector
	mov	bx,INT_NO
	mov	cx,word ptr [_lp_pm_isr+4]
	mov	edx,dword ptr [_lp_pm_isr]
	int	31h

	mov	ax,0201h	; DPMI set real-mode vector
	mov	bx,INT_NO
	mov	cx,word ptr [_alloc_seg]	; CX:DX <-- real-mode address
	xor	edx,edx
	int	31h
	sti

	pop	es
	pop	ds
	ret

_InitLcdbiosDpmi_	endp

; Exit LCDBIOS ISRs by using DPMI to re-install original interrupt handlers.
_ExitLcdbiosDpmi_	proc near

	xor	eax,eax
	mov	ax,0201h	; DPMI set real-mode vector
	mov	bx,INT_NO
	mov	cx,[_rm_int_seg]
	mov	dx,[_rm_int_off]
	int	31h

	mov	ax,0205h	; DPMI set protected-mode vector
	mov	bx,INT_NO
	mov	cx,[_pm_int_sel]
	mov	edx,[_pm_int_off]
	int	31h

	mov	ax,0601h	; DPMI unlock mem
	mov	edx,dword ptr [_lp_rm_isr]	; lock real-mode ISR
	mov	ebx,edx
	shr	ebx,16		; BX:CX <-- linear address
	movzx	ecx,dx
	xor	esi,esi
	mov	edi,ISR_SIZE
	int	31h

IF 0
	mov	ax,0601h	; DPMI unlock mem
	lea	edx,cs:_PMvertRet32_
	mov	ebx,edx
	shr	ebx,16		; BX:CX <-- linear address
	movzx	ecx,dx
	xor	esi,esi
	lea	edi,cs:_PMvertRet32end_
	lea	esi,cs:_PMvertRet32_
	sub	edi,esi
	add	edi,4
	xor	esi,esi
	int	31h
ENDIF

	mov	ax,0101h	; DPMI free real-mode mem
	mov	bx,ISR_SIZE
	shr	bx,4
	mov	dx,word ptr [_alloc_sel]
	int	31h

	xor	eax,eax		; null pointers to real-mode mem
	mov	dword ptr [_lp_rm_isr],eax
	mov	dword ptr [_lp_rm_data],eax

	ret

_ExitLcdbiosDpmi_	endp

; Init LCDBIOS shell function.
_InitLcdbios_	proc near

	call	_InitLcdbiosDpmi_	; use DPMI to load ISRs
	call	_InitLcdbios32_		; init LCDBIOS driver
	call	_InitLcdbiosTimer_	; init LCDBIOS ISR timer

	ret

_InitLcdbios_	endp

; Exit LCDBIOS shell function.
_ExitLcdbios_	proc near

	call	_ExitLcdbiosTimer_	; exit LCDBIOS timer ISR
	call	_ExitLcdbios32_		; exit LCDBIOS driver
	call	_ExitLcdbiosDpmi_	; use DPMI to restore ISRs

	ret

_ExitLcdbios_	endp

; Set LCDBIOS run-time options.
; Transfer LCDBIOS run-time options only if ISR active
_SetLcdbiosOptions_	proc near

	mov	ebx,dword ptr [_lp_rm_data]
	or	ebx,ebx			; is ISR data pointer valid ?
	jz	exitslo

	push	es			; then use ES:[EBX+D_offset]
	mov	dx,word ptr[_lp_rm_data+4]
	mov	es,dx
	mov	eax,[_svr_high_refresh]
	mov	word ptr es:[ebx+D_boostRefresh],ax
	mov	eax,[_svr_lock_flip]
	mov	word ptr es:[ebx+D_nailRetrace],ax
	mov	eax,[_svr_delay_flip]
	mov	word ptr es:[ebx+D_flipEyeOffset],ax
	pop	es

	mov	eax,[_svr_fast_intr]
	cmp	eax,[_intRateOffset]	; different ISR rate ?
	je	exitslo
	mov	[_intRateOffset],eax
	call	_DisableLcdbios32_	; disable page-flipping, just in case
        xor     eax,eax
        mov     [svr_active],eax
	call	_ExitLcdbiosTimer_	; disable ISR timer
	call	_InitLcdbiosTimer_	; re-enable ISR timer

exitslo:
	ret

_SetLcdbiosOptions_	endp

; Get LCDBIOS run-time options.
; Transfer LCDBIOS run-time options only if ISR active
_GetLcdbiosOptions_	proc near

	mov	ebx,dword ptr [_lp_rm_data]
	or	ebx,ebx			; is ISR data pointer valid ?
	jz	exitglo

	push	es			; then use ES:[EBX+D_offset]
	mov	dx,word ptr[_lp_rm_data+4]
	mov	es,dx
	movzx	eax,word ptr es:[ebx+D_boostRefresh]
	mov	[_svr_high_refresh],eax
	movzx	eax,word ptr es:[ebx+D_nailRetrace]
	mov	[_svr_lock_flip],eax
	movzx	eax,word ptr es:[ebx+D_flipEyeOffset]
	mov	[_svr_delay_flip],eax
	mov	eax,[_intRateOffset]
	mov	[_svr_fast_intr],eax
	pop	es

exitglo:
	ret

_GetLcdbiosOptions_	endp

_CODE	ENDS

	END
