; External function calls used in MODEX32.ASM:

	EXTRN	_vmode:DWORD
        extrn   _xres:DWORD
        extrn   _yres:DWORD
        extrn   _xmax:DWORD
        extrn   _ymax:DWORD
        extrn   _imax:DWORD
	extrn	_vmax:DWORD
        extrn   _ileft_front:DWORD
        extrn   _iright_front:DWORD
        extrn   _ileft_back:DWORD
        extrn   _iright_back:DWORD
        extrn   _vleft_front:DWORD
        extrn   _vright_front:DWORD
        extrn   _vleft_back:DWORD
        extrn   _vright_back:DWORD

	EXTRN	InitModexLocals_:near
	EXTRN	xGetVideoMode_ 	:near
	EXTRN	xSetVideoMode_ 	:near
	EXTRN	xSetTextMode_ 	:near
	EXTRN	xSetGraphMode13_:near
	EXTRN	xSetGraphModeX_ :near
	EXTRN	xSetPaletteColor_ 	:near
	EXTRN	xPlotPixel_ 	:near
        EXTRN   xPlotPixelPageX_:near
	EXTRN	xFillPixel4_ 	:near
	EXTRN	xMixMod4_	:near
	EXTRN	xUnMixmod4_	:near
	EXTRN	xMovePixelPage_ :near
	EXTRN	xMovePixelClip_ :near
	EXTRN	xReadPixelClip_ :near
	EXTRN	xVSync_ 	:near
	EXTRN	xWaitVSync_ 	:near
	EXTRN	xSelectDisplayMem_ 	:near
	EXTRN	xSelectDisplayPage_ 	:near
	EXTRN	xSetPaletteMode_:near
        extrn   xSetGraphLimits_:near
        extrn   xSetGraphPages_:near
        extrn   xSetGraphModeX200_:near
        extrn   xSetGraphModeX400_:near
        extrn   xSetGraphModeX240_:near
        extrn   xSetGraphModeX480_:near


