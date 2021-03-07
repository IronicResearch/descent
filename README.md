# Descent 1.5 legacy

Rebuilt the Descent 1.5 project with Watcom 10.x + MASM 6.1x.
Some of the makefiles needed tweaking when using MSVC `make`.

The main makefile was initially useless, deferring to `MAKED1.BAT` for building.
Modified the makefile to at least clean all object and lib files via `make clean`.
```
  maked1
  dir main\descentr.exe
  .. copy/move ..
  make clean
```
When attempting to run the resulting DESCENTR.EXE, kept running into asset loading
error on the briefing screen sequence, which got workaround using “-noscreens” option.
Tried `#define DEST_SAT` option since data files were copied from the "Destination Saturn” CD,
but no difference. Such commented out options are located in SETTINGS.H header, which
turned out to be convenient alternative to global makefile #defines.

## Background history:

The Descent 1.5 source looks intact with stereo support for various VR headsets and glasses.
The StereoGraphics SimulEyes glasses were the last VR device to be ported, which was done by
longtime stereo consultant Bob Akka for improved stereo viewing, and myself for graphics
driver support.

We learned from Interplay that a number of LCS glasses were using an
external page-flip driver developed by Don Sawdai called LCDBIOS.
LCDBIOS featured an alternative timer interrupt based on IRQ8 real-time clock
to avoid impacting the IRQ0 system timer used for music and sound effects.
LCDBIOS also featured a page-flip mode for stereo images composited in
alternate-line interleaved format, as used by Virtual-IO i-glasses HMD.

Hence LCDBIOS was used by default Descent releases instead of StereoGraphics’
own SVRDOS32 driver. LCDBIOS was later licensed to StereoGraphics for porting 
into their SVRDOS32 driver, and also recompiled for DOS/4G as a replacement 
called SIMBIOS. (LCDBIOS.EXE is located on the Destination Saturn CD.)

SIMBIOS has the advantage of pre-emptively loading DOS/4G instead of DOS/4GW
in order to fully handle interrupts in both protected mode and real mode to
improve responsiveness with external drivers. 
(SIMBIOS.EXE was available separately from CD, and located in SIMBIOS.ZIP.)

SVRDOS32 has the advantage of loading as a driver in the same process space
as the calling app (Descent) instead of running as a parent process shell. 
SVRDOS32 manages display memory directly, so also takes advantage of using VESA 2.0
linear framebuffer modes and higher refresh rates instead of VGA mode X variants. 
Although VESA 2.0 BIOS functionality was relatively new at the time, SciTech Software’s
UniVBE driver was able to expand refresh rate support to a large number of graphics boards.

Descent must be recompiled with `#define SVRDOS32` and linked with SVRDOS32.LIB.
SVRDOS32.DRV must be copied to the same directory as the Descent EXE.

## Runtime options for stereo modes:

For running stereo modes with default LCDBIOS shell (LCDBIOS.EXE from CD): 

	lcdbios -lcdrun:descentr.exe -lcdbios -simuleyes

For running stereo modes with alternate SIMBIOS shell (SIMBIOS.EXE from ZIP):

	simbios -lcdrun:descentr.exe -lcdbios -simuleyes

For running stereo modes with SVRDOS32.DRV driver enabled (in EXE path):

	Descentr -simuleyes

For seeing stereo alternate-line interleaved format as is (without any page-flipping):

	Descentr -iglasses
 
Having SciTech UniVBE driver enabled turned out to be essential for SVRDOS32
driver for correct operation of low-res VESA modes. Running the default LCDBIOS
shell configuration worked OK without UniVBE active, since only VGA mode X is used.

## Stereo Code port for SVRDOS32:

The stereo rendering method improved by stereo expert Bob Akka is still intact in the
Descent 1.5 source. The stereo rendering methods are delegated to separate 
`game_render_frame_stereo_` routines due to the assortment of extra conditionals for
various stereo format options. Here is the simplified stereo rendering method with
SVRDOS32 enabled:

```
gr_set_current_canvas(&RenderCanvas[0]);
render_frame(-VR_eye_width);	// Left eye

gr_set_current_canvas(&RenderCanvas[1]);
render_frame(VR_eye_width);	// Right eye

int dx = (VR_eye_offset < 0) ? labs(VR_eye_offset) : 0;
SVRDos32SetImage(SVR_LEFT,  0, 0, dw-dx, dh, RenderCanvas[0].cv_bitmap.bm_data+dx);
SVRDos32SetImage(SVR_RIGHT,dx, 0, dw-dx, dh, RenderCanvas[1].cv_bitmap.bm_data);
SVRDos32ShowImages();
```

The basic stereo rendering algorithm remains intact using the parallel projection method.
Left/right stereo perspective separation is set by `VR_eye_width`, and stereo parallax
balance adjustment is set by `VR_eye_offset`. The resulting left/right image shift allows
changing the zero-parallax point for balancing “into-screen” versus “out-of-screen” 
depth effects. Without any image shift, the resulting left/right perspective separation
would yield only “into-screen” parallax, with appears less effective for depth perception.
