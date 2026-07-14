<#
.SYNOPSIS
    Optimize-WindowsDisk.ps1 - A safe, interactive Windows disk cleanup and
    analysis tool.

.DESCRIPTION
    A menu-driven PowerShell script that helps you free up space on Windows by:
      1. Reporting free space
      2. Cleaning well-known junk locations (temp files, thumbnail cache,
         Windows Update cache, Recycle Bin)
      3. Analyzing the disk to find the biggest folders and files (read-only)
      4. Deleting a folder you choose (sent to the Recycle Bin, recoverable)
      5. Turning off hibernation to reclaim hiberfil.sys

    Design goals: conservative and transparent. It only ever clears the
    CONTENTS of known-safe junk locations automatically. It never touches your
    documents, programs, or app data on its own. Anything destructive requires
    you to type a confirmation.

.NOTES
    Author : Michael Thompson
    License : MIT
    Requires: Windows PowerShell 5.1 or PowerShell 7+
    Some actions require running as Administrator.

.EXAMPLE
    .\Optimize-WindowsDisk.ps1
    Launches the interactive menu.
#>

[CmdletBinding()]
param(
    [string]$Drive = "C"
)

# ------------------------------------------------------------------ helpers ---

function Get-FreeGB {
    param([string]$DriveLetter = $Drive)
    $d = Get-PSDrive -Name $DriveLetter
    return [math]::Round($d.Free / 1GB, 2)
}

