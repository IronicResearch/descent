; SVRDOS32 SimulEyes VR driver for DPMI 32-bit extender DOS/4G.
; Written by DaveM for StereoGraphics Inc.

; VESA Video module for SVRDOS4G driver.
; (Equivalent to "modevesa.c" C prototype code.)
; Supports 640x400, 640x480.
; Supports 320x200, 320x240 VESA modes if available instead of mode-X.

	.386P
	.MODEL	FLAT

	INCLUDE	SVRDEF.INC
	INCLUDE	SVRDOS32.INC
        INCLUDE MODEX32.INC
        INCLUDE OEM32.INC


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_DATA	SEGMENT PUBLIC DWORD USE32 'DATA'

	ASSUME	DS:_DATA

        ALIGN   4

; use 32-bit double-words wherever possible
; parameters are passed via registers wherever possible

        public _VESA_detected;
        public _VESA_active;
        public _VESA_x;
        public _VESA_y;
        public _VESA_i;
        public _VESA_page;
        public _VESA_bank;
        public _VESA_addr;
        public _VESA_xres;
        public _VESA_yres;
        public _VESA_vmode;
        public _VESA_linear;
        public _VESA_xgap;

        public _pSetStartFn;
        public _pSetWindowFn;
        public _pVI;
        public _pMI;
        public _pPI;

_VESA_detected  dd 0                    ; VESA interface detected ?
_VESA_active    dd 0                    ; VESA mode effective ?
_VESA_x         dd 0                    ; VESA absolute x coordinate
_VESA_y         dd 0                    ; VESA absolute y coordinate
_VESA_i         dd 0                    ; VESA absolute pixel index
_VESA_page      dd 0                    ; VESA virtual page #
_VESA_bank      dd 0                    ; VESA 64k address bank #
_VESA_addr      dd 000A0000h            ; VGA address entry into VESA bank
_VESA_xres      dd 640                  ; VESA x resolution
_VESA_yres      dd 400                  ; VESA y resolution
_VESA_vmode     dd 4100h                ; VESA mode
_VESA_xgap      dd 640                  ; VESA x scan line width
_VESA_linear    dd 1                    ; VESA linear video memory ?
_VESA_base      dd 0                    ; VESA linear frame buffer base addr

_pSetStartFn    dq 0                    ; pointer to call for SetStart fn
_pSetWindowFn   dq 0                    ; pointer to call for SetWindow fn

_pVI            dd 0                    ; pointer to VESA info block
_pMI            dd 0                    ; pointer to mode info block
_pPI            dd 0                    ; pointer to protected-mode block

_rmbuf_sel      dd 0                    ; real-mode buffer alloc selector
_rmbuf_seg      dd 0                    ; real-mode buffer alloc segment
_rmbuf_addr     dd 0                    ; real-mode buffer flat address

_modelist       dw 256 dup (0)          ; local copy of VESA mode list

DPMIREGS        STRUC                   ; DPMI register set
redi            dd 0
resi            dd 0
rebp            dd 0
rreserved       dd 0
rebx            dd 0
redx            dd 0
recx            dd 0
reax            dd 0
rflags          dw 0
res             dw 0
rds             dw 0
rfs             dw 0
rgs             dw 0
rip             dw 0
rcs             dw 0
rsp             dw 0
rss             dw 0
DPMIREGS        ENDS

VBE_VGAINFO     STRUC                   ; VESA info struct

VESASignature   db 4 dup (0)            ; char[4] /* 'VESA' 4 byte signature          */
VESAVersion     dw 0                    ; short /* VBE version number               */
OemStringPtr    dd 0                    ; char* /* Pointer to OEM string            */
Capabilities    dd 0                    ; ulong /* Capabilities of video card       */
VideoModePtr    dd 0                    ; ushort* /* Pointer to supported modes       */
TotalMemory     dw 0                    ; short /* Number of 64kb memory blocks     */
	                                ; /* VBE 2.0 extension information */
OemSoftwareRev  dw 0                    ; short /* OEM Software revision number		*/
OemVendorNamePtr   dd 0                 ; char* /* Pointer to Vendor Name string	*/
OemProductNamePtr  dd 0                 ; char* /* Pointer to Product Name string	*/
OemProductRevPtr   dd 0                 ; char* /* Pointer to Product Revision str	*/
reserved        db 222 dup (0)          ; char[222] /* Pad to 256 byte block size       */
OemDATA         db 256 dup (0)          ; char[256] /* Scratch pad for OEM data			*/

VBE_VGAINFO     ENDS

VBE_MODEINFO    STRUC                   ; VESA mode info struct

ModeAttributes  dw 0                    ; short /* Mode attributes                  */
WinAAttributes  db 0                    ; char  /* Window A attributes              */
WinBAttributes  db 0                    ; char  /* Window B attributes              */
WinGranularity  dw 0                    ; short /* Window granularity in k          */
WinSize         dw 0                    ; short /* Window size in k                 */
WinASegment     dw 0                    ; ushort /* Window A segment                 */
WinBSegment     dw 0                    ; ushort /* Window B segment                 */
WinFuncPtr      dd 0                    ; void*	/* Pointer to window function       */
BytesPerScanLine   dw 0                 ; short /* Bytes per scanline               */
XResolution     dw 0                    ; short /* Horizontal resolution            */
YResolution     dw 0                    ; short /* Vertical resolution              */
XCharSize       db 0                    ; char  /* Character cell width             */
YCharSize       db 0                    ; char  /* Character cell height            */
NumberOfPlanes  db 0                    ; char  /* Number of memory planes          */
BitsPerPixel    db 0                    ; char  /* Bits per pixel                   */
NumberOfBanks   db 0                    ; char  /* Number of CGA style banks        */
MemoryModel     db 0                    ; char  /* Memory model type                */
BankSize        db 0                    ; char  /* Size of CGA style banks          */
NumberOfImagePages db 0                 ; char  /* Number of images pages           */
res1            db 0                    ; char  /* Reserved                         */
RedMaskSize     db 0                    ; char  /* Size of direct color red mask    */
RedFieldPosition   db 0                 ; char  /* Bit posn of lsb of red mask      */
GreenMaskSize   db 0                    ; char  /* Size of direct color green mask  */
GreenFieldPosition db 0                 ; char  /* Bit posn of lsb of green mask    */
BlueMaskSize    db 0                    ; char  /* Size of direct color blue mask   */
BlueFieldPosition  db 0                 ; char  /* Bit posn of lsb of blue mask     */
RsvdMaskSize    db 0                    ; char  /* Size of direct color res mask    */
RsvdFieldPosition  db 0                 ; char  /* Bit posn of lsb of res mask      */
DirectColorModeInfo db 0                ; char  /* Direct color mode attributes     */
                                        ; /* VBE 2.0 extensions information */
