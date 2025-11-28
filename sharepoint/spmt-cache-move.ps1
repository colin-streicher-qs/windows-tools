param(
    [Parameter(Mandatory=$false)]
    [string]$TargetPath = "D:\MigrationToolStorage"
)

# Error handling setup
$ErrorActionPreference = "Stop"
$script:ServiceStopped = $false

# Function to handle errors and cleanup
function Exit-Script {
    param([string]$ErrorMessage, [int]$ExitCode = 1)
    
    Write-Host "`nError: $ErrorMessage" -ForegroundColor Red
    
    # Restart service if it was stopped
    if ($script:ServiceStopped) {
        try {
            Write-Host "Attempting to restart SharePoint Migration Service..." -ForegroundColor Yellow
            Start-Service -Name "SharePoint Migration Service" -ErrorAction SilentlyContinue
            Write-Host "Service restarted." -ForegroundColor Green
        } catch {
            Write-Host "Warning: Could not restart SharePoint Migration Service. Please restart it manually." -ForegroundColor Yellow
        }
    }
    
    exit $ExitCode
}

# Check for administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Exit-Script "This script requires Administrator privileges. Please run PowerShell as Administrator."
}

# Validate target path
if ([string]::IsNullOrWhiteSpace($TargetPath)) {
    Exit-Script "Target path cannot be empty."
}

# Normalize the target path
try {
    $TargetPath = [System.IO.Path]::GetFullPath($TargetPath)
} catch {
    Exit-Script "Invalid target path format: $TargetPath"
}

# Check if target path is on a different drive than the source
$SourceDrive = Split-Path -Qualifier "$env:USERPROFILE"
$TargetDrive = Split-Path -Qualifier $TargetPath
if ($SourceDrive -eq $TargetDrive) {
    Write-Host "Warning: Target path is on the same drive as the source. This may not free up space on the C: drive." -ForegroundColor Yellow
    $response = Read-Host "Continue anyway? (Y/N)"
    if ($response -ne "Y" -and $response -ne "y") {
        Exit-Script "Operation cancelled by user." 0
    }
}

# Define paths
$OldPath = "$env:USERPROFILE\AppData\Roaming\Microsoft\SPMigration\Logs\Migration\MigrationToolStorage"
$MigrationDir = "$env:USERPROFILE\AppData\Roaming\Microsoft\SPMigration\Logs\Migration"

# Check if Migration directory exists
if (-not (Test-Path $MigrationDir)) {
    Exit-Script "Migration directory not found: $MigrationDir. Is SharePoint Migration Tool installed?"
}

# Check if SharePoint Migration Service exists
$serviceName = "SharePoint Migration Service"
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if (-not $service) {
    Exit-Script "SharePoint Migration Service not found. Is SharePoint Migration Tool installed?"
}

# Stop SharePoint Migration Service
try {
    Write-Host "Stopping SharePoint Migration Service..." -ForegroundColor Cyan
    if ($service.Status -eq "Running") {
        Stop-Service -Name $serviceName -Force -ErrorAction Stop
        $script:ServiceStopped = $true
        Write-Host "Service stopped successfully." -ForegroundColor Green
    } else {
        Write-Host "Service is already stopped." -ForegroundColor Yellow
    }
} catch {
    Exit-Script "Failed to stop SharePoint Migration Service: $($_.Exception.Message)"
}

# Create new folder on target drive
try {
    Write-Host "Creating new folder at $TargetPath..." -ForegroundColor Cyan
    if (-not (Test-Path $TargetPath)) {
        New-Item -ItemType Directory -Path $TargetPath -Force -ErrorAction Stop | Out-Null
        Write-Host "Folder created successfully." -ForegroundColor Green
    } else {
        Write-Host "Target folder already exists." -ForegroundColor Yellow
    }
} catch {
    Exit-Script "Failed to create target folder: $($_.Exception.Message)"
}

# Backup old cache folder if it exists
if (Test-Path $OldPath) {
    try {
        $backupPath = "$MigrationDir\MigrationToolStorageOld"
        Write-Host "Backing up old cache folder..." -ForegroundColor Cyan
        
        # Remove old backup if it exists
        if (Test-Path $backupPath) {
            Remove-Item -Path $backupPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        Rename-Item -Path $OldPath -NewName "MigrationToolStorageOld" -ErrorAction Stop
        Write-Host "Backup created successfully." -ForegroundColor Green
    } catch {
        Exit-Script "Failed to backup old cache folder: $($_.Exception.Message)"
    }
} else {
    Write-Host "No existing cache folder found to backup." -ForegroundColor Yellow
}

# Navigate to original directory
try {
    Set-Location $MigrationDir -ErrorAction Stop
} catch {
    Exit-Script "Failed to navigate to Migration directory: $($_.Exception.Message)"
}

# Check if symbolic link already exists
$linkPath = "$MigrationDir\MigrationToolStorage"
if (Test-Path $linkPath) {
    $item = Get-Item $linkPath -ErrorAction SilentlyContinue
    if ($item.LinkType -eq "SymbolicLink") {
        $currentTarget = (Get-Item $linkPath).Target
        if ($currentTarget -eq $TargetPath) {
            Write-Host "Symbolic link already exists and points to the correct location." -ForegroundColor Green
        } else {
            Exit-Script "A symbolic link already exists pointing to: $currentTarget. Please remove it first."
        }
    } else {
        Exit-Script "A file or folder named 'MigrationToolStorage' already exists and is not a symbolic link. Please remove it first."
    }
} else {
    # Create symbolic link
    try {
        Write-Host "Creating symbolic link..." -ForegroundColor Cyan
        $result = cmd /c mklink /D "MigrationToolStorage" "$TargetPath" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "mklink command failed: $result"
        }
        Write-Host "Symbolic link created successfully." -ForegroundColor Green
    } catch {
        Exit-Script "Failed to create symbolic link: $($_.Exception.Message)"
    }
}

# Restart SharePoint Migration Service
try {
    Write-Host "Starting SharePoint Migration Service..." -ForegroundColor Cyan
    Start-Service -Name $serviceName -ErrorAction Stop
    $script:ServiceStopped = $false
    Write-Host "Service started successfully." -ForegroundColor Green
} catch {
    Exit-Script "Failed to start SharePoint Migration Service: $($_.Exception.Message). Please start it manually."
}

Write-Host "`nDone! Cache is now redirected to $TargetPath." -ForegroundColor Green
Write-Host "You can verify the symbolic link using the methods described in the README." -ForegroundColor Cyan
