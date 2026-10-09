# Script to create a success marker file in Linux home folder if Office is installed and clean up quick access to pin the home folder shared through RDP
$logFile = "C:\OEM\setup_rdp.log"
$timeoutSeconds = 60  # 1 minute timeout for QuickAccess.ps1 execution

# Function to write to log
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp $Message" | Out-File -FilePath $logFile -Append
}

# Check if we're in an RDP session
function Is-RDPSession {
    return [bool](Get-CimInstance -ClassName Win32_TerminalServiceSetting -Namespace root\cimv2\TerminalServices)
}

try {
    # Check if we're in an RDP session
    if (-not (Is-RDPSession)) {
        Write-Log "Not in RDP session, exiting..."
        exit 1
    }

    Write-Log "RDP session detected"

    # Proceed when either the linoffice share or the legacy home share is accessible.
    # C:\OEM\linoffice_paths.txt may prepend a Success= path.
    $shareCandidates = @(
        "\\tsclient\linoffice",
        "\\tsclient\home\.local\share\linoffice"
    )
    $successCandidates = @(
        "\\tsclient\linoffice\success",
        "\\tsclient\home\.local\share\linoffice\success"
    )
    $pathsFile = "C:\OEM\linoffice_paths.txt"
    if (Test-Path $pathsFile) {
        foreach ($line in Get-Content -Path $pathsFile -Encoding UTF8) {
            if ($line -match '^Success=(.+)$') {
                $successCandidates = @($matches[1].Trim()) + $successCandidates
            }
        }
    }
    $shareOk = $false
    foreach ($share in $shareCandidates) {
        if (Test-Path $share) {
            Write-Log "$share is accessible"
            $shareOk = $true
            break
        }
    }
    if ($shareOk) {

        # Run QuickAccess.ps1
        Write-Log "Running QuickAccess.ps1..."
        $job = Start-Job -ScriptBlock { & "C:\OEM\QuickAccess.ps1" }
        $result = Wait-Job -Job $job -Timeout $timeoutSeconds

        if ($result) {
            if ($job.State -eq "Completed" -and $job.HasMoreData) {
                $output = Receive-Job -Job $job
                Write-Log "QuickAccess.ps1 completed successfully"
            } else {
            Write-Log "QuickAccess.ps1 failed"
            }
        } else {
            Write-Log "QuickAccess.ps1 timed out after $timeoutSeconds seconds"
        }

        # Determine installation status: either success marker exists or Office binaries are present
        Write-Log "Checking for C:\OEM\success or installed Office binaries..."
        while (-not (Test-Path "C:\OEM\success") -and -not (Test-Path "C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE")) {
            Write-Log "No success marker yet and Office not detected, waiting..."
            Start-Sleep -Seconds 5
        }
        if (Test-Path "C:\OEM\success") {
            Write-Log "C:\OEM\success found, proceeding..."
        } elseif (Test-Path "C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE") {
            Write-Log "Office binaries detected; proceeding to create Linux-side success marker."
        }

        # Write success to every reachable target (new share, then the legacy home share).
        Write-Log "Creating success file on the LinOffice share and \\tsclient\home\.local\share\linoffice\success..."
        $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $wrote = $false
        foreach ($target in $successCandidates) {
            try {
                $parent = Split-Path $target -Parent
                if (Test-Path $parent) {
                    $currentTime | Out-File -FilePath $target -Force
                    if ($?) {
                        $wrote = $true
                        Write-Log "success file created at ${target} with timestamp: $currentTime"
                    }
                }
            } catch {
                Write-Log "Failed to create success file at ${target}: $_"
            }
        }
        if (-not $wrote) {
            Write-Log "Failed to create success file"
            exit 1
        }

        # Disconnect RDP session
        Write-Log "Disconnecting RDP session..."
        tsdiscon
        exit 0
    } else {
        Write-Log "\\tsclient\linoffice and \\tsclient\home\.local\share\linoffice are not accessible yet"
        exit 1
    }
} catch {
    Write-Log "Error in RunQuickAccess.ps1: $_"
    exit 1
} finally {
    # Terminate QuickAccess.ps1 if it is still running for some reason
    if ($job -ne $null) {
        Remove-Job -Job $job -Force
    }
}