PhysBasePtr     dd 0                    ; ulong	/* Physical address for linear buf	*/
OffScreenMemOffset dd 0                 ; ulong	/* Pointer to start of offscreen mem*/
OffScreenMemSize   dw 0                 ; short /* Amount of offscreen mem in 1K's	*/
res2            db 206 dup (0)          ; char[206] /* Pad to 256 byte block size       */

VBE_MODEINFO    ENDS

VBE_PMINFO      STRUC                   ; VESA protected-mode info struct

setWindow       dw 0                    ; short /* Offset of Set Window call		*/
setDisplayStart dw 0                    ; short /* Offset of Set Display Start call	*/
setPalette      dw 0                    ; short /* Offset of Set Primary Palette	*/
IOPrivInfo      dw 0                    ; short /* Offset of I/O priveledge info	*/
                                        ; /* UniVBE 5.2 extensions */
extensionSig    dd 0                    ; long /* Identify extension (0xFBADFBAD)	*/
setWindowLen    dd 0                    ; long /* Used to virtualise framebuffer	*/
setDisplayStartLen dd 0                 ; long
setPaletteLen   dd 0                    ; long
                                        ; /* ... code and tables located in here */
res3            db 1000 dup (0)         ; // pad to 1024 byte block

VBE_PMINFO      ENDS

DVI     EQU     0                       ; offset for VESA info block
DMI     EQU     SIZE VBE_VGAINFO        ; offset for mode info block
DPI     EQU     DMI + SIZE VBE_MODEINFO ; offset for protected-mode info block

reg             DPMIREGS                <>      ; DPMI register set
vi              VBE_VGAINFO             <>      ; VESA info struct
mi              VBE_MODEINFO            <>      ; VESA mode info struct
pi              VBE_PMINFO              <>      ; VESA protected-mode struct


_DATA	ENDS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_CODE	SEGMENT PUBLIC DWORD USE32 'CODE'

	ASSUME	CS:_CODE,DS:_DATA

; After immediate entry into each SVR driver function, selectors become:
;       CS <-- SVR driver code selector
;       DS <-- SVR driver data selector (local)
;       ES <-- application data selector (global)

	public  InitVesaLocals_

        public  xInitVesa_
        public  xExitVesa_
        public  xSetVesaMode_
        public  xSetVesaBank_
        public  xSetVesaPage_
        public  xSetVesaIndex_
        public  xPlotVesaPixel_
        public  xFillVesaPixels_
        public  xMoveVesaPixels_
        public  xDisplayVesaXY_
        public  xDisplayVesaPage_

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; InitVesaLocals
; Init local variables in SVR VESA32 module.
; entry:
;       void
; return:
;       void

        ALIGN   4

InitVesaLocals_	PROC near

	xor	eax,eax   	        ; zero defaults
	mov	[_VESA_detected],eax
        mov     [_VESA_active],eax
	ret

InitVesaLocals_	ENDP

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; int VESA_GetMode(void);
; Gets VESA video mode via BIOS call.
; entry:
;       void
; return:
;       EAX <-- VESA result
; 	EBX <-- video mode

        ALIGN 4

VESA_GetMode_   proc near

        mov     eax,4F03h               ; VESA GetMode fn
        int     10h
        ret

VESA_GetMode_   endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; int VESA_SetMode(int mode)
; Sets VESA video mode via BIOS call.
; entry:
;       EBX <-- video mode
; return:
;       EAX <-- VESA result

        ALIGN 4

VESA_SetMode_   proc near

        mov     eax,4F02h               ; VESA SetMode fn
        int     10h
        ret

VESA_SetMode_   endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; int VESA_SetWindow(int window)
; Set VESA bank window using video BIOS service.
; entry:
;       EDX <-- window
; return:
;       EAX <-- VESA result

        ALIGN 4

VESA_SetWindow_ proc near

        mov     eax,4F05h               ; VESA SetWindow fn
        mov     ebx,0                   ; Set
        int     10h
        ret

VESA_SetWindow_ endp

; int VESA_DPMI_SetWindow(int window);
; Set VESA bank window using DPMI-compatible function.

        ALIGN 4

VESA_DPMI_SetWindow_    proc near

        xor     ebx,ebx
        call    dword ptr [_pSetWindowFn]       ; direct call
        ret

VESA_DPMI_SetWindow_    endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; int VESA_SetXY(int X, int Y)
; Set VESA XY visible page using video BIOS service.
; entry:
;       ECX <-- X
;       EDX <-- Y
; return:
;       EAX <-- VESA result

        ALIGN 4

VESA_SetXY_     proc near

        mov     eax,4F07h               ; VESA SetXY fn
        mov     ebx,0                   ; Set
        int     10h
        ret

VESA_SetXY_     endp

