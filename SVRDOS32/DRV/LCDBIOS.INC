;;** Symbols for LCDBIOS
;;** Symbol names preserved for LCDBIOS32 protected-mode versions.



; Global symbols

; Interrupts
INTR_DOSTICK        EQU     01ch        ;DOS 18.2-Hz timer
INTR_TIMER          EQU     070h        ;RTC timer interrupt number (IRQ 8)
INTR_BIOS           EQU     010h        ;Video BIOS interrupt number

; CMOS register (for activating Real-Time Clock (RTC) periodic interrupt)
CMOS_ADDR           EQU     070h        ;CMOS address register
CMOS_DATA           EQU     071h        ;CMOS data register
CMOS_B              EQU     0bh         ;RTC enable interrupt offset

; VGA register I/O addresses
CRTC_ADDR           EQU     03d4h       ;VGA CRTC registers' port
MISC_WRITE_ADDR     EQU     03c2h       ;VGA Misc Output register (write only)
MISC_READ_ADDR      EQU     03cch       ;VGA Misc Output register (read only)
STA0_ADDR           EQU     03c2h       ;VGA Status 0 register
STA1_ADDR           EQU     03dah       ;VGA Status 1 register

; VGA register offsets
VRER                EQU     011h        ;Vert. Retrace End Reg. (CRTC)
OFFR                EQU     013h        ;Offset Reg. (CRTC)
MSLR                EQU     009h        ;Max. Scan Line Reg. (CRTC)
SAHR                EQU     00ch        ;Start Addr. High Reg. (CRTC)
SALR                EQU     00dh        ;Start Addr. Low Reg. (CRTC)

; other
LCDBIOS_VERSION	    EQU	    0121h	;LCDBIOS version (DaveM)
CAL_LENGTH          EQU     60          ;# retraces for calibration



;;** Data aliases for numerical offsets in [base+offset] addressing:
;;** All data items are 16-bit WORDs (dw) unless otherwise noted;
;;** 3 far interrupt vectors are 48-bit FWORDs (DF);
;;** Align all data offset values on 4-byte boundaries;
;;** Start offset at -128 for 8-bit relative indexes;

D0               EQU 0               ;offset origin

D_boostRefresh   EQU 0+D0 ; dw          ;1 = attempt to increase VGA refresh
D_flipEyeOffset  EQU 4+D0 ; dw          ;# of ticks after _retraceCount to
		                        ; flip eyes (may be +/-)
D_nailRetrace    EQU 8+D0 ; dw          ;1 = always busy-wait to nail eye
			                ; flip on retrace (no black band)
; static data variables (private)
D_mode           EQU 12+D0 ; dw         ;current RTC IRQ mode (0-4, see below)
D_countTick      EQU 16+D0 ; dw         ;# ticks after vert. retrace
D_countTickEye   EQU 20+D0 ; dw         ;extended countTick for eye flipping
					; (reset to countTick only after
					;  retrace AND after eye flips)
D_countVertRet   EQU 24+D0 ; dw         ;# vert. retrace
D_clearVertInt   EQU 28+D0 ; dw         ;clears vertical interrupt bit
D_setVertInt     EQU 32+D0 ; dw         ;sets vertical interrupt trigger
D_countMisses    EQU 36+D0 ;            ;# vertical interrupt bit misses
					;  (caught by timer overflow)
D_countMisses1C  EQU 40+D0 ; dw         ;# times that DOS 18.2-Hz went off
					;  with RTC not running
D_flippedEyes    EQU 44+D0 ; dw         ;flag=1 after eyes have been flipped
					;flag=0 after resync occurs
D_exitMode	 EQU 48+D0 ; dw         ;value of Mode when 3D mode was exited

; uninitialized static data variables (private)

D_retraceCount   EQU 52+D0 ; dw         ; Average number of ticks per retrace
				        ;  (rounded down to nearest integer)
D_flipScreenTick EQU 56+D0 ; dw         ; Flip screen on this tick count
D_flipEyeTick    EQU 60+D0 ; dw         ; Flip glasses eyes on this tick count (may
				        ;  be greater than resyncMissTick)
D_resyncCheckTick EQU 64+D0 ; dw        ; Start checking retrace bit on this tick
D_resyncMissTick EQU 68+D0 ; dw         ; Stop checking retrace bit on this tick
				        ;  (assume retrace was somehow missed)
