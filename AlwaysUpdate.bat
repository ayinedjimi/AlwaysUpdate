@echo off & goto :init
:AlwaysUpdate v1.1 - Universal Windows Upgrade Tool
::===========================================================================
::  AlwaysUpdate v1.1 - Universal Windows Upgrade Tool
::  (c) 2026 Ayi NEDJIMI Consultants - https://ayinedjimi-consultants.fr
::  (c) 2026 Ayi NEDJIMI Consultants - Tous droits reserves
::
::  Upgrades ANY Windows 10/11 to latest Windows 11 bypassing ALL hw checks
::  Nothing but Microsoft-hosted source links - no third-party tools
::
::  Enhancements over original: pre-flight checks, logging, progress bar,
::  retry downloads, comprehensive hardware bypass,
::  24H2/25H2 support, full-auto mode, polished UI
::
::  Changelog:
::  2026.06.04 v1.1
::  - Full auto mode defaults to latest available version (currently 24H2)
::  - New catalog capture method: runs fwlink MCT briefly to obtain latest
::    products catalog from Microsoft, replacing unreliable binary extraction
::  - Download verification: reject 0-byte/incomplete downloads
::  - Evaluation edition detection with user warning
::  - Dynamic TargetReleaseVersionInfo in AutoUnattend.xml
::  - Improved logging throughout
::
::  2026.03.28 v1.0 stable
::  - Initial release with all improvements
::  - Uses 23H2 MCT (last without built-in TPM check) + products catalog
::  - Comprehensive hardware bypass (TPM, SecureBoot, CPU, RAM, Storage)
::  - Real-time progress bar with status tracking
::  - Pre-flight system checks (disk, network, PS, processes)
::  - Detailed logging to %SystemDrive%\ESD\AlwaysUpdate.log
::===========================================================================

::# ======================== USER CONFIGURATION ========================
:config
::# Uncomment to skip GUI dialog - or rename script: "24H2 AlwaysUpdate.bat"
rem set MCT=2510

::# Uncomment to start auto upgrade directly (no prompts) to latest version
::# Or rename script: "auto AlwaysUpdate.bat"
rem set /a AUTO=1

::# Uncomment to start create iso directly - or rename: "iso 24H2 AlwaysUpdate.bat"
rem set /a ISO=1

::# Uncomment to change autodetected MediaEdition
rem set EDITION=Enterprise

::# Uncomment to change autodetected MediaLangCode
rem set LANGCODE=en-US

::# Uncomment to change autodetected MediaArch
rem set ARCH=x64

::# Uncomment to change autodetected KEY
rem set KEY=NPPR9-FWDCX-D2C8J-H872K-2YT43

::# Uncomment to disable dynamic update for setup sources
rem set /a NO_UPDATE=1

::# Uncomment to create default untouched MCT media (no bypass, no mods)
rem set /a DEF=1

::# Recommended setup options for upgrades
set OPTIONS=%OPTIONS% /Compat IgnoreWarning /MigrateDrivers All /ResizeRecoveryPartition Disable /ShowOOBE None

::# Disable telemetry and Compact OS
set OPTIONS=%OPTIONS% /Telemetry Disable /CompactOS Disable

::# Unhide Enterprise editions in products.xml
set /a UNHIDE_BUSINESS=1

::# Insert Enterprise esd links for older versions
set /a INSERT_BUSINESS=1

::# Version choice items and default [* 11_24H2]
set VERSIONS=11_23H2,* 11_24H2,11_25H2
set /a dV=2

::# Preset choice items and default [Manual select]
set PRESETS=^&Full Auto Upgrade,^&Auto Upgrade,Create ^&ISO,Create ^&USB,^&Manual Select,MCT ^&Default
::# 23H2 MCT is used for all versions (last MCT without built-in TPM check)
::# For 24H2/25H2: catalog is captured by running the fwlink MCT briefly, then 23H2 MCT uses it
set /a dP=5

::# ======================== END USER CONFIG ========================

:begin
call :reg_query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" "CurrentBuildNumber"     OS_VERSION
call :reg_query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" "DisplayVersion"         OS_VID
call :reg_query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" "EditionID"              OS_EDITION
call :reg_query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" "ProductName"            OS_PRODUCT
call :reg_query "HKU\S-1-5-18\Control Panel\Desktop\MuiCached" "MachinePreferredUILanguages" OS_LANGCODE
for %%s in (%OS_LANGCODE%) do set "OS_LANGCODE=%%s"
set "OS_ARCH=x64" & if "%PROCESSOR_ARCHITECTURE:~-2%" equ "86" if not defined PROCESSOR_ARCHITEW6432 set "OS_ARCH=x86"

::# Language detection (FR or EN based on OS language)
set "LANG=EN"
echo;%OS_LANGCODE% | find /i "fr-" >nul 2>nul && set "LANG=FR"
echo;[%date% %time%] OS: %OS_PRODUCT% %OS_VID% Build %OS_VERSION% %OS_EDITION% %OS_ARCH% [%LANG%] >> "%LOGFILE%" 2>nul

::# parse MCT choice from script name or commandline
for %%V in (1.2310 1.11_23H2 2.2409 2.11_24H2 3.2510 3.11_25H2) do for %%s in (%MCT% %~n0 %*) do if /i %%~xV equ .%%~s set "MCT=%%~nV" & set "VID=%%~s"
if defined MCT if not defined VID set "MCT="

::# parse AUTO from script name or commandline
for %%s in (%~n0 %*) do if /i %%s equ auto set /a AUTO=1
if defined AUTO (set /a PRE=2 & if not defined MCT set /a MCT=%dV%)

::# parse FULLAUTO from script name - Full Auto Upgrade preset
for %%s in (%~n0 %*) do if /i %%s equ fullauto set /a FULLAUTO=1
if defined FULLAUTO (set /a AUTO=1& set /a PRE=1& set /a MCT=%dV%)

::# parse ISO from script name or commandline
for %%s in (%~n0 %*) do if /i %%s equ iso set /a ISO=1
if defined ISO (set /a PRE=3 & if defined AUTO set "AUTO=")

::# parse EDITION from script name or commandline
set _=%EDITION% %~n0 %*& rem also accepts alternative names
for %%s in (%_:Home=Core% %_:Pro =Professional % %_:ProN=ProfessionalN% %_:Edu =Education % %_:EduN=EducationN%) do (
for %%E in ( ProfessionalEducation ProfessionalEducationN ProfessionalWorkstation ProfessionalWorkstationN Cloud CloudN
 Core CoreN CoreSingleLanguage CoreCountrySpecific Professional ProfessionalN Education EducationN Enterprise EnterpriseN
) do if /i %%s equ %%E set "EDITION=%%E")

::# parse LANGCODE from script name or commandline
for %%s in (%~n0 %*) do set ".=%%~s" & for /f %%C in ('cmd /q /v:on /c echo;!.:~2^,1!') do if "%%C" equ "-" set "LANGCODE=%%s"

::# parse ARCH from script name or commandline
for %%s in (%~n0 %*) do for %%A in (x86 x64) do if /i %%s equ %%A set "ARCH=%%A"

::# parse KEY from script name or commandline
for %%s in (%KEY% %~n0 %*) do for /f "tokens=1-5 delims=-" %%A in ("%%s") do if "%%E" neq "" set "PKEY=%%s" & set "KEY="
if defined PKEY set "PKEY1=%PKEY:~-1%" & set "PKEY28=%PKEY:~28,1%"
if defined EDITION if "%PKEY1%" equ "%PKEY28%" (set "KEY=%PKEY%") else set "PKEY="

::# parse NO_UPDATE from script name or commandline
for %%s in (%~n0 %*) do if /i %%s equ no_update set "NO_UPDATE=1"
if defined NO_UPDATE (set OPTIONS=%OPTIONS% /DynamicUpdate Disable) else (set OPTIONS=%OPTIONS% /DynamicUpdate Enable)

::# parse DEF from script name or commandline
for %%s in (%~n0 %*) do if /i %%s equ def set "DEF=def"

::# hide option
set /a hide=2 & for %%s in (%~n0 %*) do if /i %%s equ hide set /a hide=1

::# auto detected / selected media preset
if defined EDITION (set MEDIA_EDITION=%EDITION%) else (set MEDIA_EDITION=%OS_EDITION%)
if defined LANGCODE (set MEDIA_LANGCODE=%LANGCODE%) else (set MEDIA_LANGCODE=%OS_LANGCODE%)
if defined ARCH (set MEDIA_ARCH=%ARCH%) else (set MEDIA_ARCH=%OS_ARCH%)
if not defined VID (set VID=%OS_VID%)

::# edition fallback to ones that MCT supports (IoTEnterpriseS before IoTEnterprise)
::# warn about Eval editions (licensing restrictions may prevent upgrade)
echo;%OS_EDITION% | find /i "Eval" >nul 2>nul && (
  echo;[%date% %time%] WARN: Evaluation edition detected: %OS_EDITION% >> "%LOGFILE%" 2>nul
  if "%LANG%"=="FR" (
    %<%:4f " [AVIS] Edition Evaluation detectee: %OS_EDITION% "%>%
    %<%:3f "        La mise a niveau peut echouer ou produire une installation non activee "%>%
  ) else (
    %<%:4f " [NOTE] Evaluation edition detected: %OS_EDITION% "%>%
    %<%:3f "        Upgrade may fail or produce an unlicensed installation "%>%
  )
  echo;
)
(set MEDIA_EDITION=%MEDIA_EDITION:Eval=%)
(set MEDIA_EDITION=%MEDIA_EDITION:Embedded=Enterprise%)
(set MEDIA_EDITION=%MEDIA_EDITION:IoTEnterpriseS=Enterprise%)
(set MEDIA_EDITION=%MEDIA_EDITION:IoTEnterprise=Enterprise%)
(set MEDIA_EDITION=%MEDIA_EDITION:EnterpriseS=Enterprise%)

::# get previous GUI selection if self elevated
for %%s in (%*) do for %%P in (1 2 3 4 5 6) do if %%~ns gtr 0 if %%~ns lss 4 if %%~xs. equ .%%P. (set /a PRE=%%P & set /a MCT=%%~ns)

::# write auto media preset hint
%<%:f0 " Detected System "%>>% & if defined MCT %<%:5f " %VID% "%>>%
%<%:6f " %MEDIA_LANGCODE% "%>>%  &  %<%:9f " %MEDIA_EDITION% "%>>%  &  %<%:2f " %MEDIA_ARCH% "%>%
echo;
if "%LANG%"=="FR" (
%<%:1f " 1  Full Auto         Mise a niveau vers la derniere version - SANS INTERACTION    "%>%
%<%:1f " 2  Mise a niveau     Upgrade assistee vers la version selectionnee                "%>%
%<%:1f " 3  Creer ISO         Telecharge et cree un fichier ISO dans C:\ESD                "%>%
%<%:1f " 4  Creer USB         Telecharge et cree une cle USB bootable                     "%>%
%<%:1f " 5  Selection manuelle   Choix libre de l'edition, langue et architecture          "%>%
%<%:1f " 6  MCT par defaut    Lance le Media Creation Tool sans modification               "%>%
echo;
%<%:17 " Bypass complet : TPM, SecureBoot, CPU, RAM, Stockage                             "%>%
%<%:17 " Renommer en "%>>% & %<%:1f "def AlwaysUpdate.bat"%>>% & %<%:17 " pour un media sans modification             "%>%
) else (
%<%:1f " 1  Full Auto         Upgrade to latest Windows 11 version - NO PROMPTS            "%>%
%<%:1f " 2  Auto Upgrade      Assisted upgrade to selected version                        "%>%
%<%:1f " 3  Create ISO        Download and create ISO file in C:\ESD                       "%>%
%<%:1f " 4  Create USB        Download and create bootable USB drive                      "%>%
%<%:1f " 5  Manual Select     Choose edition, language and architecture                   "%>%
%<%:1f " 6  MCT Default       Run Media Creation Tool without modifications               "%>%
echo;
%<%:17 " Full hardware bypass: TPM, SecureBoot, CPU, RAM, Storage                         "%>%
%<%:17 " Rename to "%>>% & %<%:1f "def AlwaysUpdate.bat"%>>% & %<%:17 " to create unmodified media                    "%>%
)

::# show pseudo-menu dialog
if "%MCT%%PRE%"=="" call :choices2 MCT "%VERSIONS%" %dV% "AlwaysUpdate - Version" PRE "%PRESETS%" %dP% "AlwaysUpdate - Preset" 11 white 0x3d0000 320
if %MCT%0 lss 1 if %PRE%0 gtr 1 call :choices MCT "%VERSIONS%" %dV% "AlwaysUpdate - Version" 11 white 0x3d0000 320
if %MCT%0 gtr 1 if %PRE%0 lss 1 call :choices PRE "%PRESETS%"  %dP% "AlwaysUpdate - Preset"  11 white 0x3d0000 320
if %MCT%0 gtr 1 if %PRE%0 lss 1 goto choice-0 = cancel
goto choice-%MCT%

::# ----------- VERSION DEFINITIONS (23H2, *24H2, 25H2) -----------
::# 23H2 MCT EXE is used for ALL versions (last MCT without built-in TPM check)
::# For 24H2/25H2: catalog captured by running fwlink MCT briefly, then 23H2 MCT uses it

:choice-3
set "VER=26200" & set "VID=11_25H2" & set "CB=26200.1000.250315-1200.25h2_release" & set "CT=2026/03/" & set "CC=2.0"
set "FWLINK_MCT=https://go.microsoft.com/fwlink/?linkid=2156295"
set "EXE=https://download.microsoft.com/download/e/c/d/ecd532eb-bed0-465a-9b7a-330066bec3ce/MediaCreationTool_Win11_23H2.exe"
goto process

:choice-2
set "VER=26100" & set "VID=11_24H2" & set "CB=26100.1742.240906-0331.24h2_release_svc_refresh" & set "CT=2025/10/" & set "CC=2.0"
set "FWLINK_MCT=https://go.microsoft.com/fwlink/?linkid=2156295"
set "EXE=https://download.microsoft.com/download/e/c/d/ecd532eb-bed0-465a-9b7a-330066bec3ce/MediaCreationTool_Win11_23H2.exe"
goto process

:choice-1
set "VER=22631" & set "VID=11_23H2" & set "CB=22631.2861.231204-0538.23H2_ni_release_svc_refresh" & set "CT=2023/12/" & set "CC=2.0"
set "CAB=https://download.microsoft.com/download/6/2/b/62b47bc5-1b28-4bfa-9422-e7a098d326d4/products_win11_20231208.cab"
set "EXE=https://download.microsoft.com/download/e/c/d/ecd532eb-bed0-465a-9b7a-330066bec3ce/MediaCreationTool_Win11_23H2.exe"
goto process

:choice-
set /a MCT=%dv% & set /a PRE=%dP% & goto choice-%dV%

:choice-0
%<%:0c " CANCELED "%>% & timeout /t 3 >nul & exit /b

