; External function declarations for LCD32.ASM:

	extrn	_RMvertRet16_:far	; real-mode vertical retrace ISR
	extrn	_RMvertRet16end_:far
	extrn	_PMvertRet32_:far	; protected-mode vertical retrace ISR
	extrn	_PMvertRet32end_:far

	extrn	_InitLcdbios32_:near
	extrn	_ExitLcdbios32_:near
	extrn	_EnableLcdbios32_:near
	extrn	_DisableLcdbios32_:near
	extrn	_LowPageLcdbios32_:near
	extrn	_HighPageLcdbios32_:near

