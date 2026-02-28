# 0. Shared Foundation

全Partで共通して必要な設定です。**必ず最初にプロファイルへ追記してください。**

## 0.1 PowerShell プロファイルの設定

ターミナル起動時に自作コマンドを読み込ませるための設定です。

### 設定ファイルを開く

PowerShellで以下を実行します。設定ファイルがなければ作成し、メモ帳で開きます。

powershell

```powershell
if (!(Test-Path $PROFILE)) { New-Item -Type File -Path $PROFILE -Force }; notepad $PROFILE
```

### スクリプトの追記

メモ帳が開いたら、以下の内容を末尾に貼り付けて保存してください。

powershell

```powershell
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
```

## 0.2 設定の反映と権限許可

スクリプトを有効化するために、初回のみ以下の手順が必要です。

1. **実行権限の許可**（管理者として一度だけ実行）

powershell

```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

2. **設定の即時反映**

powershell

```powershell
   . $PROFILE
```

---

# 1. fd + fzf ファイルナビゲーション

> **Requires:** Shared Foundation (Section 0) / fd, fzf

数万〜十万件規模のファイルが存在する大規模な開発環境において、標準コマンドよりも圧倒的に高速なファイルアクセス・ディレクトリ移動を実現するための設定集です。

## 1.1 ツールの導入

| **ツール** | **役割**                       | **インストールコマンド**      |
| ---------- | ------------------------------ | ----------------------------- |
| **fd**     | ファイル・フォルダ検索エンジン | `winget install sharkdp.fd`   |
| **fzf**    | 絞り込みUI (TUI)               | `winget install junegunn.fzf` |

## 1.2 スクリプトの追記

powershell

```powershell
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

    $tmp = [System.IO.Path]::GetTempFileName() + ".ps1"
    @'
$path = $args[0].Trim()
Start-Process explorer.exe $path
'@ | Set-Content $tmp -Encoding UTF8

    fd -t d @fdOpts | fzf --height 100% --layout=reverse --border --header='[o] Explore | Enter=Open | Ctrl-C=Close' --bind="enter:execute(powershell -NoProfile -File `"$tmp`" {})+clear-selection"

    Remove-Item $tmp -ErrorAction SilentlyContinue
}

# [of] Explore with files - Enter opens parent directory in Explorer
function Invoke-FzfExploreFile {
    if (-not (Test-CommandExists fd) -or -not (Test-CommandExists fzf)) { return }

    $tmp = [System.IO.Path]::GetTempFileName() + ".ps1"
    @'
$path = $args[0].Trim()
$parent = Split-Path $path -Parent
if (-not $parent) { $parent = "." }
Start-Process explorer.exe $parent
'@ | Set-Content $tmp -Encoding UTF8

    fd @fdOpts | fzf --height 100% --layout=reverse --border --header='[of] Explore File | Enter=Open parent dir | Ctrl-C=Close' --bind="enter:execute(powershell -NoProfile -File `"$tmp`" {})+clear-selection"

    Remove-Item $tmp -ErrorAction SilentlyContinue
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
Set-Alias -Name of  -Value Invoke-FzfExploreFile -Force
Set-Alias -Name c   -Value Invoke-FzfCd      -Force
Set-Alias -Name e   -Value Invoke-FzfEdit    -Force
Set-Alias -Name fcp -Value Invoke-FzfCopy    -Force
Set-Alias -Name oe  -Value Invoke-OpenEditor -Force