::# ======================== CONSOLE INIT ========================
:init
@echo off& title AlwaysUpdate v1.1& set __COMPAT_LAYER=Installer& chcp 437 >nul& set set=& for %%s in (%*) do if /i %%s equ set (set set=1)
if not defined set set /a BackClr=0x1 & set /a TextClr=0xf & set /a Columns=32 & set /a Lines=120 & set /a Buff=9999
if not defined set set /a SColors=BackClr*16+TextClr & set /a WSize=Columns*256*256+Lines & set /a BSize=Buff*256*256+Lines
if not defined set for %%s in ("HKCU\Console\AlwaysUpdate") do (
 reg add HKCU\Console /v ForceV2 /d 0x01 /t reg_dword /f & reg add %%s /v ScreenColors /d %SColors% /t reg_dword /f
 reg add %%s /v ColorTable00 /d 0x000000 /t reg_dword /f & reg add %%s /v ColorTable08 /d 0x767676 /t reg_dword /f
 reg add %%s /v ColorTable01 /d 0x00003d /t reg_dword /f & reg add %%s /v ColorTable09 /d 0x4444ff /t reg_dword /f
 reg add %%s /v ColorTable02 /d 0x0066cc /t reg_dword /f & reg add %%s /v ColorTable10 /d 0x33aaff /t reg_dword /f
 reg add %%s /v ColorTable03 /d 0x0088dd /t reg_dword /f & reg add %%s /v ColorTable11 /d 0x44ccff /t reg_dword /f
 reg add %%s /v ColorTable04 /d 0x0000ee /t reg_dword /f & reg add %%s /v ColorTable12 /d 0x3333ff /t reg_dword /f
 reg add %%s /v ColorTable05 /d 0x220088 /t reg_dword /f & reg add %%s /v ColorTable13 /d 0x4400cc /t reg_dword /f
 reg add %%s /v ColorTable06 /d 0x3333cc /t reg_dword /f & reg add %%s /v ColorTable14 /d 0x9999ff /t reg_dword /f
 reg add %%s /v ColorTable07 /d 0xcccccc /t reg_dword /f & reg add %%s /v ColorTable15 /d 0xffffff /t reg_dword /f
 reg add %%s /v QuickEdit      /d 0x0000 /t reg_dword /f & reg add %%s /v LineWrap /d 0 /t reg_dword /f
 reg add %%s /v LineSelection  /d 0x0001 /t reg_dword /f & reg add %%s /v CtrlKeyShortcutsDisabled /d 0 /t reg_dword /f
 reg add %%s /v WindowSize    /d %WSize% /t reg_dword /f & reg add %%s /v ScreenBufferSize /d %BSize% /t reg_dword /f
 reg add %%s /v FontSize   /d 0x00100008 /t reg_dword /f & reg add %%s /v FaceName /d "Consolas" /t reg_sz /f ) >nul 2>nul
