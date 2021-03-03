; Separate header to be attached to SVRDOS32.COM file
; to create SVRDOS32.DRV file to account for 0100h offset.
; 	tasm svrhdr32.asm
;	tlink svrhdr32.obj /t
; 	copy svrhdr32.com,svrdos32.com svrdos32.drv

	.386

_CODE	SEGMENT DWORD PUBLIC USE32 'CODE'
	ASSUME	cs:_CODE, ds:_CODE

; read-only header has to be associated with code here for start of file

	ORG	0100h
MAIN:

header:	db	"****SVRDOS32****"
hname:	db	"SimulEyes VR Driver for 32-bit DOS Extender "
hver:	db	"Version 2.01 "
hcopy:	db	"Copyright 1995 StereoGraphics Inc. "

	ORG	01FFh

hend:	db	0

_CODE	ENDS

	END	MAIN