D_sumTick        EQU 72+D0 ; dw         ; Counter used to calibrate retraceCount
D_page           EQU 76+D0 ; dw         ; currently displayed page: 0 = left page
				        ;			    1 = right page
D_saveMiscOut    EQU 80+D0 ; DB -- Value of VGA MiscOutput Register on init 3D
D_saveOffset     EQU 84+D0 ; DB -- Value of VGA Offset Register on init 3D
D_saveMSL        EQU 88+D0 ; DB -- Value of VGA MaxScanLine Register on init 3D
D_saveVRER       EQU 92+D0 ; DB -- Value of VGA VertRetEnd Register on init 3D
D_saveCRTCIndex  EQU 96+D0 ; DB -- Value of VGA CRTC Index Register

D_oldhandler     EQU 100+D0 ; DF        ; DF -- old INT 70h
                            ; FWORD FWORD FWORD...

; keep these variables in the code segment so they can be accessed with
;   DS undefined/unchanged in interrupt handlers

D_oldhandlerBIOS EQU 108+D0 ; DF        ; DF -- old INT 10h
D_oldhandler1C   EQU 116+D0 ; DF        ; DF -- old INT 1Ch
                            ; FWORD FWORD FWORD...
D_timerCheckRTC  EQU 120+D0 ; dw        ; Used for countMisses1C
					; set to 0 on every retrace (mode 3)
					; set to 1 on every DOS tick (when
					;       not disabled)
					; set to 2 to disable
D_stereoMode	 EQU 124+D0 ; dw        ;method of entering 3D operation:
					;  0 = off/LCDBios TwoBuffer
					;  1 = 3D-BIOS "glasses on"
					;  2 = LCDBios AlternateFull
					;  3 = LCDBios AlternateHalf
D_vesaMode       EQU 128+D0 ; dw        ; 0 = in a VGA mode
					; 1 = in a VESA mode
D_hookVesa       EQU 132+D0 ; dw        ; 0 = ignore VESA start address calls
					; 1 = capture VESA start address
D_screenWidth	 EQU 136+D0 ; dw        ; physical width of screen (in pixels
					;   for VESA, in CPU bytes for VGA)
; The following 256 bytes *must* occur in order for LCDBios to work
;   correctly.  It can be referenced by external programs and is one
;   continuous block of data
D_startLeftX	EQU  140+D0 ; dw        ; left-eye X start address (VESA)
					;   or left-eye start address (VGA)
					; Note: VGA address is high+low bytes
D_startLeftY	EQU  144+D0 ; dw        ; left-eye Y start address (VESA)
					;   or dummy padding (VGA)
D_startRightX	EQU  148+D0 ; dw        ; right-eye X start address (VESA)
					;   or right-eye start address (VGA)
					; Note: VGA address is high+low bytes
D_startRightY	EQU  152+D0 ; dw        ; right-eye Y start address (VESA)
					;   or dummy padding (VGA)
D_pageAdvanced	EQU  156+D0 ; dw        ; set to 2 during the calibration
					;   period when 3D mode is turned on
					; set to 1 at each vertical retrace
					;   after 3D is on and calibrated
					; set to 0 by LCD/3DBios SetStartAddr
					;   or by an external program
D_interruptCount EQU 160+D0 ; dd        ; DD -- incremented every time RTC interrupt
					;   is called
D_delayCount	EQU 164+D0 ; dd         ; DD -- incremented every time LCDBios makes
					;   a long delay (when waiting to sync
					;   to vert retrace with nailRetrace)
D_pad		EQU 168+D0 ; db         ; DB -- pad to 256 bytes


D_rm_isr_count	EQU 172+D0 ; DW -- real-mode ISR event counter (DaveM)
D_pm_isr_count	EQU 176+D0 ; DD -- protected-mode ISR event counter (DaveM)


D_svr_oem	EQU 180+D0 ; DD -- SVR OEM code (DaveM)
D_oem_port      EQU 184+D0 ; DD -- SVR OEM port address (DaveM)
D_oem_data      EQU 188+D0 ; DD -- SVR OEM port data (Davem)

D_pm_setxy      EQU 192+D0 ; DD -- protected-mode external SetXY function
D_pm_external   EQU 196+D0 ; DQ -- protected-mode external callback function
D_old_passup    EQU 204+D0 ; DQ -- original auto-passup vector

D_oem_dataL     EQU 212+D0 ; DD -- SVR OEM port data (Davem)
D_oem_dataR     EQU 216+D0 ; DD -- SVR OEM port data (Davem)
