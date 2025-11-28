# Move SharePoint Migration Tool Cache to Another Drive

This guide explains how to move the SharePoint Migration Tool (SPMT) cache from the default location on the **C:** drive to another drive (e.g., **D:**), using a PowerShell script and symbolic links.

---

## ✅ Prerequisites
- Windows OS
- Administrator privileges
- PowerShell execution policy set to allow running scripts

---

## ✅ Steps to Run the PowerShell Script

1. **Save the Script**
   - Copy the PowerShell script below into a file named `MoveSPMTCache.ps1`:

   ```powershell
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
   ```

2. **Run PowerShell as Administrator**
   - Right-click PowerShell and select **Run as administrator**.

3. **Set Execution Policy (if needed)**
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope Process
   ```

4. **Execute the Script**
   ```powershell
   .\MoveSPMTCache.ps1
   ```

---

## ✅ How to Verify the Symbolic Link

Run the following command in PowerShell:

```powershell
Get-ChildItem "$env:USERPROFILE\AppData\Roaming\Microsoft\SPMigration\Logs\Migration"
```

You should see `MigrationToolStorage` listed as a **symbolic link** pointing to `D:\MigrationToolStorage`.

---

## ✅ Optional Cleanup
- If you no longer need the old cache folder, you can delete it:

```powershell
Remove-Item "$env:USERPROFILE\AppData\Roaming\Microsoft\SPMigration\Logs\Migration\MigrationToolStorageOld" -Recurse -Force
```

---

### ✅ Notes
- Ensure the SharePoint Migration Service is stopped before creating the symbolic link.
- Always run scripts with **Administrator privileges**.
