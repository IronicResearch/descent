; interface for OEM32.ASM

OEM1	EQU	1               ;Brooktree
OEM2	EQU	2               ;Rendition
OEM3	EQU	3               ;diagnostic port
OEM4	EQU	4               ;Alliance
OEM5	EQU	5               ;Alliance AT3D
OEM6    EQU     6               ;VESA 3.0 above/below stereo, NVidia NV3
OEM7    EQU     7               ;VESA 3.0 dual-address stereo

	extrn	_DetectOEM_:near
	extrn	_InitOEM_:near
	extrn	_ExitOEM_:near
	extrn	_UpdateOEM_:near

