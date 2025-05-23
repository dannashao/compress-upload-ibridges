@echo off
setlocal enabledelayedexpansion

chcp 65001 >nul
set "LONG_PATH_PREFIX=//?/"

:start

:: ======== CONFIGURATION ========
:: Change your target folder, output directory and split size here! (Set split size smaller than 8192m if uploading to YODA). For your remote path if you wish to upload after compression, check with "ibridges list".
:: Note: You will need ibridges in PATH and ibridges config .json file at default directory to upload with this script! To check this, input and run "ibridges init" in cmd to see if it returns success.
set "FOLDER=G:\SAI2"
set "OUTPUT_DIR=G:\"
set "REMOTE_PATH=/nluu6p/home/research-me-test/SAI2"

set "SPLIT=1m"

:: 7z.exe location (Must use 7-zip with zstd!)
set "ZIP=C:\Program Files\7-Zip-Zstandard\7z.exe"
:: ibridges config .json file location
set "IBRIDGES_CONFIG=D:\\Danna\\irods_env.json"

:: ==== EMAIL CONFIGURATION ====
:: Adjust if you need to get an email after the compression is finished.
:: Do not enable/modify if you don't know how OAuth work.
:: Usually it takes 6~7 hours to compress 1TB
set "SEND_EMAIL=false"
set "EMAIL_TO=recipient@example.com"
set "EMAIL_FROM=your_email@gmail.com"
set "EMAIL_SUBJECT=Compression Report"
set "EMAIL_BODY_FILE=email_body.txt"
set "CRED_FILE=oauth_credentials.txt"
set "TOKEN_FILE=current_token.txt"
set "SMTP_SERVER=smtp.gmail.com"
set "SMTP_PORT=587"
:: ======== END OF CONFIGURATION BLOCK ========

set choice=
echo.
echo ===== CONFIGURATION CHECK =====
echo Please make sure that ibridges_uploader.py is in the same directory as this script, then verify the following settings in the CONFIGURATION section:
echo   - FOLDER: %FOLDER%
echo   - OUTPUT_DIR: %OUTPUT_DIR%
echo   - SPLIT: %SPLIT%
echo   - REMOTE_PATH: %REMOTE_PATH%
echo System requirements:
echo   - 7z.exe (zstd version) location: %ZIP%
echo   - IBRIDGES_CONFIG: %IBRIDGES_CONFIG%
echo.
echo Have you edited these settings to match your purpose? (Caution: Make sure your output directory is empty (recommended), or does not contain folders named "source" and "exported".)
echo [Y] Yes, proceed with compression
echo [N] No, I need to edit the script
echo.
set /p choice=Enter your choice [Y/N]: 
set "choice=!choice:~0,1!"
if /i "!choice!"=="Y" goto yes
if /i "!choice!"=="N" goto no
echo.
echo Invalid input. Please enter Y or N.
goto start

:no
echo.
echo ===== ACTION REQUIRED =====
echo Please edit the script (right-click -- edit) and modify the CONFIGURATION section.
echo Make sure all paths are correct before running again.
echo.
pause
exit /b 1

:yes
:: ==== INITIAL setUP ====
for %%A in ("%FOLDER%") do set "ARCHIVE_NAME=%%~nxA"
set "SOURCE_DIR=%OUTPUT_DIR%\source"
set "EXPORTED_DIR=%OUTPUT_DIR%\exported"
if not exist "%SOURCE_DIR%" mkdir "%SOURCE_DIR%"
if not exist "%EXPORTED_DIR%" mkdir "%EXPORTED_DIR%"
set "SOURCE_ARCHIVE=%SOURCE_DIR%\source"
set "EXPORTED_ARCHIVE=%EXPORTED_DIR%\exported"
set "SOURCE_LOG=%SOURCE_DIR%\source_log.txt"
set "EXPORTED_LOG=%EXPORTED_DIR%\exported_log.txt"
set "COMPRESS_ARGS=a -t7z -m0=zstd -mx=9 -ms=on -mmt=20 -bsp1 -v%SPLIT%"
set "MAX_RETRIES=3"

:: Check if paths are UNC
set "IS_UNC_FOLDER=false"
set "IS_UNC_OUTPUT=false"
echo %FOLDER% | findstr /r "^\\\\" >nul && set "IS_UNC_FOLDER=true"
echo %OUTPUT_DIR% | findstr /r "^\\\\" >nul && set "IS_UNC_OUTPUT=true"

