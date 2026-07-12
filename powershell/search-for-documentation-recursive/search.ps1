<#
Inputs:
- .env: UTF-8 key=value configuration file located beside this script.
- ROOT_PATH: Existing directory to enumerate and search.
- INCLUDE_HIDDEN: true or false; includes hidden files and directories when true.
- EXCLUDE_DIRECTORIES: Directory names separated by LIST_SEPARATOR.
- EXCLUDE_EXTENSIONS: File extensions separated by LIST_SEPARATOR, including the leading dot.
- LIST_SEPARATOR: Separator used for exclusion lists; defaults to |.
- OUTPUT_CSV: Optional CSV output path. Relative paths are resolved from the script directory.

Outputs:
- Console directory tree containing directories and files under ROOT_PATH.
- Console match records containing the file name, relative path, match number, start line, end line, and complete matching text block.
- Optional UTF-8 CSV containing the same match records.
- Warning records for files or directories that cannot be read.

Functions:
- Import-DotEnv: Parses the .env file and returns its entries as a hashtable.
- ConvertTo-Boolean: Validates and converts true/false configuration values.
- ConvertTo-StringList: Splits a delimited configuration value into a trimmed string array.
- Get-RelativePath: Calculates a path relative to ROOT_PATH.
- Test-ExcludedPath: Determines whether a path is under an excluded directory.
- Show-DirectoryTree: Recursively prints the directory structure.
- Find-StructuredTextBlocks: Finds structured documentation blocks regardless of their bullet contents.
- Find-TextMatches: Reads eligible files and creates a record for every matching documentation block.

Processing flow:
- Load and validate configuration.
- Enumerate ROOT_PATH recursively.
- Print the directory structure.
- Search each eligible file for structurally matching documentation blocks.
- Display complete matching blocks and optionally export them to CSV.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-DotEnv {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file not found: $Path"
    }

    $configuration = @{}

    foreach ($rawLine in [System.IO.File]::ReadAllLines($Path)) {
        $line = $rawLine.Trim()

        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }

        $separatorIndex = $line.IndexOf('=')

        if ($separatorIndex -lt 1) {
            throw "Invalid .env entry: $rawLine"
        }

        $key = $line.Substring(0, $separatorIndex).Trim()
        $value = $line.Substring($separatorIndex + 1).Trim()

        if (
            ($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))
        ) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        $configuration[$key] = $value
    }

    return $configuration
}

function ConvertTo-Boolean {
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$Name
    )

    switch ($Value.Trim().ToLowerInvariant()) {
        'true'  { return $true }
        'false' { return $false }
        default { throw "$Name must be true or false." }
    }
}

