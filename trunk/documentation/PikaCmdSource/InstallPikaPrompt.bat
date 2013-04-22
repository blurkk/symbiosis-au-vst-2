@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

IF "%~1"=="" (
	ECHO.
	ECHO InstallPikaPrompt ^<target path^>
	ECHO.
	ECHO E.g. "InstallPikaPrompt C:\WINDOWS"
	EXIT /B 1
)
COPY PikaPrompt.cmd %1\
COPY PikaCmd.exe %1\
COPY systools.pika %1\
