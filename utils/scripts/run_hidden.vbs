Option Explicit

Dim sh, fso, target, cmd
If WScript.Arguments.Count < 1 Then WScript.Quit 1

target = WScript.Arguments(0)
Set fso = CreateObject("Scripting.FileSystemObject")
If Not fso.FileExists(target) Then WScript.Quit 2

cmd = "cmd.exe /c """ & target & """"

Set sh = CreateObject("WScript.Shell")
sh.Run cmd, 0, False