```

## 1.3 使い方まとめ

| **コマンド** | **動作**                                                             |
| ------------ | -------------------------------------------------------------------- |
| `o`          | フォルダを検索 → **エクスプローラー**で開く                          |
| `of`         | ファイル/フォルダを検索 → **親ディレクトリ**をエクスプローラーで開く |
| `c`          | フォルダを検索 → **その場所に移動**                                  |
| `e`          | ファイルを検索 → **エディタ**で開く                                  |
| `fcp`        | ファイルを検索 → **ファイルパス**をコピー                            |
| `oe`         | 現在のフォルダをエディタで開く                                       |
| `oe <path>`  | 指定フォルダをエディタで開く                                         |

## 1.3.1 fzf画面での操作

- **文字入力**: あいまい検索（スペース区切りでAND検索）
- **上下キー**: 候補の選択
- **Tab**: 複数選択（`o` と `e` で有効）
- **Enter**: 決定
- **Esc / Ctrl+C**: キャンセル

## 1.3.2 fzf 検索テクニック：絞り込み構文一覧

| **記号**       | **意味**     | **例**                  |
| -------------- | ------------ | ----------------------- |
| **(なし)**     | あいまい検索 | `main` (mainを含むもの) |
| **`^`**        | 先頭一致     | `^src` (srcで始まる)    |
| **`$`**        | 後方一致     | `.c$` (C言語ファイル)   |
| **`'`**        | 完全一致     | `'config` (正確に一致)  |
| **`!`**        | 否定 (NOT)   | `!temp` (除外)          |
| **`\|`**       | OR検索       | `pdf \| xlsx`           |
| **(スペース)** | AND検索      | `^work .xlsx$`          |

## 1.3.3 検索対象の最適化（除外設定）

`$fdOpts` 変数に除外フォルダをまとめて管理しています。追加したい場合は `--exclude` にフォルダ名を追記してください。

powershell

```powershell
$fdOpts = @("--no-ignore", "--exclude", "node_modules", "--exclude", ".git", "--exclude", "dist", "--exclude", "build")
```

**`--no-ignore` について**：デフォルトでは `fd` は `.gitignore` の内容を読んでファイルを除外します。`--no-ignore` を指定することで `.gitignore` を無視し、`--exclude` で明示的に指定したフォルダのみを除外します。

## 1.3.4 検索対象の最適化（無視リストの設定）

ユーザーフォルダ（`C:\Users\<UserName>`）直下に `.fdignore` を作成し、以下の内容を記述してください。

```
# --- Version Control Systems ---
.git/
.svn/
.hg/

# --- Build Artifacts (General) ---
DEBUG/
RELEASE/
build/
dist/
bin/
obj/
*.exe
*.dll
*.pdb

# --- Firmware / Embedded Artifacts ---
*.obj
*.o
*.bin
*.hex
*.elf
*.map
*.lst
*.lib
*.a
*.so

# --- Scripting / Web Development ---
node_modules/
__pycache__/
.venv/
.env

# --- OS / IDE Specific ---
.vs/
.vscode/
.idea/
Thumbs.db
.DS_Store
*.tmp
*.log
```

---

# 2. rg + fzf コード内文字列検索 (fs)

> **Requires:** Shared Foundation (Section 0) / rg, fzf, bat

ripgrepとfzfを組み合わせた高速コード内検索ツールです。VSCodeの検索より圧倒的に速く、キーボードだけで操作が完結します。

## 2.1 ツールの導入

| **ツール** | **役割**                                 | **インストールコマンド**                 |
| ---------- | ---------------------------------------- | ---------------------------------------- |
| **rg**     | 高速コード内文字列検索エンジン           | `winget install BurntSushi.ripgrep.MSVC` |
| **bat**    | プレビュー表示用シンタックスハイライター | `winget install sharkdp.bat`             |

## 2.2 スクリプトの追記

powershell

```powershell
# ==============================================================================
# Part B: rg + fzf Search Tools (fs) - Performance Optimized
# Requires: Shared Foundation
# Dependencies: rg, fzf, bat
# ==============================================================================

# --- Default Extension Filter ---
# Customize here to pre-select extensions on every new session.
# Example: $script:FsDefaultExtensions = @("c", "h")
$script:FsDefaultExtensions = @()

$script:FsExtensions  = $script:FsDefaultExtensions
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
    $modes = @(
        "smart            lower=ignore-case / UPPER=match-case  [default]",
        "sensitive        always match case  (Foo != foo)",
        "insensitive      always ignore case  (Foo == foo)",
        "word             whole word + smart  (log won't match logging)",
        "word+sensitive   whole word + match case",
        "word+insensitive whole word + ignore case"
    )
    $selected = $modes | fzf --height 40% --layout=reverse --border --no-mouse --header="Search mode"
    if ($selected) {
        switch -Wildcard ($selected) {
            "smart*"            { $script:FsSearchMode = @("--smart-case") }
            "word+sensitive*"   { $script:FsSearchMode = @("--case-sensitive", "--word-regexp") }
            "word+insensitive*" { $script:FsSearchMode = @("--ignore-case", "--word-regexp") }
            "word*"             { $script:FsSearchMode = @("--smart-case", "--word-regexp") }
            "sensitive*"        { $script:FsSearchMode = @("--case-sensitive") }
            "insensitive*"      { $script:FsSearchMode = @("--ignore-case") }
        }
        Write-Host " [ MODE ] >>> $selected" -ForegroundColor Green
    }
}

