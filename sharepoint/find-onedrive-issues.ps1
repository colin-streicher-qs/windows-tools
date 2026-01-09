param(
    [Parameter(Mandatory=$true)]
    [string]$Directory,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "onedrive-issues.csv",
    
    [Parameter(Mandatory=$false)]
    [int]$MaxPathLength = 400,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxFileNameLength = 255,
    
    [Parameter(Mandatory=$false)]
    [long]$MaxFileSizeMB = 256000
)

# Error handling setup
$ErrorActionPreference = "Stop"

# Validate directory parameter
if ([string]::IsNullOrWhiteSpace($Directory)) {
    Write-Error "Directory parameter cannot be empty."
    exit 1
}

# Resolve the directory path
try {
    $Directory = [System.IO.Path]::GetFullPath($Directory)
} catch {
    Write-Error "Invalid directory path format: $Directory"
    exit 1
}

# Check if directory exists
if (-not (Test-Path -Path $Directory -PathType Container)) {
    Write-Error "Directory does not exist: $Directory"
    exit 1
}

Write-Host "Scanning directory for OneDrive migration issues: $Directory" -ForegroundColor Cyan
Write-Host ""

# Resolve output file path (relative to current directory or absolute)
if (-not [System.IO.Path]::IsPathRooted($OutputFile)) {
    $OutputFile = Join-Path -Path (Get-Location) -ChildPath $OutputFile
}

