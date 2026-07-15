# setup.ps1 — %USERPROFILE%\.claude のメモリ類をこのリポジトリへリンクする (Windows)
#
# 管理者権限不要:
#   - memory フォルダ: ジャンクション (mklink /J) — 常に無権限で作成可能
#   - CLAUDE.md (ファイル): mklink — 開発者モード有効なら無権限で作成可能。
#     失敗した場合はコピーモードにフォールバックし、sync-claude.ps1 がコピーで同期する。
# 再実行可能(冪等)。新しいプロジェクトを作ったら再実行する。
#
# 環境変数:
#   CLAUDE_HOME … 既定 %USERPROFILE%\.claude
#   WORK_ROOT   … 作業ディレクトリ規約のルート。既定 C:\work
$ErrorActionPreference = 'Stop'

$RepoDir    = Split-Path -Parent $PSScriptRoot
$SrcDir     = Join-Path $RepoDir 'claude'
$ClaudeHome = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $env:USERPROFILE '.claude' }
$WorkRoot   = if ($env:WORK_ROOT)   { $env:WORK_ROOT }   else { 'C:\work' }
$Ts         = Get-Date -Format 'yyyyMMdd-HHmmss'

# Claude Code のプロジェクトスラッグ: 絶対パスの英数字以外を '-' に置換
function Slugify([string]$p) { return ($p -replace '[^A-Za-z0-9]', '-') }

New-Item -ItemType Directory -Force -Path (Join-Path $ClaudeHome 'projects'), (Join-Path $SrcDir 'projects') | Out-Null

# ---------------------------------------------------------------------------
# 1. CLAUDE.md (ファイル symlink、失敗時はコピーモード)
# ---------------------------------------------------------------------------
$repoMd = Join-Path $SrcDir 'CLAUDE.md'
$homeMd = Join-Path $ClaudeHome 'CLAUDE.md'
$homeItem = Get-Item $homeMd -ErrorAction SilentlyContinue

if ($homeItem -and $homeItem.LinkType -eq 'SymbolicLink') {
    Write-Host "CLAUDE.md: リンク済み"
} else {
    if ($homeItem) {
        $repoIsTemplate = (-not (Test-Path $repoMd)) -or
                          (Select-String -Path $repoMd -Pattern 'claude-sync: template' -Quiet)
        if ($repoIsTemplate) {
            Write-Host "CLAUDE.md: ローカルの内容をリポジトリに取り込みます"
            Copy-Item $homeMd $repoMd -Force
        } else {
            Write-Host "CLAUDE.md: リポジトリ版と競合。ローカルを CLAUDE.md.bak-$Ts に退避(必要なら手動マージ)"
            Copy-Item $homeMd (Join-Path $ClaudeHome "CLAUDE.md.bak-$Ts") -Force
        }
        Remove-Item $homeMd -Force
    }
    cmd /c mklink "$homeMd" "$repoMd" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "CLAUDE.md: symlink 作成失敗(開発者モード無効?)。コピーモードにフォールバックします。sync-claude.ps1 pull/push がコピーで同期します。"
        Copy-Item $repoMd $homeMd -Force
    } else {
        Write-Host "CLAUDE.md: linked $homeMd -> $repoMd"
    }
}

# ---------------------------------------------------------------------------
# 2. auto memory: projects\<slug>\memory → repo\claude\projects\<正規名>\memory
# ---------------------------------------------------------------------------
function Link-Memory([string]$ProjDir, [string]$Name) {
    $localMem = Join-Path $ProjDir 'memory'
    $repoMem  = Join-Path $SrcDir (Join-Path 'projects' (Join-Path $Name 'memory'))
    $memItem  = Get-Item $localMem -ErrorAction SilentlyContinue
    if ($memItem -and $memItem.LinkType) { return }   # ジャンクション/リンク済み

    New-Item -ItemType Directory -Force -Path $repoMem, $ProjDir | Out-Null
    if ($memItem) {
        Write-Host "memory[$Name]: 既存のローカル memory を取り込み(上書きなし)、memory.bak-$Ts に退避"
        Get-ChildItem $localMem -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($localMem.Length + 1)
            $dst = Join-Path $repoMem $rel
            if (-not (Test-Path $dst)) {
                New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
                Copy-Item $_.FullName $dst
            }
        }
        Rename-Item $localMem "memory.bak-$Ts"
    }
    cmd /c mklink /J "$localMem" "$repoMem" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "junction 作成失敗: $localMem" }
    Write-Host "memory[$Name]: junction $localMem -> $repoMem"
}

$known = @{}

# 2a. WORK_ROOT 配下の実プロジェクト(正規名で共有 — OS をまたいで同一メモリ)
if (Test-Path $WorkRoot) {
    Get-ChildItem $WorkRoot -Directory | ForEach-Object {
        $slug = Slugify (Join-Path $WorkRoot $_.Name)
        $known[$slug] = $true
        Link-Memory (Join-Path $ClaudeHome (Join-Path 'projects' $slug)) $_.Name
    }
}

# 2b. リポジトリ側にあってローカルにまだ無いプロジェクト(他マシンで作られたもの)
Get-ChildItem (Join-Path $SrcDir 'projects') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    # スラッグ名ディレクトリ(規約外プロジェクト、2c 由来)は正規名ではない。
    # 同一パスを持つマシン(= 同名の projects\<slug> が存在する)でのみリンクする。
    if ($_.Name -match '^(-|[A-Za-z]--)') {
        $localProj = Join-Path $ClaudeHome (Join-Path 'projects' $_.Name)
        if ((Test-Path $localProj) -and -not $known[$_.Name]) {
            $known[$_.Name] = $true
            Link-Memory $localProj $_.Name
        }
        return
    }
    $slug = Slugify (Join-Path $WorkRoot $_.Name)
    if (-not $known[$slug]) {
        $known[$slug] = $true
        Link-Memory (Join-Path $ClaudeHome (Join-Path 'projects' $slug)) $_.Name
    }
}

# 2c. WORK_ROOT 規約外の既存プロジェクト: スラッグ名そのままで同期
$projRoot = Join-Path $ClaudeHome 'projects'
if (Test-Path $projRoot) {
    Get-ChildItem $projRoot -Directory | ForEach-Object {
        if ($known[$_.Name]) { return }
        $mem = Get-Item (Join-Path $_.FullName 'memory') -ErrorAction SilentlyContinue
        if ($mem -and -not $mem.LinkType) {
            Write-Host "注意: $($_.Name) は WORK_ROOT 規約外です(スラッグ名のまま同期します)"
            Link-Memory $_.FullName $_.Name
        }
    }
}

Write-Host "完了。新しいプロジェクトを作ったら本スクリプトを再実行してください。"
