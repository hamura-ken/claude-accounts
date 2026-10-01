@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$d=[Environment]::GetFolderPath('Desktop'); $s=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $d 'Claude Accounts.lnk')); $s.TargetPath=\"$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe\"; $s.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0Claude-Accounts.ps1\"'; $s.WorkingDirectory='%~dp0'; $s.WindowStyle=7; $s.IconLocation='%~dp0claude-accounts.ico,0'; $s.Save(); Write-Host 'Shortcut created on Desktop: Claude Accounts'"
pause