pushd "%~dp0" & set "S=%SystemRoot%" & set "nx0=%~nx0" & call set "nx0=%%nx0:)=]%%" & call set "nx0=%%nx0:(=[%%"
set "PATH=%S%\Sysnative;%S%\Sysnative\windowspowershell\v1.0\;%S%\System32;%S%\System32\windowspowershell\v1.0\;%PATH%"
set "WORK=%SystemDrive%\ESD" & if not defined ROOT (set "ROOT=%CD%") else if not exist "%ROOT%\*.bat" set "ROOT=%CD%"
set "LOGFILE=%SystemDrive%\ESD\AlwaysUpdate.log"
mkdir "%WORK%" >nul 2>nul & attrib -R -S -H "%WORK%" >nul 2>nul & copy /y "%~f0" "%WORK%\%~nx0" >nul 2>nul
if "%~nx0" neq "%nx0%" copy /y "%WORK%\%~nx0" "%WORK%\%nx0%" >nul & del /f /q "%WORK%\%~nx0" >nul
if not exist "%WORK%\%nx0%" (echo;FATAL: Cannot copy script to %WORK% - check disk space or permissions & pause & exit /b 1)
if not defined set start "AlwaysUpdate" cmd /d /x /c set "ROOT=%ROOT%" ^& call "%WORK%\%nx0%" %* set& exit /b
::# display banner
prompt $G & echo;
echo;  ================================================================
echo;  ^|                                                              ^|
echo;  ^|     #####  #      #   #  #####  #   #  ####                 ^|
echo;  ^|     #   #  #      #   #  #   #  #   #  #                    ^|
echo;  ^|     #####  #      # # #  #####   # #   ####                 ^|
echo;  ^|     #   #  #      ## ##  #   #    #       #                 ^|
echo;  ^|     #   #  #####  #   #  #   #    #    ####                 ^|
echo;  ^|                                                              ^|
echo;  ^|          U P D A T E   v 1 . 0                               ^|
echo;  ^|                                                              ^|
echo;  ^|  Universal Windows Upgrade Tool                              ^|
echo;  ^|  Full bypass: TPM, SecureBoot, CPU, RAM, Storage            ^|
echo;  ^|                                                              ^|
echo;  ^|  (c) 2026 Ayi NEDJIMI Consultants                           ^|
echo;  ^|  https://ayinedjimi-consultants.fr                           ^|
echo;  ^|                                                              ^|
echo;  ================================================================
echo;
::# lean xp+ color macros
for /f "delims=:" %%s in ('echo;prompt $h$s$h:^|cmd /d') do set "|=%%s"&set ">>=\..\c nul&set /p s=%%s%%s%%s%%s%%s%%s%%s<nul&popd"
set "<=pushd "%WORK%"&2>nul findstr /c:\ /a" &set ">=%>>%&echo;" &set "|=%|:~0,1%" &set /p s=\<nul>"%WORK%\c"
::# init log
echo;[%date% %time%] === AlwaysUpdate v1.1 Started === >> "%LOGFILE%" 2>nul
::# undefine main variables
for %%s in (OPTIONS MCT XML CAB EXE VID PRE AUTO FULLAUTO ISO EDITION KEY ARCH LANGCODE NO_UPDATE DEF AKEY FWLINK_MCT) do set "%%s="
for %%s in (latest_AlwaysUpdate.url) do if not exist %%s (echo;[InternetShortcut]&echo;URL=https://ayinedjimi-consultants.fr)>%%s
goto config

::# ======================== REGISTRY QUERY UTILITY ========================
:reg_query [USAGE] call :reg_query "HKCU\Volatile Environment" Value variable
(for /f "tokens=2*" %%R in ('reg query "%~1" /v "%~2" /se "," 2^>nul') do set "%~3=%%S")& exit /b

::# ======================== PRE-FLIGHT CHECKS ========================
:preflight
echo;[%date% %time%] Running pre-flight checks... >> "%LOGFILE%"
set /a PREFLIGHT_OK=1

::# Check 1: Admin rights
fltmc >nul 2>nul
if %errorlevel% neq 0 (
  %<%:4f " [WARN] "%>>% & %<%:0f " Not running as Administrator - will self-elevate "%>%
  echo;[%date% %time%] WARN: Not admin, will self-elevate >> "%LOGFILE%"
)

::# Check 2: Disk space on system drive (need at least 12GB)
set "FREE_GB=0"
for /f "tokens=*" %%a in ('powershell -nop -ep bypass -c "try{$d=(Get-PSDrive $env:SystemDrive[0]).Free/1GB;[math]::Floor($d)}catch{0}"') do set "FREE_GB=%%a"
if %FREE_GB%0 lss 120 (
  %<%:4f " [FAIL] "%>>% & %<%:0f " Insufficient disk space: %FREE_GB% GB free, need 12 GB minimum "%>%
  echo;[%date% %time%] FAIL: Only %FREE_GB% GB free disk space >> "%LOGFILE%"
  set /a PREFLIGHT_OK=0
) else (
  %<%:2f " [ OK ] "%>>% & %<%:0f " Disk space: %FREE_GB% GB free "%>%
  echo;[%date% %time%] OK: %FREE_GB% GB free disk space >> "%LOGFILE%"
)

::# Check 3: Disk space on TEMP drive (need at least 8GB)
set "TEMP_GB=0"
for /f "tokens=*" %%a in ('powershell -nop -ep bypass -c "try{$t=[io.path]::GetTempPath();$d=(Get-PSDrive ($t[0])).Free/1GB;[math]::Floor($d)}catch{0}"') do set "TEMP_GB=%%a"
if %TEMP_GB%0 lss 80 (
  %<%:3f " [WARN] "%>>% & %<%:0f " TEMP drive low: %TEMP_GB% GB free, 8 GB recommended "%>%
  echo;[%date% %time%] WARN: TEMP drive only %TEMP_GB% GB free >> "%LOGFILE%"
) else (
  %<%:2f " [ OK ] "%>>% & %<%:0f " TEMP drive: %TEMP_GB% GB free "%>%
  echo;[%date% %time%] OK: TEMP drive %TEMP_GB% GB free >> "%LOGFILE%"
)

::# Check 4: Internet connectivity
ping -n 1 -w 3000 download.microsoft.com >nul 2>nul
if %errorlevel% neq 0 (
  %<%:4f " [FAIL] "%>>% & %<%:0f " Cannot reach download.microsoft.com - check internet "%>%
  echo;[%date% %time%] FAIL: No internet connectivity >> "%LOGFILE%"
  set /a PREFLIGHT_OK=0
) else (
  %<%:2f " [ OK ] "%>>% & %<%:0f " Internet connectivity verified "%>%
  echo;[%date% %time%] OK: Internet reachable >> "%LOGFILE%"
)

::# Check 5: PowerShell version and execution policy
set "PS_VER=0"
for /f "tokens=*" %%a in ('powershell -nop -ep bypass -c "$PSVersionTable.PSVersion.Major"') do set "PS_VER=%%a"
if %PS_VER%0 lss 30 (
  %<%:3f " [WARN] "%>>% & %<%:0f " PowerShell %PS_VER% detected, v3+ recommended "%>%
  echo;[%date% %time%] WARN: PowerShell v%PS_VER% (v3+ recommended) >> "%LOGFILE%"
) else (
  %<%:2f " [ OK ] "%>>% & %<%:0f " PowerShell v%PS_VER% "%>%
  echo;[%date% %time%] OK: PowerShell v%PS_VER% >> "%LOGFILE%"
)

::# Check 6: No conflicting processes
set "CONFLICT="
for %%p in (SetupHost.exe SetupPrep.exe) do tasklist /fi "imagename eq %%p" 2>nul | find /i "%%p" >nul && set "CONFLICT=%%p"
tasklist 2>nul | find /i "MediaCreationTool" >nul && set "CONFLICT=MediaCreationTool"
if defined CONFLICT (
  %<%:4f " [WARN] "%>>% & %<%:0f " %CONFLICT% is already running - may cause conflicts "%>%
  echo;[%date% %time%] WARN: %CONFLICT% already running >> "%LOGFILE%"
) else (
  %<%:2f " [ OK ] "%>>% & %<%:0f " No conflicting processes "%>%
  echo;[%date% %time%] OK: No conflicting processes >> "%LOGFILE%"
)

::# Check 7: Pending reboot
set "REBOOT_PENDING=0"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>nul && set "REBOOT_PENDING=1"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>nul && set "REBOOT_PENDING=1"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>nul && set "REBOOT_PENDING=1"
if %REBOOT_PENDING% equ 1 (
  %<%:4f " [WARN] "%>>% & %<%:0f " System reboot pending - upgrade may fail, reboot first "%>%
  echo;[%date% %time%] WARN: Reboot pending >> "%LOGFILE%"
) else (
  %<%:2f " [ OK ] "%>>% & %<%:0f " No pending reboot "%>%
  echo;[%date% %time%] OK: No pending reboot >> "%LOGFILE%"
)

::# Check 8: Battery check for laptops
set "ON_BATTERY=0"
for /f "tokens=*" %%a in ('powershell -nop -ep bypass -c "try{$b=(Get-WmiObject Win32_Battery -ea 0);if($b -and $b.BatteryStatus -eq 1){'1'}else{'0'}}catch{'0'}"') do set "ON_BATTERY=%%a"
if %ON_BATTERY% equ 1 (
  %<%:4f " [WARN] "%>>% & %<%:0f " Running on battery - plug in AC power before upgrading "%>%
  echo;[%date% %time%] WARN: Running on battery >> "%LOGFILE%"
) else (
  %<%:2f " [ OK ] "%>>% & %<%:0f " Power supply OK "%>%
  echo;[%date% %time%] OK: Power supply OK >> "%LOGFILE%"
)

echo;
if %PREFLIGHT_OK% equ 0 (
  %<%:4f " Pre-flight checks FAILED "%>>% & %<%:0f " Fix issues above before continuing "%>%
  echo;[%date% %time%] Pre-flight checks FAILED >> "%LOGFILE%"
  echo;& pause & exit /b 1
)
%<%:2f " Pre-flight checks PASSED "%>%
echo;[%date% %time%] Pre-flight checks PASSED >> "%LOGFILE%"
echo;
exit /b 0

::# ======================== PREPARE SYSTEM ========================
::# Active fixes: stops conflicting services, removes upgrade blocks, enables TLS
::# Called AFTER elevation, BEFORE MCT download
:prepare_system
echo;
%<%:5f " Preparing system for upgrade... "%>%
echo;[%date% %time%] Preparing system... >> "%LOGFILE%"

::# Fix 1: Enable and start BITS service (required for downloads)
sc query BITS | find /i "RUNNING" >nul 2>nul
if %errorlevel% neq 0 (
  sc config BITS start= demand >nul 2>nul
  net start BITS >nul 2>nul
  %<%:6f " [FIX ] "%>>% & %<%:0f " BITS service started "%>%
  echo;[%date% %time%] FIX: BITS service started >> "%LOGFILE%"
) else (
  %<%:2f " [ OK ] "%>>% & %<%:0f " BITS service running "%>%
)

::# Fix 2: Stop Windows Update service (prevents conflicts during upgrade)
net stop wuauserv >nul 2>nul
net stop cryptSvc >nul 2>nul
net stop msiserver >nul 2>nul
%<%:6f " [FIX ] "%>>% & %<%:0f " Windows Update services stopped "%>%
echo;[%date% %time%] FIX: Stopped wuauserv, cryptSvc, msiserver >> "%LOGFILE%"

::# Fix 3: Disable WaaSMedicSvc (Windows Update Medic - auto-restarts WU on 1903+)
if %OS_VERSION%0 geq 183620 (
  sc stop WaaSMedicSvc >nul 2>nul
  sc config WaaSMedicSvc start= disabled >nul 2>nul
  rem Also disable via registry - more reliable than sc on some builds
  reg add "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v Start /t reg_dword /d 4 /f >nul 2>nul
  %<%:6f " [FIX ] "%>>% & %<%:0f " WaaSMedicSvc (Update Medic) disabled "%>%
  echo;[%date% %time%] FIX: WaaSMedicSvc disabled >> "%LOGFILE%"
)

::# Fix 4: Remove WSUS redirection (allow direct Microsoft downloads)
set "WSUS_WAS_SET=0"
reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v WUServer >nul 2>nul && set "WSUS_WAS_SET=1"
if %WSUS_WAS_SET% equ 1 (
  reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v UseWUServer /t reg_dword /d 0 /f >nul 2>nul
  net stop wuauserv >nul 2>nul & net start wuauserv >nul 2>nul & net stop wuauserv >nul 2>nul
  %<%:6f " [FIX ] "%>>% & %<%:0f " WSUS bypassed (UseWUServer=0) - will restore after "%>%
  echo;[%date% %time%] FIX: WSUS bypassed >> "%LOGFILE%"
) else (
  %<%:2f " [ OK ] "%>>% & %<%:0f " No WSUS configured "%>%
)

::# Fix 5: Remove Group Policy upgrade blocks
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v TargetReleaseVersion /f >nul 2>nul
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v TargetReleaseVersionInfo /f >nul 2>nul
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DisableOSUpgrade /f >nul 2>nul
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\OSUpgrade" /v AllowOSUpgrade /f >nul 2>nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v DisableWUfBSafeguards /t reg_dword /d 1 /f >nul 2>nul
%<%:6f " [FIX ] "%>>% & %<%:0f " Group Policy upgrade blocks removed "%>%
echo;[%date% %time%] FIX: GP upgrade blocks removed >> "%LOGFILE%"

::# Fix 6: Enable TLS 1.2 system-wide for .NET (required on 1507-1607 for HTTPS downloads)
reg add "HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto /t reg_dword /d 1 /f >nul 2>nul
reg add "HKLM\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto /t reg_dword /d 1 /f >nul 2>nul
reg add "HKLM\SOFTWARE\Microsoft\.NETFramework\v2.0.50727" /v SystemDefaultTlsVersions /t reg_dword /d 1 /f >nul 2>nul
reg add "HKLM\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v2.0.50727" /v SystemDefaultTlsVersions /t reg_dword /d 1 /f >nul 2>nul
%<%:6f " [FIX ] "%>>% & %<%:0f " TLS 1.2 enabled system-wide (.NET) "%>%
echo;[%date% %time%] FIX: TLS 1.2 enabled system-wide >> "%LOGFILE%"

::# Fix 7: Clean old Appraiser data (prevents stale compat blocks)
if exist "%SystemRoot%\appcompat\appraiser\*.sdb" (
  del /f /q "%SystemRoot%\appcompat\appraiser\*.sdb" >nul 2>nul
  %<%:6f " [FIX ] "%>>% & %<%:0f " Old Appraiser compatibility data cleaned "%>%
  echo;[%date% %time%] FIX: Appraiser data cleaned >> "%LOGFILE%"
) else (
  %<%:2f " [ OK ] "%>>% & %<%:0f " No stale Appraiser data "%>%
)

::# Fix 8: Clear pending reboot flags (so setup will start)
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" /f >nul 2>nul
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress" /f >nul 2>nul
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" /f >nul 2>nul
%<%:6f " [FIX ] "%>>% & %<%:0f " Pending reboot flags cleared "%>%
echo;[%date% %time%] FIX: Reboot pending flags cleared >> "%LOGFILE%"

::# Fix 9: Add Defender exclusion for work directory
powershell -nop -ep bypass -c "try{Add-MpPreference -ExclusionPath '%WORK%' -ea 0}catch{}" >nul 2>nul
%<%:6f " [FIX ] "%>>% & %<%:0f " Defender exclusion added for %WORK% "%>%
echo;[%date% %time%] FIX: Defender exclusion for %WORK% >> "%LOGFILE%"

echo;
%<%:2f " System preparation complete "%>%
echo;[%date% %time%] System preparation complete >> "%LOGFILE%"
echo;
exit /b 0

::# ======================== PROCESS ========================
:process
call :preflight
if %errorlevel% neq 0 exit /b 1
if %PRE%0 lss 1 goto choice-0

if %PRE% equ 1 (set "PRESET=Full Auto Upgrade" & set /a AUTO=1)
if %PRE% equ 2 (set "PRESET=Auto Upgrade")
if %PRE% equ 3 (set "PRESET=Auto ISO")
if %PRE% equ 4 (set "PRESET=Auto USB")
if %PRE% equ 5 (set "PRESET=Select"       & set EDITION=& set LANGCODE=& set ARCH=& set KEY=)
if %PRE% equ 6 (set "PRESET=MCT Defaults" & set EDITION=& set LANGCODE=& set ARCH=& set KEY=)
if %PRE% equ 6 (goto noelevate_lp) else set set=%MCT%.%PRE%

fltmc>nul||(set A=/d /x /c set "ROOT=%ROOT%"^& start "AlwaysUpdate" "%~f0" %* %set%& powershell -nop -ep bypass -c start -verb runas cmd $env:A;&exit)
:noelevate_lp

::# Prepare system (stop WU, fix WSUS, enable TLS, clean appraiser, etc.)
call :prepare_system

::# Apply hardware bypass for ALL versions (not just Win11)
reg add "HKLM\SYSTEM\Setup\LabConfig" /f /v BypassTPMCheck /d 1 /t reg_dword >nul 2>nul
reg add "HKLM\SYSTEM\Setup\LabConfig" /f /v BypassSecureBootCheck /d 1 /t reg_dword >nul 2>nul
reg add "HKLM\SYSTEM\Setup\LabConfig" /f /v BypassCPUCheck /d 1 /t reg_dword >nul 2>nul
reg add "HKLM\SYSTEM\Setup\LabConfig" /f /v BypassRAMCheck /d 1 /t reg_dword >nul 2>nul
reg add "HKLM\SYSTEM\Setup\LabConfig" /f /v BypassStorageCheck /d 1 /t reg_dword >nul 2>nul
reg add "HKLM\SYSTEM\Setup\MoSetup" /f /v AllowUpgradesWithUnsupportedTPMorCPU /d 1 /t reg_dword >nul 2>nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /f /v DisableWUfBSafeguards /d 1 /t reg_dword >nul 2>nul

mkdir "%WORK%\MCT" >nul 2>nul & attrib -R -S -H "%WORK%" /D
pushd "%WORK%\MCT" || (echo;FATAL: Cannot access %WORK%\MCT & pause & exit /b 1)
del /f /q products.* *.key EI.cfg PID.txt auto.cmd AutoUnattend.xml >nul 2>nul
set /a latest=0 & if exist latest set /p latest=<latest
echo;20260328>latest & if %latest% lss 20211116 del /f /q products*.* MediaCreationTool*.exe >nul 2>nul

::# edition fallback (IoTEnterpriseS must come before IoTEnterprise to avoid partial match)
(set MEDIA_EDITION=%MEDIA_EDITION:Eval=%)
(set MEDIA_EDITION=%MEDIA_EDITION:Embedded=Enterprise%)
(set MEDIA_EDITION=%MEDIA_EDITION:IoTEnterpriseS=Enterprise%)
(set MEDIA_EDITION=%MEDIA_EDITION:IoTEnterprise=Enterprise%)
(set MEDIA_EDITION=%MEDIA_EDITION:EnterpriseS=Enterprise%)
if %VER% leq 16299 (set MEDIA_EDITION=%MEDIA_EDITION:ProfessionalWorkstation=Enterprise%)
if %VER% leq 16299 (set MEDIA_EDITION=%MEDIA_EDITION:ProfessionalEducation=Education%)
if %VER% leq 10586 (set MEDIA_EDITION=%MEDIA_EDITION:Enterprise=Professional%)
if %VER% leq 15063 if %INSERT_BUSINESS%0 lss 1 (set MEDIA_EDITION=%MEDIA_EDITION:Enterprise=Professional%)
if %VER% leq 10586 if %UNHIDE_BUSINESS%0 lss 1 (set MEDIA_EDITION=%MEDIA_EDITION:Education=Professional%)
if %VER% neq 15063 (set MEDIA_EDITION=%MEDIA_EDITION:Cloud=Professional%)

::# generic key preset
for %%s in (%MEDIA_EDITION%) do for %%K in (
  V3WVW-N2PV2-CGWC3-34QGF-VMJ2C.Cloud                     NH9J3-68WK7-6FB93-4K3DF-DJ4F6.CloudN
  YTMG3-N6DKC-DKB77-7M9GH-8HVX7.Core                      4CPRK-NM3K3-X6XXQ-RXX86-WXCHW.CoreN
  BT79Q-G7N6G-PGBYW-4YWX6-6F4BT.CoreSingleLanguage        N2434-X9D7W-8PF6X-8DV9T-8TYMD.CoreCountrySpecific
  VK7JG-NPHTM-C97JM-9MPGT-3V66T.Professional              2B87N-8KFHP-DKV6R-Y2C8J-PKCKT.ProfessionalN
  8PTT6-RNW4C-6V7J2-C2D3X-MHBPB.ProfessionalEducation     GJTYN-HDMQY-FRR76-HVGC7-QPF8P.ProfessionalEducationN
  DXG7C-N36C4-C4HTG-X4T3X-2YV77.ProfessionalWorkstation   WYPNQ-8C467-V2W6J-TX4WX-WT2RQ.ProfessionalWorkstationN
  YNMGQ-8RYV3-4PGQ3-C8XTP-7CFBY.Education                 84NGF-MHBT6-FXBX8-QWJK7-DRR8H.EducationN
  NPPR9-FWDCX-D2C8J-H872K-2YT43.Enterprise                DPH2V-TTNVB-4X9Q3-TJR4H-KHJW4.EnterpriseN
) do if /i %%~xK equ .%%s set MEDIA_EDITION=%%~xK& call set MEDIA_EDITION=%%MEDIA_EDITION:.=%%& set "MEDIA_KEY=%%~nK"

::# detected / selected media preset
if defined EDITION (set EDITION=%MEDIA_EDITION%)
if "%MEDIA_EDITION%" neq "%OS_EDITION%" (set REG_EDITION=%MEDIA_EDITION%) else (set "REG_EDITION=")
set "CONSUMER=%MEDIA_EDITION:Enterprise=%"
if "%CONSUMER%" equ "%MEDIA_EDITION%" (set CFG=Consumer) else (set CFG=Business)
if not defined EDITION (set UNSTAGED=1& set STAGED=) else (set UNSTAGED=& set STAGED=%MEDIA_EDITION%)
if defined STAGED (set MEDIA_CFG=%STAGED%) else (set MEDIA_CFG=%CFG%)
set MEDIA=& for %%s in (%LANGCODE%%EDITION%%ARCH%%KEY%) do (set MEDIA=%%s)
if defined MEDIA for %%s in (%MEDIA_LANGCODE%) do (set LANGCODE=%%s)
if defined MEDIA for %%s in (%MEDIA_EDITION%) do (set EDITION=%%s)
if defined MEDIA for %%s in (%MEDIA_ARCH%) do (set ARCH=%%s)
if defined MEDIA for %%s in (%MEDIA_KEY%) do (if not defined KEY set KEY=%%s)
if %VER% geq 22000 (set MEDIA_ARCH=x64& if defined ARCH set ARCH=x64)

::# labels
if %VER% geq 22000 (set X=11& set VIS=21H2) else (set X=10& set VIS=%VID%)
if %VER% geq 22621 (set X=11& set VIS=22H2)
if %VER% geq 22631 (set X=11& set VIS=23H2)
if %VER% geq 26100 (set X=11& set VIS=24H2)
if %VER% geq 26200 (set X=11& set VIS=25H2)

::# refresh screen with banner
cls
echo;
echo;  ===========================================================================
echo;  AlwaysUpdate v1.1 - (c) 2026 Ayi NEDJIMI Consultants
echo;  https://ayinedjimi-consultants.fr
echo;  ===========================================================================
echo;
%<%:f0 " Windows %X% Version "%>>% & %<%:5f " %VIS% "%>>%  &  %<%:f1 " %CB% "%>>%
if %PRE% leq 4 %<%:6f " %MEDIA_LANGCODE% "%>>%  &  %<%:9f " %MEDIA_CFG% "%>>%  &  %<%:2f " %MEDIA_ARCH% "%>%
echo;

::# diagnostic info for troubleshooting
echo;[%date% %time%] --- Diagnostic --- >> "%LOGFILE%"
echo;[%date% %time%] Script: %~f0 >> "%LOGFILE%"
echo;[%date% %time%] WorkDir: %CD% >> "%LOGFILE%"
echo;[%date% %time%] PRESET=%PRESET% VER=%VER% VID=%VID% VIS=%VIS% >> "%LOGFILE%"
echo;[%date% %time%] EXE=%EXE% >> "%LOGFILE%"
echo;[%date% %time%] CAB=%CAB% FWLINK_MCT=%FWLINK_MCT% >> "%LOGFILE%"
echo;[%date% %time%] Edition=%MEDIA_EDITION% Lang=%MEDIA_LANGCODE% Arch=%MEDIA_ARCH% >> "%LOGFILE%"
%<%:8f " Preset: %PRESET% "%>>% & %<%:8f " Target: Windows %X% %VIS% "%>%
echo;
if "%LANG%"=="FR" (
  %<%:8f " Script : %~f0 "%>%
  %<%:8f " Dossier: %CD% "%>%
) else (
  %<%:8f " Script : %~f0 "%>%
  %<%:8f " WorkDir: %CD% "%>%
)
echo;

::# verify critical functions exist in script
set "DIAG_OK=1"
findstr /b /c:":DOWNLOAD" "%~f0" >nul 2>nul || (
  %<%:4f " [ERREUR] Label :DOWNLOAD manquant dans le script "%>%
  echo;[%date% %time%] FATAL: :DOWNLOAD label missing >> "%LOGFILE%"
  set "DIAG_OK=0"
)
findstr /b /c:":PRODUCTS_XML" "%~f0" >nul 2>nul || (
  %<%:4f " [ERREUR] Label :PRODUCTS_XML manquant dans le script "%>%
  echo;[%date% %time%] FATAL: :PRODUCTS_XML label missing >> "%LOGFILE%"
  set "DIAG_OK=0"
)
if "%DIAG_OK%"=="0" (
  %<%:4f " Script corrompu - retelecharger depuis GitHub "%>%
  echo;& pause & exit /b 1
)

::# verify PowerShell can execute embedded functions
powershell -nop -ep bypass -c "exit 0" >nul 2>nul
if %errorlevel% neq 0 (
  %<%:4f " [ERREUR] PowerShell ne peut pas executer de scripts "%>%
  echo;[%date% %time%] FATAL: PowerShell execution blocked >> "%LOGFILE%"
  echo;& pause & exit /b 1
)

::# download MCT and CAB/XML with progress
%<%:6f " Downloading components... "%>%
echo;[%date% %time%] Downloading MCT and product catalog >> "%LOGFILE%"
if defined EXE echo;%EXE% & call :DOWNLOAD "%EXE%" MediaCreationTool%VID%.exe
if defined XML echo;%XML% & call :DOWNLOAD "%XML%" products%VID%.xml
if defined CAB echo;%CAB% & call :DOWNLOAD "%CAB%" products%VID%.cab

::# For 24H2/25H2: obtain products catalog by running fwlink MCT briefly
::# The fwlink MCT downloads the latest catalog from Microsoft on startup,
::# before any hardware checks. We capture it and kill the MCT.
set "FALLBACK_CAB=https://download.microsoft.com/download/6/2/b/62b47bc5-1b28-4bfa-9422-e7a098d326d4/products_win11_20231208.cab"
if defined FWLINK_MCT if not defined CAB (
  %<%:6f " Obtaining latest products catalog from Microsoft... "%>%
  echo;[%date% %time%] Downloading fwlink MCT to obtain catalog >> "%LOGFILE%"
  call :DOWNLOAD "%FWLINK_MCT%" MCT_fwlink.exe
  if exist MCT_fwlink.exe (
    set "0=%~f0"& powershell -nop -ep bypass -c "iex ([io.file]::ReadAllText($env:0) -split '[:]capture_products_catalog')[1];"
    del /f /q MCT_fwlink.exe >nul 2>nul
  )
  if exist products.xml (
    %<%:2f " Products catalog obtained successfully "%>%
    echo;[%date% %time%] Products catalog captured from fwlink MCT >> "%LOGFILE%"
  ) else (
    if "%LANG%"=="FR" (
      %<%:3f " [WARN] "%>>% & %<%:0f " Catalogue non obtenu - fallback sur le catalogue 23H2 "%>%
    ) else (
      %<%:3f " [WARN] "%>>% & %<%:0f " Catalog not obtained - falling back to 23H2 catalog "%>%
    )
    echo;[%date% %time%] WARN: Catalog capture failed, using 23H2 fallback >> "%LOGFILE%"
    call :DOWNLOAD "%FALLBACK_CAB%" products%VID%.cab
  )
)

if exist products%VID%.xml copy /y products%VID%.xml products.xml >nul 2>nul
if exist products%VID%.cab del /f /q products%VID%.xml >nul 2>nul
if exist products%VID%.cab (
  expand.exe -R products%VID%.cab -F:* . >nul 2>nul
  if not exist products.xml echo;[%date% %time%] WARN: CAB expand failed, trying cabextract >> "%LOGFILE%" & extrac32 /Y /E products%VID%.cab >nul 2>nul
)
set "/hint=Check urls in browser | del ESD dir | use powershell v3.0+ | unblock powershell | enable BITS serv"
echo;& set err=& for %%s in (products.xml MediaCreationTool%VID%.exe) do if not exist %%s set err=1
if defined err (%<%:4f " ERROR "%>>% & %<%:0f " %/hint% "%>%) else if not defined err %<%:2f " Downloads complete "%>%
if defined err (
  echo;[%date% %time%] ERROR: Download failed >> "%LOGFILE%"
  del /f /q products%VID%.* MediaCreationTool%VID%.exe 2>nul & pause & exit /b 1
)
echo;[%date% %time%] Downloads complete >> "%LOGFILE%"

::# configure products.xml
set "XML_SIZE_BEFORE=0"
for %%f in (products.xml) do set "XML_SIZE_BEFORE=%%~zf"
call :PRODUCTS_XML
for %%f in (products.xml) do if %%~zf lss 100 (
  echo;[%date% %time%] WARN: products.xml mangled by PRODUCTS_XML, restoring >> "%LOGFILE%"
  %<%:3f " [WARN] "%>>% & %<%:0f " products.xml config failed, using original "%>%
  if exist products%VID%.cab expand.exe -R products%VID%.cab -F:* . >nul 2>nul
)

::# repack XML into CAB
makecab products.xml products.cab >nul

::# MCT Defaults - just launch and quit
if "MCT Defaults" equ "%PRESET%" (start MediaCreationTool%VID%.exe /Selfhost& exit /b)

::# setup options
if defined EDITION (set EDITION_SWITCH=%EDITION%) else (set EDITION_SWITCH=)
if not defined MEDIA (set LANGCODE=%MEDIA_LANGCODE%& set EDITION=%MEDIA_EDITION%& set ARCH=%MEDIA_ARCH%)
if defined UNSTAGED (set KEY=)

if %VER% gtr 15063 (set MEDIA_SEL=/MediaLangCode %LANGCODE% /MediaEdition %EDITION% /MediaArch %ARCH%) else (set MEDIA_SEL=)
if "Select" equ "%PRESET%" (set MEDIA_SEL=)

set MOPTIONS=/Action CreateMedia %MEDIA_SEL% /Pkey Defer %OPTIONS% /SkipSummary /Eula Accept
set AOPTIONS=/Auto Upgrade /MigChoice Upgrade %OPTIONS% /SkipSummary /Eula Accept
set MAKE_OPTIONS=/SelfHost& for %%s in (%MOPTIONS%) do call set MAKE_OPTIONS=%%MAKE_OPTIONS%% %%s
set AUTO_OPTIONS=/SelfHost& for %%s in (%AOPTIONS%) do call set AUTO_OPTIONS=%%AUTO_OPTIONS%% %%s

::# generate PID.txt
for %%s in (Workstation WorkstationN Education EducationN) do if "Professional%%s" equ "%EDITION%" set "KEY="
if not defined PKEY if "Enterprise" equ "%EDITION%" set "KEY="
if not defined KEY (del /f /q PID.txt 2>nul) else (echo;[PID]& echo;Value=%KEY%& echo;;Edition=%EDITION%)>PID.txt

::# generate EI.cfg
if not defined KEY if %VER% geq 22000 (echo;[Channel]& echo;_Default)>EI.cfg

::# generate auto.cmd
set "0=%~f0"& powershell -nop -ep bypass -c "iex ([io.file]::ReadAllText($env:0) -split '[:]generate_auto_cmd')[1];"
if not exist auto.cmd (
  echo;[%date% %time%] WARN: auto.cmd generation failed >> "%LOGFILE%"
  %<%:3f " [WARN] "%>>% & %<%:0f " auto.cmd not generated - PowerShell may be broken "%>%
)

::# generate AutoUnattend.xml
set "0=%~f0"& powershell -nop -ep bypass -c "iex ([io.file]::ReadAllText($env:0) -split '[:]generate_AutoUnattend_xml')[1];"

::# cleanup stale
dism /cleanup-wim >nul 2>nul

::# start Assisted MCT
echo;
%<%:5f " Starting Media Creation Tool with progress tracking... "%>%
echo;[%date% %time%] Starting Assisted MCT >> "%LOGFILE%"
set "0=%~f0" & powershell -nop -ep bypass -c "iex ([io.file]::ReadAllText($env:0) -split '[:]Assisted_MCT')[1];"
if %errorlevel% neq 0 (
  echo;[%date% %time%] ERROR: Assisted MCT returned error %errorlevel% >> "%LOGFILE%"
  %<%:4f " ERROR "%>>% & %<%:0f " MCT process failed. Check %LOGFILE% for details "%>%
)
if not defined DEF if %hide% neq 1 pause >nul

EXIT

::# ======================== ASSISTED MCT (PowerShell) ========================
::--------------------------------------------------------------------------------------------------------------------------------
:Assisted_MCT
#:: AlwaysUpdate v1.1 - Enhanced Assisted MCT with progress bar
 $host.ui.rawui.windowtitle = "AlwaysUpdate v1.1 - $env:PRESET $env:X $env:DEF"; $ErrorActionPreference = 0
 [io.path]::GetTempPath(),$env:TEMP,$env:TMP |% { if ($env:ROOT -like "*$_*") {$env:ROOT=$env:WORK} }
 $DRIVE = [environment]::SystemDirectory[0]; $WD = $DRIVE+':\ESD'; $WS = $DRIVE+':\$WINDOWS.~WS\Sources'; $DIR = $WS+'\Windows'
 $ESD = $null; $USB = $null; $ISO = "$env:ROOT\$env:X $env:VIS $env:MEDIA_CFG $env:MEDIA_ARCH $env:MEDIA_LANGCODE.iso"
 $LOGFILE = $env:LOGFILE
 if ('Auto Upgrade' -eq $env:PRESET -or 'Full Auto Upgrade' -eq $env:PRESET) {$ISO = [io.path]::GetTempPath() + "~temporary.iso"}
 del $ISO -force -ea 0 >$null
 if (test-path $ISO) {write-host " ERROR! " -fore Red -nonew; write-host "$ISO is read-only or in use`r`n"; sleep 5; return}
 cd -Lit("$env:WORK\MCT")

#:: Progress bar function
 $script:lastLoggedPct = -1
 function Show-ProgressBar ($pct, $status, $color = 'Cyan') {
   $pct = [math]::Max(0, [math]::Min(100, $pct))
   $width = 50; $filled = [math]::Floor($pct * $width / 100); $empty = $width - $filled
   $bar = '#' * $filled + '-' * $empty
   $line = ("`r  [$bar] {0,3}% - $status" -f $pct).PadRight(120)
   write-host -nonew -fore $color $line
   Write-Progress -Activity "AlwaysUpdate v1.1" -Status $status -PercentComplete $pct
   if ($pct -ne $script:lastLoggedPct) {
     Add-Content $LOGFILE "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] Progress: $pct% - $status"
     $script:lastLoggedPct = $pct
   }
 }

 Show-ProgressBar 5 "Initializing..."

#:: workaround for version 1703 and earlier
 if ($env:VER -le 15063 -and $null -ne $env:REG_EDITION) {
   $K = '"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion"'; $E = $env:REG_EDITION
   cmd /d /x /c "(reg add $K /v EditionID /d $E /reg:32 /f & reg delete $K /v ProductName /reg:32 /f) >nul 2>nul"
   cmd /d /x /c "(reg add $K /v EditionID /d $E /reg:64 /f & reg delete $K /v ProductName /reg:64 /f) >nul 2>nul"
 }

#:: setup file watcher
 function Watcher {
   $A = $args; $Exe = $A[0]; $File = $A[1]; $Folder = $A[2]; $Subdirs = @($false,$true)[$A[3] -eq 'all']
   $P = mkdir $Folder -force -ea 0; if (!(test-path $P)) {return 1}; $W = new-object IO.FileSystemWatcher; $W.Path = $P.FullName
   $W.Filter = $File; $W.IncludeSubdirectories = $Subdirs; $W.NotifyFilter = 125; $W.EnableRaisingEvents = $true; $ret = 1
   while ($true) {
     try { $get = $W.WaitForChanged(15, 15000) } catch { mkdir $Folder -ea 0 >$null; continue }
     if (-not $get.TimedOut) { write-host -fore Gray $get.ChangeType,$get.Name; $ret = 0;break} else {if ($Exe.HasExited) {break}}
   } ; $W.Dispose(); return $ret
 }

#:: load ui automation
 Show-ProgressBar 8 "Loading UI automation..."
 $an = 'UIAutomationClientsideProviders','UIAutomationClient','UIAutomationTypes','System.Windows.Forms','Microsoft.VisualBasic'
 $ca = { [Windows.Automation.ClientSettings]::RegisterClientSideProviderAssembly($re[0].GetName()) }
 $re = $an |% { [Reflection.Assembly]::LoadWithPartialName("$_") } ; try { & $ca } catch { & $ca }
 $cp = [Windows.Automation.AutomationElement]::ClassNameProperty
 $bt = "Button","ComboBox","Edit" |% {new-object Windows.Automation.PropertyCondition($cp, $_)}
 $null = new-item -path function: -name "Enter" -value { $app = get-process "SetupHost" -ea 0
 if ($null -ne $app) {[Microsoft.VisualBasic.Interaction]::AppActivate($app.Id)}; [Windows.Forms.SendKeys]::SendWait("{ENTER}") }
 $id = 0; if ('Auto USB' -ne $env:PRESET) {$id = 1}
 $sw = "ShowWindowAsync"; $dm = [AppDomain]::CurrentDomain."DefineDynami`cAssembly"(1,1)."DefineDynami`cModule"(1)
 $dt = $dm."Defin`eType"("AlwaysUpdate",1179913,[ValueType]); $ptr = (get-process -pid $PID).MainWindowHandle.gettype()
 $dt."DefinePInvok`eMethod"($sw,"user`32",8214,1,[void],@($ptr,[int]),1,4) >$null; $nt = $dt."Creat`eType"()
 new-item -path function: -name "ShowWindow" -value {$nt."G`etMethod"($sw).invoke(0,@($args[0],$args[1]))} >$null

 Show-ProgressBar 10 "Launching Media Creation Tool..."

#:: start monitoring
 :mct while ($true) {
   $set = get-process SetupHost -ea 0; if ($set) {$set.Kill()}
   $mct = start -passthru "$env:WORK\MCT\MediaCreationTool${env:VID}.exe" $env:MAKE_OPTIONS; if ($null -eq $mct) {break :mct}
   while ($null -eq (get-process SetupHost -ea 0)) {if ($mct.HasExited) {break :mct}; sleep -m 200 }
   $set = get-process SetupHost -ea 0; if ($null -eq $set) {break :mct}
   while ($set.MainWindowHandle -eq 0) { if ($mct.HasExited) {break :mct}; $set.Refresh(); sleep -m 200 }

   Show-ProgressBar 15 "MCT GUI loaded, configuring..."

  #:: automate GUI
   if ('Select' -ne $env:PRESET) { try {
     $win = [Windows.Automation.AutomationElement]::FromHandle($set.MainWindowHandle); $nr = $win.FindAll(5, $bt[0]).Count
     if ($env:VER -le 15063) {while ($win.FindAll(5,$bt[1]).Count -lt 3) {if ($mct.HasExited) {break :mct}; sleep -m 200}; Enter}
     while ($win.FindAll(5,$bt[0]).Count -le $nr) {if ($mct.HasExited) {break :mct}; sleep -m 200}; $all = $win.FindAll(5,$bt[0])
     $all[$id].GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select();$all[$all.Count-1].SetFocus(); Enter
     if ('Auto USB' -ne $env:PRESET) {
       while ($win.FindAll(5,$bt[2]).Count -le 0) {if ($mct.HasExited) {break :mct};sleep -m 50}; $val = $win.FindAll(5,$bt[2])[0]
       [Windows.Forms.SendKeys]::SendWait(" "); $val.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue($ISO)
       [Windows.Forms.SendKeys]::Flush(); $b = $win.FindAll(5, $bt[0]); ($b |? {$_.Current.AutomationId -eq 1}).SetFocus(); Enter
     }
   } catch {} }

   Show-ProgressBar 20 "MCT configured, preparing download..."

   if ($null -ne $env:DEF -and 'Auto Upgrade' -ne $env:PRESET -and 'Full Auto Upgrade' -ne $env:PRESET) {break :mct}

  #:: get target from state file (timeout: 10 min)
   $ready = $false; $task = "PreDownload"; $action = "GetWebSetupUserInput"; $timeout = [datetime]::Now.AddMinutes(10)
   while (-not $ready) {
     if ([datetime]::Now -gt $timeout) {write-host "`n TIMEOUT waiting for MCT state" -fore Red; break :mct}
     try {[xml]$xml = get-content "$WS\Panther\windlp.state.xml" -ea Stop} catch {sleep -m 2000; continue}
     foreach ($t in $xml.WINDLP.TASK) { if ($t.Name -eq $task) { foreach ($a in $t.ACTION) { if ($a.ActionName -eq $action) {
       if ($null -ne $a.DownloadUrlX86) {$ESD = $a.DownloadUrlX86}
       if ($null -ne $a.DownloadUrlX64) {$ESD = $a.DownloadUrlX64}
       if ($null -ne $a.TargetISO) {$ISO = $a.TargetISO; $ready = $true}
       $u = $a.TargetUsbDrive; if ($null -ne $u -and $u -gt 0) {$USB = [char][Convert]::ToInt32($u, 16) + ":"; $ready = $true}
     }}}} ; if ($mct.HasExited) {break :mct}; sleep -m 1000
   }

   if ($mct.HasExited) {break :mct}
   if ('Auto Upgrade' -ne $env:PRESET -and 'Full Auto Upgrade' -ne $env:PRESET -and $null -eq $USB) {write-host "`n"; Show-ProgressBar 25 "Target: $ISO"}
   if ('Auto Upgrade' -ne $env:PRESET -and 'Full Auto Upgrade' -ne $env:PRESET -and $null -ne $USB) {write-host "`n"; Show-ProgressBar 25 "Target: $USB"}
   if ('Auto Upgrade' -eq $env:PRESET -or 'Full Auto Upgrade' -eq $env:PRESET) {write-host "`n"; Show-ProgressBar 25 "Preparing upgrade media..."}
   $label = "${env:X}_${env:VIS}" + ($ESD -split '(?=_client)')[1]
   $label = $label -replace '_clientconsumer','' -replace '_clientbusiness','' -replace 'fre_','_' -replace '.esd',''
   sleep 10; powershell -win $env:hide -nop -c ";"
   if ($mct.HasExited) {break :mct}

  #:: watch ESD download with progress
   write-host "`n"
   Show-ProgressBar 30 "Downloading Windows ESD image..."
   Add-Content $LOGFILE "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] ESD download started"
   Watcher $mct "*.esd" $WD all >$null; if ($mct.HasExited) {break :mct}

   Show-ProgressBar 60 "Creating installation media..."
   Add-Content $LOGFILE "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] Media creation started"
   Watcher $mct "*.wim" $WS all >$null; if ($mct.HasExited) {break :mct}

  #:: add to media: EI.cfg, PID.txt, auto.cmd, $ISO$ dir
   if ($null -eq $env:DEF) {
     Show-ProgressBar 70 "Adding bypass files to media..."
     pushd -lit "$env:ROOT"
     $f1 = '$ISO$'; if (test-path $f1) {xcopy /CYBERHIQ $f1 "$DIR" >$null; write-host -fore Gray "`nAddDirs $f1"} ; popd
     pushd -lit "$env:WORK"
     if (-not (test-path "$DIR\auto.cmd")) {
       $f2 = "MCT\auto.cmd"; if (test-path $f2) {copy -path $f2 -dest $DIR -force >$null; write-host -fore Gray "AddFile $f2"}
     }
     foreach ($P in "$DIR\x86\sources","$DIR\x64\sources","$DIR\sources") {
       if (!(test-path "$P\setupprep.exe")) {continue}
       if (-not (test-path "$DIR\EI.cfg") -and ($ESD -like '*_ret_*')) {
         $f3 = "MCT\EI.cfg"; if (test-path $f3) {copy -path $f3 -dest $P -force >$null; write-host -fore Gray "AddFile $f3"}
       }
       if (-not (test-path "$DIR\PID.txt")) {
         $f4 = "MCT\PID.txt"; if (test-path $f4) {copy -path $f4 -dest $P -force >$null; write-host -fore Gray "AddFile $f4"}
       }
     } ; popd
   }

  #:: watch media layout with realistic progress
   Show-ProgressBar 75 "Converting install.esd..."
   $ready = $false; $task = "MediaCreate"; $action = "Layout"; $timeout2 = [datetime]::Now.AddMinutes(60)
   while (-not $ready) {
     if ([datetime]::Now -gt $timeout2) {write-host "`n TIMEOUT waiting for media layout" -fore Red; break :mct}
     try {[xml]$xml = get-content "$WS\Panther\windlp.state.xml" -ea Stop} catch {sleep -m 5000; continue}
     foreach ($t in $xml.WINDLP.TASK) { if ($t.Name -eq $task) { foreach ($a in $t.ACTION) { if ($a.ActionName -eq $action) {
       $total = $a.ProgressTotal; $current = $a.ProgressCurrent
       if ($null -ne $total -and 0 -ne $total -and $total -eq $current) {$ready = $true}
       try {if ($null -ne $current -and 0 -ne $current) {$done = [Convert]::ToInt64($current, 16)} else {$done = 0}} catch {$done = 0}
       $rpct = 75 + [math]::Floor($done * 10 / 100)
       if ($rpct -gt 85) {$rpct = 85}
       Show-ProgressBar $rpct "Converting install.esd ($done%)..."
     }}}} ; if ($mct.HasExited) {break :mct}; sleep -m 10000
   }
   $action = "IsoLayout"; if ($null -ne $USB) {$action = "UsbLayout"}
   Show-ProgressBar 85 "Layout: $action..."

  #:: watch usb layout progress
   if ($null -ne $USB) {
     $ready = $false; $task = "MediaCreate"; $action = "UsbLayout"; $size = 0; $almost = 0; $foreground = 0
     while (-not $ready) {
       sleep -m 5000; if ($mct.HasExited) {break :mct}
       try {[xml]$xml = get-content "$WS\Panther\windlp.state.xml" -ea Stop} catch {continue}
       foreach ($t in $xml.WINDLP.TASK) { if ($t.Name -eq $task) { foreach ($a in $t.ACTION) { if ($a.ActionName -eq $action) {
         $total = $a.ProgressTotal; $current = $a.ProgressCurrent
         if ($null -ne $total -and 0 -ne $total -and $total -eq $current) {$ready = $true}
         try {if ($size -eq 0) {$size = [Math]::Ceiling([Convert]::ToInt64($total, 16)/1048576); $almost = $size * 0.8}
         $done = [Math]::Ceiling([Convert]::ToInt64($current, 16)/1048576)} catch {$done = 0}
         if ($foreground -eq 0 -and $done -gt $almost) {
           $set = get-process SetupHost -ea 0; $SetupHost = $set.MainWindowHandle; powershell -win 0 -nop -c ";"
           ShowWindow $SetupHost 0; ShowWindow (get-process -Id $PID).MainWindowHandle 1; $foreground = 1
         }
         if ($size -gt 0) {$wpct = 85 + [math]::Floor($done * 10 / $size)} else {$wpct = 85}
         if ($wpct -gt 95) {$wpct = 95}
         Show-ProgressBar $wpct "Writing USB: ${done}/${size} MB..."
       }}}}
     }
   }

  #:: kill MCT before temporary iso finish (for Win11 or Auto Upgrade)
   if ($env:VER -ge 22000 -or 'Auto Upgrade' -eq $env:PRESET -or 'Full Auto Upgrade' -eq $env:PRESET) {
     $mct.Kill(); $s = get-process SetupPrep,SetupHost -ea 0; if ($s) { foreach ($setup in $s) {$setup.Kill()} }
     powershell -win 0 -nop -c ";"; ShowWindow (get-process -Id $PID).MainWindowHandle 1
     sleep 3; cmd /d /x /c "dism /cleanup-wim >nul 2>nul"; del $ISO -force -ea 0 >$null
   }

   break :mct
 }

#:: undo registry workaround for 1703-
 if ($env:VER -le 15063 -and $null -ne $env:REG_EDITION) {
   $K = '"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion"'; $E = $env:OS_EDITION; $P = $env:OS_PRODUCT
   cmd /d /x /c "(reg add $K /v EditionID /d $E /reg:32 /f & reg add $K /v ProductName /d $P /reg:32 /f) >nul 2>nul"
   cmd /d /x /c "(reg add $K /v EditionID /d $E /reg:64 /f & reg add $K /v ProductName /d $P /reg:64 /f) >nul 2>nul"
 }

#:: error check
 if (-not (test-path "$DIR\sources\ws.dat")) {
   if ((get-process SetupHost -ea 0) -and $null -ne $env:DEF) {return}
   powershell -win 0 -nop -c ";"; ShowWindow (get-process -Id $PID).MainWindowHandle 1
   pushd -lit "$env:WORK"; cmd /d /x /c "pushd c:\ & rmdir /s /q ""$DIR"" >nul 2>nul & del /f /q ""$WS\*.*"" >nul 2>nul"
   write-host "`n ERROR! " -fore Red -nonew; write-host "setup terminated unexpectedly"
   Add-Content $LOGFILE "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] ERROR: setup terminated unexpectedly"
   write-host " Check log at: $LOGFILE`r`n"; sleep 7; return
 }

 Show-ProgressBar 90 "Applying hardware bypass to media..."

#:: skip 11 upgrade checks: 0-byte appraiserres.dll
 if ($env:VER -ge 22000) {
   cmd /d /x /c "cd.>""$DIR\sources\appraiserres.dll"""
   Add-Content $LOGFILE "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] Applied appraiserres.dll bypass"
 }

#:: Auto Upgrade / Full Auto Upgrade
 if ('Auto Upgrade' -eq $env:PRESET -or 'Full Auto Upgrade' -eq $env:PRESET) {
   Show-ProgressBar 92 "Starting auto upgrade..."
   cd -Lit("$env:WORK\MCT"); cmd /d /x /c "call ""$env:WORK\MCT\auto.cmd"" ""$DIR"""; sleep 7; return
 }

#:: skip win11 upgrade checks in boot.wim
 if ($env:VER -ge 22000 -and (test-path "$DIR\sources\boot.wim")) {
   Show-ProgressBar 92 "Patching boot.wim for hardware bypass..."
   Add-Content $LOGFILE "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] Patching boot.wim"
   rmdir "$WD\MOUNT" -re -force -ea 0; mkdir "$WD\MOUNT" -force -ea 0 >$null; $winsetup = "$WD\MOUNT\sources\winsetup.dll"
   dism.exe /mount-wim /wimfile:"$DIR\sources\boot.wim" /index:2 /mountdir:"$WD\MOUNT"; write-host
   if (-not (test-path "$DIR\AutoUnattend.xml")) {
     $f5 = "$env:WORK\MCT\AutoUnattend.xml"
     if (test-path $f5) {write-host importing file: $f5; copy -path $f5 -dest "$WD\MOUNT" -force >$null}
   }
   try { takeown.exe /f $winsetup /a >$null; icacls.exe $winsetup /grant *S-1-5-32-544:f; attrib -R -S $winsetup
     $patch = '/commit'; [io.file]::OpenWrite($winsetup).close() } catch {$patch = '/discard'}
   if ($patch -eq '/commit') {
     $b = [io.file]::ReadAllBytes($winsetup); $h = [BitConverter]::ToString($b) -replace '-'
     $s = [BitConverter]::ToString([Text.Encoding]::Unicode.GetBytes('Module_Init_HWRequirements')) -replace '-'
     $i = ($h.IndexOf($s)/2); $r = [Text.Encoding]::Unicode.GetBytes('Module_Init_GatherDiskInfo'); $l = $r.Length
     if ($i -gt 1) {for ($k=0;$k -lt $l;$k++) {$b[$i+$k] = $r[$k]}; [io.file]::WriteAllBytes($winsetup,$b)}; [GC]::Collect()
     Add-Content $LOGFILE "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] winsetup.dll patched successfully"
   }
   dism.exe /unmount-wim /mountdir:"$WD\MOUNT" $patch; rmdir "$WD\MOUNT" -re -force -ea 0

   Show-ProgressBar 95 "Finalizing media..."

   if ($null -ne $USB) {
     write-host -fore Yellow "`nRefresh USB $USB"
     replace "$DIR\sources\boot.wim" "$USB\sources" /r /u
   } else {
     write-host -fore Yellow "`nCreating ISO..."
     iex ([io.file]::ReadAllText($env:0) -split '#\:MakeISO\:' ,3)[1]
     MakeISO $DIR $ISO $label
   }
   pushd -lit "$env:WORK"; try {start -wait "$DIR\sources\setupprep.exe" "/cleanup"} catch {}
   cmd /d /x /c "pushd c:\ & rmdir /s /q ""$DIR"" >nul 2>nul & del /f /q ""$WS\*.*"" >nul 2>nul"
 }

 Show-ProgressBar 100 "COMPLETE!"
 write-host -fore Green "`r`n`n DONE! " -nonew
 write-host "AlwaysUpdate v1.1 - Operation completed successfully"
 write-host " Log saved to: $LOGFILE"
 write-host " (c) 2026 Ayi NEDJIMI Consultants - https://ayinedjimi-consultants.fr`r`n"
 Add-Content $LOGFILE "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] === AlwaysUpdate completed successfully ==="
 Write-Progress -Activity "AlwaysUpdate v1.1" -Completed
 sleep 7; return
#:: done #:Assisted_MCT

::--------------------------------------------------------------------------------------------------------------------------------
:generate_auto_cmd $text = @"
@echo off& title AlwaysUpdate - Auto Upgrade  ||  supports Ultimate / PosReady / Embedded / LTSC / Enterprise Eval
::  (c) 2026 Ayi NEDJIMI Consultants - https://ayinedjimi-consultants.fr
set "EDITION_SWITCH=$env:EDITION_SWITCH"
set "SKIP_11_SETUP_CHECKS=$((0,1)[$null -eq $env:DEF])"
set OPTIONS=$env:AUTO_OPTIONS`r`n`r`n
"@ + @'
pushd "%~dp0" & for %%w in (%1) do pushd %%w
for %%i in ("x86\" "x64\" "") do if exist "%%~isources\setupprep.exe" set "dir=%%~i"
pushd "%dir%sources" || (echo "%dir%sources" not found! script should be run from windows setup media & timeout /t 5 & exit /b)

::# start sources\setup if under winpe
reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion\WinPE">nul 2>nul && (
 for %%s in (sCPU sRAM sSecureBoot sStorage sTPM) do reg add HKLM\SYSTEM\Setup\LabConfig /f /v Bypas%%sCheck /d 1 /t reg_dword
 start "WinPE" sources\setup.exe & exit /b
)

setlocal EnableDelayedExpansion
set "PATH=%SystemRoot%\System32;%SystemRoot%\System32\windowspowershell\v1.0\;%PATH%"
set "PATH=%SystemRoot%\Sysnative;%SystemRoot%\Sysnative\windowspowershell\v1.0\;%PATH%"

::# elevate
fltmc >nul || (set _="%~f0" %*& powershell -nop -ep bypass -c start -verb runas cmd \"/d /x /c call $env:_\"& exit /b)

::# undo any previous regedit edition rename
set "NT=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
for %%v in (CompositionEditionID EditionID ProductName) do (
 call :reg_query "%NT%" %%v_undo %%v
 if defined %%v reg delete "%NT%" /v %%v_undo /f & for %%A in (32 64) do reg add "%NT%" /v %%v /d "!%%v!" /f /reg:%%A
) >nul 2>nul

::# get current version
for %%v in (CompositionEditionID EditionID ProductName CurrentBuildNumber) do call :reg_query "%NT%" %%v %%v
for /f "tokens=2-3 delims=[." %%i in ('ver') do for %%s in (%%i) do set /a Version=%%s*10+%%j

::# Apply ALL hardware bypass registry keys
for %%s in (sCPU sRAM sSecureBoot sStorage sTPM) do reg add "HKLM\SYSTEM\Setup\LabConfig" /f /v Bypas%%sCheck /d 1 /t reg_dword >nul 2>nul
reg add "HKLM\SYSTEM\Setup\MoSetup" /f /v AllowUpgradesWithUnsupportedTPMorCPU /d 1 /t reg_dword >nul 2>nul

::# WIM_INFO
set "0=%~f0"& set wim=& set ext=.esd& if exist install.wim (set ext=.wim) else if exist install.swm set ext=.swm
set snippet=powershell -nop -ep bypass -c iex ([io.file]::ReadAllText($env:0)-split'#[:]wim_info[:]')[1]; WIM_INFO install%ext% 0 0
set w_count=0& for /f "tokens=1-7 delims=," %%i in ('"%snippet%"') do (set w_%%i=%%i,%%j,%%k,%%l,%%m,%%n,%%o& set /a w_count+=1
set b_%%i=%%j& set p_%%i=%%k& set a_%%i=%%l& set l_%%i=%%m& set e_%%i=%%n& set d_%%i=%%o& set i_%%n=%%i& set i_%%i=%%n)

echo;------------------------------------------------------------------------------------
for /l %%i in (1,1,%w_count%) do call echo;%%w_%%i%%
echo;------------------------------------------------------------------------------------

::# get requested edition
if exist product.ini for /f "tokens=1,2 delims==" %%O in (product.ini) do if not "%%P" equ "" (set pid_%%O=%%P& set pn_%%P=%%O)
set EI=& set Name=& set eID=& set reg=& set "cfg_filter=EditionID Channel OEM Retail Volume _Default VL 0 1 ^$"
if exist EI.cfg for /f "tokens=*" %%i in ('findstr /v /i /r "%cfg_filter%" EI.cfg') do (set EI=%%i& set eID=%%i)
if exist PID.txt for /f "delims=;" %%i in (PID.txt) do set %%i 2>nul
if not defined Value for %%s in (%OPTIONS%) do if defined pn_%%s (set Name=!pn_%%s!& set Name=!Name:gvlk=!)
if defined Value if not defined Name for %%s in (%Value%) do (set Name=!pn_%%s!& set Name=!Name:gvlk=!)
if defined EDITION_SWITCH (set eID=%EDITION_SWITCH%) else if defined Name for %%s in (%Name%) do (set eID=%Name%)
if not defined eID set eID=%EditionID%& if not defined EditionID set eID=Professional& set EditionID=Professional
if /i "%EditionID%" equ "%eID%" (set changed=) else set changed=1

::# upgrade matrix
if /i CoreCountrySpecific equ %eID% set "comp=!eID!" & set "reg=!eID!" & if not defined i_!eID! set "eID=Core"
if /i CoreSingleLanguage  equ %eID% set "comp=Core"  & set "reg=!eID!" & if not defined i_!eID! set "eID=Core"
for %%e in (Starter HomeBasic HomePremium CoreConnectedCountrySpecific CoreConnectedSingleLanguage CoreConnected Core) do (
 if /i %%e  equ %eID% set "comp=Core"  & set "eID=Core"
 if /i %%eN equ %eID% set "comp=CoreN" & set "eID=CoreN"
 if /i %%e  equ %eID% if not defined i_Core  set "eID=Professional"  & if not defined reg set "reg=Core"
 if /i %%eN equ %eID% if not defined i_CoreN set "eID=ProfessionalN" & if not defined reg set "reg=CoreN"
)
for %%e in (Ultimate ProfessionalStudent ProfessionalCountrySpecific ProfessionalSingleLanguage) do (
  if /i %%e equ %eID% (set "eID=Professional") else if /i %%eN equ %eID% set "eID=ProfessionalN"
)
for %%e in (EnterpriseG EnterpriseS IoTEnterpriseS IoTEnterprise Embedded) do (
  if /i %%e equ %eID% (set "eID=Enterprise") else if /i %%eN equ %eID% set "eID=EnterpriseN"
)
for %%e in (Enterprise EnterpriseS) do (
  if /i %%eEval equ %eID% (set "eID=Enterprise") else if /i %%eNEval equ %eID% set "eID=EnterpriseN"
)
if /i Enterprise  equ %eID% set "comp=!eID!" & if not defined i_!eID! set "eID=Professional"  & set "reg=!comp!"
if /i EnterpriseN equ %eID% set "comp=!eID!" & if not defined i_!eID! set "eID=ProfessionalN" & set "reg=!comp!"
for %%e in (Education ProfessionalEducation ProfessionalWorkstation Professional Cloud) do (
  if /i %%eN equ %eID% set "comp=EnterpriseN"  & if not defined reg set "reg=%%eN"
  if /i %%e  equ %eID% set "comp=Enterprise"   & if not defined reg set "reg=%%e"
  if /i %%eN equ %eID% set "eID=ProfessionalN" & if defined i_%%eN  set "eID=%%eN"
  if /i %%e  equ %eID% set "eID=Professional"  & if defined i_%%e   set "eID=%%e"
)
set index=& set lst=Professional& for /l %%i in (1,1,%w_count%) do if /i !i_%%i! equ !eID! set "index=%%i" & set "eID=!i_%%i!"
if not defined index set index=1& set eID=!i_1!& if defined i_%lst% set "index=!i_%lst%!" & set "eID=%lst%"& set "comp=Enterprise"
set Build=!b_%index%!& set OPTIONS=%OPTIONS% /ImageIndex %index%& if defined changed if not defined reg set "reg=!eID!"
echo;Current edition: %EditionID% & echo;Regedit edition: %reg% & echo;Index: %index%  Image: %eID%
timeout /t 10

::# disable upgrade blocks
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /f /v DisableWUfBSafeguards /d 1 /t reg_dword >nul 2>nul

::# prevent MCT intermediate upgrade
if "%Build%" gtr "15063" (set OPTIONS=%OPTIONS% /UpdateMedia Decline)

::# skip windows 11 upgrade checks with all methods
if "%Build%" lss "22000" set /a SKIP_11_SETUP_CHECKS=0
reg add HKLM\SYSTEM\Setup\MoSetup /f /v AllowUpgradesWithUnsupportedTPMorCPU /d 1 /t reg_dword >nul 2>nul
if "%SKIP_11_SETUP_CHECKS%" equ "1" cd.>appraiserres.dll 2>nul
for %%A in (appraiserres.dll) do if %%~zA gtr 0 (set TRICK=/Product Server ) else (set TRICK=)
if "%SKIP_11_SETUP_CHECKS%" equ "1" (set OPTIONS=%TRICK%%OPTIONS%)

::# auto upgrade with edition lie workaround
if defined reg call :rename %reg%
start "auto" setupprep.exe %OPTIONS%
echo;DONE

EXIT /b

:rename EditionID
set "NT=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
for %%v in (CompositionEditionID EditionID ProductName) do reg add "%NT%" /v %%v_undo /d "!%%v!" /f >nul 2>nul
for %%A in (32 64) do (
 reg add "%NT%" /v CompositionEditionID /d "%comp%" /f /reg:%%A
 reg add "%NT%" /v EditionID /d "%~1" /f /reg:%%A
 reg add "%NT%" /v ProductName /d "%~1" /f /reg:%%A
) >nul 2>nul
exit /b

:reg_query [USAGE] call :reg_query "HKCU\Volatile Environment" Value variable
(for /f "tokens=2*" %%R in ('reg query "%~1" /v "%~2" /se "|" %4 2^>nul') do set "%~3=%%S") & exit /b

#:WIM_INFO:# [PARAMS]: "file" [optional]Index or 0 = all  Output 0 = txt 1 = xml 2 = file.txt 3 = file.xml 4 = xml object
set ^ #=;$f0=[io.file]::ReadAllText($env:0); $0=($f0-split '#[:]WIM_INFO[:]' ,3)[1]; $1=$env:1-replace'([`@$])','`$1'; iex($0+$1)
set ^ #=& set "0=%~f0"& set 1=;WIM_INFO %*& powershell -nop -ep bypass -c "%#%"& exit /b %errorlevel%
function WIM_INFO ($file = 'install.esd', $index = 0, $out = 0) { :info while ($true) {
  $block = 2097152; $bytes = new-object 'Byte[]' ($block); $begin = [uint64]0; $final = [uint64]0; $limit = [uint64]0
  $steps = [int]([uint64]([IO.FileInfo]$file).Length / $block - 1); $enc = [Text.Encoding]::GetEncoding(28591); $delim = @()
  foreach ($d in '/INSTALLATIONTYPE','/WIM') {$delim += $enc.GetString([Text.Encoding]::Unicode.GetBytes([char]60+ $d +[char]62))}
  $f = new-object IO.FileStream ($file, 3, 1, 1); $p = 0; $p = $f.Seek(0, 2)
  for ($o = 1; $o -le $steps; $o++) {
    $p = $f.Seek(-$block, 1); $r = $f.Read($bytes, 0, $block); if ($r -ne $block) {write-host invalid block $r; break}
    $u = [Text.Encoding]::GetEncoding(28591).GetString($bytes); $t = $u.LastIndexOf($delim[0], [StringComparison]::Ordinal)
    if ($t -lt 0) { $p = $f.Seek(-$block, 1)} else { [void]$f.Seek(($t -$block), 1)
      for ($o = 1; $o -le $block; $o++) { [void]$f.Seek(-2, 1); if ($f.ReadByte() -eq 0xfe) {$begin = $f.Position; break} }
      $limit = $f.Length - $begin; if ($limit -lt $block) {$x = $limit} else {$x = $block}
      $bytes = new-object 'Byte[]' ($x); $r = $f.Read($bytes, 0, $x)
      $u = [Text.Encoding]::GetEncoding(28591).GetString($bytes); $t = $u.IndexOf($delim[1], [StringComparison]::Ordinal)
      if ($t -ge 0) {[void]$f.Seek(($t + 12 -$x), 1); $final = $f.Position} ; break } }
  if ($begin -gt 0 -and $final -gt $begin) {
    $x = $final - $begin; [void]$f.Seek(-$x, 1); $bytes = new-object 'Byte[]' ($x); $r = $f.Read($bytes, 0, $x)
    if ($r -ne $x) {$f.Dispose(); break} else {[xml]$xml = [Text.Encoding]::Unicode.GetString($bytes); $f.Dispose()}
  } else {$f.Dispose()} ; break :info }
  if ($out -eq 1) {[console]::OutputEncoding=[Text.Encoding]::UTF8; $xml.Save([Console]::Out); ''; return}
  if ($out -eq 3) {try{$xml.Save(($file-replace'esd$','xml'))}catch{}; return}; if ($out -eq 4) {return $xml}
  $txt = ''; foreach ($i in $xml.WIM.IMAGE) {if ($index -gt 0 -and $($i.INDEX) -ne $index) {continue}; [int]$a='1'+$i.WINDOWS.ARCH
  $txt+= $i.INDEX+','+$i.WINDOWS.VERSION.BUILD+','+$i.WINDOWS.VERSION.SPBUILD+','+$(@{10='x86';15='arm';19='x64';112='arm64'}[$a])
  $txt+= ','+$i.WINDOWS.LANGUAGES.LANGUAGE+','+$i.WINDOWS.EDITIONID+','+$i.NAME+[char]13+[char]10}; $txt=$txt-replace',(?=,)',', '
  if ($out -eq 2) {try{[io.file]::WriteAllText(($file-replace'esd$','txt'),$txt)}catch{}; return}; if ($out -eq 0) {return $txt}
} #:WIM_INFO:#

'@; [io.file]::WriteAllText('auto.cmd', $text) #:generate_auto_cmd

::--------------------------------------------------------------------------------------------------------------------------------
:generate_AutoUnattend_xml $text = @'
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE"><component name="Microsoft-Windows-Setup" processorArchitecture="amd64" language="neutral"
   xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
   publicKeyToken="31bf3856ad364e35" versionScope="nonSxS">
    <UserData><ProductKey><Key>AAAAA-VVVVV-EEEEE-YYYYY-OOOOO</Key><WillShowUI>OnError</WillShowUI></ProductKey></UserData>
    <ComplianceCheck><DisplayReport>Never</DisplayReport></ComplianceCheck><Diagnostics><OptIn>false</OptIn></Diagnostics>
    <DynamicUpdate><Enable>true</Enable><WillShowUI>Never</WillShowUI></DynamicUpdate><EnableNetwork>true</EnableNetwork>
  </component></settings>
  <settings pass="specialize"><component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" language="neutral"
   xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
   publicKeyToken="31bf3856ad364e35" versionScope="nonSxS">
    <RunSynchronous>
      <RunSynchronousCommand wcm:action="add"><Order>1</Order>
        <Path>reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE /v BypassNRO /t reg_dword /d 1 /f</Path>
      </RunSynchronousCommand>
      <RunSynchronousCommand wcm:action="add"><Order>2</Order>
        <Path>reg add HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate /v TargetReleaseVersion /d 1 /t reg_dword /f</Path>
      </RunSynchronousCommand>
      <RunSynchronousCommand wcm:action="add"><Order>3</Order>
        <Path>reg add HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate /v TargetReleaseVersionInfo /d 25H2 /f</Path>
      </RunSynchronousCommand>
      <RunSynchronousCommand wcm:action="add"><Order>4</Order>
        <Path>reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassTPMCheck /t reg_dword /d 1 /f</Path>
      </RunSynchronousCommand>
      <RunSynchronousCommand wcm:action="add"><Order>5</Order>
        <Path>reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassSecureBootCheck /t reg_dword /d 1 /f</Path>
      </RunSynchronousCommand>
      <RunSynchronousCommand wcm:action="add"><Order>6</Order>
        <Path>reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassCPUCheck /t reg_dword /d 1 /f</Path>
      </RunSynchronousCommand>
      <RunSynchronousCommand wcm:action="add"><Order>7</Order>
        <Path>reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassRAMCheck /t reg_dword /d 1 /f</Path>
      </RunSynchronousCommand>
      <RunSynchronousCommand wcm:action="add"><Order>8</Order>
        <Path>reg add "HKLM\SYSTEM\Setup\LabConfig" /v BypassStorageCheck /t reg_dword /d 1 /f</Path>
      </RunSynchronousCommand>
    </RunSynchronous>
  </component></settings>
  <settings pass="oobeSystem"><component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" language="neutral"
   xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
   publicKeyToken="31bf3856ad364e35" versionScope="nonSxS">
    <OOBE>
      <HideLocalAccountScreen>false</HideLocalAccountScreen><HideOnlineAccountScreens>false</HideOnlineAccountScreens>
      <HideWirelessSetupInOOBE>false</HideWirelessSetupInOOBE><ProtectYourPC>3</ProtectYourPC>
    </OOBE>
    <FirstLogonCommands>
      <SynchronousCommand wcm:action="add"><Order>1</Order>
        <CommandLine>reg add "HKCU\Control Panel\UnsupportedHardwareNotificationCache" /v SV1 /d 0 /t reg_dword /f</CommandLine>
      </SynchronousCommand><SynchronousCommand wcm:action="add"><Order>2</Order>
        <CommandLine>reg add "HKCU\Control Panel\UnsupportedHardwareNotificationCache" /v SV2 /d 0 /t reg_dword /f</CommandLine>
      </SynchronousCommand>
    </FirstLogonCommands>
  </component></settings>
</unattend>

'@; if ($env:VIS) {$text = $text -replace 'TargetReleaseVersionInfo /d 25H2','TargetReleaseVersionInfo /d '+$env:VIS}; [io.file]::WriteAllText('AutoUnattend.xml', $text); #:generate_AutoUnattend_xml

::--------------------------------------------------------------------------------------------------------------------------------
:reg_query [USAGE] call :reg_query "HKCU\Volatile Environment" Value variable
(for /f "tokens=2*" %%R in ('reg query "%~1" /v "%~2" /se "," 2^>nul') do set "%~3=%%S")& exit /b

::--------------------------------------------------------------------------------------------------------------------------------
#:MakeISO:#  [PARAMS] "directory" "file.iso" [optional]"label"
set ^ #=;$f0=[io.file]::ReadAllText($env:0); $0=($f0-split '#\:MakeISO\:' ,3)[1]; $1=$env:1-replace'([`@$])','`$1'; iex($0+$1)
set ^ #=& set "0=%~f0"& set 1=;MakeISO %*& powershell -nop -ep bypass -c "%#%"& exit /b %errorlevel%
function MakeISO ($dir,$iso,$label='DVD_ROM') {if (!(test-path -Path $dir -pathtype Container)) {"[ERR] $dir"; return 1}; $code=@"
 using System; using System.IO; using System.Runtime.Interop`Services; using System.Runtime.Interop`Services.ComTypes;
 public class dir2iso {public int Ver=2026; [Dll`Import("shlwapi",CharSet=CharSet.Unicode,PreserveSig=false)]
 internal static extern void SHCreateStreamOnFileEx(string f,uint m,uint d,bool b,IStream r,out IStream s);
 public static int Create(string file, ref object obj, int bs, int tb) { IStream dir=(IStream)obj, iso;
 try {SHCreateStreamOnFileEx(file,0x1001,0x80,true,null,out iso);} catch(Exception e) {Console.WriteLine(e.Message); return 1;}
 int d=tb>1024 ? 1024 : 1, pad=tb%d, block=bs*d, total=(tb-pad)/d, c=total>100 ? total/100 : total, i=1, MB=(bs/1024)*tb/1024;
 Console.Write("{0}\r\n{1,2}%  {2}MB  MakeISO",file,0,MB); if (pad > 0) dir.CopyTo(iso, pad * block, Int`Ptr.Zero, Int`Ptr.Zero);
 while (total-- > 0) {dir.CopyTo(iso, block, Int`Ptr.Zero, Int`Ptr.Zero); if (total % c == 0) {Console.Write("\r{0,2}%",i++);}}
 iso.Commit(0); Console.WriteLine("\r{0,2}%  {1}MB  MakeISO",100,MB); return 0;} }
"@; & { $cs = new-object CodeDom.Compiler.CompilerParameters; $cs.GenerateInMemory = 1
 $compile = (new-object Microsoft.CSharp.CSharpCodeProvider).CompileAssemblyFromSource($cs, $code)
 $BOOT = @(); $bootable = 0; $mbr_efi = @(0,0xEF); $images = @('boot\etfsboot.com','efi\microsoft\boot\efisys.bin')
 0,1|% { $bootimage = join-path $dir -child $images[$_]; if (test-path -Path $bootimage -pathtype Leaf) {
 $bin = new-object -ComObject ADODB.Stream; $bin.Open(); $bin.Type = 1; $bin.LoadFromFile($bootimage)
 $opt = new-object -ComObject IMAPI2FS.BootOptions;$opt.AssignBootImage($bin.psobject.BaseObject); $opt.PlatformId = $mbr_efi[$_]
 $opt.Emulation = 0; $bootable = 1; $opt.Manufacturer = 'Microsoft'; $BOOT += $opt.psobject.BaseObject } }
 $fsi = new-object -ComObject IMAPI2FS.MsftFileSystemImage; $fsi.FileSystemsToCreate = 4; $fsi.FreeMediaBlocks = 0
 if ($bootable) {$fsi.BootImageOptionsArray = $BOOT}; $TREE = $fsi.Root; $TREE.AddTree($dir,$false); $fsi.VolumeName = $label
 $obj = $fsi.CreateResultImage(); $ret = [dir2iso]::Create($iso,[ref]$obj.ImageStream,$obj.BlockSize,$obj.TotalBlocks) }
 [GC]::Collect(); return $ret
} #:MakeISO:#

::--------------------------------------------------------------------------------------------------------------------------------
:DOWNLOAD
#:DOWNLOAD:# [PARAMS] "url" "file" [optional]"path"
set ^ #=;$f0=[io.file]::ReadAllText($env:0); $0=($f0-split '#\:DOWNLOAD\:' ,3)[1]; $1=$env:1-replace'([`@$])','`$1'; iex($0+$1)
set ^ #=& set "0=%~f0"& set 1=;DOWNLOAD %*& powershell -nop -ep bypass -c "%#%"& exit /b %errorlevel%
function DOWNLOAD ($u, $f, $p = (get-location).Path) {
  $LOGFILE = $env:LOGFILE
  try {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11} catch {}
  $null = Import-Module BitsTransfer -ea 0; $wc = new-object Net.WebClient; $wc.Headers.Add('user-agent','Mozilla/5.0')
  $file = join-path $p $f; $s = 'https://'; $i = 'http://'; $d = $u.replace($s,'').replace($i,''); $https = $s+$d; $http = $i+$d
  $maxRetry = 3; $retry = 0
  while ($retry -lt $maxRetry) {
    foreach ($url in $https, $http) {
      if (([IO.FileInfo]$file).Exists) {break}
      write-host -nonew -fore Gray "`r  Attempt $($retry+1)/$maxRetry - BITS... "
      try {Start-BitsTransfer $url $file -ea 1} catch {}
      if (([IO.FileInfo]$file).Exists) {break}
      write-host -nonew -fore Gray "`r  Attempt $($retry+1)/$maxRetry - WebRequest... "
      try {Invoke-WebRequest $url -OutFile $file -UseBasicParsing} catch {}; $j = (Get-Date).Ticks
      if (([IO.FileInfo]$file).Exists) {break}
      write-host -nonew -fore Gray "`r  Attempt $($retry+1)/$maxRetry - WebClient... "
      try {$wc.DownloadFile($url, $file)} catch {}
      if (([IO.FileInfo]$file).Exists) {break}
      write-host -nonew -fore Gray "`r  Attempt $($retry+1)/$maxRetry - bitsadmin... "
      try {$null = bitsadmin /transfer $j /priority foreground $url $file} catch {}
      if (([IO.FileInfo]$file).Exists) {break}
      write-host -nonew -fore Gray "`r  Attempt $($retry+1)/$maxRetry - certutil... "
      try {certutil -urlcache -split -f $url $file 2>$null} catch {}
    }
    if (([IO.FileInfo]$file).Exists -and ([IO.FileInfo]$file).Length -gt 0) {
      $dlSize = [math]::Round(([IO.FileInfo]$file).Length/1KB, 0)
      write-host -fore Green "`r  Downloaded: $f (${dlSize} KB)                              "
      Add-Content $LOGFILE "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] Downloaded: $f (${dlSize} KB)"
      return
    } elseif (([IO.FileInfo]$file).Exists -and ([IO.FileInfo]$file).Length -eq 0) {
      Remove-Item $file -Force -ea 0
    }
    $retry++
    if ($retry -lt $maxRetry) {
      write-host -fore Yellow "`r  Retry $retry/$maxRetry in 5s...                         "
      sleep 5
    }
  }
  write-host -fore Red "`r  FAILED: $f download failed after $maxRetry attempts       "
  Add-Content $LOGFILE "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] FAILED: $f download failed"
} #:DOWNLOAD:# Enhanced with retry, certutil fallback, logging - AlwaysUpdate v1.1

