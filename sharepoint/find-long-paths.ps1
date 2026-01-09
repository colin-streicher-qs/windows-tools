param(
    [Parameter(Mandatory=$true)]
    [string]$Directory,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "long-paths.csv",
    
    [Parameter(Mandatory=$false)]
    [int]$MaxLength = 280
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

Write-Host "Scanning directory: $Directory" -ForegroundColor Cyan
Write-Host "Looking for paths exceeding $MaxLength characters..." -ForegroundColor Cyan
Write-Host ""

# Resolve output file path (relative to current directory or absolute)
if (-not [System.IO.Path]::IsPathRooted($OutputFile)) {
    $OutputFile = Join-Path -Path (Get-Location) -ChildPath $OutputFile
}

# Initialize CSV file and stream writer for incremental writing
$csvWriter = $null
$headersWritten = $false
$longPathCount = 0
$itemCount = 0

# Small array to track top 10 longest paths for display (limited memory usage)
$topPaths = @()

# Function to write a long path to CSV
function Write-LongPathToCsv {
    param(
        [string]$Path,
        [int]$Length,
        [string]$Type,
        [string]$Name,
        [string]$Directory
    )
    
    $obj = [PSCustomObject]@{
        Path = $Path
        Length = $Length
        Type = $Type
        Name = $Name
        Directory = $Directory
    }
    
    # Write header on first long path found
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

try {
    # Open CSV file for writing
    $csvWriter = [System.IO.StreamWriter]::new($OutputFile, $false, [System.Text.Encoding]::UTF8)
    
    # Get all items recursively (files and directories)
    $allItems = Get-ChildItem -Path $Directory -Recurse -File -ErrorAction SilentlyContinue
    
    Write-Host "Scanning files..." -ForegroundColor Yellow
    
    foreach ($item in $allItems) {
        $itemCount++
        $fullPath = $item.FullName
        $pathLength = $fullPath.Length
        
        if ($pathLength -gt $MaxLength) {
            $longPathCount++
            
            # Write immediately to CSV
            Write-LongPathToCsv -Path $fullPath -Length $pathLength -Type "File" -Name $item.Name -Directory $item.DirectoryName
            
            # Track top 10 for display (keep only top 10 in memory)
            $topPaths += [PSCustomObject]@{
                Path = $fullPath
                Length = $pathLength
                Type = "File"
            }
            if ($topPaths.Count -gt 10) {
                $topPaths = $topPaths | Sort-Object -Property Length -Descending | Select-Object -First 10
            }
            
            # Progress indicator every 100 items
            if ($itemCount % 100 -eq 0) {
                Write-Host "  Scanned $itemCount items, found $longPathCount long paths..." -ForegroundColor Gray
            }
        }
    }
    
    # Also check directories
    Write-Host "Scanning directories..." -ForegroundColor Yellow
    $allDirs = Get-ChildItem -Path $Directory -Recurse -Directory -ErrorAction SilentlyContinue
    
    foreach ($dir in $allDirs) {
        $itemCount++
        $fullPath = $dir.FullName
        $pathLength = $fullPath.Length
        
        if ($pathLength -gt $MaxLength) {
            $longPathCount++
            
            # Write immediately to CSV
            Write-LongPathToCsv -Path $fullPath -Length $pathLength -Type "Directory" -Name $dir.Name -Directory $dir.Parent.FullName
            
            # Track top 10 for display (keep only top 10 in memory)
            $topPaths += [PSCustomObject]@{
                Path = $fullPath
                Length = $pathLength
                Type = "Directory"
            }
            if ($topPaths.Count -gt 10) {
                $topPaths = $topPaths | Sort-Object -Property Length -Descending | Select-Object -First 10
            }
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
    Write-Host "Long paths found: $longPathCount" -ForegroundColor $(if ($longPathCount -gt 0) { "Yellow" } else { "Green" })
    
    if ($longPathCount -gt 0) {
        Write-Host ""
        Write-Host "Results exported to: $OutputFile" -ForegroundColor Green
        Write-Host ""
        Write-Host "Top 10 longest paths:" -ForegroundColor Cyan
        $topPaths | Sort-Object -Property Length -Descending | Format-Table -Property Length, Type, @{Label="Path"; Expression={if ($_.Path.Length -gt 80) { $_.Path.Substring(0, 77) + "..." } else { $_.Path }}} -AutoSize
    } else {
        Write-Host ""
        Write-Host "No paths exceeding $MaxLength characters were found." -ForegroundColor Green
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