:: ==== PATH VALIDATION ====
echo Checking prerequisites...
if not exist "%ZIP%" (
    echo ERROR: 7-Zip not found at "%ZIP%"
    pause
    exit /b 1
)

:: Check input folder
if "!IS_UNC_FOLDER!"=="true" (
    net use >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Unable to access network resources. Please check your network connection.
        pause
        exit /b 1
    )
    dir "!FOLDER!" >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Input folder "!FOLDER!" does not exist or is not accessible.
        pause
        exit /b 1
    )
) else (
    if not exist "%FOLDER%" (
        echo ERROR: Input folder "%FOLDER%" does not exist.
        pause
        exit /b 1
    )
)

:: Check output directory
if "!IS_UNC_OUTPUT!"=="true" (
    net use >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Unable to access network resources. Please check your network connection.
        pause
        exit /b 1
    )
    dir "!OUTPUT_DIR!" >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Output directory "!OUTPUT_DIR!" does not exist or is not accessible.
        pause
        exit /b 1
    )
) else (
    if not exist "%OUTPUT_DIR%" (
        echo ERROR: Output directory "%OUTPUT_DIR%" does not exist.
        pause
        exit /b 1
    )
)

echo All paths verified.


:: ==== IRODS UPLOAD CHOICE ====
echo.
echo Choose upload mode (You will need ibridges in PATH and ibridges config .json file at default directory to upload with this script! To check this, input and run "ibridges init" in cmd to see if it returns success.):
echo [1] [Recommended for large files] Auto-upload after compression during off-peak hours (20:00-06:00)
echo [2] Auto-upload directly after compression
echo [3] Prompt before upload
echo [4] Compress only
set /p upload_choice=Enter choice [1/2/3/4]: 
if "%upload_choice%"=="1" (
    set "UPLOAD_MODE=auto_wait"
) else if "%upload_choice%"=="2" (
    set "UPLOAD_MODE=auto_now"
) else if "%upload_choice%"=="3" (
    set "UPLOAD_MODE=prompt"
) else if "%upload_choice%"=="4" (
    set "UPLOAD_MODE=compress_only"
) else (
    echo Invalid choice. Defaulting to compress only.
    set "UPLOAD_MODE=compress_only"
)
echo Upload mode selected: !UPLOAD_MODE!


:: ==== BEGIN ====
goto :begin_compression

:: ==== TIMESTAMP FUNCTION (European Format) ====
:now
for /f "tokens=2-4 delims=/ " %%a in ("%date%") do (
    set "d=%%a/%%b/%%c"
)
for /f "tokens=1-2 delims=:." %%a in ("%time%") do (
    set "t=%%a:%%b"
)
set "timestamp=[!d! !t!]"
goto :eof

:: ==== REFRESH OAUTH TOKEN ====
:refresh_token
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$cred = Get-Content '%CRED_FILE%' | ForEach-Object { ($_ -split '=')[0,1] } | ForEach-Object -Begin { $o = @{} } -Process { $o[$_[0]] = $_[1] } -End { $o };" ^
  "$body = @{client_id=$cred.client_id; client_secret=$cred.client_secret; refresh_token=$cred.refresh_token; grant_type='refresh_token'};" ^
  "$response = Invoke-RestMethod -Uri 'https://oauth2.googleapis.com/token' -Method POST -Body $body;" ^
  "$response.access_token | Out-File -Encoding ascii '%TOKEN_FILE%'"
goto :eof

:: ==== START MAIN PROCESS ====
:begin_compression
echo Starting compression of "%FOLDER%"...
set "RETRY_COUNT=0"
set "SOURCE_SUCCESS=false"
set "EXPORTED_SUCCESS=false"
goto :retry_source

:: ==== COMPRESS .tar FILES (source) ====
:retry_source
:: Cleanup
for %%F in ("%SOURCE_ARCHIVE%.7z*") do del "%%F" >nul 2>&1
if exist "%SOURCE_DIR%\source.sha256" del "%SOURCE_DIR%\source.sha256" >nul 2>&1
if exist "%SOURCE_LOG%" del "%SOURCE_LOG%" >nul 2>&1
if exist "%EMAIL_BODY_FILE%" del "%EMAIL_BODY_FILE%" >nul 2>&1
call :now