function ConvertTo-StringList {
    param(
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$Separator
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @(
        $Value.Split(
            @($Separator),
            [System.StringSplitOptions]::RemoveEmptyEntries
        ) |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    $normalizedBasePath = [System.IO.Path]::GetFullPath($BasePath)
    $normalizedTargetPath = [System.IO.Path]::GetFullPath($TargetPath)
    $directorySeparator = [System.IO.Path]::DirectorySeparatorChar.ToString()

    if (-not $normalizedBasePath.EndsWith($directorySeparator)) {
        $normalizedBasePath += $directorySeparator
    }

    $baseUri = New-Object System.Uri($normalizedBasePath)
    $targetUri = New-Object System.Uri($normalizedTargetPath)

    if ($baseUri.Scheme -ne $targetUri.Scheme) {
        return $normalizedTargetPath
    }

    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    $relativePath = [System.Uri]::UnescapeDataString(
        $relativeUri.ToString()
    )

    $relativePath = $relativePath.Replace(
        [char]'/',
        [System.IO.Path]::DirectorySeparatorChar
    )

    if (:IsNullOrEmpty($relativePath)) {
        return '.'
    }

    return $relativePath
}


function Test-ExcludedPath {
    param(
        [Parameter(Mandatory)]
        [string]$RelativePath,

        [string[]]$ExcludedDirectories = @()
    )

    $pathParts = $RelativePath -split '[\\/]'

    foreach ($excludedDirectory in $ExcludedDirectories) {
        if ($pathParts -contains $excludedDirectory) {
            return $true
        }
    }

    return $false
}

function Show-DirectoryTree {
    param(
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]$Directory,

        [Parameter(Mandatory)]
        [string]$RootPath,

        [string[]]$ExcludedDirectories = @(),

        [bool]$IncludeHidden = $false,

        [string]$Indent = ''
    )

    try {
        $children = @(
            Get-ChildItem `
                -LiteralPath $Directory.FullName `
                -Force:$IncludeHidden `
                -ErrorAction Stop |
                Where-Object {
                    $relativePath = Get-RelativePath `
                        -BasePath $RootPath `
                        -TargetPath $_.FullName

                    -not (Test-ExcludedPath `
                        -RelativePath $relativePath `
                        -ExcludedDirectories $ExcludedDirectories)
                } |
                Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name
        )
    }
    catch {
        $relativeDirectory = Get-RelativePath `
            -BasePath $RootPath `
            -TargetPath $Directory.FullName

        Write-Warning "Could not enumerate '$relativeDirectory': $($_.Exception.Message)"
        return
    }

    for ($index = 0; $index -lt $children.Count; $index++) {
        $child = $children[$index]
        $isLast = $index -eq ($children.Count - 1)
        $branch = if ($isLast) { '\-- ' } else { '|-- ' }

        Write-Host "$Indent$branch$($child.Name)"

        if ($child.PSIsContainer) {
            $nextIndent = if ($isLast) { "$Indent    " } else { "$Indent|   " }

            Show-DirectoryTree `
                -Directory $child `
                -RootPath $RootPath `
                -ExcludedDirectories $ExcludedDirectories `
                -IncludeHidden $IncludeHidden `
                -Indent $nextIndent
        }
    }
}

function Find-StructuredTextBlocks {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    $headings = @(
        'Inputs:',
        'Outputs:',
        'Functions:',
        'Processing flow:'
    )

    $matches = [System.Collections.Generic.List[object]]::new()
    $startIndex = 0

    while ($startIndex -lt $Lines.Count) {
        if (
            -not $Lines[$startIndex].Trim().Equals(
                $headings[0],
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            $startIndex++
            continue
        }

        $cursor = $startIndex
        $blockIsValid = $true
        $blockEndIndex = $startIndex

        for ($sectionIndex = 0; $sectionIndex -lt $headings.Count; $sectionIndex++) {
            while (
                $cursor -lt $Lines.Count -and
                [string]::IsNullOrWhiteSpace($Lines[$cursor])
            ) {
                $cursor++
            }

            if (
                $cursor -ge $Lines.Count -or
                -not $Lines[$cursor].Trim().Equals(
                    $headings[$sectionIndex],
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            ) {
                $blockIsValid = $false
                break
            }

            $cursor++
            $bulletCount = 0
            $lastBulletIndex = -1

            while ($cursor -lt $Lines.Count) {
                $trimmedLine = $Lines[$cursor].Trim()

                if ([string]::IsNullOrWhiteSpace($trimmedLine)) {
                    $cursor++
                    continue
                }

                if ($trimmedLine -match '^\-\s+.+$') {
                    $bulletCount++
                    $lastBulletIndex = $cursor
                    $cursor++
                    continue
                }

                break
            }

            if ($bulletCount -eq 0) {
                $blockIsValid = $false
                break
            }

            $blockEndIndex = $lastBulletIndex
        }

        if ($blockIsValid) {
            $matches.Add(
                [pscustomobject]@{
                    StartLine = $startIndex + 1
                    EndLine   = $blockEndIndex + 1
                    FullText  = $Lines[$startIndex..$blockEndIndex] -join [Environment]::NewLine
                }
            )

            $startIndex = $blockEndIndex + 1
            continue
        }

        $startIndex++
    }

    return $matches
}

function Find-TextMatches {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [bool]$IncludeHidden = $false,

        [string[]]$ExcludedDirectories = @(),

        [string[]]$ExcludedExtensions = @()
    )

    $enumerationParameters = @{
        LiteralPath = $RootPath
        File        = $true
        Recurse     = $true
        Force       = $IncludeHidden
        ErrorAction = 'SilentlyContinue'
    }

    foreach ($file in Get-ChildItem @enumerationParameters) {
        $relativePath = Get-RelativePath `
            -BasePath $RootPath `
            -TargetPath $file.FullName

        if (
            Test-ExcludedPath `
                -RelativePath $relativePath `
                -ExcludedDirectories $ExcludedDirectories
        ) {
            continue
        }

        if ($ExcludedExtensions -contains $file.Extension) {
            continue
        }

        try {
            $lines = [System.IO.File]::ReadAllLines($file.FullName)
            $fileMatches = Find-StructuredTextBlocks -Lines $lines
            $matchNumber = 0

            foreach ($fileMatch in $fileMatches) {
                $matchNumber++

                [pscustomobject]@{
                    FileName     = $file.Name
                    RelativePath = $relativePath
                    MatchNumber  = $matchNumber
                    StartLine    = $fileMatch.StartLine
                    EndLine      = $fileMatch.EndLine
                    FullText     = $fileMatch.FullText
                }
            }
        }
        catch {
            Write-Warning "Could not read '$relativePath': $($_.Exception.Message)"
        }
    }
}

$scriptDirectory = $PSScriptRoot
$environmentPath = Join-Path $scriptDirectory '.env'
$configuration = Import-DotEnv -Path $environmentPath

foreach ($requiredKey in @('ROOT_PATH')) {
    if (
        -not $configuration.ContainsKey($requiredKey) -or
        [string]::IsNullOrWhiteSpace($configuration[$requiredKey])
    ) {
        throw "Required configuration entry is missing or empty: $requiredKey"
    }
}

$listSeparator = if ($configuration.ContainsKey('LIST_SEPARATOR')) {
    $configuration['LIST_SEPARATOR']
}
else {
    '|'
}

if ([string]::IsNullOrEmpty($listSeparator)) {
    throw 'LIST_SEPARATOR cannot be empty.'
}

$rootPath = $configuration['ROOT_PATH']

if (-not [System.IO.Path]::IsPathRooted($rootPath)) {
    $rootPath = Join-Path $scriptDirectory $rootPath
}

$rootPath = [System.IO.Path]::GetFullPath($rootPath)

if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
    throw "ROOT_PATH does not identify an existing directory: $rootPath"
}

$includeHidden = if ($configuration.ContainsKey('INCLUDE_HIDDEN')) {
    ConvertTo-Boolean `
        -Value $configuration['INCLUDE_HIDDEN'] `
        -Name 'INCLUDE_HIDDEN'
}
else {
    $false
}

$excludedDirectories = if ($configuration.ContainsKey('EXCLUDE_DIRECTORIES')) {
    ConvertTo-StringList `
        -Value $configuration['EXCLUDE_DIRECTORIES'] `
        -Separator $listSeparator
}
else {
    @()
}

$excludedExtensions = if ($configuration.ContainsKey('EXCLUDE_EXTENSIONS')) {
    @(
        ConvertTo-StringList `
            -Value $configuration['EXCLUDE_EXTENSIONS'] `
            -Separator $listSeparator |
            ForEach-Object {
                if ($_.StartsWith('.')) {
                    $_
                }
                else {
                    ".$_"
                }
            }
    )
}
else {
    @()
}

Write-Host ''
Write-Host "Directory structure: $rootPath" -ForegroundColor Cyan
Write-Host ([System.IO.DirectoryInfo]::new($rootPath).Name)

Show-DirectoryTree `
    -Directory ([System.IO.DirectoryInfo]::new($rootPath)) `
    -RootPath $rootPath `
    -ExcludedDirectories $excludedDirectories `
    -IncludeHidden $includeHidden

Write-Host ''
Write-Host 'Searching for structured documentation blocks...' -ForegroundColor Cyan

$results = @(
    Find-TextMatches `
        -RootPath $rootPath `
        -IncludeHidden $includeHidden `
        -ExcludedDirectories $excludedDirectories `
        -ExcludedExtensions $excludedExtensions
)

if ($results.Count -eq 0) {
    Write-Host 'No matching documentation blocks were found.' -ForegroundColor Yellow
}
else {
    foreach ($result in $results | Sort-Object RelativePath, StartLine) {
        Write-Host ''
        Write-Host ('=' * 80) -ForegroundColor DarkGray
        Write-Host "File name:     $($result.FileName)" -ForegroundColor Green
        Write-Host "Relative path: $($result.RelativePath)"
        Write-Host "Match number:  $($result.MatchNumber)"
        Write-Host "Lines:         $($result.StartLine)-$($result.EndLine)"
        Write-Host ('-' * 80) -ForegroundColor DarkGray
        Write-Host $result.FullText
    }

    Write-Host ''
    Write-Host "Matching blocks found: $($results.Count)" -ForegroundColor Green
}

if (
    $configuration.ContainsKey('OUTPUT_CSV') -and
    -not [string]::IsNullOrWhiteSpace($configuration['OUTPUT_CSV'])
) {
    $outputCsv = $configuration['OUTPUT_CSV']

    if (-not [System.IO.Path]::IsPathRooted($outputCsv)) {
        $outputCsv = Join-Path $scriptDirectory $outputCsv
    }

    $outputCsv = [System.IO.Path]::GetFullPath($outputCsv)
    $outputDirectory = Split-Path -Parent $outputCsv

    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    $results |
        Sort-Object RelativePath, StartLine |
        Export-Csv -LiteralPath $outputCsv -NoTypeInformation -Encoding utf8

    Write-Host "CSV output: $outputCsv" -ForegroundColor Green
}
