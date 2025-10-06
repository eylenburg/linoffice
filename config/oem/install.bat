@echo off

echo %DATE% %TIME% Starting install.bat >> C:\OEM\setup.log

REM Apply system registry settings
echo %DATE% %TIME% Adding system-wide registry settings >> C:\OEM\setup.log
reg import %~dp0\registry\linoffice.reg

REM Apply default user registry settings
echo %DATE% %TIME% Applying default user registry settings >> C:\OEM\setup.log
reg load "HKU\DefaultUser" "C:\Users\Default\NTUSER.DAT" >> C:\OEM\setup.log 2>&1
reg import %~dp0\registry\regional_settings.reg >> C:\OEM\setup.log 2>&1
reg import %~dp0\registry\explorer_settings.reg >> C:\OEM\setup.log 2>&1
reg unload "HKU\DefaultUser" >> C:\OEM\setup.log 2>&1

REM Create network profile cleanup scheduled task
echo %DATE% %TIME% Scheduling NetProfileCleanup task >> C:\OEM\setup.log
copy %~dp0\NetProfileCleanup.ps1 %windir% >> C:\OEM\setup.log 2>&1
set "taskname=NetworkProfileCleanup"
set "command=powershell.exe -ExecutionPolicy Bypass -File \"%windir%\NetProfileCleanup.ps1\""

schtasks /query /tn "%taskname%" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo %DATE% %TIME% Task "%taskname%" already exists, skipping creation. >> C:\OEM\setup.log
) else (
    REM Try creating with SYSTEM account first
    schtasks /create /tn "%taskname%" /tr "%command%" /sc onstart /ru "SYSTEM" /rl HIGHEST /f >> C:\OEM\setup.log 2>&1
    if %ERRORLEVEL% equ 0 (
        echo %DATE% %TIME% Scheduled task "%taskname%" created successfully with SYSTEM account. >> C:\OEM\setup.log
    ) else (
        echo %DATE% %TIME% Failed to create task with SYSTEM account, trying without /ru parameter... >> C:\OEM\setup.log
        REM Retry without /ru SYSTEM parameter (uses current user context)
        schtasks /create /tn "%taskname%" /tr "%command%" /sc onstart /rl HIGHEST /f >> C:\OEM\setup.log 2>&1
        if %ERRORLEVEL% equ 0 (
            echo %DATE% %TIME% Scheduled task "%taskname%" created successfully with default account. >> C:\OEM\setup.log
        ) else (
            echo %DATE% %TIME% Failed to create scheduled task "%taskname%" with both SYSTEM and default account. >> C:\OEM\setup.log
        )
    )
)

REM Set time zone to UTC, disable automatic time zone updates, resync time with NTP server
echo %DATE% %TIME% Setting time to UTC >> C:\OEM\setup.log
tzutil /s "UTC"
sc config tzautoupdate start= disabled
sc stop tzautoupdate
net start w32time
w32tm /resync

REM Create time sync task to be run by the user at login
echo %DATE% %TIME% Scheduling time sync task >> C:\OEM\setup.log
copy %~dp0\TimeSync.ps1 %windir% >> C:\OEM\setup.log 2>&1
set "taskname2=TimeSync"
set "command2=powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File \"%windir%\TimeSync.ps1\""

schtasks /query /tn "%taskname2%" >nul
if %ERRORLEVEL% equ 0 (
    echo %DATE% %TIME% Task "%taskname2%" already exists, skipping creation. >> C:\OEM\setup.log
) else (
    schtasks /create /tn "%taskname2%" /tr "%command2%" /sc onlogon /rl HIGHEST /f >> C:\OEM\setup.log 2>&1
    REM Ensure the TimeSync task only runs once per boot and does not restart on every logon (RDP, etc.)
    powershell -Command "Set-ScheduledTask -TaskName 'TimeSync' -Settings (New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew)" >> C:\OEM\setup.log 2>&1
    if %ERRORLEVEL% equ 0 (
        echo %DATE% %TIME% Scheduled task "%taskname2%" created successfully. >> C:\OEM\setup.log
    ) else (
        echo %DATE% %TIME% Failed to create scheduled task %taskname2%. >> C:\OEM\setup.log
    )
)

REM Schedule a postsetup script for installing Office
echo %DATE% %TIME% Schedulding PostSetup script >> C:\OEM\setup.log
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v "InstallOffice" /t REG_SZ /d "powershell.exe -ExecutionPolicy Bypass -Command C:\OEM\InstallOffice.ps1" /f >> C:\OEM\setup.log 2>&1

REM Configure AutoLogon for the next reboot. This seems to be necessary for the RunOnce script, InstallOffice.ps1, to actually run.
echo %DATE% %TIME% Setting up AutoLogon >> C:\OEM\setup.log
reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "AutoAdminLogon" /t REG_SZ /d "1" /f >> C:\OEM\setup.log 2>&1
reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultUserName" /t REG_SZ /d "MyWindowsUser" /f >> C:\OEM\setup.log 2>&1
reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultPassword" /t REG_SZ /d "MyWindowsPassword" /f >> C:\OEM\setup.log 2>&1

REM Initiate a reboot. This seems to be necessary for the RunOnce script, InstallOffice.ps1, to actually run.
echo %DATE% %TIME% Initiating reboot at the end of install.bat >> C:\OEM\setup.log
shutdown /r /t 0

echo %DATE% %TIME% install.bat completed >> C:\OEM\setup.log