::--------------------------------------------------------------------------------------------------------------------------------
:CHOICES
#:CHOICES:#  [PARAMS] indexvar "c,h,o,i,c,e,s"  [OPTIONAL]  default-index "title" fontsize backcolor forecolor winsize
set ^ #=;$f0=[io.file]::ReadAllText($env:0); $0=($f0-split '#\:CHOICES\:' ,3)[1]; $1=$env:1-replace'([`@$])','`$1'; iex($0+$1)
set ^ #=&set "0=%~f0"& set 1=;CHOICES %*& (for /f %%x in ('powershell -nop -ep bypass -c "%#%"') do set "%1=%%x")& exit /b
function CHOICES ($index,$choices,$def=1,$title='Choices',[int]$sz=12,$bc='MidnightBlue',$fc='Snow',[string]$win='300') {
 [void][Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); $f=new-object Windows.Forms.Form; $global:ret=''
 $bt=@(); $i=1; $ch=($choices+',Cancel').split(','); $ch |foreach {$b=New-Object Windows.Forms.Button; $b.Font='Consolas,'+$sz
 $b.Name=$i; $b.Text=$_;  $b.Margin='0,0,9,9'; $b.Location='9,'+($sz*3*$i-$sz); $b.MinimumSize=$win+',18'; $b.AutoSize=1
 $b.add_GotFocus({$this.BackColor=$fc; $this.ForeColor=$bc}); $b.add_LostFocus({$this.BackColor=$bc; $this.ForeColor=$fc})
 $b.FlatStyle=0; $b.Cursor='Hand'; $b.add_Click({$global:ret=$this.Name;$f.Close()}); $f.Controls.Add($b); $bt+=$b; $i++}
 $f.Text=$title; $f.BackColor=$bc; $f.ForeColor=$fc; $f.StartPosition=4; $f.AutoSize=1; $f.AutoSizeMode=0; $f.MaximizeBox=0
 $f.AcceptButton=$bt[$def-1]; $f.CancelButton=$bt[-1]; $f.Add_Shown({$f.Activate();$bt[$def-1].focus()})
 $f.ShowDialog() >$null; $index=$global:ret; if ($index -eq $ch.length) {return 0} else {return $index}
} #:CHOICES:#