echo !timestamp! === Attempt !RETRY_COUNT! to compress .tar files ===
echo !timestamp! === Attempt !RETRY_COUNT! to compress .tar files === >> "%SOURCE_LOG%"
set "TAR_LIST="
for %%F in ("%FOLDER%\*.tar") do (
  if exist "%%F" set "TAR_LIST=!TAR_LIST! "%%F""
)
if not defined TAR_LIST (
  echo No .tar files found in %FOLDER%.
  echo No .tar files found in %FOLDER%. >> "%SOURCE_LOG%"
  set "SOURCE_SUCCESS=true"
  goto :after_source
)
call :now
echo !timestamp! Compressing .tar files...
echo !timestamp! Compressing .tar files... >> "%SOURCE_LOG%"
"%ZIP%" %COMPRESS_ARGS% "%SOURCE_ARCHIVE%" !TAR_LIST! 2>> "%SOURCE_LOG%"
if errorlevel 1 (
    call :now
    echo !timestamp! Compression failed. Retrying...
    echo !timestamp! Compression failed. Retrying... >> "%SOURCE_LOG%"
    set /a RETRY_COUNT+=1
    if !RETRY_COUNT! GEQ %MAX_RETRIES% (
        echo Compression failed after %MAX_RETRIES% attempts.
        echo Compression failed after %MAX_RETRIES% attempts. >> "%SOURCE_LOG%"
        set "FAIL_REASON=Compression failure (source)"
        goto :after_source
    )
    goto :retry_source
)
call :now
echo !timestamp! Generating checksums...
echo !timestamp! Generating checksums... >> "%SOURCE_LOG%"
for %%F in ("%SOURCE_ARCHIVE%.7z.*") do (
    certutil -hashfile "%%F" SHA256 >> "%SOURCE_DIR%\source.sha256" 2>>"%SOURCE_LOG%"
)
call :now
echo !timestamp! Verifying archive integrity...
echo !timestamp! Verifying archive integrity... >> "%SOURCE_LOG%"
if exist "%SOURCE_ARCHIVE%.7z.001" (
    "%ZIP%" t "%SOURCE_ARCHIVE%.7z.001" >> "%SOURCE_LOG%" 2>&1
) else (
    "%ZIP%" t "%SOURCE_ARCHIVE%.7z" >> "%SOURCE_LOG%" 2>&1
)
if errorlevel 1 (
    call :now
    echo !timestamp! Verification failed. Retrying...
    echo !timestamp! Verification failed. Retrying... >> "%SOURCE_LOG%"
    set /a RETRY_COUNT+=1
    if !RETRY_COUNT! GEQ %MAX_RETRIES% (
        echo Verification failed after %MAX_RETRIES% attempts.
        echo Verification failed after %MAX_RETRIES% attempts. >> "%SOURCE_LOG%"
        set "FAIL_REASON=Verification failure (source)"
        goto :after_source
    )
    goto :retry_source
)
call :now
echo !timestamp! Done. Archive verified successfully.
echo !timestamp! Done. Archive verified successfully. >> "%SOURCE_LOG%"
set "SOURCE_SUCCESS=true"

:after_source
set "RETRY_COUNT=0"

:: ==== COMPRESS OTHER (exported) FILES ====
:retry_exported
:: Cleanup
for %%F in ("%EXPORTED_ARCHIVE%.7z*") do del "%%F" >nul 2>&1
if exist "%EXPORTED_DIR%\exported.sha256" del "%EXPORTED_DIR%\exported.sha256" >nul 2>&1
if exist "%EXPORTED_LOG%" del "%EXPORTED_LOG%" >nul 2>&1
if exist "%EMAIL_BODY_FILE%" del "%EMAIL_BODY_FILE%" >nul 2>&1

call :now
echo !timestamp! === Attempt !RETRY_COUNT! to compress exported files ===
echo !timestamp! === Attempt !RETRY_COUNT! to compress exported files === >> "%EXPORTED_LOG%"

:: First, check if there are any non-tar files or folders
set "HAS_EXPORTED=false"
if "!IS_UNC_FOLDER!"=="true" (
    net use >nul 2>&1
    if errorlevel 1 (
        echo ERROR: Unable to access network resources. Please check your network connection.
        pause
        exit /b 1
    )
    for /f "delims=" %%F in ('dir /b /s "!FOLDER!\*" ^| findstr /v /i "\\source\\ \\exported\\" ^| findstr /v /i "\.tar$"') do (
        set "HAS_EXPORTED=true"
        goto :found_exported
    )
) else (
    for /f "delims=" %%F in ('dir /b /s "%FOLDER%\*" ^| findstr /v /i "\\source\\ \\exported\\" ^| findstr /v /i "\.tar$"') do (
        set "HAS_EXPORTED=true"
        goto :found_exported
    )
)