; int VESA_DPMI_SetXY(int X, int Y);
; Set VESA XY page using DPMI-compatible function.
; direct access version wants DX:CX = linear offset, not XY...
; index = x + 320*y = x +   (64+256)*y = x +   (y<<6) +   (y<<8)
; index = x + 640*y = x + 2*(64+256)*y = x + 2*(y<<6) + 2*(y<<8)
; entry:
;       ECX <-- linear index
; return:
;       EAX <-- VESA result

        ALIGN 4

VESA_DPMI_SetXY_ proc near

        xor      ebx,ebx                ; Set
        shr      ecx,2                  ; scale / 4 for DWORDs
        mov      edx,ecx
        movzx    ecx,cx
        shr      edx,16
        call     dword ptr [_pSetStartFn]       ; direct call
        ret

VESA_DPMI_SetXY_ endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; int VESA_GetXY(int *X, int *Y)
; Get VESA XY visible page using video BIOS service.
; entry:
;       void
; return:
;       EAX <-- VESA result
;       ECX <-- X
;       EDX <-- Y

        ALIGN 4

VESA_GetXY_     proc near

        mov     eax,4F07h               ; VESA SetXY fn
        mov     ebx,0001h               ; Get
        int     10h
        ret

VESA_GetXY_     endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Get VESA logical scan line width using video BIOS service.
; int VESA_GetWidth(void)
; entry:
;       void
; return:
;       EAX <-- VESA result
;       EBX <-- scan line width

        ALIGN 4

VESA_GetWidth_  proc near

        mov     eax,4F06h               ; VESA SetWidth fn
        mov     ebx,0001h               ; Get
        int     10h
        ret

VESA_GetWidth_  endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; int VESA_GetVesaInfo(void);
; Gets VESA info block.
; entry:
; 	void
; return:
;       EAX <-- VESA result
;       EBX <-- VESA signature
;       ECX <-- VESA version

        ALIGN 4

VESA_GetVesaInfo_      proc near

        push    es
        mov     dx,ds
        mov     es,dx                   ; local selector

        xor     eax,eax
        lea     edi,reg                 ; zero DPMI reg set
        mov     ecx,SIZE reg
        cld
        rep     stosb

        lea     edi,vi                  ; zero VESA info buffer
        mov     dword ptr[_pVI],edi
        mov     ecx,SIZE vi
        rep     stosb

        mov     es,word ptr[_app_dsel]          ; global selector
        mov     edi,dword ptr[_rmbuf_addr]      ; zero real-mode buffer
        add     edi,DVI
        mov     ecx,SIZE vi
        rep     stosb

        mov     ebx,"2EBV"              ; request VESA 2.0 (low-byte first)
        mov     dword ptr[vi.VESASignature],ebx
        mov     edi,dword ptr[_rmbuf_addr]
        add     edi,DVI
        mov     dword ptr es:[edi],ebx  ; must be in real-mode buffer

        mov     [reg.reax],4F00h        ; VESA GetVesaInfo fn
        mov     edi,DVI                 ; get real-mode offset
        mov     [reg.redi],edi
        mov     edx,dword ptr[_rmbuf_seg]       ; get real-mode segment
        mov     [reg.res],dx
        mov     [reg.rflags],0

        mov     eax,0300h               ; DPMI real-mode call
        mov     ebx,10h                 ; call INT 10h
        mov     ecx,0                   ; no stack
        lea     edi,reg                 ; DPMI register set
        mov     dx,ds
        mov     es,dx                   ; plus local selector
        int     31h

        push    ds
        mov     esi,dword ptr[_rmbuf_addr]      ; get real-mode buffer flat address
        add     esi,DVI                         ; +offset
        mov     ds,word ptr[_app_dsel]  ; get flat selector
        lea     edi,vi                  ; copy to local protected-mode buffer
        mov     ecx,SIZE vi
        cld
        rep     movsb

        ASSUME  ES:_DATA

        mov     esi,dword ptr es:[vi.VideoModePtr]  ; get real-mode mode list ptr
        mov     edi,esi
        and     edi,0FFFF0000h          ; get real-mode segment
        shr     edi,12                  ; convert to linear address
        and     esi,0000FFFFh           ; + offset
        add     esi,edi
        lea     edi,_modelist           ; copy to local mode list buffer
        mov     ecx,SIZE _modelist
        cld
        rep     movsb

        ASSUME  ES:NOTHING

        pop     ds
        pop     es

        mov     eax,[reg.reax]          ; VESA result
        cmp     eax,004Fh
        mov     ebx,dword ptr[vi.VESASignature]
        cmp     ebx,"ASEV"              ; VESA signature low-byte first
        movzx   ecx,word ptr[vi.VESAVersion]

        ret

VESA_GetVesaInfo_      endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; int VESA_GetModeInfo(int mode);
; Gets VESA mode info block for selected video mode.
; entry:
; 	EBX <-- video mode
; return:
;       EAX <-- VESA result

        ALIGN 4

VESA_GetModeInfo_      proc near

        push    es
        mov     dx,ds
        mov     es,dx                   ; local selector

        xor     eax,eax
        lea     edi,mi                  ; zero VESA mode info buffer
        mov     dword ptr[_pMI],edi
        mov     ecx,SIZE mi
        cld
        rep     stosb

        lea     edi,reg                 ; zero DPMI reg set
        mov     ecx,SIZE reg
        rep     stosb

        mov     [reg.reax],4F01h        ; VESA GetModeInfo fn
        mov     [reg.recx],ebx          ; VESA mode number
        mov     edi,DMI                 ; get real-mode offset
        mov     [reg.redi],edi
        mov     edx,dword ptr[_rmbuf_seg]       ; get real-mode segment
        mov     [reg.res],dx
        mov     [reg.rflags],0

        mov     eax,0300h               ; DPMI real-mode call
        mov     ebx,10h                 ; call INT 10h
        mov     ecx,0                   ; no stack
        lea     edi,reg                 ; DPMI register set
        mov     dx,ds
        mov     es,dx                   ; plus local selector
        int     31h

        push    ds
        mov     esi,dword ptr[_rmbuf_addr]      ; get real-mode buf flat addr
        add     esi,DMI                         ; + offset
        mov     ds,word ptr[_app_dsel]  ; get flat selector
        lea     edi,mi                  ; get local protected-mode buffer
        mov     ecx,SIZE mi
        cld
        rep     movsb

        pop     ds
        pop     es

        mov     eax,[reg.reax]          ; VESA result
        cmp     eax,004Fh
        ret

