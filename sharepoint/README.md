# Move SharePoint Migration Tool Cache to Another Drive

This guide explains how to move the SharePoint Migration Tool (SPMT) cache from the default location on the **C:** drive to another drive (e.g., **D:**), using a PowerShell script and symbolic links.

---

## ✅ Prerequisites
- Windows OS
- Administrator privileges
- PowerShell execution policy set to allow running scripts

---

## ✅ Steps to Run the PowerShell Script

1. **Run PowerShell as Administrator**
   - Right-click PowerShell and select **Run as administrator**.

2. **Set Execution Policy (if needed)**
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope Process
   ```

3. **Navigate to the Script Directory**
   ```powershell
   cd path\to\windows-tools\sharepoint
   ```

4. **Execute the Script**
   
   **Default usage** (uses `D:\MigrationToolStorage` as the target):
   ```powershell
   .\spmt-cache-move.ps1
   ```
   
   **Custom target path** (specify your own target directory):
   ```powershell
   .\spmt-cache-move.ps1 -TargetPath "E:\MyCacheFolder"
   ```
   
   > **Note:** The script includes comprehensive error handling and will automatically restart the SharePoint Migration Service if any errors occur during execution.

---

## ✅ How to Verify the Symbolic Link

There are several ways to verify that the symbolic link was created successfully in Windows:

### Method 1: PowerShell (Recommended)

1. **Open PowerShell** (no need for administrator privileges for verification)

2. **Check the directory contents:**
   ```powershell
   Get-ChildItem "$env:USERPROFILE\AppData\Roaming\Microsoft\SPMigration\Logs\Migration"
   ```

3. **Look for the LinkType property:**
   ```powershell
   Get-ChildItem "$env:USERPROFILE\AppData\Roaming\Microsoft\SPMigration\Logs\Migration" | Select-Object Name, LinkType, Target
   ```
   
   You should see `MigrationToolStorage` with:
   - **LinkType**: `SymbolicLink`
   - **Target**: The path you specified (default: `D:\MigrationToolStorage`)

4. **Verify the target path exists:**
   ```powershell
   Test-Path "D:\MigrationToolStorage"
   ```
   > **Note:** Replace `D:\MigrationToolStorage` with your custom target path if you used the `-TargetPath` parameter.
   
   This should return `True`.

### Method 2: File Explorer

1. **Navigate to the directory:**
   - Press `Win + R`, type `%USERPROFILE%\AppData\Roaming\Microsoft\SPMigration\Logs\Migration`, and press Enter
   - Or manually navigate: `C:\Users\[YourUsername]\AppData\Roaming\Microsoft\SPMigration\Logs\Migration`

2. **Look for visual indicators:**
   - The `MigrationToolStorage` folder will have a **small arrow icon** overlay, indicating it's a shortcut/symbolic link
   - When you hover over it, you may see the target path in a tooltip

3. **Verify by accessing:**
   - Double-click the `MigrationToolStorage` folder
   - It should open and show the contents from your target directory (default: `D:\MigrationToolStorage`)
   - Check that files created in this location actually appear on the target drive

### Method 3: Command Prompt

1. **Open Command Prompt** (cmd.exe)

2. **Use the `dir` command with `/AL` flag:**
   ```cmd
   dir "%USERPROFILE%\AppData\Roaming\Microsoft\SPMigration\Logs\Migration" /AL
   ```
   
   The `/AL` flag shows only symbolic links. You should see `MigrationToolStorage` listed.

3. **Check the link target:**
   ```cmd
   dir "%USERPROFILE%\AppData\Roaming\Microsoft\SPMigration\Logs\Migration\MigrationToolStorage"
   ```
   
   This should show the contents of your target directory (default: `D:\MigrationToolStorage`).

### What to Look For

- ✅ The `MigrationToolStorage` folder appears in the Migration directory
- ✅ PowerShell shows `LinkType: SymbolicLink` when queried
- ✅ The folder redirects to your target directory (default: `D:\MigrationToolStorage`) when accessed
- ✅ Files created in the symbolic link location appear on the target drive
- ✅ The SharePoint Migration Tool can successfully write to the cache location

---

## ✅ Optional Cleanup
- If you no longer need the old cache folder, you can delete it:

```powershell
Remove-Item "$env:USERPROFILE\AppData\Roaming\Microsoft\SPMigration\Logs\Migration\MigrationToolStorageOld" -Recurse -Force
```

---

### ✅ Notes
- The script automatically stops and restarts the SharePoint Migration Service as needed.
- Always run scripts with **Administrator privileges**.
- The script includes error handling and will attempt to restore the service if errors occur.
- If you don't specify a `-TargetPath`, the default location `D:\MigrationToolStorage` will be used.