# [fse] Extension Filter
function Set-FsExt {
    if (-not (Test-Path $extHistFile)) { New-Item $extHistFile -Force | Out-Null }
    $defaultExts = @("all","py","ts","js","tsx","jsx","go","rs","cs","cpp","c","h","rb","java","kt","vue","svelte")
    $savedExts   = @(Get-Content $extHistFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\w+$' })
    $allExts     = @($defaultExts) + @($savedExts | Where-Object { $defaultExts -notcontains $_ }) | Select-Object -Unique

    # Currently active extensions shown first so they're easy to re-select or remove
    $activeExts  = @($script:FsExtensions | Where-Object { $allExts -contains $_ })
    $restExts    = @($allExts | Where-Object { $activeExts -notcontains $_ })
    $orderedExts = @($activeExts) + @($restExts)
    $activeLabel = if ($activeExts.Count -gt 0) { $activeExts -join "," } else { "all" }

    $fzfResult = $orderedExts | fzf --multi --height 40% --layout=reverse --border --no-mouse --header="Ext | current: $activeLabel" --print-query
    $typedQuery = $fzfResult | Select-Object -First 1
    $selectedExts = @($fzfResult | Select-Object -Skip 1 | Where-Object { $_ -match '^\w+$' })
    if ($selectedExts.Count -eq 0 -and $typedQuery -ne "") { $selectedExts = @($typedQuery) }
    $script:FsExtensions = $selectedExts

    # Save any newly typed (non-default, non-already-saved) extensions to history
    foreach ($ext in $selectedExts) {
        if ($ext -match '^\w+$' -and $defaultExts -notcontains $ext -and $savedExts -notcontains $ext) {
            Add-Content $extHistFile $ext -Encoding UTF8
        }
    }

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

    $tmpOpen    = _FsMakeTmpOpen
    $tmpPreview = _FsMakeTmpPreview
    $bindCmd    = "enter:execute-silent(powershell -NoProfile -WindowStyle Hidden -File `"$tmpOpen`" {})+clear-selection"
    $previewCmd = "powershell -NoProfile -File `"$tmpPreview`" {}"

    Get-Content $script:FsCacheFile | fzf --ansi --height 100% --layout=reverse --border --no-sort --exact --delimiter=":" --header="[fsg] F2=Preview  Alt-S=Sort  Alt-F=FileOnly  Alt-A=All" --preview=$previewCmd --preview-window="right:50%:hidden:wrap" --bind="f2:toggle-preview" --bind="alt-s:toggle-sort" --bind="alt-f:change-nth(1)+change-prompt([file] )" --bind="alt-a:change-nth()+change-prompt([fsg] )" --bind=$bindCmd

    Remove-Item $tmpOpen, $tmpPreview -ErrorAction SilentlyContinue
}

# [fs] Main Search Function
function Invoke-FzfGrep {
    param([string]$Query)
    if (-not $Query) { $Query = Read-Host "Search for" }
    if (-not $Query) { return }
    $query = $Query

    $tmpOpen    = _FsMakeTmpOpen
    $tmpPreview = _FsMakeTmpPreview
    $bindCmd    = "enter:execute-silent(powershell -NoProfile -WindowStyle Hidden -File `"$tmpOpen`" {})+clear-selection"
    $previewCmd = "powershell -NoProfile -File `"$tmpPreview`" {}"

    $rgArgs = @("--line-number", "--column", "--color=always", "--no-ignore", "--max-columns", "200")
    $rgArgs += @("--glob", "!node_modules", "--glob", "!dist", "--glob", "!.git")
    $rgArgs += "--sort=path"
    $rgArgs += $script:FsSearchMode
    if ($script:FsExtensions.Count -gt 0 -and $script:FsExtensions -notcontains "all") {
        foreach ($ext in $script:FsExtensions) { $rgArgs += "--glob"; $rgArgs += "*.$ext" }
    }
    $rgArgs += $query

    $extLabel = if ($script:FsExtensions.Count -eq 0 -or $script:FsExtensions -contains 'all') { 'all' } else { $script:FsExtensions -join ',' }
    $fzfArgs = @(
        "--ansi", "--height", "100%", "--layout=reverse", "--border",
        "--no-sort", "--exact",
        "--delimiter=:",
        "--header=[fs] $query | EXT:$extLabel | F2=Preview  Alt-S=Sort  Alt-F=FileOnly  Alt-A=All",
        "--preview=$previewCmd",
        "--preview-window=right:50%:hidden:wrap",
        "--bind=f2:toggle-preview",
        "--bind=alt-s:toggle-sort",
        "--bind=alt-f:change-nth(1)+change-prompt([file] )",
        "--bind=alt-a:change-nth()+change-prompt([fs] )",
        "--bind=$bindCmd"
    )

    & rg @rgArgs | Tee-Object -FilePath $script:FsCacheFile | fzf @fzfArgs

    Remove-Item $tmpOpen, $tmpPreview -ErrorAction SilentlyContinue
}

# [fsl] Live Search
function Invoke-FzfLiveSearch {
    $tmpOpen    = _FsMakeTmpOpen
    $tmpPreview = _FsMakeTmpPreview

    # Build rg args directly — no PowerShell subprocess in reload
    $rgArgs = @("--line-number", "--column", "--color=always", "--no-ignore", "--max-columns", "200",
                "--glob=!node_modules", "--glob=!dist", "--glob=!.git")
    $rgArgs += $script:FsSearchMode
    if ($script:FsExtensions.Count -gt 0 -and $script:FsExtensions -notcontains "all") {
        foreach ($ext in $script:FsExtensions) { $rgArgs += "--glob=*.$ext" }
    }
    $rgCmd = "rg " + ($rgArgs -join " ") + " -- {q}"

    $bindOpen   = "enter:execute-silent(powershell -NoProfile -WindowStyle Hidden -File `"$tmpOpen`" {})+clear-selection"
    $previewCmd = "powershell -NoProfile -File `"$tmpPreview`" {}"
    $extLabel   = if ($script:FsExtensions.Count -eq 0 -or $script:FsExtensions -contains 'all') { 'all' } else { $script:FsExtensions -join ',' }

    $fzfArgs = @(
        "--ansi", "--height", "100%", "--layout=reverse", "--border",
        "--disabled",
        "--prompt=[fsl] ",
        "--header=EXT:$extLabel | F2=Preview  Enter=Open",
        "--preview=$previewCmd",
        "--preview-window=right:50%:hidden:wrap",
        "--bind=f2:toggle-preview",
        "--bind=change:reload($rgCmd)+first",
        "--bind=$bindOpen"
    )

    @() | fzf @fzfArgs

    Remove-Item $tmpOpen, $tmpPreview -ErrorAction SilentlyContinue
}

# --- Aliases ---
Set-Alias fs  Invoke-FzfGrep       -Force
Set-Alias fsl Invoke-FzfLiveSearch -Force
Set-Alias fsg Invoke-FzfGrepFilter -Force
Set-Alias fse Set-FsExt            -Force
Set-Alias fsd Remove-FsExtHistory  -Force
Set-Alias fsm Set-FsMode           -Force

```

## 2.3 使い方まとめ

| **コマンド** | **動作**                                                         |
| ------------ | ---------------------------------------------------------------- |
| `fs`         | キーワードでコード内を検索してエディタで開く（パス順ソート）     |
| `fs <word>`  | キーワードを直接渡して検索（`fs "my keyword"` でスペース含む）  |
| `fsl`        | タイプするたびにリアルタイムで検索結果が更新されるライブ検索     |
| `fse`        | 検索対象の拡張子をセット（セッション中保持）                     |
| `fsm`        | 検索モードをセット（大文字小文字・単語一致など）                 |
| `fsg`        | 直前の `fs` 結果を絞り込む                                       |
| `fsd`        | `fse` で追加した拡張子の履歴を削除する                           |

### 基本的な使い方の流れ

1. `fse` で検索対象の拡張子をセット（省略時は全ファイル対象）
2. `fsm` で検索モードをセット（省略時は smart）
3. `fs` でキーワードを入力して検索（または `fsl` でライブ検索）
4. fzf画面で候補を選び **Enter** でエディタの該当行に直接ジャンプ
5. ヒット件数が多い場合は `fsg` でさらに絞り込み

### fs / fsl / fsg 画面での操作

| **操作**        | **動作**                                     |
| --------------- | -------------------------------------------- |
| **文字入力**    | fzf上でさらに絞り込み（完全一致モード）      |
| **上下キー**    | 候補を選択                                   |
| **Enter**       | エディタの該当行に直接ジャンプ               |
| **F2**          | プレビュー（前後コード）の表示/非表示        |
| **Alt-S**       | ソートのON/OFF切り替え                       |
| **Alt-F**       | ファイル名のみで絞り込むモードに切り替え     |
| **Alt-A**       | 全フィールド（ファイル名+行内容）に戻す      |
| **Ctrl-C**      | 終了                                         |

## 2.4 fse：拡張子フィルタの詳細

`fs` を実行するたびに拡張子を選ぶのは面倒なので、`fse` で事前にセットしておく方式です。

- ヘッダーに現在有効な拡張子が `current: ts,tsx` のように表示される
- 現在有効な拡張子はリストの先頭に表示されるので再選択・解除が簡単
- **Tab** で複数選択可能（例：`ts` と `tsx` を同時に選択）
- リストにない拡張子は直接入力すると自動で履歴に保存される
- **Esc** を押すと全拡張子が対象（`all`）になる
- `fsd` で履歴に追加した拡張子を削除できる

デフォルトで選択できる拡張子：`all`, `py`, `ts`, `js`, `tsx`, `jsx`, `go`, `rs`, `cs`, `cpp`, `c`, `h`, `rb`, `java`, `kt`, `vue`, `svelte`

### セッション開始時のデフォルト拡張子

毎回 `fse` を実行しなくても、特定の拡張子を常に有効にしたい場合はスクリプト内の変数を変更します。

```powershell
# Example: C/C++ プロジェクト専用環境
$script:FsDefaultExtensions = @("c", "h")
```

## 2.5 fsm：検索モードの詳細

検索キーワードを `log` とした場合の例です。

| **モード**        | **動作**                                              | ✅ ヒット         | ❌ スルー                |
| ----------------- | ----------------------------------------------------- | ----------------- | ------------------------ |
| `smart` (default) | lowercase → ignore case / UPPERCASE → match case      | `log` `Log` `LOG` | -                        |
| `smart` (default) | 〃（`Log` で検索した場合）                            | `Log`             | `log` `LOG`              |
| `sensitive`       | always match case                                     | `log`             | `Log` `LOG`              |
| `insensitive`     | always ignore case                                    | `log` `Log` `LOG` | -                        |
| `word`            | whole word + smart                                    | `log`             | `logger` `blog` `dialog` |
| `word+sensitive`  | whole word + match case                               | `log`             | `Log` `logger` `blog`    |
| `word+insensitive`| whole word + ignore case                              | `log` `Log` `LOG` | `logger` `blog`          |

**word が便利なケース**：変数名 `id` を検索したいが `valid` や `userId` もヒットしてしまう場合など、ノイズを減らしたいときに使います。

## 2.6 fsg：絞り込みの詳細

`fs` の検索結果が大量にある場合に使います。

1. `fs` でキーワード検索（例：`Pin` で2000件ヒット）
2. **Ctrl-C** で一旦閉じる
3. `fsg` を実行 → 直前の `fs` 結果が表示される
4. **Alt-F** でファイル名のみモードに切り替えて絞り込み
5. **Alt-A** で全フィールド表示に戻す
6. **Enter** でエディタの該当行にジャンプ

**注意**：`fsg` は直前の `fs` 結果をキャッシュファイルに保持しているため、`fs` を再実行すると結果が上書きされます。

## 2.7 fsl：ライブ検索の詳細

`fsl` を起動すると入力プロンプト `[fsl]` が表示され、タイプするたびに即座に検索が走ります。

- `fs` との違い：事前にキーワードを確定する必要がなく、タイプしながら結果を確認できる
- `fse` / `fsm` の設定を引き継ぐ（起動時点の設定を使用）
- 結果はキャッシュに保存されないため、`fsg` との連携はできない

## 2.8 検索対象と除外設定

`fs` / `fsl` はデフォルトで以下のファイル・フォルダを除外します。

| **除外対象**     | **理由**                               |
| ---------------- | -------------------------------------- |
| `node_modules`   | 依存パッケージ（膨大な件数になるため） |
| `dist` / `build` | ビルド成果物                           |
| `.git`           | バージョン管理データ                   |

---

# 3. zoxide スマートナビゲーション (z)

> **Requires:** Shared Foundation (Section 0) / zoxide

過去の移動履歴から「頻度」と「新しさ」を学習し、数文字の入力だけで目的の場所へジャンプします。

## 3.1 ツールの導入

| **ツール** | **役割**               | **インストールコマンド**            |
| ---------- | ---------------------- | ----------------------------------- |
| **zoxide** | 統計的ディレクトリ移動 | `winget install ajeetdsouza.zoxide` |

## 3.2 スクリプトの追記

powershell

```powershell
# ==============================================================================
# Part C: Smart Navigation (zoxide)
# Requires: Shared Foundation
# Dependencies: zoxide
# ==============================================================================

if (Test-CommandExists zoxide) {
    # Initialize zoxide: automatically registers 'z' and 'zi' aliases.
    # Tracks directory usage to enable faster navigation to frequently visited paths.
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
} else {
    Write-Host " [ NOTE ] zoxide not found. Run 'winget install ajeetdsouza.zoxide' to enable." -ForegroundColor DarkGray
}
```

## 3.3 使い方まとめ

| **コマンド** | **動作**                                        |
| ------------ | ----------------------------------------------- |
| `z <ワード>` | 履歴から最も一致するディレクトリへ移動          |
| `zi`         | 履歴を **fzf** で絞り込んでディレクトリ選択移動 |

---

# 4. コマンド履歴検索 (fhi)

> **Requires:** PSReadLine（PowerShell標準搭載）/ fzf

PSReadLine の履歴ファイルをfzfで検索し、選択したコマンドをそのまま実行します。

## 4.1 スクリプトの追記

```powershell
# ==============================================================================
# Part D: Command History Search (fhi)
# Requires: PSReadLine (built-in), fzf
# ==============================================================================

function Invoke-FzfHistory {
    $histFile = (Get-PSReadLineOption).HistorySavePath
    if (Test-Path $histFile) {
        $lines = @(Get-Content $histFile | Where-Object { $_.Trim() -ne '' })
        [array]::Reverse($lines)
        $source = $lines | Select-Object -Unique
    } else {
        $source = Get-History | Sort-Object Id -Descending | Select-Object -ExpandProperty CommandLine
    }

    $selected = $source | fzf --height 50% --layout=reverse --border --no-sort --exact --header='[fhi] History | Enter=Run'
    if ($selected) {
        Write-Host " >>> $selected" -ForegroundColor DarkGray
        Invoke-Expression $selected
    }
}

Set-Alias fhi Invoke-FzfHistory -Force
```

## 4.2 使い方まとめ

| **コマンド** | **動作**                                   |
| ------------ | ------------------------------------------ |
| `fhi`        | コマンド履歴をfzfで検索 → **Enter**で実行  |

### fhi 画面での操作

| **操作**     | **動作**                          |
| ------------ | --------------------------------- |
| **文字入力** | 完全一致で絞り込み                |
| **上下キー** | 候補を選択（新しい順）            |
| **Enter**    | 選択したコマンドを実行            |
| **Ctrl-C**   | キャンセル（何も実行しない）      |

---

# 5. Help (fsh)

> **Requires:** なし（独立して動作）

## 5.1 スクリプトの追記

```powershell
# ==============================================================================
# Part E: Help (fsh)
# Requires: None (works independently)
# ==============================================================================

function Show-ToolkitHelp {
    Write-Host ""
    Write-Host "  Windows PowerShell Productivity Toolkit" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [Part A] fd + fzf  -------------------------" -ForegroundColor Yellow
    Write-Host "   o          Search folders  -> Open in Explorer"
    Write-Host "   of         Search files+folders -> Open parent dir in Explorer"
    Write-Host "   c          Search folders  -> CD"
    Write-Host "   e          Search files    -> Open in Editor"
    Write-Host "   fcp        Search files    -> Copy path"
    Write-Host "   oe [path]  Open folder in Editor"
    Write-Host ""
    Write-Host "  [Part B] rg + fzf  -------------------------" -ForegroundColor Yellow
    Write-Host "   fs         Search code by keyword (sort順)"
    Write-Host "   fsl        Live search (タイプで即検索)"
    Write-Host "   fse        Set extension filter"
    Write-Host "   fsm        Set search mode"
    Write-Host "   fsg        Filter last fs results"
    Write-Host "   fsd        Delete extension history"
    Write-Host ""
    Write-Host "  [Part C] zoxide  ---------------------------" -ForegroundColor Yellow
    Write-Host "   z  <word>  Jump to directory by history"
    Write-Host "   zi         Jump to directory via fzf"
    Write-Host ""
    Write-Host "  [Part D] History  --------------------------" -ForegroundColor Yellow
    Write-Host "   fhi        Search command history -> Run"
    Write-Host ""
    Write-Host "  [Part E] Help  -----------------------------" -ForegroundColor Yellow
    Write-Host "   fsh        Show this help"
    Write-Host ""
}

Set-Alias fsh Show-ToolkitHelp -Force
```

## 5.2 使い方

| **コマンド** | **動作**               |
| ------------ | ---------------------- |
| `fsh`        | 全コマンドの一覧を表示 |