VESA_GetModeInfo_      endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; int VESA_GetProtectedInfo(int mode);
; Gets VESA protected-mode info block for selected VESA 2.0 mode.
; entry:
; 	EBX <-- video mode
; return:
;       EAX <-- VESA result

        ALIGN 4

VESA_GetProtectedInfo_ proc near

        push    es
        mov     dx,ds
        mov     es,dx                   ; local selector

        xor     eax,eax
        mov     dword ptr[_pSetStartFn],eax     ; null protected-mode function pointers
        mov     dword ptr[_pSetWindowFn],eax

        lea     edi,pi                  ; zero protected-mode info block
        mov     dword ptr[_pPI],edi
        mov     ecx,SIZE pi
        cld
        rep     stosb

        lea     edi,reg                 ; zero DPMI reg set
        mov     ecx,SIZE reg
        rep     stosb

        mov     [reg.reax],4F0Ah        ; VESA GetProtectedInfo fn
        mov     [reg.rebx],0            ; get protected-mode interface
        mov     [reg.rflags],0

        mov     eax,0300h               ; DPMI real-mode call
        mov     ebx,10h                 ; call INT 10h
        mov     ecx,0                   ; no stack
        lea     edi,reg                 ; DPMI register set
        mov     dx,ds
        mov     es,dx                   ; plus local selector
        int     31h

        cmp     [reg.reax],004Fh        ; VESA fn OK ?
        jne     xgpi

        mov     dx,[reg.res]            ; get real-mode pointer ES:DI
        mov     edi,[reg.redi]
        movzx   edx,dx
        shl     edx,4                   ; convert to flat address
        add     edx,edi
        mov     esi,edx                 ; transfer real-mode buffer
        lea     edi,pi                  ; to protected-mode buffer
        mov     ecx,[reg.recx]          ; by specific number of bytes

        push    ds
        mov     ds,word ptr[_app_dsel]  ; get flat selector
        cld
        rep     movsb
        pop     ds

        lea     edi,pi                  ; compute pointer to SetXY() fn
        movzx   ebx,word ptr[pi.setDisplayStart]  ; offset to SetXY() code
        add     edi,ebx
        mov     dword ptr[_pSetStartFn],edi
        mov     word ptr[_pSetStartFn+4],cs

        lea     edi,pi                  ; compute pointer to SetWindow() fn
        movzx   ebx,word ptr[pi.setWindow]      ; offset to SetWindow() code
        add     edi,ebx
        mov     dword ptr[_pSetWindowFn],edi
        mov     word ptr[_pSetWindowFn+4],cs

xgpi:   pop     es

        mov     eax,[reg.reax]          ; VESA result
        cmp     eax,004Fh
        ret

VESA_GetProtectedInfo_ endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; int VESA_MatchMode(int X, int Y, int Z)
; entry:
;       EBX <-- X res
;       ECX <-- Y res
;       EDX <-- Z bpp
;        ES <-- global data selector
; return:
;       EAX <-- match

VESA_MatchMode_ proc near

        lea     esi,_modelist           ; get local mode list (buffered)

        cmp     word ptr ds:[esi],0FFFFh        ; premature end of mode list ?
        je      mmerr

mm1:
        push    ebx
        push    ecx
        push    edx
        push    esi
        movzx   ebx,word ptr ds:[esi]   ; get mode from list
        call    VESA_GetModeInfo_       ; query mode info
        pop     esi
        pop     edx
        pop     ecx
        pop     ebx
        cmp     eax,004Fh               ; VESA error ?
        jne     mmerr

        cmp     bx,word ptr[mi.XResolution]
        jne     mm2
        cmp     cx,word ptr[mi.YResolution]
        jne     mm2
        cmp     dl,byte ptr[mi.BitsPerPixel]
        jne     mm2
        jmp     mmok                    ; matched

mm2:
        inc     esi                     ; update ptr to next mode
        inc     esi
        cmp     word ptr ds:[esi],0FFFFh        ; end of mode list ?
        je      mmerr
        jmp     mm1

mmok:
        movzx   eax,word ptr ds:[esi]   ; get mode which matched
        ret

mmerr:
        xor     eax,eax                 ; no matches
        ret

VESA_MatchMode_ endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; int InitVesa(void);
; Detect and Init VESA BIOS interface.
; entry:
;       void
; return:
;       EAX <-- VESA result
;       ECX <-- VESA BIOS version

        ALIGN 4

