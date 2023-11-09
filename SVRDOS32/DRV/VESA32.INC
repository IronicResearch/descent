; External variable and function declarations for VESA32.ASM:

        extrn   _VESA_detected:dword
        extrn   _VESA_active:dword
        extrn   _VESA_x:dword
        extrn   _VESA_y:dword
        extrn   _VESA_i:dword
        extrn   _VESA_page:dword
        extrn   _VESA_bank:dword
        extrn   _VESA_addr:dword
        extrn   _VESA_xres:dword
        extrn   _VESA_yres:dword
        extrn   _VESA_vmode:dword
        extrn   _VESA_linear:dword
        extrn   _VESA_xgap:dword

        extrn   _pSetStartFn:qword
        extrn   _pSetWindowFn:qword

        extrn   _pVI:dword
        extrn   _pMI:dword
        extrn   _pPI:dword

	extrn   InitVesaLocals_:near

        extrn   xInitVesa_:near
        extrn   xExitVesa_:near
        extrn   xSetVesaMode_:near
        extrn   xSetVesaBank_:near
        extrn   xSetVesaPage_:near
        extrn   xSetVesaIndex_:near
        extrn   xPlotVesaPixel_:near
        extrn   xFillVesaPixels_:near
        extrn   xMoveVesaPixels_:near
        extrn   xDisplayVesaXY_:near
        extrn   xDisplayVesaPage_:near

        extrn   xSetVesaGraphLimits_:near
        extrn   xSetVesaGraphPages_:near