function Get-TotalGB {
    param([string]$DriveLetter = $Drive)
    $d = Get-PSDrive -Name $DriveLetter
    return [math]::Round(($d.Free + $d.Used) / 1GB, 2)
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Clear-FolderContents {
    param([string]$Path, [string]$Label)

    if (Test-Path -LiteralPath $Path) {
        Write-Host "  Cleaning $Label ..." -NoNewline
        try {
            Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host " done." -ForegroundColor Green
        }
        catch {
            Write-Host " skipped (some files in use)." -ForegroundColor DarkYellow
        }
    }
    else {
        Write-Host "  $Label not found, skipping." -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------------------ actions ---

function Show-FreeSpace {
    $free  = Get-FreeGB
    $total = Get-TotalGB
    Write-Host ""
    Write-Host ("Drive {0}: {1} GB free of {2} GB total" -f $Drive, $free, $total) -ForegroundColor Cyan
}

function Invoke-JunkCleanup {
    Write-Host ""
    Write-Host "=== Cleaning junk files ===" -ForegroundColor Cyan
    if (-not (Test-IsAdmin)) {
        Write-Host "Note: not running as Administrator - protected locations will be skipped." -ForegroundColor DarkYellow
    }

    $before = Get-FreeGB

    # 1. Current user's temp folder
    Clear-FolderContents -Path $env:TEMP -Label "user temp files"

    # 2. System temp folder (needs admin)
    Clear-FolderContents -Path "$env:SystemRoot\Temp" -Label "Windows temp files"

    # 3. Thumbnail / icon cache
    Clear-FolderContents -Path "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Label "thumbnail cache"

    # 4. Empty the Recycle Bin (all drives)
    Write-Host "  Emptying Recycle Bin ..." -NoNewline
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Host " done." -ForegroundColor Green
    }
    catch { Write-Host " skipped." -ForegroundColor DarkYellow }

    # 5. Windows Update download cache (needs admin)
    Write-Host "  Cleaning Windows Update cache ..." -NoNewline
    try {
        Stop-Service -Name wuauserv -Force -ErrorAction Stop
        Clear-FolderContents -Path "$env:SystemRoot\SoftwareDistribution\Download" -Label "" | Out-Null
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        Write-Host " done." -ForegroundColor Green
    }
    catch {
        Write-Host " skipped (run as Administrator)." -ForegroundColor DarkYellow
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    }

    $after = Get-FreeGB
    Write-Host ("`n  Reclaimed: {0} GB" -f [math]::Round($after - $before, 2)) -ForegroundColor Green
    Write-Host "  Tip: for update backups and old Windows installs, also run 'cleanmgr'." -ForegroundColor Gray
}

function Invoke-DiskAnalysis {
    Write-Host ""
    Write-Host "=== Disk analysis (read-only, deletes nothing) ===" -ForegroundColor Cyan
    $root = "$Drive`:\"
    Write-Host "Scanning $root - this can take a few minutes..." -ForegroundColor Yellow

    # Top-level folders by size
    Write-Host "`n--- Top-level folders by size ---" -ForegroundColor Cyan
    Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $sum = (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        [PSCustomObject]@{
            SizeGB = [math]::Round(($sum / 1GB), 2)
            Folder = $_.FullName
        }
    } | Sort-Object SizeGB -Descending | Format-Table -AutoSize

    # Largest individual files
    Write-Host "--- 25 largest files ---" -ForegroundColor Cyan
    Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
        Sort-Object Length -Descending |
        Select-Object -First 25 |
        ForEach-Object {
            [PSCustomObject]@{
                SizeGB = [math]::Round(($_.Length / 1GB), 2)
                Path   = $_.FullName
            }
        } | Format-Table -AutoSize

    Write-Host "Scan complete. Nothing was deleted." -ForegroundColor Green
}

function Remove-FolderSafely {
    Write-Host ""
    Write-Host "=== Delete a folder (sent to Recycle Bin) ===" -ForegroundColor Cyan
    $path = Read-Host "Enter the FULL path of the folder to delete (or blank to cancel)"
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "That path does not exist." -ForegroundColor Red
        return
    }

    $sum = (Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
    $gb = [math]::Round(($sum / 1GB), 2)

    Write-Host ("`nTarget : {0}" -f $path)
    Write-Host ("Size   : {0} GB" -f $gb)
    Write-Host "It will be sent to the Recycle Bin (recoverable)." -ForegroundColor Cyan
    Write-Host "Note: folders too large for the Recycle Bin may be deleted permanently by Windows." -ForegroundColor DarkYellow

    $answer = Read-Host "`nType YES to delete this folder"
    if ($answer -ne "YES") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }

    try {
        Add-Type -AssemblyName Microsoft.VisualBasic
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $path,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
        Write-Host "Deleted (moved to Recycle Bin)." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Disable-Hibernation {
    Write-Host ""
    Write-Host "=== Turn off hibernation (reclaims hiberfil.sys) ===" -ForegroundColor Cyan
    if (-not (Test-IsAdmin)) {
        Write-Host "This requires Administrator. Re-run the script as admin." -ForegroundColor Red
        return
    }
    Write-Host "This deletes hiberfil.sys and disables Hibernate + Fast Startup." -ForegroundColor Yellow
    Write-Host "Reversible later with:  powercfg /hibernate on" -ForegroundColor Gray
    $answer = Read-Host "Type YES to turn hibernation off"
    if ($answer -ne "YES") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        return
    }
    powercfg /hibernate off
    Write-Host "Hibernation turned off." -ForegroundColor Green
}

# --------------------------------------------------------------------- menu ---

function Show-Menu {
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor White
    Write-Host "        Optimize-WindowsDisk" -ForegroundColor White
    Write-Host "==============================================" -ForegroundColor White
    Show-FreeSpace
    Write-Host ""
    Write-Host "  1. Show free space"
    Write-Host "  2. Clean junk files (temp, cache, update, recycle bin)"
    Write-Host "  3. Analyze disk - find biggest folders & files (read-only)"
    Write-Host "  4. Delete a folder I choose (to Recycle Bin)"
    Write-Host "  5. Turn off hibernation (reclaim hiberfil.sys)"
    Write-Host "  Q. Quit"
    Write-Host ""
}

# --------------------------------------------------------------------- main ---

do {
    Show-Menu
    $choice = Read-Host "Choose an option"
    switch ($choice.ToUpper()) {
        "1" { Show-FreeSpace }
        "2" { Invoke-JunkCleanup }
        "3" { Invoke-DiskAnalysis }
        "4" { Remove-FolderSafely }
        "5" { Disable-Hibernation }
        "Q" { Write-Host "`nGoodbye." -ForegroundColor Cyan }
        default { Write-Host "Invalid choice, try again." -ForegroundColor Red }
    }
    if ($choice.ToUpper() -ne "Q") {
        Write-Host "`nPress Enter to return to the menu..." -ForegroundColor DarkGray
        [void](Read-Host)
    }
} while ($choice.ToUpper() -ne "Q")