::--------------------------------------------------------------------------------------------------------------------------------
:CHOICES2
#:CHOICES2:#  [INTERNAL]
set ^ #=;$f0=[io.file]::ReadAllText($env:0); $0=($f0-split '#\:CHOICES2\:' ,3)[1]; $1=$env:1-replace'([`@$])','`$1'; iex($0+$1)
set ^ #=&set "0=%~f0"&set 1=;CHOICES2 %*&(for /f "tokens=1,2" %%x in ('powershell -nop -ep bypass -c "%#%"')do set %1=%%x&set %5=%%y)&exit /b
function CHOICES2 {iex($f0-split '#\:CHOICES\:' ,3)[1]; function :LOOP { $a=$args
 $c1 = @($a[0], $a[1], $a[2], $a[3],  $a[-4], $a[-3], $a[-2], $a[-1]); $r1= CHOICES @c1; if ($r1 -lt 1) {return "0 0"}
 $a_7_ = $a[1].Split(',')[$r1-1] + ' ' + $a[7]
 $c2 = @($a[4], $a[5], $a[6], $a_7_,  $a[-4], $a[-3], $a[-2], $a[-1]); $r2= CHOICES @c2; if ($r2 -ge 1) {return "$r1 $r2"}
 if ($r2 -lt 1) {$a[2]=$r1; :LOOP @a} }; :LOOP @args
} #:CHOICES2:#