:found_exported
if "!HAS_EXPORTED!"=="false" (
    echo No exported files/folders found in !FOLDER!.
    echo No exported files/folders found in !FOLDER!. >> "%EXPORTED_LOG%"
    set "EXPORTED_SUCCESS=true"
    goto :after_exported
)

:: Create a temporary file to store the file list
set "TEMP_LIST=%TEMP%\export_list.txt"
if exist "%TEMP_LIST%" del "%TEMP_LIST%" >nul 2>&1

:: Get all files and folders recursively, excluding .tar files and output directories
if "!IS_UNC_FOLDER!"=="true" (
    dir /b /s "!FOLDER!\*" | findstr /v /i "\\source\\ \\exported\\" | findstr /v /i "\.tar$" > "%TEMP_LIST%"
) else (
    dir /b /s "%FOLDER%\*" | findstr /v /i "\\source\\ \\exported\\" | findstr /v /i "\.tar$" > "%TEMP_LIST%"
)

:: Check if we found any files
set "EXPORT_LIST="
for /f "usebackq delims=" %%F in ("%TEMP_LIST%") do (
    :: Get the relative path from FOLDER
    set "FULL_PATH=%%F"
    set "REL_PATH=!FULL_PATH:%FOLDER%\=!"
    :: Double check to exclude any .tar files that might have slipped through
    echo "!REL_PATH!" | findstr /i "\.tar$" >nul || (
        set "EXPORT_LIST=!EXPORT_LIST! "!REL_PATH!""
    )
)

if not defined EXPORT_LIST (
    echo No exported files/folders found in !FOLDER!.
    echo No exported files/folders found in !FOLDER!. >> "%EXPORTED_LOG%"
    set "EXPORTED_SUCCESS=true"
    del "%TEMP_LIST%" >nul 2>&1
    goto :after_exported
)

call :now
echo !timestamp! Compressing exported files/folders...
echo !timestamp! Compressing exported files/folders... >> "%EXPORTED_LOG%"

:: Create a temporary directory for the file list
set "TEMP_DIR=%TEMP%\compress_list"
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"

:: Create a file list with relative paths
type nul > "%TEMP_DIR%\filelist.txt"
for /f "usebackq delims=" %%F in ("%TEMP_LIST%") do (
    set "FULL_PATH=%%F"
    set "REL_PATH=!FULL_PATH:%FOLDER%\=!"
    echo "!REL_PATH!" >> "%TEMP_DIR%\filelist.txt"
)

:: Change to the source directory and compress
if "!IS_UNC_FOLDER!"=="true" (
    pushd "!FOLDER!"
) else (
    pushd "%FOLDER%"
)

:: Use the correct path format for the output archive
if "!IS_UNC_OUTPUT!"=="true" (
    "%ZIP%" %COMPRESS_ARGS% "!EXPORTED_ARCHIVE!" @"%TEMP_DIR%\filelist.txt" 2>> "%EXPORTED_LOG%"
) else (
    "%ZIP%" %COMPRESS_ARGS% "%EXPORTED_ARCHIVE%" @"%TEMP_DIR%\filelist.txt" 2>> "%EXPORTED_LOG%"
)
popd

if errorlevel 1 (
    call :now
    echo !timestamp! Compression failed. Retrying...
    echo !timestamp! Compression failed. Retrying... >> "%EXPORTED_LOG%"
    set /a RETRY_COUNT+=1
    if !RETRY_COUNT! GEQ %MAX_RETRIES% (
        echo Compression failed after %MAX_RETRIES% attempts.
        echo Compression failed after %MAX_RETRIES% attempts. >> "%EXPORTED_LOG%"
        set "FAIL_REASON=Compression failure (exported)"
        rmdir /s /q "%TEMP_DIR%" >nul 2>&1
        del "%TEMP_LIST%" >nul 2>&1
        goto :after_exported
    )
    rmdir /s /q "%TEMP_DIR%" >nul 2>&1
    del "%TEMP_LIST%" >nul 2>&1
    goto :retry_exported
)

:: Clean up temp files
rmdir /s /q "%TEMP_DIR%" >nul 2>&1
del "%TEMP_LIST%" >nul 2>&1

