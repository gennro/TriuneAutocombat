@echo off
setlocal
echo [TriuneAutocombat Updater]

:: Check if Python is available
where python >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo Launching Python updater...
    python "%~dp0triune_updater.py" %*
    goto :end
)

where py >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo Launching Python updater via py launcher...
    py "%~dp0triune_updater.py" %*
    goto :end
)

echo Python 3 is not installed on this system. Running PowerShell fallback updater...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$repo = 'gennro/TriuneAutocombat'; ^
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; ^
    Write-Host '[INFO] Fetching latest release info from GitHub...' -ForegroundColor Cyan; ^
    $rel = Invoke-RestMethod -Uri \"https://api.github.com/repos/$repo/releases/latest\" -UserAgent \"TriuneUpdater\"; ^
    $tag = $rel.tag_name; ^
    Write-Host \"[INFO] Latest Release Tag: $tag\" -ForegroundColor Green; ^
    $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1; ^
    if (-not $asset) { $url = $rel.zipball_url } else { $url = $asset.browser_download_url }; ^
    $tmp = [System.IO.Path]::GetTempFileName() + '.zip'; ^
    Write-Host '[INFO] Downloading update archive...' -ForegroundColor Cyan; ^
    $wc = New-Object System.Net.WebClient; ^
    $wc.Headers.Add('User-Agent', 'TriuneUpdater'); ^
    $wc.DownloadFile($url, $tmp); ^
    Write-Host '[INFO] Extracting update archive...' -ForegroundColor Cyan; ^
    $targetDir = (Resolve-Path '%~dp0..').Path; ^
    Expand-Archive -Path $tmp -DestinationPath $targetDir -Force; ^
    Remove-Item $tmp -Force; ^
    Write-Host '[SUCCESS] Update applied successfully!' -ForegroundColor Green;"

:end
endlocal