::--------------------------------------------------------------------------------------------------------------------------------
:PRODUCTS_XML
#:PRODUCTS_XML:#
set ^ #=;$f0=[io.file]::ReadAllText($env:0); $0=($f0-split '#\:PRODUCTS_XML\:' ,3)[1]; $1=$env:1-replace'([`@$])','`$1';iex($0+$1)
set ^ #=& set "0=%~f0"& set 1=;PRODUCTS_XML %*& powershell -nop -ep bypass -c "%#%"& exit /b
function PRODUCTS_XML { [xml]$xml = [io.file]::ReadAllText("$pwd\products.xml",[Text.Encoding]::UTF8); $root = $null
 $eulas = 0; $langs = 0; $ver = $env:VER; $vid = $env:VID; $X = $env:X; if ($X-eq'11') {$vid = "11 $env:VIS"}
 $url = "http://b1.download.windowsupdate.com/"
 if ($null -ne $xml.SelectSingleNode('/MCT')) {
   $xml.MCT.Catalogs.Catalog.version = $env:CC; $root = $xml.SelectSingleNode('/MCT/Catalogs/Catalog/PublishedMedia')
 } else {
   $temp = [xml]('<?xml version="1.0" encoding="UTF-8"?><MCT><Catalogs><Catalog version="' + $env:CC + '"/></Catalogs></MCT>')
   $temp.SelectSingleNode('/MCT/Catalogs/Catalog').AppendChild($temp.ImportNode($xml.PublishedMedia,$true)) >$null
   $xml = $temp; $root = $xml.SelectSingleNode('/MCT/Catalogs/Catalog/PublishedMedia')
 }
 foreach ($l in $root.ChildNodes) {if ($l.LocalName -eq 'EULAS') {$eulas = 1}; if ($l.LocalName -eq 'Languages') {$langs = 1} }
 $eula = "http://download.microsoft.com/download/C/0/3/C036B882-9F99-4BC9-A4B5-69370C4E17E9/EULA_MCTool_"
 if ($eulas -eq 1) { foreach ($i in $root.EULAS.EULA) {$i.URL = $eula + $i.LanguageCode.ToUpperInvariant() + '_6.27.16.rtf'} }
 if ($eulas -eq 0) {
   $tmp = [xml]('<EULA><LanguageCode/><URL/></EULA>'); $el = $xml.CreateElement('EULAS'); $node = $xml.ImportNode($tmp.EULA,$true)
   foreach ($lang in ($root.Languages.Language |where {$_.LanguageCode -ne 'default'})) {
     $i = $el.AppendChild($node.Clone()); $lc = $lang.LanguageCode
     $i.LanguageCode = $lc; $i.URL = $eula + $lc.ToUpperInvariant() + '_6.27.16.rtf'
   }
   $root.AppendChild($el) >$null
 }
 if ($langs -eq 1) {
   if ($ver -gt 15063) {$CONSUMER = "$vid Pro | Edu | Home"} else {$CONSUMER = "$vid Pro | Home"}
   foreach ($i in $root.Languages.Language) {
     foreach ($l in $i.ChildNodes) { $l.InnerText = $l.InnerText.replace("Windows 10", $vid) }
     if ($null -ne $i.CLIENT)    {$i.CLIENT   = "$CONSUMER"}    ;  if ($null -ne $i.CLIENT_K)  {$i.CLIENT_K  = "$CONSUMER K"}
     if ($null -ne $i.CLIENT_N)  {$i.CLIENT_N = "$CONSUMER N"}  ;  if ($null -ne $i.CLIENT_KN) {$i.CLIENT_KN = "$CONSUMER KN"}
   }
 }
 $BUSINESS = "$vid Pro | Edu | Enterprise"
 $root.Files.File | & { process {
   $_arch = $_.Architecture; $_lang = $_.LanguageCode; $_edi = $_.Edition; $_loc = $_.Edition_Loc; $ok = $true
   if ($_arch -eq 'ARM64' -or ($ver -lt 22000 -and $_loc -eq '%BASE_CHINA%')) {$root.Files.RemoveChild($_) >$null; return}
   if ($env:UNHIDE_BUSINESS -ge 1) {
     if ($_edi -eq 'Enterprise' -or $_edi -eq 'EnterpriseN') {$_.IsRetailOnly = 'False'; $_.Edition_Loc = $BUSINESS}
     if ($ver -le 15063 -and ($_edi -eq 'Education' -or $_edi -eq 'EducationN')) {$_.IsRetailOnly = 'False'}
   }
 }}
 $lines = ([io.file]::ReadAllText($env:0) -split':PS_INSERT_BUSINESS_CSV\:')[1]; $insert = $false
 if ($null -ne $lines -and $env:INSERT_BUSINESS -ge 1 -and 19043,19042,19041,18363,15063,14393 -contains $ver) {
   $csv = ConvertFrom-CSV -Input $lines.replace('sr-rs','sr-latn-rs') | & { process { if ($_.Ver -eq $ver) {$_} } }
   $edi = @{ent='Enterprise';enN='EnterpriseN';edu='Education';edN='EducationN';clo='Cloud';clN='CloudN';
            pro='Professional';prN='ProfessionalN'}
   $insert = $true
 }
 if ($insert -and $ver -le 15063) {
   foreach ($e in 'ent','enN','pro','prN','edu','edN','clo','clN') {
     $items = $csv | & { process { if ($_.Client -eq $e) {$_} } } | group Lang -AsHashTable -AsString
     if ($null -eq $items) {continue}
     $cli = '_CLIENT' + $edi[$e]; $up = '/upgr/'; if ($ver -eq 14393 -and $e -like 'en*') {$up = '/updt/'}
     if ($e -like 'cl*') {$cli += '_RET_'} elseif ($e -like 'p*') {$cli += 'VL_VOL_'} else {$cli += '_VOL_'}
     if ($e -like 'cl*') {$BUSINESS = $edi[$e] -replace 'Cloud','S'} else {$BUSINESS = $edi[$e] -creplace 'N',' N'}
     $root.Files.File | & { process { if ($_.Edition -eq "Education") {
       $arch = $_.Architecture; $lang = $_.LanguageCode; $item = $items[$lang]; if ($null -eq $item) {return}
       if ($arch -eq 'x64')     {$_size = $item[0].Size_x64; $_sha1 = $item[0].Sha1_x64; $_dir = $item[0].Dir_x64}
       elseif ($arch -eq 'x86') {$_size = $item[0].Size_x86; $_sha1 = $item[0].Sha1_x86; $_dir = $item[0].Dir_x86}
       $c = $_.Clone(); if ($c.HasAttribute('id')) {$c.RemoveAttribute('id')} $c.IsRetailOnly = 'False'; $c.Edition = $edi[$e]
       $name = $env:CB + $cli + $arch + 'FRE_' + $lang; $c.Edition_Loc = "$vid $BUSINESS"
       $c.FileName = $name + '.esd'; $c.Size = $_size; $c.Sha1 = $_sha1
       $c.FilePath = $url + $_dir + $up + $env:CT + $name.ToLowerInvariant() + '_' + $_sha1 + '.esd'
       $root.Files.AppendChild($c) >$null
     }}}
   }
 }
 if ($insert -and $ver -gt 15063) {
   $items = $csv |group Client,Lang -AsHashTable -AsString
   if ($null -ne $items) {
     $root.Files.File | & { process {
       $cli = '_CLIENTCONSUMER_'; $chan = 'ret'; $edition = $_.Edition
       if ($edition -eq 'Enterprise' -or $edition -eq 'EnterpriseN') {$cli = '_CLIENTBUSINESS_'; $chan = 'vol'}
       $arch = $_.Architecture; $lang = $_.LanguageCode; $item = $items["$chan, $lang"]; if ($null -eq $item) {return}
       if ($arch -eq 'x64')     {$_size = $item[0].Size_x64; $_sha1 = $item[0].Sha1_x64; $_dir = $item[0].Dir_x64}
       elseif ($arch -eq 'x86') {$_size = $item[0].Size_x86; $_sha1 = $item[0].Sha1_x86; $_dir = $item[0].Dir_x86}
       if ('' -eq $_size) {$root.Files.RemoveChild($_) >$null; return}
       $name = $env:CB + $cli + $chan.ToUpperInvariant() + '_' + $arch + 'FRE_' + $_.LanguageCode
       $_.FileName = $name + '.esd'; $_.Size = $_size; $_.Sha1 = $_sha1
       $_.FilePath = $url + $_dir + '/upgr/' + $env:CT + $name.ToLowerInvariant() + '_' + $_sha1 + '.esd'
     }}
   }
 }
 $source = 'Enterprise'; $sourceN = 'EnterpriseN'; $clone = 'Embedded','IoTEnterpriseS','EnterpriseS'; $cloneN = 'EnterpriseSN'
 if ($ver -le 10586) {$source = 'Professional'; $sourceN = 'ProfessionalN'; $clone +='Enterprise'; $cloneN+='EnterpriseN'}
 if ($ver -le 16299) {$clone +='ProfessionalEducation','ProfessionalWorkstation'}
 if ($ver -le 16299) {$cloneN+='ProfessionalEducationN','ProfessionalWorkstationN'}
 if ($env:UNHIDE_BUSINESS -ge 1) {
   $root.Files.File | & { process {
     if ($_.Edition -eq $source) {
       foreach ($s in $clone) {
         $c = $_.Clone(); if ($c.HasAttribute('id')) {$c.RemoveAttribute('id')}
         $c.IsRetailOnly='False'; $c.Edition=$s; $root.Files.AppendChild($c) >$null
       }
     }
     elseif ($_.Edition -eq $sourceN) {
       foreach ($s in $cloneN) {
         $c = $_.Clone(); if ($c.HasAttribute('id')) {$c.RemoveAttribute('id')}
         $c.IsRetailOnly='False'; $c.Edition=$s; $root.Files.AppendChild($c) >$null
       }
   }}}
 }
 $xml.Save("$pwd\products.xml");
} #:PRODUCTS_XML:#

