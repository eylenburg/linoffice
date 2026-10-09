# Script to monitor if there is a sleep_marker created by LinOffice (indicating the Linux host was suspended) in order to trigger a time sync as the time in the Windows VM will otherwise drift while Linux is suspended.

# Candidate shares and marker files. The linoffice drive is preferred.
# The legacy home share is kept so an existing VM still sees sleep_marker.
# C:\OEM\linoffice_paths.txt may prepend a SleepMarker= path.
$networkCandidates = @(
    "\\tsclient\linoffice",
    "\\tsclient\home"
)
$fileCandidates = @(
    "\\tsclient\linoffice\sleep_marker",
    "\\tsclient\home\.local\share\linoffice\sleep_marker"
)
$pathsFile = "C:\OEM\linoffice_paths.txt"
if (Test-Path $pathsFile) {
    foreach ($line in Get-Content -Path $pathsFile -Encoding UTF8) {
        if ($line -match '^SleepMarker=(.+)$') {
            $fileCandidates = @($matches[1].Trim()) + $fileCandidates
        }
    }
}

# Function to check and handle file
function Monitor-File {
    while ($true) {
        $shareUp = $false
        foreach ($networkPath in $networkCandidates) {
            try {
                if (Test-Path -Path $networkPath -ErrorAction Stop) {
                    $shareUp = $true
                    break
                }
            }
            catch {
                # This share is not available; try the next one.
            }
        }

        if ($shareUp) {
            $found = $false
            foreach ($filePath in $fileCandidates) {
                try {
                    if (Test-Path -Path $filePath) {
                        $found = $true
                        break
                    }
                }
                catch {
                }
            }
            if ($found) {
                w32tm /resync
                foreach ($filePath in $fileCandidates) {
                    try {
                        if (Test-Path -Path $filePath) {
                            Remove-Item -Path $filePath -Force
                        }
                    }
                    catch {
                    }
                }
            }
        }

        # Wait 60 seconds before next check
        Start-Sleep -Seconds 60
    }
}

# Start monitoring silently
Monitor-File