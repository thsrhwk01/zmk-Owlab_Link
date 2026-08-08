[CmdletBinding()]
param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"
$FirmwareName = "owlab_link_hotswap-zmk.bin"
$ExpectedVidPid = "1688:2220"
$DfuModeSelector = ",$ExpectedVidPid"
$ApplicationAddress = "0x08006000"
$MaximumImageSize = 0x1A000

function Stop-Flasher {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host ""
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

try {
    $FirmwarePath = Join-Path $PSScriptRoot $FirmwareName
    $DfuUtilPath = Join-Path $PSScriptRoot "dfu-util.exe"
    $LibusbPath = Join-Path $PSScriptRoot "libusb-1.0.dll"
    $ChecksumsPath = Join-Path $PSScriptRoot "SHA256SUMS.txt"

    if (-not (Test-Path -LiteralPath $FirmwarePath -PathType Leaf)) {
        Stop-Flasher "Firmware file not found: $FirmwareName"
    }

    if (-not $ValidateOnly) {
        foreach ($RequiredPath in @($DfuUtilPath, $LibusbPath, $ChecksumsPath)) {
            if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
                Stop-Flasher ("{0} is missing. Extract the complete ZIP before running this file." -f (Split-Path $RequiredPath -Leaf))
            }
        }
    }

    [byte[]]$Image = [System.IO.File]::ReadAllBytes($FirmwarePath)
    if ($Image.Length -lt 8) {
        Stop-Flasher "The firmware image is too small to contain a vector table."
    }

    if ($Image.Length -gt $MaximumImageSize) {
        Stop-Flasher ("The firmware image is {0} bytes; the LINK65 application partition is {1} bytes." -f $Image.Length, $MaximumImageSize)
    }

    [uint32]$InitialMsp = [System.BitConverter]::ToUInt32($Image, 0)
    [uint32]$ResetHandler = [System.BitConverter]::ToUInt32($Image, 4)
    [uint32]$ResetAddress = $ResetHandler -band 0xFFFFFFFE

    if (($InitialMsp -band 0x2FFFB000) -ne 0x20000000) {
        Stop-Flasher ("The firmware has an invalid initial stack pointer: 0x{0:X8}" -f $InitialMsp)
    }

    if (($ResetHandler -band 1) -eq 0 -or $ResetAddress -lt 0x08006000 -or $ResetAddress -ge 0x08020000) {
        Stop-Flasher ("The firmware has an invalid reset handler: 0x{0:X8}" -f $ResetHandler)
    }

    $FirmwareHash = (Get-FileHash -LiteralPath $FirmwarePath -Algorithm SHA256).Hash

    if (-not $ValidateOnly) {
        $ExpectedHashes = @{}
        foreach ($ChecksumLine in Get-Content -LiteralPath $ChecksumsPath) {
            if ($ChecksumLine -match '^([0-9A-Fa-f]{64})\s+\*?(.+)$') {
                $ExpectedHashes[$Matches[2]] = $Matches[1]
            }
        }

        foreach ($BundleFile in @($FirmwareName, "dfu-util.exe", "libusb-1.0.dll")) {
            if (-not $ExpectedHashes.ContainsKey($BundleFile)) {
                Stop-Flasher "SHA256SUMS.txt has no checksum for $BundleFile."
            }

            $BundlePath = Join-Path $PSScriptRoot $BundleFile
            $ActualHash = (Get-FileHash -LiteralPath $BundlePath -Algorithm SHA256).Hash
            if ($ActualHash -ne $ExpectedHashes[$BundleFile]) {
                Stop-Flasher "Checksum mismatch for $BundleFile. Download and extract the ZIP again."
            }
        }
    }

    Write-Host "LINK65 firmware image verified." -ForegroundColor Green
    Write-Host ("  File:          {0}" -f $FirmwareName)
    Write-Host ("  Size:          {0} bytes" -f $Image.Length)
    Write-Host ("  Reset handler: 0x{0:X8}" -f $ResetHandler)
    Write-Host ("  SHA-256:       {0}" -f $FirmwareHash)

    if ($ValidateOnly) {
        exit 0
    }

    Write-Host ""
    Write-Host "WARNING: Confirm the target keyboard before continuing." -ForegroundColor Yellow
    Write-Host "Only use this flasher with an Owlab LINK65 HOTSWAP PCB" -ForegroundColor Yellow
    Write-Host "that has an APM32F103CBT6 at U3." -ForegroundColor Yellow
    $Confirmation = Read-Host "Will you connect that exact board in DFU mode? [y/N]"
    if ([string]::IsNullOrWhiteSpace($Confirmation) -or $Confirmation.Trim() -notmatch '^y$') {
        Write-Host "Cancelled. Nothing was written to any device." -ForegroundColor Cyan
        exit 0
    }

    Write-Host ""
    Write-Host "Disconnect the keyboard." -ForegroundColor Cyan
    Write-Host "Hold the physical B button, connect USB, then release B." -ForegroundColor Cyan
    Write-Host "Waiting for LINK65 DFU device $ExpectedVidPid (press Ctrl+C to cancel)..."
    Write-Host ""

    & $DfuUtilPath -w -d $DfuModeSelector -a 0 -s $ApplicationAddress -D $FirmwarePath
    if ($LASTEXITCODE -ne 0) {
        Stop-Flasher ("dfu-util exited with code {0}. See README_KO.txt for driver help." -f $LASTEXITCODE)
    }

    Write-Host ""
    Write-Host "Flash complete." -ForegroundColor Green
    Write-Host "Disconnect USB, then reconnect it WITHOUT holding the B button." -ForegroundColor Cyan
    Write-Host "The keyboard should start as Owlab Link."
    exit 0
}
catch {
    Stop-Flasher $_.Exception.Message
}
