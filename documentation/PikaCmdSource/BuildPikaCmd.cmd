@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

IF NOT EXIST PikaCmd.exe (
	CALL :BuildCpp PikaCmd.exe -DPLATFORM_STRING=WINDOWS PikaCmdAmalgam.cpp
	IF ERRORLEVEL 1 EXIT /B 1
	ECHO Testing...
	IF EXIST unittests.pika (
		.\PikaCmd unittests.pika >NUL
		IF ERRORLEVEL 1 (
			ECHO Unit tests failed
			EXIT /B 1
		)
	)
	IF EXIST systoolsTests.pika (
		.\PikaCmd systoolsTests.pika
		IF ERRORLEVEL 1 (
			ECHO Systools tests failed
			EXIT /B 1
		)
	)
	ECHO Success
)

EXIT /B 0

:BuildCpp

IF "%~1"=="" (
	ECHO BuildCpp ^<output.exe^> ^<compiler options and source files^>
	EXIT /B 1
)

SET pfpath=%ProgramFiles(x86)%
SET temppath=%TEMP%\%~n1\
IF NOT DEFINED pfpath SET pfpath=%ProgramFiles%

IF NOT DEFINED VCINSTALLDIR (
	IF EXIST "%pfpath%\Microsoft Visual Studio 10.0\VC\vcvarsall.bat" (
		CALL "%pfpath%\Microsoft Visual Studio 10.0\VC\vcvarsall.bat" x86 >NUL
	) ELSE (
		IF EXIST "%pfpath%\Microsoft Visual Studio 9.0\VC\vcvarsall.bat" (
			CALL "%pfpath%\Microsoft Visual Studio 9.0\VC\vcvarsall.bat" >NUL
		) ELSE (
			ECHO Could not find Visual C++ in one of the standard paths.
			ECHO Manually run vcvarsall.bat first or run this batch from a Visual Studio command line.
			EXIT /B 1
		)
	)
)
	
MKDIR "%TEMP%\%~n1\" >NUL
ECHO Compiling %~1...
cl /nologo /W3 /WX- /Ox /GL /GF /Gm- /EHsc /MT /GS- /Gy /arch:SSE /fp:fast /Zc:wchar_t /Zc:forScope /GR- /Gd /wd"4355" /wd"4267" /analyze- /errorReport:queue /D "WIN32" /D "NDEBUG" /D "_CONSOLE" /D "_CRT_SECURE_NO_WARNINGS" /D "_SCL_SECURE_NO_WARNINGS" /Fo"%TEMP%\\%~n1\\" /Fe%* >"%TEMP%\buildlog.txt"
IF ERRORLEVEL 1 (
	TYPE %TEMP%\buildlog.txt
	ECHO Compilation of %~1 failed
	DEL /Q "%TEMP%\%~n1\*" >NUL
	RMDIR /Q "%TEMP%\%~n1\" >NUL
	EXIT /B 1
) ELSE (
	ECHO Compiled %~1
	DEL /Q "%TEMP%\%~n1\*" >NUL
	RMDIR /Q "%TEMP%\%~n1\" >NUL

	EXIT /B 0
)
