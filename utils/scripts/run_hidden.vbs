' Запускает указанный файл без окна.
' Использование: wscript.exe run_hidden.vbs "C:\path\file.bat"
Option Explicit

Dim sh, target, cmd
If WScript.Arguments.Count < 1 Then WScript.Quit 1

target = WScript.Arguments(0)
cmd = "cmd.exe /c """ & target & """"

Set sh = CreateObject("WScript.Shell")
sh.Run cmd, 0, False