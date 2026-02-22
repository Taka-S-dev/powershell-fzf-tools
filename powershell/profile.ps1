# ==============================================================================
# Shared Foundation
# Required by: Part A (fd + fzf), Part B (rg + fzf), Part C (zoxide)
# ==============================================================================

# --- Environment Setup ---
if (-not (Get-Command rg -ErrorAction SilentlyContinue)) {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
}

# --- Encoding Optimization ---
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# --- Dependency Check ---
function Test-CommandExists($Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# --- Editor Configuration ---
# Change this value to switch the editor used across all commands.
# Examples: "code" (VS Code), "nvim" (Neovim), "notepad"
$script:Editor = "code"



# ==============================================================================
# Part A: fd + fzf Tools (File & Directory Operations)
# Requires: Shared Foundation
# Dependencies: fd, fzf
# ==============================================================================

# --- Common fd Options ---
$fdOpts = @("--no-ignore", "--exclude", "node_modules", "--exclude", ".git", "--exclude", "dist", "--exclude", "build")

# [o] Explore
function Invoke-FzfExplore {
    if (-not (Test-CommandExists fd) -or -not (Test-CommandExists fzf)) { return }
    $selected = fd -t d @fdOpts | fzf -m --height 40% --layout=reverse --border --header='[o] Explore'
    if ($selected) {
        foreach ($s in $selected) {
            Start-Process explorer.exe ($s.Trim([char]0xfeff).Trim())
        }
    }
}

# [c] CD
function Invoke-FzfCd {
    if (-not (Test-CommandExists fd) -or -not (Test-CommandExists fzf)) { return }
    $s = fd -t d @fdOpts | fzf --height 40% --layout=reverse --border --header='[c] CD'
    if ($s) {
        Set-Location -LiteralPath ($s.Trim([char]0xfeff).Trim())
    }
}

# [e] Edit
function Invoke-FzfEdit {
    if (-not (Test-CommandExists fd) -or -not (Test-CommandExists fzf)) { return }
    $selected = fd -t f @fdOpts | fzf -m --height 60% --layout=reverse --border --header='[e] Editor'
    if ($selected) {
        foreach ($s in $selected) {
            Start-Process $script:Editor -ArgumentList ($s.Trim([char]0xfeff).Trim()) -WindowStyle Hidden
        }
    }
}

# [fcp] Copy Path
function Invoke-FzfCopy {
    if (-not (Test-CommandExists fd) -or -not (Test-CommandExists fzf)) { return }
    $selected = fd -t f -a @fdOpts | fzf -m --height 40% --layout=reverse --border --header='[fcp] Copy Path'
    if ($selected) {
        $paths = $selected | ForEach-Object { $_.Trim([char]0xfeff).Trim() }
        $content = $paths -join "`r`n"
        $content | clip.exe
        Write-Host "`n--- $($paths.Count) Paths Copied! ---" -ForegroundColor Yellow
    }
}

# [oe] Open Editor
function Invoke-OpenEditor {
    param([string]$Path = ".")
    $resolved = Resolve-Path $Path -ErrorAction SilentlyContinue
    if ($resolved) {
        Start-Process $script:Editor -ArgumentList "`"$($resolved.Path)`"" -WindowStyle Hidden
    } else {
        Write-Host "Path not found: $Path" -ForegroundColor Red
    }
}

# --- Aliases ---
Set-Alias -Name o   -Value Invoke-FzfExplore -Force
Set-Alias -Name c   -Value Invoke-FzfCd      -Force
Set-Alias -Name e   -Value Invoke-FzfEdit    -Force
Set-Alias -Name fcp -Value Invoke-FzfCopy    -Force
Set-Alias -Name oe  -Value Invoke-OpenEditor -Force



# ==============================================================================
# Part B: rg + fzf Search Tools (fs) - Performance Optimized
# Requires: Shared Foundation
# Dependencies: rg, fzf, bat
# ==============================================================================

$script:FsExtensions  = @()
$script:FsCacheFile   = Join-Path $env:TEMP "fs_last_results.txt"
$script:FsSearchMode  = @("--smart-case")
$extHistFile = "$HOME\.fs_ext_history"

# --- Helper Scripts (handles variable errors and spaces in paths for standalone PS execution) ---

function _FsMakeTmpOpen {
    $tmp = [System.IO.Path]::GetTempFileName() + ".ps1"
    $basePath = (Get-Location).Path
    $template = @'
$plain = $args[0] -replace '\x1b\[[0-9;]*m', ''
if ($plain -match '^([A-Za-z]:[^:]+):(\d+):') { $file = $Matches[1].Trim(); $line = [int]$Matches[2] }
elseif ($plain -match '^([^:]+):(\d+):') { $file = $Matches[1].Trim(); $line = [int]$Matches[2] }
else { exit }

$fullPath = $file
if (-not [System.IO.Path]::IsPathRooted($fullPath)) {
    $fullPath = Join-Path "BASE_PATH_PLACEHOLDER" $file
}

# Separate variable and colon completely to prevent drive letter misdetection
$target = $fullPath + ":" + $line
Start-Process EDITOR_PLACEHOLDER -ArgumentList "--goto", "`"$target`"" -WindowStyle Hidden
'@
    $template.Replace("BASE_PATH_PLACEHOLDER", $basePath).Replace("EDITOR_PLACEHOLDER", $script:Editor) | Set-Content $tmp -Encoding UTF8
    return $tmp
}

function _FsMakeTmpPreview {
    $tmp = [System.IO.Path]::GetTempFileName() + ".ps1"
    $basePath = (Get-Location).Path
    $template = @'
$plain = $args[0] -replace '\x1b\[[0-9;]*m', ''
if ($plain -match '^([A-Za-z]:[^:]+):(\d+):') { $file = $Matches[1].Trim(); $line = [int]$Matches[2] }
elseif ($plain -match '^([^:]+):(\d+):') { $file = $Matches[1].Trim(); $line = [int]$Matches[2] }
else { exit }

$fullPath = $file
if (-not [System.IO.Path]::IsPathRooted($fullPath)) {
    $fullPath = Join-Path "BASE_PATH_PLACEHOLDER" $file
}

$from = [Math]::Max(1, $line - 5)
$lineRange = [string]$from + ":"

if (Test-Path -LiteralPath $fullPath) {
    bat --color=always --style=numbers --highlight-line $line --line-range $lineRange "$fullPath"
} else {
    Write-Host "File not found: $fullPath" -ForegroundColor Red
}
'@
    $template.Replace("BASE_PATH_PLACEHOLDER", $basePath) | Set-Content $tmp -Encoding UTF8
    return $tmp
}

# [fsm] Search Mode
function Set-FsMode {
    $modes = @("smart-case (default)", "case-sensitive", "ignore-case", "word-match", "word + case-sensitive", "word + ignore-case")
    $selected = $modes | fzf --height 40% --layout=reverse --border --no-mouse --header="Search mode"
    if ($selected) {
        switch ($selected) {
            "smart-case (default)"  { $script:FsSearchMode = @("--smart-case") }
            "case-sensitive"        { $script:FsSearchMode = @("--case-sensitive") }
            "ignore-case"           { $script:FsSearchMode = @("--ignore-case") }
            "word-match"            { $script:FsSearchMode = @("--smart-case", "--word-regexp") }
            "word + case-sensitive" { $script:FsSearchMode = @("--case-sensitive", "--word-regexp") }
            "word + ignore-case"    { $script:FsSearchMode = @("--ignore-case", "--word-regexp") }
        }
        Write-Host " [ MODE ] >>> $selected" -ForegroundColor Green
    }
}

# [fse] Extension Filter
function Set-FsExt {
    if (-not (Test-Path $extHistFile)) { New-Item $extHistFile -Force | Out-Null }
    $defaultExts = @("all","py","ts","js","tsx","jsx","go","rs","cs","cpp","c","rb","java","kt","vue","svelte")
    $savedExts   = @(Get-Content $extHistFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\w+$' })
    $allExts     = @($defaultExts) + @($savedExts | Where-Object { $defaultExts -notcontains $_ }) | Select-Object -Unique
    $fzfResult = $allExts | fzf --multi --height 40% --layout=reverse --border --no-mouse --header="Ext" --print-query
    $typedQuery = $fzfResult | Select-Object -First 1
    $selectedExts = @($fzfResult | Select-Object -Skip 1 | Where-Object { $_ -match '^\w+$' })
    if ($selectedExts.Count -eq 0 -and $typedQuery -ne "") { $selectedExts = @($typedQuery) }
    $script:FsExtensions = $selectedExts
    Write-Host " [ EXT ] >>> $($selectedExts -join ', ')" -ForegroundColor Green
}

# [fsd] Delete Extension History
function Remove-FsExtHistory {
    if (-not (Test-Path $extHistFile)) { return }
    $toDelete = Get-Content $extHistFile -Encoding UTF8 | fzf --multi --height 40% --layout=reverse --border --header="Delete history"
    if ($toDelete) { Get-Content $extHistFile -Encoding UTF8 | Where-Object { $toDelete -notcontains $_ } | Set-Content $extHistFile -Encoding UTF8 }
}

# [fsg] Filter by File
function Invoke-FzfGrepFilter {
    if (-not (Test-Path $script:FsCacheFile)) { Write-Host "Run fs first" -ForegroundColor Yellow; return }

    $tmpOpen = _FsMakeTmpOpen; $tmpPreview = _FsMakeTmpPreview
    $bindCmd = "enter:execute(powershell -NoProfile -File `"$tmpOpen`" {})+clear-selection"
    $previewCmd = "powershell -NoProfile -File `"$tmpPreview`" {}"

    # Load results from cache file and pipe into fzf
    Get-Content $script:FsCacheFile | fzf --ansi --height 100% --layout=reverse --border --header="[fsg] Filter Mode | F2=Preview" --preview=$previewCmd --preview-window="right:50%:hidden:wrap" --bind="f2:toggle-preview" --bind=$bindCmd

    Remove-Item $tmpOpen, $tmpPreview -ErrorAction SilentlyContinue
}

# [fs] Main Search Function
function Invoke-FzfGrep {
    $query = Read-Host "Search for"
    if (-not $query) { return }

    $tmpOpen = _FsMakeTmpOpen; $tmpPreview = _FsMakeTmpPreview
    $bindCmd = "enter:execute(powershell -NoProfile -File `"$tmpOpen`" {})+clear-selection"
    $previewCmd = "powershell -NoProfile -File `"$tmpPreview`" {}"

    $rgArgs = @("--line-number", "--column", "--color=always", "--no-ignore", "--max-columns", "200")
    $rgArgs += @("--glob", "!node_modules", "--glob", "!dist", "--glob", "!.git")
    $rgArgs += $script:FsSearchMode
    if ($script:FsExtensions.Count -gt 0 -and $script:FsExtensions -notcontains "all") {
        foreach ($ext in $script:FsExtensions) { $rgArgs += "--glob"; $rgArgs += "*.$ext" }
    }
    $rgArgs += $query

    Write-Host " [ SEARCHING... ]" -ForegroundColor Cyan

    # Stream results to fzf while simultaneously writing to cache file for fsg
    & rg @rgArgs | Tee-Object -FilePath $script:FsCacheFile | fzf --ansi --height 100% --layout=reverse --border --header="[fs] $query | F2=Preview  fsg=Filter" --preview=$previewCmd --preview-window="right:50%:hidden:wrap" --bind="f2:toggle-preview" --bind=$bindCmd

    Remove-Item $tmpOpen, $tmpPreview -ErrorAction SilentlyContinue
}

# --- Aliases ---
Set-Alias fs  Invoke-FzfGrep       -Force
Set-Alias fsg Invoke-FzfGrepFilter -Force
Set-Alias fse Set-FsExt            -Force
Set-Alias fsd Remove-FsExtHistory  -Force
Set-Alias fsm Set-FsMode           -Force



# ==============================================================================
# Part C: Smart Navigation (zoxide)
# Requires: Shared Foundation
# Dependencies: zoxide
# ==============================================================================

# --- zoxide Initialization ---
if (Test-CommandExists zoxide) {
    # Initialize zoxide: automatically registers 'z' and 'zi' aliases.
    # Tracks directory usage to enable faster navigation to frequently visited paths.
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
} else {
    Write-Host " [ NOTE ] zoxide not found. Run 'winget install ajeetdsouza.zoxide' to enable." -ForegroundColor DarkGray
}



# ==============================================================================
# Part D: Help (fsh)
# Requires: None (works independently)
# ==============================================================================

function Show-ToolkitHelp {
    Write-Host ""
    Write-Host "  Windows PowerShell Productivity Toolkit" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [Part A] fd + fzf  -------------------------" -ForegroundColor Yellow
    Write-Host "   o          Search folders  -> Open in Explorer"
    Write-Host "   c          Search folders  -> CD"
    Write-Host "   e          Search files    -> Open in Editor"
    Write-Host "   fcp        Search files    -> Copy path"
    Write-Host "   oe [path]  Open folder in Editor"
    Write-Host ""
    Write-Host "  [Part B] rg + fzf  -------------------------" -ForegroundColor Yellow
    Write-Host "   fs         Search code by keyword"
    Write-Host "   fse        Set extension filter"
    Write-Host "   fsm        Set search mode"
    Write-Host "   fsg        Filter last fs results by filename"
    Write-Host "   fsd        Delete extension history"
    Write-Host ""
    Write-Host "  [Part C] zoxide  ---------------------------" -ForegroundColor Yellow
    Write-Host "   z  <word>  Jump to directory by history"
    Write-Host "   zi         Jump to directory via fzf"
    Write-Host ""
    Write-Host "  [Part D] Help  -----------------------------" -ForegroundColor Yellow
    Write-Host "   fsh        Show this help"
    Write-Host ""
}

Set-Alias fsh Show-ToolkitHelp -Force