xInitVesa_      proc near

	mov	ax,0100h	; DPMI alloc real-mode mem
	mov	bx,1000h        ; 4K page
	shr	bx,4            ; real-mode paragraphs
	int	31h
	mov	word ptr [_rmbuf_sel],dx	; DX --> alloc selector
	mov	word ptr [_rmbuf_seg],ax	; AX --> real-mode segment
	movzx	eax,ax
	shl	eax,4		; convert segment to flat address
	mov	dword ptr [_rmbuf_addr],eax	; flat address for real-mode buf

        push    es
        mov     es,word ptr[_app_dsel]          ; flat selector
        mov     edi,eax         ; zero alloc buffer
        xor     eax,eax
        mov     ecx,1000h/4     ; 4k bytes in DWORDs
        cld
        rep     stosd
        pop     es

        call    VESA_GetVesaInfo_               ; get VESA BIOS info
        cmp     eax,004Fh                       ; VESA call OK ?
        jne     @iverr
        shr     ecx,8                           ; VESA 1.x or 2.x ?
        mov     [_VESA_detected],ecx            ; log VESA version

        pusha
        mov     ebx,0100h
        call    VESA_GetModeInfo_               ; get VESA mode info too
        popa
        ret

@iverr:
        xor     eax,eax
        mov     [_VESA_detected],eax            ; no VESA interface
        ret

xInitVesa_      endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; void ExitVesa(void);
; Exit VESA BIOS interface.
; entry:
;       void
; return:
;       void

        ALIGN 4

xExitVesa_      proc near

	mov	ax,0101h	; DPMI free real-mode mem
	mov	bx,1000h        ; 4k page
	shr	bx,4            ; real-mode paragraphs
	mov	dx,word ptr [_rmbuf_sel]    ; selector to alloc mem
	int	31h

        xor     eax,eax
        mov     [_VESA_detected],eax
        ret

xExitVesa_      endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; void SetVesaMode(int vmode);
; Sets VESA video mode via BIOS call.
; entry:
; 	EBX <-- video mode
; return:
;       EAX <-- VESA result
;       EBX <-- video mode
;       ECX <-- X resolution
;       EDX <-- Y resolution
;       ESI <-- X scan width
;       EDI <-- linear address

        ALIGN 4

xSetVesaMode_   proc near

        cmp     ebx,0153h               ; UNIVBE 320x200 mode ?
        je      @svm200
        cmp     ebx,0154h               ; UNIVBE 320x240 mode ?
        je      @svm240
        cmp     ebx,0155h               ; UNIVBE 320x400 mode ?
        je      @svm400
        cmp     ebx,0156h               ; UNIVBE 320x480 mode ?
        je      @svm480
        jmp     @svmx
@svm200:
        mov     ebx,320
        mov     ecx,200
        mov     edx,8
        call    VESA_MatchMode_         ; find matching VESA mode
        or      eax,eax
        jz      @svmerr
        mov     ebx,eax
        jmp     @svmx
@svm240:
        mov     ebx,320
        mov     ecx,240
        mov     edx,8
        call    VESA_MatchMode_         ; find matching VESA mode
        or      eax,eax
        jz      @svmerr
        mov     ebx,eax
        jmp     @svmx
@svm400:
        mov     ebx,320
        mov     ecx,400
        mov     edx,8
        call    VESA_MatchMode_         ; find matching VESA mode
        or      eax,eax
        jz      @svmerr
        mov     ebx,eax
        jmp     @svmx
@svm480:
        mov     ebx,320
        mov     ecx,480
        mov     edx,8
        call    VESA_MatchMode_         ; find matching VESA mode
        or      eax,eax
        jz      @svmerr
        mov     ebx,eax
        jmp     @svmx

@svmx:
        mov     [_VESA_vmode],ebx       ; save VESA video mode
        call    VESA_GetModeInfo_       ; get video mode info
        cmp     eax,004Fh               ; VESA call OK ?
        jne     @svmerr
        movzx   eax,word ptr[mi.ModeAttributes]
        and     eax,0080h               ; linear frame buffer supported ?
        mov     [_VESA_linear],eax
        jz      @svmerr
        mov     ebx,[_VESA_vmode]
        or      ebx,4000h               ; select linear frame buffer mode
        mov     [_VESA_vmode],ebx
        call    VESA_SetMode_           ; set video mode
        cmp     eax,004Fh               ; VESA call OK ?
        jne     @svmerr
        mov     ebx,[_VESA_vmode]
        call    VESA_GetProtectedInfo_  ; get protected-mode interface

        mov     eax,0800h               ; DPMI map physical to linear addr
        mov     ebx,dword ptr[mi.PhysBaseptr]
        mov     ecx,ebx
        shr     ebx,16
        mov     esi,dword ptr[vi.TotalMemory]   ; # 64K blocks
        xor     edi,edi
        int     31h
        shl     ebx,16
        movzx   ecx,cx
        or      ebx,ecx
        mov     dword ptr[_VESA_base],ebx       ; linear base address

        movzx   ecx,word ptr[mi.XResolution]    ; X res
        mov     [_VESA_xres],ecx
        movzx   edx,word ptr[mi.YResolution]    ; Y res
        mov     [_VESA_yres],edx
        movzx   esi,word ptr[mi.BytesPerScanLine]       ; X scan line pitch
        mov     [_VESA_xgap],esi
        mov     edi,dword ptr[_VESA_base]       ; linear address
        mov     [_VESA_addr],edi
        mov     ebx,[_VESA_vmode]
        mov     [_VESA_active],0FFFFFFFFh

        pusha
        imul    ecx,esi                 ; compute video page size
        shl     ecx,2                   ; * 4 pages
        xor     eax,eax
        cld
        rep     stosd                   ; clear video mem quad buffers
        popa
        ret

@svmerr:
        xor     ebx,ebx
        mov     [_VESA_vmode],ebx       ; no VESA mode
        mov     [_VESA_active],ebx
        ret

xSetVesaMode_   endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; void SetVesaBank(int vbank);
; Sets VESA bank in VGA 64K memory window.
; entry:
; 	EBX <-- video memory bank
; return:
;       void

        ALIGN 4

xSetVesaBank_   proc near

        cmp     dword ptr[_VESA_detected],2     ; VESA 2.0 ?
        jl      @svb1
        call    VESA_DPMI_SetWindow_            ; call direct
        ret