call :now
echo !timestamp! Generating checksums...
echo !timestamp! Generating checksums... >> "%EXPORTED_LOG%"
for %%F in ("%EXPORTED_ARCHIVE%.7z.*") do (
    certutil -hashfile "%%F" SHA256 >> "%EXPORTED_DIR%\exported.sha256" 2>>"%EXPORTED_LOG%"
)
call :now
echo !timestamp! Verifying archive integrity...
echo !timestamp! Verifying archive integrity... >> "%EXPORTED_LOG%"
if exist "%EXPORTED_ARCHIVE%.7z.001" (
    "%ZIP%" t "%EXPORTED_ARCHIVE%.7z.001" >> "%EXPORTED_LOG%" 2>&1
) else (
    "%ZIP%" t "%EXPORTED_ARCHIVE%.7z" >> "%EXPORTED_LOG%" 2>&1
)
if errorlevel 1 (
    call :now
    echo !timestamp! Verification failed. Retrying...
    echo !timestamp! Verification failed. Retrying... >> "%EXPORTED_LOG%"
    set /a RETRY_COUNT+=1
    if !RETRY_COUNT! GEQ %MAX_RETRIES% (
        echo Verification failed after %MAX_RETRIES% attempts.
        echo Verification failed after %MAX_RETRIES% attempts. >> "%EXPORTED_LOG%"
        set "FAIL_REASON=Verification failure (exported)"
        goto :after_exported
    )
    goto :retry_exported
)
call :now
echo !timestamp! Done. Archive verified successfully.
echo !timestamp! Done. Archive verified successfully. >> "%EXPORTED_LOG%"
set "EXPORTED_SUCCESS=true"

:after_exported
:: ==== UPLOAD LOGIC ====
if "!SOURCE_SUCCESS!"=="false" (
    echo Source compression/verification failed. Skipping upload.
    goto :exit_done
)
if "!EXPORTED_SUCCESS!"=="false" (
    echo Exported compression/verification failed. Skipping upload.
    goto :exit_done
)

if "!UPLOAD_MODE!"=="compress_only" (
    echo Upload skipped due to user choice.
    goto :exit_done
)

:: Set wait_off_peak based on upload mode
if "!UPLOAD_MODE!"=="auto_wait" (
    set "WAIT_OFF_PEAK=true"
    goto :do_upload
) else if "!UPLOAD_MODE!"=="auto_now" (
    set "WAIT_OFF_PEAK=false"
    goto :do_upload
) else if "!UPLOAD_MODE!"=="prompt" (
    echo.
    echo ===== UPLOAD CONFIRMATION =====
    echo Compression completed successfully.
    echo.
    echo [1] Start upload now
    echo [2] Start upload at off-peak hours (20:00-06:00)
    echo [3] Skip upload
    echo.
    set /p user_upload=Enter your choice [1/2/3]: 
    if "!user_upload!"=="1" (
        set "WAIT_OFF_PEAK=false"
        goto :do_upload
    ) else if "!user_upload!"=="2" (
        set "WAIT_OFF_PEAK=true"
        goto :do_upload
    ) else if "!user_upload!"=="3" (
        echo.
        echo Upload skipped by user.
        goto :exit_done
    ) else (
        echo.
        echo Invalid input. Please enter 1, 2, or 3.
        goto :after_exported
    )
)

:do_upload
:: Upload source files
echo.
echo ===== STARTING UPLOAD =====
echo Starting uploader for source...
for %%A in ("%SOURCE_DIR%") do set "SOURCE_DIR=%%~A"
if not "%SOURCE_DIR:~-1%"=="\" set "SOURCE_DIR=%SOURCE_DIR%\"
set "SOURCE_DIR=%SOURCE_DIR%."
python ibridges_uploader.py "%SOURCE_DIR%" "source" "%REMOTE_PATH%" !WAIT_OFF_PEAK! "%IBRIDGES_CONFIG%"

:: Upload exported files
echo.
echo Starting uploader for exported...
for %%A in ("%EXPORTED_DIR%") do set "EXPORTED_DIR=%%~A"
if not "%EXPORTED_DIR:~-1%"=="\" set "EXPORTED_DIR=%EXPORTED_DIR%\"
set "EXPORTED_DIR=%EXPORTED_DIR%."
python ibridges_uploader.py "%EXPORTED_DIR%" "exported" "%REMOTE_PATH%" !WAIT_OFF_PEAK! "%IBRIDGES_CONFIG%"

goto :exit_done
:exit_done
pause
exit /b 0