::--------------------------------------------------------------------------------------------------------------------------------
:capture_products_catalog
#:: Run the fwlink MCT briefly to let it download the latest catalog from Microsoft.
#:: The MCT downloads products.cab/xml to C:\$WINDOWS.~WS\Sources\ before hardware checks.
 $LOGFILE = $env:LOGFILE; $exePath = "$pwd\MCT_fwlink.exe"
 Add-Content $LOGFILE "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] Starting fwlink MCT to capture catalog..."
 $WS = [environment]::SystemDirectory[0] + ':\$WINDOWS.~WS\Sources'
 $proc = Start-Process -FilePath $exePath -PassThru -WorkingDirectory $pwd
 if ($null -eq $proc) { write-host " WARN: failed to start MCT" -fore Yellow; return }
 $ok = $false; $timeout = 90
 for ($i = 0; $i -lt $timeout; $i += 2) {
   Start-Sleep -Seconds 2
   if (Test-Path "$WS\products.xml") {
     $xmlSize = (Get-Item "$WS\products.xml").Length
     if ($xmlSize -gt 1000) {
       Copy-Item "$WS\products.xml" "$pwd\products.xml" -Force
       Copy-Item "$WS\products.cab" "$pwd\products.cab" -Force -ea 0
       write-host " Catalog captured ($xmlSize bytes in ${i}s)" -fore Gray
       Add-Content $LOGFILE "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] Catalog captured: $xmlSize bytes after ${i}s"
       $ok = $true; break
     }
   }
   if ($proc.HasExited) {
     Add-Content $LOGFILE "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] MCT exited (code $($proc.ExitCode)) after ${i}s"
     break
   }
 }
 try { if (-not $proc.HasExited) { $proc.Kill() } } catch {}
 Get-Process "SetupHost","SetupPrep" -ea 0 | Stop-Process -Force -ea 0
 if (-not $ok) {
   write-host " WARN: catalog capture timed out (${timeout}s)" -fore Yellow
   Add-Content $LOGFILE "[$(Get-Date -f 'yyyy-MM-dd HH:mm:ss')] WARN: catalog capture timed out"
 }
