; Include file for all SVRDOS32 ASM modules

OBIN	EQU	0100h		;origin for binary COM file

OHDR	EQU	0000h		;offset for file header
ODAT	EQU	0100h		;offset for data area
OJMP	EQU	1000h   	;offset for jump table
OJMP2	EQU	1100h   	;offset for jump table (aligned)
OCOD	EQU	1200h		;offset for code area

SVR_VGA		EQU	1	;SVR ISR for VGA interrupts
SVR_TMR		EQU	2	;SVR ISR for PC timer interrupts
SVR_SOS		EQU	3	;SVR ISR for internal SOS emulation (not used)
SVR_EMU		EQU	4	;SVR ISR for externally emulated timeouts
SVR_LCD		EQU	5	;SVR ISR for external LCDBIOS calls
SVR_LCD32	EQU	6	;SVR ISR for internal LCDBIOS interrupts

PAGES_PACKED	EQU	0	;for contiguous video memory pages

	IF	PAGES_PACKED
PAGESIZE	EQU	64000	;for contiguous video memory pages
PAGESIZE4	EQU	16000	;for contiguous video memory pages
	ELSE
PAGESIZE	EQU	10000h	;for page-aligned video memory pages
PAGESIZE4	EQU	4000h	;for page-aligned video memory pages
	ENDIF

SVR_DEBUG	EQU	0	;for debugging SVR ISR activity

RED_HACK        EQU     0
GREEN_HACK      EQU     0
CYAN_HACK       EQU     0

; Macro for putting short IO delay inline to account for IO bus access.
; (Michael Abrash sez 1 JMP is enough nowadays, and he knows everything...)

IODELAY	MACRO

	jmp	$+2

	ENDM

; Macro for using explicit DEC/JNZ instead of LOOP instruction
; This is faster on 386/486+ machines.

LOOPM   MACRO    @jmpt

        dec      ecx
        jnz      @jmpt

        ENDM

