' Headless launcher for Sloppy (no PowerShell console window).
Set Fso = CreateObject("Scripting.FileSystemObject")
AppRoot = Fso.GetParentFolderName(WScript.ScriptFullName)
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "pwsh -WindowStyle Hidden -STA -NoProfile -File """ & AppRoot & "\src\Slop.ps1""", 0, False
Set WshShell = Nothing
Set Fso = Nothing