@svb1:
        call    VESA_SetWindow_                 ; call BIOS
        ret

xSetVesaBank_   endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; void SetVesaPage(int vpage);
; Sets VESA page info for page-flip assignments in VGA 64K bank.
; Note magic number multiplication for 640-wide or 320-wide resolution:
; index = x + 320*y = x +   (64+256)*y = x +   (y<<6) +   (y<<8)
; index = x + 640*y = x + 2*(64+256)*y = x + 2*(y<<6) + 2*(y<<8)
; entry:
; 	EAX <-- video page
; return:
;       void

        ALIGN 4

xSetVesaPage_   proc near

        and     eax,03h                 ; insure only pages 0-3
        mov     dword ptr[_VESA_page],eax
        mov     ecx,eax
        xor     edi,edi                 ; zero index

        mov     eax,dword ptr[_VESA_xgap]
        mov     ebx,dword ptr[_VESA_yres]
        cmp     eax,640                 ; xgap = 640 ?
        jne     @svp1
        shl     ebx,7                   ; yres * 2*64
        mov     edx,ebx
        shl     ebx,2                   ; + yres * 2*256
        add     edx,ebx                 ; = yres * 2*320
        jmp     @svp3

@svp1:
        cmp     eax,320                 ; xgap = 320 ?
        jne     @svp2
        shl     ebx,6                   ; yres * 64
        mov     edx,ebx
        shl     ebx,2                   ; + yres * 256
        add     edx,ebx                 ; = yres * 320
        jmp     @svp3

@svp2:
        mov     edx,eax
        imul    edx,ebx                 ; = xgap * yres

@svp3:
        or      ecx,ecx                 ; page #
        jz      @svp4
        add     edi,edx                 ; 1, 2, or 3 * (xgap * yres)
        dec     ecx
        jmp     @svp3

@svp4:
        mov     dword ptr[_VESA_i],edi  ; cummulative index
        mov     esi,edi                 ; page * (xgap * yres)

if 0    ; no support for banking
        shr     esi,16                  ; ... / 0x10000
        mov     dword ptr[_VESA_bank],esi
        shl     esi,16
        sub     edi,esi                 ; ... % 0x10000
        mov     dword ptr[_VESA_i],edi  ; = index within 64K bank
endif

        mov     eax,edi
        mov     ebx,dword ptr[_VESA_xgap]
        xor     edx,edx
        idiv    ebx                     ; compute index / xgap
        mov     dword ptr[_VESA_y],eax  ; y = index / xgap
        mov     dword ptr[_VESA_x],edx  ; x = index % xgap
        add     edi,dword ptr[mi.PhysBaseptr]   ; address = base + index
        mov     dword ptr[_VESA_addr],edi

        ret

xSetVesaPage_   endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; void SetVesaIndex(int vpage, int x, int y);
; Sets VESA pixel index for selected page and relative X,Y coordinate.
; Note magic number multiplication for 640-wide or 320-wide resolution:
; index = x + 320*y = x +   (64+256)*y = x +   (y<<6) +   (y<<8)
; index = x + 640*y = x + 2*(64+256)*y = x + 2*(y<<6) + 2*(y<<8)
; entry:
;	EAX <-- video page
;       EBX <-- pixel X
; 	ECX <-- pixel Y
; return:
;       void

        ALIGN 4

xSetVesaIndex_  proc near

        and     eax,03h                 ; insure only pages 0-3
        mov     dword ptr[_VESA_page],eax
        mov     dword ptr[_VESA_x],ebx  ; x for any page
        mov     dword ptr[_VESA_y],ecx  ; y for page 0
        mov     ecx,eax
        xor     edi,edi                 ; zero index accumulator
        xor     esi,esi                 ; zero yres accumulator

        mov     eax,dword ptr[_VESA_xgap]
        mov     ebx,dword ptr[_VESA_yres]
        cmp     eax,640                 ; xgap = 640 ?
        jne     @svi1
        shl     ebx,7                   ; yres * 2*64
        mov     edx,ebx
        shl     ebx,2                   ; + yres * 2*256
        add     edx,ebx                 ; = yres * 2*320
        shr     ebx,9
        jmp     @svi3

@svi1:
        cmp     eax,320                 ; xgap = 320 ?
        jne     @svi2
        shl     ebx,6                   ; yres * 64
        mov     edx,ebx
        shl     ebx,2                   ; + yres * 256
        add     edx,ebx                 ; = yres * 320
        shr     ebx,8
        jmp     @svi3

@svi2:
        mov     edx,ebx
        imul    edx,eax                 ; = xgap * yres

@svi3:
        or      ecx,ecx                 ; page #
        jz      @svi4
        add     edi,edx                 ; 1, 2, or 3 * (xgap * yres)
        add     esi,ebx                 ; 1, 2, or 3 * yres
        dec     ecx
        jmp     @svi3

@svi4:
        mov     eax,dword ptr[_VESA_xgap]
        mov     ebx,dword ptr[_VESA_y]
        mov     ecx,dword ptr[_VESA_x]
        add     dword ptr[_VESA_y],esi  ; y = y + (page * yres)
        cmp     eax,640                 ; xgap = 640 ?
        jne     @svi5
        shl     ebx,7                   ; y * 2*64
        mov     edx,ebx
        shl     ebx,2                   ; + y * 2*256
        add     edx,ebx                 ; = y * 2*320
        add     edx,ecx                 ; ... + x
        jmp     @svi7

@svi5:
        cmp     eax,320                 ; xgap = 320 ?
        jne     @svi6
        shl     ebx,6                   ; y * 64
        mov     edx,ebx
        shl     ebx,2                   ; + y * 256
        add     edx,ebx                 ; = y * 320
        add     edx,ecx                 ; ... + x
        jmp     @svi7

