' Starts the setup window (install.ps1 -Gui) without a console window.
' Install.bat runs this; arguments are passed on to install.ps1.
Set sh = CreateObject("WScript.Shell")
dir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
args = ""
For Each a In WScript.Arguments
    args = args & " """ & a & """"
Next
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & dir & "\install.ps1"" -Gui" & args, 0, False
