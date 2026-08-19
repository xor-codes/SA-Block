' SA-Block Widget silent launcher — starts the widget with NO console window.
' Keep this file in the same folder as SA-Block-Widget.ps1 and double-click it.
Option Explicit
Dim sh, fso, dir
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\SA-Block-Widget.ps1""", 0, False