@svi6:
        mov     edx,eax
        imul    edx,ebx                 ; = xgap * y
        add     edx,ecx                 ; ... + x

@svi7:
        add     edx,edi                 ; ... + page * (xgap * yres)
        mov     dword ptr[_VESA_i],edx  ; = index
        mov     edi,dword ptr[_VESA_base]
        add     edi,edx
        mov     dword ptr[_VESA_addr],edi       ; = base addr + index

        ret

xSetVesaIndex_  endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; void PlotVesaPixel(int vpage, int x, int y, BYTE pixel);
; Plots pixels directly into VESA video memory.
; Optimized in case of repetitive calls.
; entry:
; 	EAX <-- page #
; 	EBX <-- pixel X
; 	ECX <-- pixel Y
; 	EDX <-- pixel color
;        ES <-- application data selector (global)
; return:
;       void

        ALIGN 4

xPlotVesaPixel_ proc near

        push    edx
	call    xSetVesaIndex_          ; compute video address index
        pop     edx

        mov     edi,[_VESA_addr]        ; get video address + index
        mov     byte ptr es:[edi],dl    ; transfer pixel
        ret

xPlotVesaPixel_ endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; void FillVesaPixels(int vpage, int x0, int y0, int xd, int yd, BYTE pixel);
; Fills pixels directly into VESA video memory.
; Compatible with mode-X function FillPixels4.
; entry:
; 	EAX <-- page # (ignored)
; 	EBX <-- VESA video memory address index
; 	ECX <-- VESA pixel count
; 	EDX <-- pixel color
;        ES <-- application data selector (global)
; return:
;       void

        ALIGN 4

xFillVesaPixels_        proc near

        mov	edi,[_VESA_base]        ;init video memory destination
	add	edi,ebx		        ;adjust destination address by index
	mov	eax,edx		        ;transfer pixel color to copy
	mov	ah,al		        ;duplicate pixel byte
	shl	eax,16
	mov	al,dl		        ;duplicate 2x more
	mov	ah,al
        shr     ecx,2                   ;count by quads
	cld
	rep	stosd		        ;copy pixel in quads

        ret

xFillVesaPixels_        endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; void MoveVesaPixels(int vpage, int x0, int y0, int xd, int yd, LPBYTE lpBuf);
; Move a X*Y-byte block of pixels to video memory page.
; Compatible with mode-x function MovePixelsClip.
; on entry:
; 	EAX <-- page
; 	EBX <-- x0,y0 (packed)
; 	ECX <-- xd,yd (packed)
; 	ESI <-- screenbuf address
;  	 DX <-- screenbuf selector
;  	 DS <-- SVR driver data selector (local)
;        ES <-- application data selector (global)
; during operation:
; 	DS:ESI <-- source address in screen buffer
; 	ES:EDI <-- destination address in video memory
; 	ECX <-- block counter
; return:
;       void

        ALIGN 4

xMoveVesaPixels_        proc near

        push    esi
        push    edx
        push    ecx

        mov     ecx,ebx
	movzx	ebx,bx		;unpack x0
	shr	ecx,16		;unpack y0
        call    xSetVesaIndex_          ;compute XY index and address

        pop     ecx
	movzx	eax,cx		;unpack xd
	shr	ecx,16		;unpack yd
        imul	ecx		;count = xd * yd
	mov	ecx,eax		;xy count --> ECX

        pop     edx
        pop     esi
	mov	edi,[_VESA_addr]        ;init video memory destination
	shr	ecx,2		        ;count by quads
	cld
        push    ds
        mov     ds,dx                   ;source from dx:esi
	rep	movsd		        ;blit
        pop     ds

        ret

xMoveVesaPixels_        endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; void DisplayVesaXY(int x, int y);
; Display VESA memory according to absolute X,Y coordinates.
; entry:
; 	EBX <-- X
;       ECX <-- Y
; return:
;       void

        ALIGN 4

xDisplayVesaXY_         proc near

        cmp     dword ptr[_VESA_detected],2     ; VESA 2.0 ?
        jl      @dvxy1

        mov     eax,[_VESA_page]        ; whatever page is current
        call    xSetVesaIndex_          ; compute linear index
        mov     ecx,[_VESA_i]           ; pass linear index
        call    VESA_DPMI_SetXY_        ; call direct
        ret

@dvxy1:
        mov     edx,ecx                 ; pass virtual XY as-is for VESA 1.2
        mov     ecx,ebx
        call    VESA_SetXY_             ; call thru BIOS
        ret

xDisplayVesaXY_         endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; void DisplayVesaPage(int vpage);
; Display VESA memory page.
; entry:
; 	EBX <-- video page
; return:
;       void

        ALIGN 4

xDisplayVesaPage_       proc near

        movzx   eax,bl
        and     al,03h                  ; insure pages 0-3
        call    xSetVesaPage_           ; compute XY info per page #
        mov     ebx,[_VESA_x]
        mov     ecx,[_VESA_y]
        call    xDisplayVesaXY_         ; set display page per XY coordinates
        ret

xDisplayVesaPage_       endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; VESA version of SetGraphLimits
; Sets pixel X,Y and index limits for selected resolution and format.
; VESA Video memory indexes are in actual bytes (not bytes / 4).
; entry:
;       void
; return:
;       void

        public  xSetVesaGraphLimits_

        ALIGN   4

xSetVesaGraphLimits_        proc near

        mov     eax,[_svr_line_alternate]       ; line-alt format ?
        or      eax,eax
        jnz     @sgl2

        mov     eax,[svr_halfed]                ; half-res format ?
        or      eax,eax
        jnz     @sgl1

@sgl0:  ; full-resolution format
        mov     eax,[_VESA_xres]        ; max x = x resolution
        mov     [_xres],eax
        mov     [_xmax],eax
        mov     ebx,[_VESA_yres]        ; max y = y resolution - 1
        mov     [_yres],ebx
        dec     ebx
