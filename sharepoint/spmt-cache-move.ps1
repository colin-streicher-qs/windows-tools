
# Stop SharePoint Migration Service
Write-Host "Stopping SharePoint Migration Service..."
Stop-Service -Name "SharePoint Migration Service" -Force

# Define paths
$OldPath = "$env:USERPROFILE\AppData\Roaming\Microsoft\SPMigration\Logs\Migration\MigrationToolStorage"
$NewPath = "D:\MigrationToolStorage"
$MigrationDir = "$env:USERPROFILE\AppData\Roaming\Microsoft\SPMigration\Logs\Migration"

# Create new folder on D: drive
Write-Host "Creating new folder at $NewPath..."
New-Item -ItemType Directory -Path $NewPath -Force

# Backup old cache folder if it exists
if (Test-Path $OldPath) {
    Write-Host "Backing up old cache folder..."
    Rename-Item -Path $OldPath -NewName "MigrationToolStorageOld"
}

# Navigate to original directory
Set-Location $MigrationDir

# Create symbolic link
Write-Host "Creating symbolic link..."
cmd /c mklink /D "MigrationToolStorage" "$NewPath"

# Restart SharePoint Migration Service
Write-Host "Starting SharePoint Migration Service..."
Start-Service -Name "SharePoint Migration Service"

Write-Host "Done! Cache is now redirected to $NewPath."

