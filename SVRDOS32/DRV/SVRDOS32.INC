; Include file for "svrdos32.asm"

	EXTRN	_app_csel:DWORD
	EXTRN	_app_dsel:DWORD
	EXTRN	_svr_csel:DWORD
	EXTRN	_svr_dsel:DWORD

	EXTRN	_svr_technique:WORD
	EXTRN	_svr_timerate:WORD
	EXTRN	_svr_pcallin:FWORD
	EXTRN	_svr_pcallout:FWORD

	EXTRN	_svr_calls_far:DWORD
	EXTRN	_svr_debug_port:DWORD
	EXTRN	_svr_pixels_modex:DWORD
	EXTRN	_svr_pixels_width:DWORD

	EXTRN	_svr_ISR_options:DWORD
	EXTRN	_svr_sync_edge:DWORD
	EXTRN	_svr_PIC_reset:DWORD
	EXTRN	_svr_STI_reset:DWORD
	EXTRN	_svr_HZ18_chain:DWORD
	EXTRN	_svr_timer_reload:DWORD
	EXTRN	_svr_timer_oneshot:DWORD
	EXTRN	_svr_ticks_adjust:DWORD
	EXTRN	_svr_double_rate:DWORD
	EXTRN	_svr_timer_chan2:DWORD

	extrn	_svr_calls_far:dword
	extrn	_svr_pixels_modex:dword
	extrn	_svr_pixels_width:dword
	extrn	_svr_debug_port:dword
	extrn	_svr_pal_protect:dword
	extrn	_svr_line_alternate:dword
	extrn	_svr_high_refresh:dword
	extrn	_svr_lock_flip:dword
	extrn	_svr_delay_flip:dword
	extrn	_svr_fast_intr:dword
	extrn	_svr_OEM_support:dword

        extrn   svr_active:dword
	extrn	svr_halfed:dword

