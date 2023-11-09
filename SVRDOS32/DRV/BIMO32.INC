; External function declarations for BIMO32.ASM:

	extrn	_lp_rm_isr	:fword
	extrn	_lp_rm_data	:fword
	extrn	_lp_pm_isr	:fword
	extrn	_intRateOffset	:dword

	extrn	_InitLcdbios_:near
	extrn	_ExitLcdbios_:near
	extrn	_InitLcdbiosDpmi_:near
	extrn	_ExitLcdbiosDpmi_:near
	extrn	_InitLcdbiosTimer_:near
	extrn	_ExitLcdbiosTimer_:near
	extrn	_SetLcdbiosOptions_:near
	extrn	_GetLcdbiosOptions_:near