if 1
        cmp     [_svr_OEM_support],OEM6 ; NVidia NV3 ?
        jne     @sgl00
        dec     ebx                     ; adjust 1 less line for NV3 stereo bug
@sgl00:
endif
        mov     [_ymax],ebx
        xor     edx,edx                 ; max index = max x * max y
        imul    ebx
        mov     [_imax],eax             ; linear index
        add     eax,[_VESA_addr]        ; max video address
        mov     [_vmax],eax
        ret

        ALIGN   4

@sgl1:  ; half-resolution format
        mov     eax,[_VESA_xres]        ; max x = x resolution
        mov     [_xmax],eax
        mov     ebx,[_VESA_yres]        ; max y = (y resolution /2) - 1
        shr     ebx,1
        dec     ebx
        mov     [_ymax],ebx
        xor     edx,edx                 ; max index = max x * max y
        imul    ebx
        mov     [_imax],eax
        add     eax,[_VESA_addr]        ; max video address
        mov     [_vmax],eax
        ret

        ALIGN   4

@sgl2:  ; line-alternate format
        mov     eax,[_VESA_xres]        ; max x = x resolution
        mov     [_xmax],eax
        mov     ebx,[_VESA_yres]        ; max y = y resolution - 2
        dec     ebx
        dec     ebx
        mov     [_ymax],ebx
        xor     edx,edx                 ; max index = max x * max y
        imul    ebx
        mov     [_imax],eax
        add     eax,[_VESA_addr]        ; max video address
        mov     [_vmax],eax
        ret

xSetVesaGraphLimits_        endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; VESA version of SetGraphPages
; Sets video page addresses for selected resolution and format.
; VESA Video memory indexes are in actual bytes (not bytes / 4).
; entry:
;       void
; return:
;       void

        public  xSetVesaGraphPages_

        ALIGN   4

xSetVesaGraphPages_        proc near

        mov     eax,[_svr_line_alternate]       ; line-alt format ?
        or      eax,eax
        jnz     @sgp2

        mov     eax,[svr_halfed]                ; half-res format ?
        or      eax,eax
        jnz     @sgp1

@sgp0:  ; full-resolution format on 4 pages
        xor     eax,eax
        call    xSetVesaPage_
        mov     eax,[_VESA_i]
        mov     edx,[_VESA_addr]
        mov     [_ileft_front],eax      ; set page 0 index
        mov     [_vleft_front],edx      ; + video address
        mov     eax,1
        call    xSetVesaPage_
        mov     eax,[_VESA_i]
        mov     edx,[_VESA_addr]
        mov     [_iright_front],eax     ; set page 1 index
        mov     [_vright_front],edx     ; + video address
        mov     eax,2
        call    xSetVesaPage_
        mov     eax,[_VESA_i]
        mov     edx,[_VESA_addr]
        mov     [_ileft_back],eax       ; set page 2 index
        mov     [_vleft_back],edx       ; + video address
        mov     eax,3
        call    xSetVesaPage_
        mov     eax,[_VESA_i]
        mov     edx,[_VESA_addr]
        mov     [_iright_back],eax      ; set page 3 index
        mov     [_vright_back],edx      ; + video address
        ret

        ALIGN   4

@sgp1:  ; half-resolution format on 2 pages
        xor     eax,eax                 ; page 0
        call    xSetVesaPage_
        mov     eax,[_VESA_i]
        mov     edx,[_VESA_addr]
        mov     [_ileft_front],eax      ; set page 0 index
        mov     [_vleft_front],edx      ; + video address
        mov     ebx,[_imax]             ; get half-res max index
        add     ebx,[_VESA_xgap]        ; adjust past bottom reg line
        add     eax,ebx
        add     edx,ebx
        mov     [_iright_front],eax     ; set page 1 index on bottom half
        mov     [_vright_front],edx     ; + video address
        mov     eax,1                   ; next full-size page 1
        call    xSetVesaPage_
        mov     eax,[_VESA_i]
        mov     edx,[_VESA_addr]
        mov     [_ileft_back],eax       ; set page 2 index at mid video mem
        mov     [_vleft_back],edx       ; + video address
        mov     ebx,[_imax]             ; get half-res max index
        add     ebx,[_VESA_xgap]        ; adjust past bottom reg line
        add     eax,ebx
        add     edx,ebx
        mov     [_iright_back],eax      ; set page 3 index on bottom half
        mov     [_vright_back],edx      ; + video address
        ret

        ALIGN   4

@sgp2:  ; line-alternate format on 2 pages
        xor     eax,eax                 ; page 0
        call    xSetVesaPage_
        mov     eax,[_VESA_i]
        mov     edx,[_VESA_addr]
        mov     [_ileft_front],eax      ; set page 0 index
        mov     [_vleft_front],edx      ; + video address
        mov     ebx,[_VESA_xgap]        ; difference between alternate lines
        add     eax,ebx
        add     edx,ebx
        mov     [_iright_front],eax     ; set page 1 index on same video page
        mov     [_vright_front],edx     ; + video address
        mov     eax,2                   ; advance to full-size page 2
        call    xSetVesaPage_
        mov     eax,[_VESA_i]
        mov     edx,[_VESA_addr]
        mov     [_ileft_back],eax       ; set page 2 index at mid video mem
        mov     [_vleft_back],edx       ; + video address
        mov     ebx,[_VESA_xgap]        ; difference between alternate lines
        add     eax,ebx
        add     edx,ebx
        mov     [_iright_back],eax      ; set page 3 index on same video page
        mov     [_vright_back],edx      ; + video address
        ret

xSetVesaGraphPages_        endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_CODE	ENDS

	END

