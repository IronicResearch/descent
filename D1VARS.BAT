@echo off
set TOOLDIR=c:\c\bin-win32
set MASMDIR=c:\c\masm611
set WATCOM=c:\c\wc10
set DESCENT=y:\Development\IronicResearch\descent
set PATH=%MASMDIR%\bin;%WATCOM%\binnt;%TOOLDIR%;%PATH%
set INCLUDE=%WATCOM%\h;%INCLUDE%;%DESCENT%\lib;%DESCENT%\includes;
set LIB=%WATCOM%\lib;%LIB%