# OneDrive invalid characters (cannot be used in file/folder names)
$invalidChars = @('<', '>', ':', '"', '|', '?', '*', '/', '\', [char]0x00, [char]0x01, [char]0x02, [char]0x03, [char]0x04, [char]0x05, [char]0x06, [char]0x07, [char]0x08, [char]0x09, [char]0x0A, [char]0x0B, [char]0x0C, [char]0x0D, [char]0x0E, [char]0x0F, [char]0x10, [char]0x11, [char]0x12, [char]0x13, [char]0x14, [char]0x15, [char]0x16, [char]0x17, [char]0x18, [char]0x19, [char]0x1A, [char]0x1B, [char]0x1C, [char]0x1D, [char]0x1E, [char]0x1F)

# OneDrive reserved/invalid names (cannot be used as file/folder names)
# Based on Microsoft documentation: CON, PRN, AUX, NUL, COM0-COM9, LPT0-LPT9, .lock, _vti_, desktop.ini, and names starting with ~$
$reservedNames = @('CON', 'PRN', 'AUX', 'NUL', 'COM0', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT0', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
$reservedExactNames = @('.lock', '_vti_', 'desktop.ini')

# Initialize CSV file and stream writer for incremental writing
$csvWriter = $null
$headersWritten = $false
$issueCount = 0
$itemCount = 0
$issueSummary = @{
    PathTooLong = 0
    FileNameTooLong = 0
    InvalidCharacters = 0
    ReservedName = 0
    FileTooLarge = 0
    InvalidEnding = 0
    TrailingPeriod = 0
    TrailingSpace = 0
    LeadingSpace = 0
    InvalidFileName = 0
}

# Function to check for invalid characters in name
function Test-InvalidCharacters {
    param([string]$Name)
    
    foreach ($char in $invalidChars) {
        if ($Name.Contains($char)) {
            return $true
        }
    }
    return $false
}

# Function to check if name is reserved
function Test-ReservedName {
    param([string]$Name)
    
    $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($Name).ToUpper()
    return $reservedNames -contains $nameWithoutExt
}

# Function to check for invalid file/folder names (exact matches)
function Test-InvalidFileName {
    param([string]$Name)
    
    $nameUpper = $Name.ToUpper()
    
    # Check for exact reserved names
    foreach ($reserved in $reservedExactNames) {
        if ($nameUpper -eq $reserved.ToUpper()) {
            return $true
        }
    }
    
    # Check for names starting with ~$
    if ($Name.StartsWith('~$')) {
        return $true
    }
    
    return $false
}

# Function to check for invalid endings (trailing period or space)
function Test-InvalidEnding {
    param([string]$Name)
    
    $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    if ($nameWithoutExt.EndsWith('.') -or $nameWithoutExt.EndsWith(' ')) {
        return $true
    }
    return $false
}

# Function to check for leading space
function Test-LeadingSpace {
    param([string]$Name)
    
    return $Name.StartsWith(' ')
}

# Function to get invalid characters found in name
function Get-InvalidCharacters {
    param([string]$Name)
    
    $found = @()
    foreach ($char in $invalidChars) {
        if ($Name.Contains($char)) {
            $found += $char
        }
    }
    return $found -join ', '
}

# Function to write an issue to CSV
function Write-IssueToCsv {
    param(
        [string]$Path,
        [string]$IssueType,
        [string]$IssueDescription,
        [string]$FileName,
        [string]$Directory,
        [long]$FileSize = 0,
        [int]$PathLength = 0,
        [int]$FileNameLength = 0
    )
    
    $obj = [PSCustomObject]@{
        Path = $Path
        IssueType = $IssueType
        IssueDescription = $IssueDescription
        FileName = $FileName
        Directory = $Directory
        FileSizeBytes = $FileSize
        FileSizeMB = [math]::Round($FileSize / 1MB, 2)
        PathLength = $PathLength
        FileNameLength = $FileNameLength
    }
    
    # Write header on first issue found
    if (-not $headersWritten) {
        $header = ($obj | ConvertTo-Csv -NoTypeInformation)[0]
        $csvWriter.WriteLine($header)
        $headersWritten = $true
    }
    
    # Write data row
    $dataRow = ($obj | ConvertTo-Csv -NoTypeInformation)[1]
    $csvWriter.WriteLine($dataRow)
    $csvWriter.Flush()
}

# Function to check a file for issues
function Test-FileForIssues {
    param(
        [System.IO.FileInfo]$File
    )
    
    $fullPath = $File.FullName
    $fileName = $File.Name
    $pathLength = $fullPath.Length
    $fileNameLength = $fileName.Length
    $fileSize = $File.Length
    $issuesFound = @()
    
    # Check path length
    if ($pathLength -gt $MaxPathLength) {
        $issuesFound += @{
            Type = "PathTooLong"
            Description = "Path length ($pathLength) exceeds OneDrive limit ($MaxPathLength characters)"
            PathLength = $pathLength
        }
        $script:issueSummary.PathTooLong++
    }
    
    # Check file name length
    if ($fileNameLength -gt $MaxFileNameLength) {
        $issuesFound += @{
            Type = "FileNameTooLong"
            Description = "File name length ($fileNameLength) exceeds OneDrive limit ($MaxFileNameLength characters)"
            FileNameLength = $fileNameLength
        }
        $script:issueSummary.FileNameTooLong++
    }
    
    # Check for invalid characters
    if (Test-InvalidCharacters -Name $fileName) {
        $invalidChars = Get-InvalidCharacters -Name $fileName
        $issuesFound += @{
            Type = "InvalidCharacters"
            Description = "File name contains invalid characters: $invalidChars"
        }
        $script:issueSummary.InvalidCharacters++
    }
    
    # Check for reserved name
    if (Test-ReservedName -Name $fileName) {
        $issuesFound += @{
            Type = "ReservedName"
            Description = "File name is a Windows reserved name"
        }
        $script:issueSummary.ReservedName++
    }
    
    # Check for invalid file names (.lock, _vti_, desktop.ini, names starting with ~$)
    if (Test-InvalidFileName -Name $fileName) {
        $issuesFound += @{
            Type = "InvalidFileName"
            Description = "File name is not allowed in OneDrive (.lock, _vti_, desktop.ini, or starts with ~$)"
        }
        $script:issueSummary.InvalidFileName++
    }
    
    # Check for leading space
    if (Test-LeadingSpace -Name $fileName) {
        $issuesFound += @{
            Type = "LeadingSpace"
            Description = "File name starts with a space (invalid in OneDrive)"
        }
        $script:issueSummary.LeadingSpace++
    }
    
    # Check file size
    if ($fileSize -gt ($MaxFileSizeMB * 1MB)) {
        $sizeMB = [math]::Round($fileSize / 1MB, 2)
        $issuesFound += @{
            Type = "FileTooLarge"
            Description = "File size ($sizeMB MB) exceeds OneDrive limit ($MaxFileSizeMB MB)"
            FileSize = $fileSize
        }
        $script:issueSummary.FileTooLarge++
    }
    
    # Check for invalid ending (period or space)
    if (Test-InvalidEnding -Name $fileName) {
        $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        if ($nameWithoutExt.EndsWith('.')) {
            $issuesFound += @{
                Type = "TrailingPeriod"
                Description = "File name ends with a period (invalid in OneDrive)"
            }
            $script:issueSummary.TrailingPeriod++
        }
        if ($nameWithoutExt.EndsWith(' ')) {
            $issuesFound += @{
                Type = "TrailingSpace"
                Description = "File name ends with a space (invalid in OneDrive)"
            }
            $script:issueSummary.TrailingSpace++
        }
    }
    
    # Write all issues to CSV
    foreach ($issue in $issuesFound) {
        $script:issueCount++
        Write-IssueToCsv -Path $fullPath -IssueType $issue.Type -IssueDescription $issue.Description `
            -FileName $fileName -Directory $File.DirectoryName -FileSize $fileSize `
            -PathLength $pathLength -FileNameLength $fileNameLength
    }
}

# Function to check a directory for issues
function Test-DirectoryForIssues {
    param(
        [System.IO.DirectoryInfo]$Dir
    )
    
    $fullPath = $Dir.FullName
    $dirName = $Dir.Name
    $pathLength = $fullPath.Length
    $dirNameLength = $dirName.Length
    $issuesFound = @()
    
    # Check path length
    if ($pathLength -gt $MaxPathLength) {
        $issuesFound += @{
            Type = "PathTooLong"
            Description = "Path length ($pathLength) exceeds OneDrive limit ($MaxPathLength characters)"
            PathLength = $pathLength
        }
        $script:issueSummary.PathTooLong++
    }
    
    # Check directory name length
    if ($dirNameLength -gt $MaxFileNameLength) {
        $issuesFound += @{
            Type = "FileNameTooLong"
            Description = "Directory name length ($dirNameLength) exceeds OneDrive limit ($MaxFileNameLength characters)"
            FileNameLength = $dirNameLength
        }
        $script:issueSummary.FileNameTooLong++
    }
    
    # Check for invalid characters
    if (Test-InvalidCharacters -Name $dirName) {
        $invalidChars = Get-InvalidCharacters -Name $dirName
        $issuesFound += @{
            Type = "InvalidCharacters"
            Description = "Directory name contains invalid characters: $invalidChars"
        }
        $script:issueSummary.InvalidCharacters++
    }
    
    # Check for reserved name
    if (Test-ReservedName -Name $dirName) {
        $issuesFound += @{
            Type = "ReservedName"
            Description = "Directory name is a Windows reserved name"
        }
        $script:issueSummary.ReservedName++
    }
    
    # Check for invalid directory names (.lock, _vti_, desktop.ini, names starting with ~$)
    if (Test-InvalidFileName -Name $dirName) {
        $issuesFound += @{
            Type = "InvalidFileName"
            Description = "Directory name is not allowed in OneDrive (.lock, _vti_, desktop.ini, or starts with ~$)"
        }
        $script:issueSummary.InvalidFileName++
    }
    
    # Check for leading space
    if (Test-LeadingSpace -Name $dirName) {
        $issuesFound += @{
            Type = "LeadingSpace"
            Description = "Directory name starts with a space (invalid in OneDrive)"
        }
        $script:issueSummary.LeadingSpace++
    }
    
    # Check for invalid ending (period or space)
    if ($dirName.EndsWith('.') -or $dirName.EndsWith(' ')) {
        if ($dirName.EndsWith('.')) {
            $issuesFound += @{
                Type = "TrailingPeriod"
                Description = "Directory name ends with a period (invalid in OneDrive)"
            }
            $script:issueSummary.TrailingPeriod++
        }
        if ($dirName.EndsWith(' ')) {
            $issuesFound += @{
                Type = "TrailingSpace"
                Description = "Directory name ends with a space (invalid in OneDrive)"
            }
            $script:issueSummary.TrailingSpace++
        }
    }
    
    # Write all issues to CSV
    foreach ($issue in $issuesFound) {
        $script:issueCount++
        Write-IssueToCsv -Path $fullPath -IssueType $issue.Type -IssueDescription $issue.Description `
            -FileName $dirName -Directory $Dir.Parent.FullName -FileSize 0 `
            -PathLength $pathLength -FileNameLength $dirNameLength
    }
}

try {
    # Open CSV file for writing
    $csvWriter = [System.IO.StreamWriter]::new($OutputFile, $false, [System.Text.Encoding]::UTF8)
    
    Write-Host "Scanning files..." -ForegroundColor Yellow
    
    # Get all files recursively
    $allFiles = Get-ChildItem -Path $Directory -Recurse -File -ErrorAction SilentlyContinue
    
    foreach ($file in $allFiles) {
        $itemCount++
        Test-FileForIssues -File $file
        
        # Progress indicator every 1000 items
        if ($itemCount % 1000 -eq 0) {
            Write-Host "  Scanned $itemCount items, found $issueCount issues..." -ForegroundColor Gray
        }
    }
    
    Write-Host "Scanning directories..." -ForegroundColor Yellow
    
    # Get all directories recursively
    $allDirs = Get-ChildItem -Path $Directory -Recurse -Directory -ErrorAction SilentlyContinue
    
    foreach ($dir in $allDirs) {
        $itemCount++
        Test-DirectoryForIssues -Dir $dir
        
        # Progress indicator every 1000 items
        if ($itemCount % 1000 -eq 0) {
            Write-Host "  Scanned $itemCount items, found $issueCount issues..." -ForegroundColor Gray
        }
    }
    
    # Close CSV file
    if ($null -ne $csvWriter) {
        $csvWriter.Close()
        $csvWriter.Dispose()
        $csvWriter = $null
    }
    
    Write-Host ""
    Write-Host "Scan complete. Total items scanned: $itemCount" -ForegroundColor Green
    Write-Host "Total issues found: $issueCount" -ForegroundColor $(if ($issueCount -gt 0) { "Yellow" } else { "Green" })
    Write-Host ""
    
    if ($issueCount -gt 0) {
        Write-Host "Issue Summary:" -ForegroundColor Cyan
        Write-Host "  Path Too Long: $($issueSummary.PathTooLong)" -ForegroundColor $(if ($issueSummary.PathTooLong -gt 0) { "Yellow" } else { "Gray" })
        Write-Host "  File/Directory Name Too Long: $($issueSummary.FileNameTooLong)" -ForegroundColor $(if ($issueSummary.FileNameTooLong -gt 0) { "Yellow" } else { "Gray" })
        Write-Host "  Invalid Characters: $($issueSummary.InvalidCharacters)" -ForegroundColor $(if ($issueSummary.InvalidCharacters -gt 0) { "Yellow" } else { "Gray" })
        Write-Host "  Reserved Names: $($issueSummary.ReservedName)" -ForegroundColor $(if ($issueSummary.ReservedName -gt 0) { "Yellow" } else { "Gray" })
        Write-Host "  Invalid File/Directory Names: $($issueSummary.InvalidFileName)" -ForegroundColor $(if ($issueSummary.InvalidFileName -gt 0) { "Yellow" } else { "Gray" })
        Write-Host "  Files Too Large: $($issueSummary.FileTooLarge)" -ForegroundColor $(if ($issueSummary.FileTooLarge -gt 0) { "Yellow" } else { "Gray" })
        Write-Host "  Leading Space: $($issueSummary.LeadingSpace)" -ForegroundColor $(if ($issueSummary.LeadingSpace -gt 0) { "Yellow" } else { "Gray" })
        Write-Host "  Trailing Period: $($issueSummary.TrailingPeriod)" -ForegroundColor $(if ($issueSummary.TrailingPeriod -gt 0) { "Yellow" } else { "Gray" })
        Write-Host "  Trailing Space: $($issueSummary.TrailingSpace)" -ForegroundColor $(if ($issueSummary.TrailingSpace -gt 0) { "Yellow" } else { "Gray" })
        Write-Host ""
        Write-Host "Results exported to: $OutputFile" -ForegroundColor Green
    } else {
        Write-Host "No OneDrive migration issues found!" -ForegroundColor Green
        # Remove empty CSV file if no results
        if (Test-Path $OutputFile) {
            Remove-Item $OutputFile -Force
        }
    }
    
} catch {
    # Ensure CSV file is closed on error
    if ($null -ne $csvWriter) {
        try {
            $csvWriter.Close()
            $csvWriter.Dispose()
        } catch {
            # Ignore errors during cleanup
        }
    }
    Write-Error "An error occurred while scanning: $($_.Exception.Message)"
    exit 1
}

