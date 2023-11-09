; External function calls used in SVRISR32.ASM:

	EXTRN	_svr_stereomode	:DWORD
	EXTRN	_svr_visiblepage:WORD

	EXTRN	InitISRLocals_	:near
	EXTRN	xEnableAutoStereo_ 	:near
	EXTRN	xDisableAutoStereo_ 	:near
	EXTRN	xVGA_Enable_ 	:near
	EXTRN	xVGA_Disable_ 	:near
	EXTRN	xVGA_ISR_ 	:near
	EXTRN	xTMR_Enable_ 	:near
	EXTRN	xTMR_Disable_ 	:near
	EXTRN	xTMR_ISR_ 	:near
	EXTRN	xTMR_Init_ 	:near
	EXTRN	xTMR_Exit_ 	:near
	EXTRN	xTMR_Adjust_ 	:near
	EXTRN	xEMU_Enable_ 	:near
	EXTRN	xEMU_Disable_ 	:near
	EXTRN	xEMU_ISR_ 	:near