#:capture_products_catalog

::--------------------------------------------------------------------------------------------------------------------------------
::# ESD CSV data for INSERT_BUSINESS feature (versions 14393, 15063, 18363, 19041, 19042, 19043)
::# Format: Ver,Client,Lang,Size_x64,Size_x86,Sha1_x64,Sha1_x86,Dir_x64,Dir_x86
:PS_INSERT_BUSINESS_CSV:_,Ver,Client,Lang,Size_x64,Size_x86,Sha1_x64,Sha1_x86,Dir_x64,Dir_x86
::#,14393,enN,bg-bg,2773448902,2111500580,d090ecc0e32e05a6c075eb8384f577315ac35ee2,f2206f926561fd89b69d6e7e61aa98956966dfd6,c,c
::#,14393,enN,cs-cz,2775734726,2113434488,3979b107d1af43aae3cc79bd7a2a081def5d04cf,e773288e71f7a17ec8e1525415134acbfa13a803,d,d
::#,14393,enN,da-dk,2799132592,2137434148,f0a667d9584f10c47b3db96b0e6700f1a47021c3,9defa59a1627b3440684ce9605a43a0c4e88c770,d,d
::#,14393,enN,de-de,2888504080,2219030252,e8a1023f0f21a7c99d1b5006ef520323238833cd,e62e766faffcd25ebce37b758aeac6e63208c332,d,d
::#,14393,enN,el-gr,2798418934,2123659240,8bd00622321661b9ca1eb7289d907a9056c713ce,880756cb261c7a7b32289e549011d9bb968d2706,d,d
::#,14393,enN,en-gb,2861883002,2200050658,f145a8eff3121dc8fb020c5a1750a0f2c117ecb3,7c3415af341630a1f01f2f0983e44579d6a23487,d,d
::#,14393,enN,en-us,2859877184,2201813278,fab646ab44b5d956a91e0d2aa0e4a37f22ddf7cd,5166cb73561f9c1190f9d6f8a35fe444877318f9,c,c
::#,14393,enN,es-es,2848523494,2196489320,7386e7b352e080a15f6a565feeace4c6e854703d,191a58383195e53864fcacb41313043a5ea77663,d,d
::#,14393,enN,et-ee,2748248864,2095947306,b487809fa9f137624e4bb205e389f0e599d17093,d9f88ee10c3f41e5e152b24c78a35ab1f15d6af4,d,d
::#,14393,enN,fi-fi,2796624854,2137783028,dc40703bd5eca75ce2d234e367f23db5a71c807f,d3ed9db8b398eda4497c6b9d897555f5a5663d84,c,c
::#,14393,enN,fr-fr,2852055774,2193600366,5838ee4f277ebd8ab33f3d40bbcc380a95f9e69b,36286ca54f121ca1247e1026e0c76bf3fdc4f2be,c,c
::#,14393,enN,hr-hr,2765426784,2100724714,f8d5c52045248839329634468038b184b7e9a491,742c2541073a78be847cbe684651b7fcab6b6fdb,c,c
::#,14393,enN,hu-hu,2780468248,2122154560,65b67804be6e6a5e66f0046a8c779fc9599b571e,444ac3b15980f3ef4f911fa2f920891e230118ca,d,d
::#,14393,enN,it-it,2798572882,2144445692,162bbba0399ed2e0cc12569676f4afcc685f08a0,f4deb16739ba26ec597725cc5a9a2580b33e7ca2,d,d
::#,14393,enN,lt-lt,2755834506,2094863630,11c047008667638f72cfa7391b0ac14ce954a427,0a1d7d1bd8456251c623d5c3f3e7e6f0a9c00e86,d,d
::#,14393,enN,lv-lv,2752316336,2093716546,230ac84bf1c669d375fd05159a8d26edb87cf264,98948912070a686f3b7060b9f80446faba677b2d,d,d
::#,14393,enN,nb-no,2773039326,2113695528,7939fcefabeed9a8cebf6ca04984e9c0f8470f50,ba8c7be3fb2a12ae3a227ac60b69ce225f367933,c,c
::#,14393,enN,nl-nl,2775118184,2130921230,fbb84419e1b8618b83b91873ed5cc7fa1365a009,40d9d1a599a5266947f337fa6acfcaeeece8a865,c,c
::#,14393,enN,pl-pl,2778912686,2125591884,7ea026557e632da890a64e0fcf72f3672ef12e53,487eab83f1e6f67058b50b9a889d790f49384567,d,d
::#,14393,enN,pt-pt,2787935254,2125017148,0afce496d59bbfc1f1c6580dfb49bf0ca1e30275,40a28c0263920c0e13a1c450511718f61f2c67e1,d,d
::#,14393,enN,ro-ro,2763055438,2101442992,d88e0b470995cc081f9e73d06baf0ce6080445c9,5452de2544692ba234c744cb18676f1cbc3c7c3c,d,d
::#,14393,enN,sk-sk,2763328164,2096292986,be661b5d237a8a93259d64754b09ae29f26cb42b,6322ebdfaea5955e28ec0edba5595e6ecc3eabba,c,c
::#,14393,enN,sl-si,2754008752,2096786702,73a4a166b1eedff7c7465eed4ce3daa8eec1c051,882e91a3c1e7a239ac4d39288c19228b8ba20c8d,c,c
::#,14393,enN,sv-se,2799778090,2130127248,70e0831a0c4078705b6699e8662d6cb0dc4875a0,66c58033888d81d9e914463d941a525ef1f1c29b,d,d
::#,14393,ent,ar-sa,2955820350,2253811598,672bb229c831b84e95a6dbff94818528894540d3,c6daaa38f3eb589e8654a266320032ed3aa3a6f5,d,d
::#,14393,ent,bg-bg,2911551848,2218360574,97d613cdfb2ded4df2f71ef29fc93ca3656c6ed8,2c0063b9f769ba2307f84717ac2b915206a9d4a3,d,d
::#,14393,ent,cs-cz,2918785956,2214354874,7542eab92328937b8d09ee02cf8fa9cc6a196830,3108854bb25b7c75bac13289db5c2a2e9c920578,d,d
::#,14393,ent,da-dk,2946222420,2240352350,bb9da04cd47d7973597386ffd203ed56e19d4d65,297f5fb65fa79f3ed1d0a6dcad202d863b71e9bc,c,c
::#,14393,ent,de-de,3019388686,2321843034,c9b01f8eceb84ea2e7abf8c8823a623d759a61d0,8af78913db117260a888d57c5376470cfc109670,d,d
::#,14393,ent,el-gr,2933879638,2226440968,14e182c6ed9ba36c720fbd0c3f5ce7d64ed38ca5,b8bad577e15fbfaa27b8bdb53d1c6724fe64357a,d,d
::#,14393,ent,en-gb,3002224046,2305860070,b972022ec65c9205195833b842983e527f287d0a,6d0466628b39e192bd675fae1dfafded7fff94d9,d,d
::#,14393,ent,en-us,3012544034,2310343386,cbf97f9ee545d6bbff70c7fb9740e9fe5d6f4d77,72e16690f022fde1c59abc93457a1c6b8bd4c5dc,c,c
::#,14393,ent,es-es,3002625924,2298493682,d6b21213c81c83c46965baf0c1da2f14d4f3eff2,4b3999d40e9ac39c1ba4c1dec301c51aacc50f28,c,c
::#,14393,ent,es-mx,2943527594,2249633892,e7bb91c6aa0c9295718f0ea2761005ac4c556cc8,3341b800403bb93375745ea4c3a4529ae5472fe3,c,c
::#,14393,ent,et-ee,2889988048,2192782608,ca9eba2953c9aed39e051f5d984e4a58c945d17d,06e7a360daba3388edefbdf56d958e98b2cae2d2,c,c
::#,14393,ent,fi-fi,2932564162,2235053854,b250bb11cbbea356417993455d639582ca4fd052,3d13bc3b7ca9411cd791c5c861e022bfbf2db2ce,d,d
::#,14393,ent,fr-ca,2970085652,2267316492,e33bc497cc5ef1a2ef362c23d2814d580aa22e26,2200c921718cf3b8246cf4e82ae7127668790444,d,d
::#,14393,ent,fr-fr,2996998394,2297031996,b599b3275302e57b8e1ad25271da68c299c4de39,8b6805f55fd7c6641d182131f500c0340887c0b6,d,d
::#,14393,ent,he-il,2927278142,2224939840,b82d6122d55c838393c5645520692acd101834a9,4011de9ecdf53b41fdb2ea9e0910bc6a0bca7939,c,c
::#,14393,ent,hr-hr,2898184950,2202588894,bc2cbd1d92e60598115098238f12e8dac2c2166f,c689528beb00b9157cc3d08c2409ffaec84ea56c,c,c
::#,14393,ent,hu-hu,2918877960,2223268852,a0453e7dc3d34716caac2cacb473aa65ccecea3e,47e181c321033ac99850fb222047635a83d71d43,d,d
::#,14393,ent,it-it,2953574274,2247219130,9b48a0fef984b867e8018708785a6c70a696a469,4e68dba7258c1af508d8c180564749b5b1b9b3fc,d,d
::#,14393,ent,ja-jp,3063387292,2355095860,ec30e2dfa29223fbeda28feeed89f7ed6d2911fd,24d900e9937c520b10056e53775e6a5934a916a2,c,c
::#,14393,ent,ko-kr,2979348462,2265728512,8b9af5c684e639b1787c901baddb33e3ec1f17d5,296956b802ccf9a76083e6398db20d2b67186fd0,c,c
::#,14393,ent,lt-lt,2890387644,2196863664,97f81a28fa526e57e2e38235ce7103aa0fca0ff5,1636c7532f21ebf6282e785f35840201ed6cb81c,c,c
::#,14393,ent,lv-lv,2897092188,2196617270,26775e677727ad2296e7de0620be132d144abd55,aa16e2b2f317ab45e43885bb700a428d74244ef3,d,d
::#,14393,ent,nb-no,2922664364,2218857478,7c42bfed895f37cf86153ee75325b5d4b71e3eab,a9bbff5197b258a37d4639a9699e938f86030777,d,d
::#,14393,ent,nl-nl,2934556272,2223733356,81b8974317b76417ae102951ec191f90fdfc00f9,c1ad0d57e0ba595e81ef7820f9db2b7c12114629,c,c
::#,14393,ent,pl-pl,2929138222,2228062654,7ddc4be2c46d3aa5b562bc593936b7bac33c6a4a,165494554c7fdb1be55e4399b6372515c2d6b1ab,c,c
::#,14393,ent,pt-br,2953378710,2264016962,71de2e5a288324151bec24830bcedca5ad77a1ad,a5006f26410655f0efa3a42c0ff63b6c9acf4d74,d,d
::#,14393,ent,pt-pt,2941611330,2229207498,52dc57e4107dec547e68a9e74eec10244cea4f92,0b1a60b57e687aba766001a8b306870c9e7241b3,d,d
::#,14393,ent,ro-ro,2887834662,2201439796,24950dd0d69cd50fe01f8e9309583772ef231518,f1d43e2cbf3006e034b64eca9bc94de7ffa8cf94,c,c
::#,14393,ent,ru-ru,2957770620,2261034630,8ce69e0236a2b5269c08a67edab908211585b3c1,50f2f76e8a0e62f26a6238fd9471b16ca1b26186,c,c
::#,14393,ent,sk-sk,2888894912,2197855320,14accd88aa808e900ba902ac6509a5786d41be79,1796ddb7072d64e971b3f7ef7c3c3ecadfc7dd00,d,d
::#,14393,ent,sl-si,2881745984,2196163006,c1ac7d37d86e4dbdbb2992acc8d3b6e60e52919a,2bcc0dd24a8fcf85e041d29c27be612d20f6c39a,d,d
::#,14393,ent,sr-rs,2910809030,2204793922,f8d80cb91733aa8b48c6b84327494e210b8e5494,242810176bd2c17e25c94b5478762bacd04f0c2c,c,c
::#,14393,ent,sv-se,2931748080,2231055130,d6196f5e660ef7055a0a5efad8892045131a7f9b,14642e83ecd3d000bfc10d5bcea08de83ca1fe39,c,c
::#,14393,ent,th-th,2910791934,2218450936,1286f4fef88b41884d8083aad666d63ca232be42,5660b3c566e05bbb58504c392470916996988bf5,c,c
::#,14393,ent,tr-tr,2915633822,2215962556,871cf4807375a39b335468d44407023f19bade5f,2dbe29adf9297d98e66e42558fa673c0e76b4cf8,d,d
::#,14393,ent,uk-ua,2915857130,2219357380,5b88fcd4211676ced3350a9bdf5abe0a37707991,02a14a526045c75cbbc1aa279d01f1f23686dd93,c,c
::#,14393,ent,zh-cn,3131493920,2421427008,e78e04e6204b107ffa36d898d58232c86e98199d,2ddd95d076810d788d63082cffcbbd75bf921243,d,d
::#,14393,ent,zh-tw,3059396808,2361521848,4b4e82301a37192b69d70496fcf57c16aad681eb,589eb269e0666134c1d31d67c665da50ea9b2a66,d,d
::#,15063,clN,en-us,3144657572,2437732564,e69925fec9aebc5fbf3852086ecb4c3fe00dfc2e,0fcc1248ab6ac55cae7ec24be5b21ff163d34fc1,c,c
::#,15063,clo,en-us,3315033420,2546331272,7e8eae476222bbb48de04862a8ac85bdd563461c,9d92ec014d1dcc4d1968b33e9cc9bc0748e07bcd,d,d
::#,15063,enN,bg-bg,3063703618,2343397300,859fd1064516d2d86970313e20682c3f2da3b0f7,3f2d95b5af40290989b42d7e85fb73c2deecb107,c,c
::#,15063,enN,en-us,3140230812,2433137092,3e2111b94ad40b063d6fc224da72f83205c374c8,b17b8827e6954672d2bd85276b73770801a3bf6a,c,c
::#,15063,ent,en-us,3312849564,2542115274,5477ecbdb80b477d3cb049d0d64831b72797be8b,65162f45583f38d53d01c5e5a64a69d1e73cc005,d,d
::#,18363,ret,en-us,3746732457,2646270866,170e462a455d70ca336bf4675c1fec02a21a9d67,c8393ee4bcb304ec61b5a8fb0198b60db36b4435,d,d
::#,18363,vol,en-us,3626567900,2586064754,6e83a5e8f3ca99b74467e51cc9f5cf4f8e5de476,d29c815c75e7d1e5ab9937704596f0bd97b45e2d,d,d
::#,19041,ret,en-us,3597848148,2571735054,06bd415350b963311586e1de57febcf257d9cff3,0f1b95cd0d53ba38bbcdc8c458ebfb87542d8451,c,c
::#,19041,vol,en-us,3500119894,2494569638,a48a1cfc278325ab8a1c42ceedb987bbb80eda56,77dfcb554d1ae7c917ab15c1e9d0c2f4856ba9f5,c,c
::#,19042,ret,en-us,4209286277,3125180216,db2236f14e920b94af43e9adbc9061aaebad0651,7ed8b93befe6445abf71774a669bc6b8a86b9448,d,c
::#,19042,vol,en-us,4209286277,3125180216,db2236f14e920b94af43e9adbc9061aaebad0651,7ed8b93befe6445abf71774a669bc6b8a86b9448,d,c
::#,19043,ret,en-us,3974282652,2850851984,97ae12fd67d7607c94c39656e2b2f84ff9083874,086af468927c859b65211bb0d344934e702ee9d1,d,c
::#,19043,vol,en-us,3862540292,2771733936,1f2d5c58815a486a9e67220aad3133b0bd45d0fa,5ff7197abe3c121fdddbe1b29f3458a124f66fdc,d,d
::# NOTE: Ajouter les donnees CSV ESD completes ci-dessus pour le support multi-langue
::# (c) 2026 Ayi NEDJIMI Consultants - https://ayinedjimi-consultants.fr
