# ARK ASCENDED resource monitor.
# CPU and GPU percentages are shares of the whole machine / the whole GPU.
# Memory bars are shares of total capacity.
# "External" is usage that is not ARK. Empty bar space is idle (CPU/GPU) or free (memory).
# GPU memory is dedicated VRAM. External = adapter dedicated usage - ARK dedicated usage.
param(
    [switch]$SelfTest,
    [string]$SnapshotPath,
    [switch]$LogicTest,
    [ValidateSet('Live', 'Running', 'Pressure', 'Suspected', 'Unknown')]
    [string]$PreviewState = 'Live'
)

$ErrorActionPreference = 'Stop'

function Get-ConsoleCodePage {
    $raw = & "$env:SystemRoot\System32\chcp.com"
    $text = ($raw | Out-String)
    if ($text -match '(\d+)\s*$') { return $Matches[1] }
    return $null
}

$script:CodePageBefore = Get-ConsoleCodePage
if ($script:CodePageBefore -ne '65001') {
    & "$env:SystemRoot\System32\chcp.com" 65001 | Out-Null
}
try {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [Console]::OutputEncoding = $utf8
    $OutputEncoding = $utf8
} catch {
}
$script:CodePageNow = Get-ConsoleCodePage
Write-Host ("Code page check: {0} -> {1}" -f $script:CodePageBefore, $script:CodePageNow)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# Display language resets to English on every launch; no machine settings are changed.
$script:Language = 'ENG'
$script:Translations = @{
    ENG = @{
        TopMost = 'Always on top'; Diagnose = 'Diagnostics'; DiagnosticTitle = 'ARK Resmon · Diagnostics'
        Copy = 'Copy diagnostics'; Copied = 'Copied'; Retry = 'Try again'; DiagnosticNote = 'Details about measurement failures.'
        Running = 'ARK running'; Waiting = 'Waiting for ARK'; Session = 'PID {0} · Updated {1}'; AutoConnect = 'Waiting to connect · {0}'
        idle = 'Waiting'; warming = 'Warming up'; normal = 'No signs'; pressure = 'Memory pressure'; suspected = 'Swap suspected'; unknown = 'Unavailable'
        Reason_idle = 'Waiting for ARK to start'; Reason_warming = 'Collecting memory usage trends'
        Reason_normal = 'No recent signs of memory pressure'
        Reason_pressure = 'High VRAM usage · Shared memory alone does not confirm swapping'
        Reason_suspected = 'VRAM saturation and rising ARK shared memory observed'
        Reason_unknown = 'GPU memory measurements are unavailable'
        Shared = 'ARK shared GPU memory'; External = 'External'; IdleUsage = 'Idle'; Free = 'Free'; Total = 'Total'
        GpuMemory = 'GPU memory'; SystemMemory = 'System memory'; Legend = '/  Empty: idle or free capacity'
        MeasurementError = 'Measurement error: {0}'; MissingSmi = 'nvidia-smi.exe was not found'
        MemoryTip = 'Estimated from usage trends. Actual paging events are not measured directly.'
        AvatarTip = '64×64 status character · fun / cheer / sick / dizzy'
        GpuTip = 'Total: NVIDIA / ARK: Windows 3D engine. External usage is estimated from their difference.'
        VramTip = 'Estimated total GPU usage minus ARK usage. Memory shared across processes may prevent an exact split.'
        SharedTip = 'System RAM used by the GPU. Shared memory usage alone does not imply swapping.'
    }
    KOR = @{
        TopMost = '항상 위에'; Diagnose = '진단'; DiagnosticTitle = 'ARK Resmon · 진단 정보'
        Copy = '진단 정보 복사'; Copied = '복사 완료'; Retry = '다시 눌러주세요'; DiagnosticNote = '조회 실패 이유를 확인할 수 있습니다.'
        Running = 'ARK 실행 중'; Waiting = 'ARK 실행 대기'; Session = 'PID {0} · {1} 업데이트'; AutoConnect = '자동 연결 대기 · {0}'
        idle = '대기'; warming = '측정 준비'; normal = '징후 없음'; pressure = '메모리 압박'; suspected = '스왑 의심'; unknown = '측정 불가'
        Reason_idle = 'ARK 실행을 기다리고 있습니다'; Reason_warming = '메모리 변화 추세를 수집하고 있습니다'
        Reason_normal = '최근 측정에서 메모리 압박 징후가 없습니다'
        Reason_pressure = 'VRAM 점유율이 높습니다 · 공유 메모리만으로 스왑을 확정하지 않습니다'
        Reason_suspected = 'VRAM 포화와 ARK 공유 메모리 증가가 함께 관측됐습니다'
        Reason_unknown = 'GPU 메모리 측정값을 확인할 수 없습니다'
        Shared = 'ARK 공유 GPU 메모리'; External = '외부'; IdleUsage = '유휴'; Free = '남음'; Total = '전체'
        GpuMemory = 'GPU 메모리'; SystemMemory = '시스템 메모리'; Legend = '/  빈 구간: 유휴·남은 용량'
        MeasurementError = '측정 오류: {0}'; MissingSmi = 'nvidia-smi.exe를 찾지 못했습니다'
        MemoryTip = '변화 추세로 추정한 상태입니다. 실제 페이징 이벤트를 직접 측정하지 않습니다.'
        AvatarTip = '64×64 상태 캐릭터 · fun / cheer / sick / dizzy'
        GpuTip = '전체: NVIDIA 측정 / ARK: Windows 3D 엔진 측정. 외부는 두 측정값의 차이로 추정합니다.'
        VramTip = '전체 GPU 사용량에서 ARK 사용량을 뺀 추정치. 프로세스 간 공유로 정확한 분리가 어려울 수 있습니다.'
        SharedTip = 'GPU가 사용하는 시스템 RAM입니다. 사용량이 있다는 것만으로 스왑을 뜻하지 않습니다.'
    }
    JPN = @{
        TopMost = '最前面に表示'; Diagnose = '診断'; DiagnosticTitle = 'ARK Resmon · 診断情報'
        Copy = '診断情報をコピー'; Copied = 'コピー完了'; Retry = '再試行'; DiagnosticNote = '測定に失敗した原因を確認できます。'
        Running = 'ARK 実行中'; Waiting = 'ARK 起動待ち'; Session = 'PID {0} · {1} 更新'; AutoConnect = '自動接続待ち · {0}'
        idle = '待機'; warming = '測定準備'; normal = '兆候なし'; pressure = 'メモリ逼迫'; suspected = 'スワップの疑い'; unknown = '測定不可'
        Reason_idle = 'ARK の起動を待っています'; Reason_warming = 'メモリ使用量の変化を収集しています'
        Reason_normal = '最近の測定ではメモリ逼迫の兆候はありません'
        Reason_pressure = 'VRAM 使用率が高い状態です · 共有メモリだけではスワップを断定できません'
        Reason_suspected = 'VRAM の飽和と ARK 共有メモリの増加を検出しました'
        Reason_unknown = 'GPU メモリの測定値を取得できません'
        Shared = 'ARK 共有 GPU メモリ'; External = 'その他'; IdleUsage = 'アイドル'; Free = '空き'; Total = '全体'
        GpuMemory = 'GPU メモリ'; SystemMemory = 'システムメモリ'; Legend = '/  空白: アイドル・空き容量'
        MeasurementError = '測定エラー: {0}'; MissingSmi = 'nvidia-smi.exe が見つかりません'
        MemoryTip = '使用量の変化に基づく推定です。実際のページングイベントは直接測定していません。'
        AvatarTip = '64×64 状態キャラクター · fun / cheer / sick / dizzy'
        GpuTip = '全体: NVIDIA / ARK: Windows 3D エンジン。その他の使用率は両者の差から推定します。'
        VramTip = 'GPU 全体から ARK の使用量を引いた推定値です。プロセス間の共有により正確に分離できない場合があります。'
        SharedTip = 'GPU が使用するシステム RAM です。共有メモリの使用だけではスワップを意味しません。'
    }
}

function Get-Text([string]$key) {
    $value = $script:Translations[$script:Language][$key]
    if ($null -eq $value) { $value = $script:Translations['ENG'][$key] }
    if ($null -eq $value) { throw "Unknown translation key: $key" }
    return $value
}

function Set-UiLanguage([ValidateSet('KOR', 'JPN', 'ENG')][string]$language) {
    $script:Language = $language
    if (-not $script:Ui) { return }
    $ui.TopMost.Text = Get-Text 'TopMost'
    $ui.LegendExt.Text = '● ' + (Get-Text 'External')
    $ui.Legend.Text = Get-Text 'Legend'
    $ui.Units.Text = Get-Text 'Total'
    $ui.GpuMem.Title.Text = Get-Text 'GpuMemory'
    $ui.Ram.Title.Text = Get-Text 'SystemMemory'
    $ui.Tips.SetToolTip($ui.MemoryState, (Get-Text 'MemoryTip'))
    $ui.Tips.SetToolTip($ui.Avatar, (Get-Text 'AvatarTip'))
    $ui.Tips.SetToolTip($ui.Gpu.Total, (Get-Text 'GpuTip'))
    $ui.Tips.SetToolTip($ui.GpuMem.Ext, (Get-Text 'VramTip'))
    $ui.Tips.SetToolTip($ui.Shared, (Get-Text 'SharedTip'))
    foreach ($code in @('KOR', 'JPN', 'ENG')) {
        $button = $ui.LanguageButtons[$code]
        $selected = $code -eq $language
        $button.ForeColor = if ($selected) { $script:ColorArk } else { $script:ColorMuted }
        $button.BackColor = if ($selected) { $script:ColorCard } else { $script:ColorBg }
        $button.FlatAppearance.BorderColor = if ($selected) { $script:ColorArk } else { $script:ColorLine }
        $button.AccessibleDescription = if ($selected) { 'Selected' } else { '' }
    }
    if ($script:UiSample) { Update-Ui $script:UiSample }
    else { $ui.Status.Text = Get-Text 'warming'; $ui.MemoryState.Text = Get-Text 'idle' }
}

$script:ColorBg = [System.Drawing.Color]::FromArgb(20, 23, 27)
$script:ColorCard = [System.Drawing.Color]::FromArgb(27, 31, 36)
$script:ColorTrack = [System.Drawing.Color]::FromArgb(43, 48, 54)
$script:ColorText = [System.Drawing.Color]::FromArgb(235, 236, 232)
$script:ColorMuted = [System.Drawing.Color]::FromArgb(144, 151, 157)
$script:ColorArk = [System.Drawing.Color]::FromArgb(216, 180, 111)
$script:ColorExt = [System.Drawing.Color]::FromArgb(116, 143, 163)
$script:ColorLine = [System.Drawing.Color]::FromArgb(50, 56, 62)
$script:ColorOk = [System.Drawing.Color]::FromArgb(143, 203, 155)
$script:ColorWarn = [System.Drawing.Color]::FromArgb(224, 161, 90)
$script:ColorSwapOk = [System.Drawing.Color]::FromArgb(46, 160, 98)
$script:ColorSwapBad = [System.Drawing.Color]::FromArgb(214, 64, 64)

$script:BrushArk = New-Object System.Drawing.SolidBrush $script:ColorArk
$script:BrushExt = New-Object System.Drawing.SolidBrush $script:ColorExt
$script:BrushTrack = New-Object System.Drawing.SolidBrush $script:ColorTrack
$script:BrushUnknown = New-Object System.Drawing.SolidBrush $script:ColorMuted
$script:BrushSwapOk = New-Object System.Drawing.SolidBrush $script:ColorSwapOk
$script:BrushSwapBad = New-Object System.Drawing.SolidBrush $script:ColorSwapBad
$script:PenLine = New-Object System.Drawing.Pen $script:ColorLine

$script:LogicalProcessors = [Environment]::ProcessorCount
if ($script:LogicalProcessors -lt 1) { $script:LogicalProcessors = 1 }
$script:ComputerInfo = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
$script:Smi = "$env:SystemRoot\System32\nvidia-smi.exe"
if (-not (Test-Path -LiteralPath $script:Smi)) {
    $script:Smi = $null
    foreach ($programRoot in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $programRoot) { continue }
        $candidate = Join-Path $programRoot 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
        if (Test-Path -LiteralPath $candidate) { $script:Smi = $candidate; break }
    }
    if (-not $script:Smi) {
        $cmd = Get-Command nvidia-smi -ErrorAction SilentlyContinue
        if ($cmd) { $script:Smi = $cmd.Source }
    }
}

$script:NvLuid = $null
$script:AdapterCounter = $null
$script:CpuCounter = $null
$script:GpuName = 'NVIDIA GPU'
$script:VramTotal = [int64]0
$script:LastSmiUtil = 0.0
$script:ArkKey = ''
$script:UtilCounters = @()
$script:VramCounters = @()
$script:NonLocalCounters = @()
$script:SwapBaseline = [int64]-1
$script:SwapHistory = @()
$script:SwapState = 'warming'
$script:SwapOn = $false
$script:SwapReason = (Get-Text 'Reason_warming')
$script:SwapCandidate = ''
$script:SwapCandidateSince = [datetime]::MinValue
$script:SwapBaselineSamples = 0
$script:SwapEvidenceAt = [datetime]::MinValue
$script:LastCounterSync = [datetime]::MinValue
$script:CpuProcessKey = ''
$script:VramReadOk = $false
$script:NonLocalReadOk = $false
$script:LastSmiAt = [datetime]::MinValue
$script:SmiHealthy = $false
$script:SmiUtilValid = $false
$script:SmiVramValid = $false
$script:SmiVramUsed = [int64]0
$script:LastSmiError = ''
$script:LastGpuInitError = ''
$script:LastGpuSyncError = ''
$script:DriverVersion = ''
$script:LastSample = $null
$script:AvatarImages = @{}
$script:AvatarState = ''
$script:CharacterRoot = $PSScriptRoot
$script:UtilWarm = [datetime]::MinValue
$script:LastCpuTime = [timespan]::Zero
$script:LastCpuStamp = [datetime]::MinValue
$script:LastArkGpu = 0.0
$script:Busy = $false

function Convert-MB([int64]$bytes) {
    if ($bytes -le 0) { return [int64]0 }
    return [int64][Math]::Round($bytes / 1MB)
}

function Format-MB([double]$bytes) {
    return ('{0:N0} MB' -f (Convert-MB ([int64]$bytes)))
}

function Split-Capacity([int64]$ark, [int64]$ext, [int64]$total) {
    $totalMb = Convert-MB $total
    $arkMb = Convert-MB $ark
    $extMb = Convert-MB $ext
    if (($arkMb + $extMb) -gt $totalMb) { $extMb = $totalMb - $arkMb }
    if ($extMb -lt 0) { $extMb = 0 }
    $freeMb = $totalMb - $arkMb - $extMb
    if ($freeMb -lt 0) { $freeMb = 0 }
    return [pscustomobject]@{ Ark = $arkMb; Ext = $extMb; Free = $freeMb; Total = $totalMb; Used = ($arkMb + $extMb) }
}

function Format-Pct([double]$value) {
    return ('{0:N1}%' -f $value)
}

function Get-RoundedPath([System.Drawing.RectangleF]$rect, [single]$radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $radius * 2
    if ($rect.Width -le $diameter -or $rect.Height -le $diameter) {
        $path.AddRectangle($rect)
        return $path
    }
    $path.AddArc($rect.X, $rect.Y, $diameter, $diameter, 180, 90)
    $path.AddArc(($rect.Right - $diameter), $rect.Y, $diameter, $diameter, 270, 90)
    $path.AddArc(($rect.Right - $diameter), ($rect.Bottom - $diameter), $diameter, $diameter, 0, 90)
    $path.AddArc($rect.X, ($rect.Bottom - $diameter), $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function Get-ArkProcesses {
    @(Get-Process -Name 'ArkAscended*' -ErrorAction SilentlyContinue)
}

function Get-ArkCpuTime($procs) {
    $sum = [timespan]::Zero
    foreach ($proc in @($procs)) {
        try { $sum = $sum.Add($proc.TotalProcessorTime) } catch { }
    }
    return $sum
}

function Get-ArkWorkingSet($procs) {
    $sum = [int64]0
    foreach ($proc in @($procs)) {
        try { $sum += [int64]$proc.WorkingSet64 } catch { }
    }
    return $sum
}

function Initialize-Gpu {
    $script:LastGpuInitError = ''
    $category = New-Object System.Diagnostics.PerformanceCounterCategory('GPU Adapter Memory')
    $bestValue = [int64]-1
    $bestCounter = $null
    $bestInstance = $null
    foreach ($instance in @($category.GetInstanceNames())) {
        $counter = New-Object System.Diagnostics.PerformanceCounter('GPU Adapter Memory', 'Dedicated Usage', $instance, $true)
        $value = [int64]0
        try { $value = [int64]$counter.RawValue } catch { $value = 0 }
        if ($value -gt $bestValue) {
            if ($bestCounter) { $bestCounter.Dispose() }
            $bestValue = $value
            $bestCounter = $counter
            $bestInstance = $instance
        } else {
            $counter.Dispose()
        }
    }
    $script:AdapterCounter = $bestCounter
    $matched = [regex]::Match([string]$bestInstance, 'luid_0x[0-9A-Fa-f]+_0x[0-9A-Fa-f]+')
    if ($matched.Success) { $script:NvLuid = $matched.Value }
}

function Update-NvidiaInfo {
    # Query slowly; the 1-second UI timer need not spawn nvidia-smi every tick.
    if (-not $script:Smi) {
        $script:SmiHealthy = $false; $script:SmiUtilValid = $false; $script:SmiVramValid = $false
        $script:LastSmiError = (Get-Text 'MissingSmi')
        return $script:LastSmiUtil
    }
    if ((([datetime]::UtcNow) - $script:LastSmiAt).TotalSeconds -lt 3) { return $script:LastSmiUtil }
    $script:LastSmiAt = [datetime]::UtcNow
    $worker = New-Object System.Diagnostics.Process
    try {
        $worker.StartInfo.FileName = $script:Smi
        $worker.StartInfo.Arguments = '--query-gpu=name,memory.total,utilization.gpu,memory.used,driver_version --format=csv,noheader,nounits'
        $worker.StartInfo.UseShellExecute = $false
        $worker.StartInfo.CreateNoWindow = $true
        $worker.StartInfo.RedirectStandardOutput = $true
        $worker.StartInfo.RedirectStandardError = $true
        [void]$worker.Start()
        $outTask = $worker.StandardOutput.ReadToEndAsync()
        $errTask = $worker.StandardError.ReadToEndAsync()
        if (-not $worker.WaitForExit(1000)) { $worker.Kill(); throw 'GPU query timed out' }
        if ($worker.ExitCode -ne 0) { throw ('GPU query failed: ' + $errTask.Result.Trim()) }
        $line = @($outTask.Result -split '\r?\n' | Where-Object { $_.Trim() })[0]
        $parts = @($line -split ',')
        if ($parts.Count -lt 5) { throw 'Invalid GPU query' }
        $totalMiB = 0
        $util = 0.0
        if (-not [int]::TryParse($parts[1].Trim(), [ref]$totalMiB)) { throw 'Unknown VRAM capacity' }
        $script:SmiUtilValid = [double]::TryParse($parts[2].Trim(), [Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$util)
        $usedMiB = 0
        $script:SmiVramValid = [int]::TryParse($parts[3].Trim(), [ref]$usedMiB) -and $usedMiB -ge 0
        $script:GpuName = $parts[0].Trim()
        $script:VramTotal = [int64]$totalMiB * 1MB
        if ($script:SmiUtilValid) { $script:LastSmiUtil = [Math]::Max(0.0, [Math]::Min(100.0, $util)) }
        if ($script:SmiVramValid) { $script:SmiVramUsed = [int64]$usedMiB * 1MB }
        $script:DriverVersion = $parts[4].Trim()
        $script:LastSmiError = ''
        $script:SmiHealthy = $true
    } catch {
        $script:SmiHealthy = $false; $script:SmiUtilValid = $false; $script:SmiVramValid = $false
        $script:LastSmiError = $_.Exception.Message
    } finally { $worker.Dispose() }
    return $script:LastSmiUtil
}

function Clear-ArkCounters {
    foreach ($counter in @($script:UtilCounters)) {
        try { $counter.Dispose() } catch { }
    }
    foreach ($counter in @($script:VramCounters)) {
        try { $counter.Dispose() } catch { }
    }
    foreach ($counter in @($script:NonLocalCounters)) {
        try { $counter.Dispose() } catch { }
    }
    $script:UtilCounters = @()
    $script:VramCounters = @()
    $script:NonLocalCounters = @()
}

function Sync-ArkCounters($procs) {
    $ids = @($procs | ForEach-Object { $_.Id } | Sort-Object)
    $key = ($ids -join ',')
    $now = [datetime]::UtcNow
    $changed = $key -ne $script:ArkKey
    $missing = $ids.Count -gt 0 -and ($script:VramCounters.Count -eq 0 -or $script:NonLocalCounters.Count -eq 0)
    $refreshAfter = 10
    if ($missing) { $refreshAfter = 2 }
    if (-not $changed -and ($now - $script:LastCounterSync).TotalSeconds -lt $refreshAfter) { return }
    $script:LastGpuSyncError = ''
    if ($changed) { Reset-SwapTracking; $script:LastArkGpu = 0.0 }
    $script:ArkKey = $key
    $script:LastCounterSync = $now
    Clear-ArkCounters
    $script:UtilWarm = $now
    if ($ids.Count -eq 0 -or -not $script:NvLuid) { return }
    $memoryNames = @((New-Object System.Diagnostics.PerformanceCounterCategory('GPU Process Memory')).GetInstanceNames())
    foreach ($processId in $ids) {
        foreach ($instance in $memoryNames) {
            if ($instance -like "pid_${processId}_$($script:NvLuid)_phys_*") {
                $script:VramCounters += New-Object System.Diagnostics.PerformanceCounter('GPU Process Memory', 'Dedicated Usage', $instance, $true)
                $script:NonLocalCounters += New-Object System.Diagnostics.PerformanceCounter('GPU Process Memory', 'Non Local Usage', $instance, $true)
            }
        }
    }
    # A missing 3D engine must not prevent memory diagnostics.
    try {
        $engineNames = @((New-Object System.Diagnostics.PerformanceCounterCategory('GPU Engine')).GetInstanceNames())
        foreach ($processId in $ids) {
            foreach ($instance in $engineNames) {
                if ($instance -like "pid_${processId}_$($script:NvLuid)_*_engtype_3D") {
                    $counter = New-Object System.Diagnostics.PerformanceCounter('GPU Engine', 'Utilization Percentage', $instance, $true)
                    [void]$counter.NextValue()
                    $script:UtilCounters += $counter
                }
            }
        }
    } catch { $script:LastGpuSyncError = $_.Exception.Message }
}

function Get-ArkGpuUtil {
    $warm = (([datetime]::UtcNow) - $script:UtilWarm).TotalMilliseconds -ge 900
    if (-not $warm -or $script:UtilCounters.Count -eq 0) { return $script:LastArkGpu }
    $max = 0.0
    $failed = $false
    foreach ($counter in @($script:UtilCounters)) {
        try {
            $value = [double]$counter.NextValue()
            if ($value -gt $max) { $max = $value }
        } catch {
            $failed = $true
        }
    }
    if ($failed) { $script:LastCounterSync = [datetime]::MinValue }
    if ($max -lt 0) { $max = 0 }
    if ($max -gt 100) { $max = 100 }
    $script:LastArkGpu = $max
    return $max
}

function Get-CounterSum($counters) {
    $sum = [int64]0
    $failed = $false
    foreach ($counter in @($counters)) {
        try { $sum += [int64]$counter.RawValue } catch { $failed = $true }
    }
    if ($failed) { $script:LastCounterSync = [datetime]::MinValue }
    if ($sum -lt 0) { return [int64]0 }
    return $sum
}

function Get-ArkVramBytes {
    $script:VramReadOk = $script:VramCounters.Count -gt 0
    $sum = [int64]0
    foreach ($counter in $script:VramCounters) {
        try { $sum += [int64]$counter.RawValue } catch { $script:VramReadOk = $false; $script:LastCounterSync = [datetime]::MinValue }
    }
    return [Math]::Max([int64]0, $sum)
}

function Get-ArkNonLocalBytes {
    $script:NonLocalReadOk = $script:NonLocalCounters.Count -gt 0
    $sum = [int64]0
    foreach ($counter in $script:NonLocalCounters) {
        try { $sum += [int64]$counter.RawValue } catch { $script:NonLocalReadOk = $false; $script:LastCounterSync = [datetime]::MinValue }
    }
    return [Math]::Max([int64]0, $sum)
}

function Reset-SwapTracking {
    $script:SwapHistory = @()
    $script:SwapBaseline = [int64]-1
    $script:SwapBaselineSamples = 0
    $script:SwapState = 'warming'
    $script:SwapReason = (Get-Text 'Reason_warming')
    $script:SwapCandidate = ''
    $script:SwapCandidateSince = [datetime]::MinValue
    $script:SwapEvidenceAt = [datetime]::MinValue
    $script:SwapOn = $false
}

function Get-MemoryEvidence($history, [int64]$baseline, [int64]$total) {
    $last = $history[-1]
    $first = $history[0]
    $span = ($last.Time - $first.Time).TotalSeconds
    $ratio = [double]$last.Used / $total
    $sharedDelta = $last.Shared - $first.Shared
    $dedicatedDelta = $last.Dedicated - $first.Dedicated
    $growthThreshold = [Math]::Max([double]64MB, $total * 0.004)
    $excess = [int64]0
    if ($baseline -ge 0) { $excess = $last.Shared - $baseline }
    # A large, constant shared allocation alone is not swap evidence.
    $growing = $span -ge 4 -and $sharedDelta -ge $growthThreshold
    $plateau = $dedicatedDelta -le 64MB
    $aboveBaseline = $baseline -lt 0 -or $excess -ge 256MB
    $suspected = $ratio -ge 0.90 -and $growing -and $plateau -and $aboveBaseline
    return [pscustomobject]@{ Ratio = $ratio; SharedDelta = $sharedDelta; DedicatedDelta = $dedicatedDelta; Suspected = $suspected }
}

function Update-SwapState([bool]$arkRunning, [int64]$vramUsed, [int64]$vramTotal, [int64]$nonLocal, [int64]$arkDedicated, [bool]$valid, [datetime]$now = [datetime]::UtcNow) {
    if (-not $arkRunning) {
        Reset-SwapTracking
        $script:SwapState = 'idle'
        $script:SwapReason = (Get-Text 'Reason_idle')
        return
    }
    if (-not $valid -or $vramTotal -le 0) {
        Reset-SwapTracking
        $script:SwapState = 'unknown'
        $script:SwapReason = (Get-Text 'Reason_unknown')
        return
    }
    $script:SwapHistory = @($script:SwapHistory | Where-Object { ($now - $_.Time).TotalSeconds -le 15 })
    $script:SwapHistory += [pscustomobject]@{ Time = $now; Used = $vramUsed; Shared = $nonLocal; Dedicated = $arkDedicated }
    $ratio = [double]$vramUsed / $vramTotal
    # Learn the normal shared allocation only while memory pressure is low.
    if ($ratio -lt 0.80) {
        if ($script:SwapBaseline -lt 0) { $script:SwapBaseline = $nonLocal }
        else { $script:SwapBaseline = [int64]($script:SwapBaseline * 0.9 + $nonLocal * 0.1) }
        $script:SwapBaselineSamples++
    }
    $evidence = Get-MemoryEvidence $script:SwapHistory $script:SwapBaseline $vramTotal
    $span = ($now - $script:SwapHistory[0].Time).TotalSeconds
    $want = 'normal'
    if ($span -lt 5) { $want = 'warming' }
    elseif ($evidence.Suspected) { $want = 'suspected'; $script:SwapEvidenceAt = $now }
    elseif ($ratio -ge 0.85) {
        $want = 'pressure'
        # Briefly retain recent evidence; never latch on a static shared allocation forever.
        if ($script:SwapState -eq 'suspected' -and ($now - $script:SwapEvidenceAt).TotalSeconds -lt 6 -and $evidence.SharedDelta -gt -128MB) { $want = 'suspected' }
    }
    if ($want -ne $script:SwapCandidate) { $script:SwapCandidate = $want; $script:SwapCandidateSince = $now }
    $hold = 3
    if ($want -eq 'normal') { $hold = 5 }
    $firstDecision = $script:SwapState -in @('idle', 'unknown', 'warming') -and $want -ne 'suspected'
    if ($want -eq 'warming' -or $firstDecision -or ($now - $script:SwapCandidateSince).TotalSeconds -ge $hold) {
        $script:SwapState = $want
    }
    $script:SwapOn = $script:SwapState -eq 'suspected'
    switch ($script:SwapState) {
        'warming' { $script:SwapReason = (Get-Text 'Reason_warming') }
        'normal' { $script:SwapReason = (Get-Text 'Reason_normal') }
        'pressure' { $script:SwapReason = (Get-Text 'Reason_pressure') }
        'suspected' { $script:SwapReason = (Get-Text 'Reason_suspected') }
    }
}

function Get-Sample {
    $procs = @(Get-ArkProcesses)
    $now = [datetime]::UtcNow
    $cpuTotal = 0.0
    $cpuValid = $false
    try {
        $nativeCpu = [ArkResmon.CpuSampler]::Read()
        if (-not [double]::IsNaN($nativeCpu)) { $cpuTotal = $nativeCpu; $cpuValid = $true }
    } catch { }
    if ($cpuTotal -lt 0) { $cpuTotal = 0 }
    if ($cpuTotal -gt 100) { $cpuTotal = 100 }

    $cpuTime = Get-ArkCpuTime $procs
    $cpuKey = (@($procs | ForEach-Object { $_.Id } | Sort-Object) -join ',')
    if ($cpuKey -ne $script:CpuProcessKey) {
        $script:LastCpuStamp = [datetime]::MinValue
        $script:CpuProcessKey = $cpuKey
    }
    $cpuArk = 0.0
    if ($script:LastCpuStamp -ne [datetime]::MinValue) {
        $elapsed = ($now - $script:LastCpuStamp).TotalSeconds
        if ($elapsed -gt 0.05) {
            $delta = ($cpuTime - $script:LastCpuTime).TotalSeconds
            if ($delta -lt 0) { $delta = 0 }
            $cpuArk = ($delta / $elapsed) / $script:LogicalProcessors * 100
        }
    }
    $script:LastCpuTime = $cpuTime
    $script:LastCpuStamp = $now
    if ($cpuArk -lt 0) { $cpuArk = 0 }
    if ($cpuArk -gt 100) { $cpuArk = 100 }
    if ($cpuArk -gt $cpuTotal) { $cpuTotal = $cpuArk }
    $cpuExt = $cpuTotal - $cpuArk

    $smiUtil = Update-NvidiaInfo
    try { Sync-ArkCounters $procs } catch { $script:LastCounterSync = [datetime]::MinValue; $script:LastGpuSyncError = $_.Exception.Message }
    $gpuArk = Get-ArkGpuUtil
    $gpuTotal = $smiUtil
    if ($gpuArk -gt $gpuTotal) { $gpuTotal = $gpuArk }
    $gpuExt = $gpuTotal - $gpuArk

    $vramArk = Get-ArkVramBytes
    $vramNonLocal = Get-ArkNonLocalBytes
    $vramUsed = [int64]0
    $adapterOk = $null -ne $script:AdapterCounter
    if ($script:AdapterCounter) {
        try { $vramUsed = [int64]$script:AdapterCounter.RawValue } catch { $vramUsed = 0; $adapterOk = $false }
    }
    if (-not $adapterOk -and $script:SmiVramValid) { $vramUsed = $script:SmiVramUsed }
    if ($vramArk -gt $vramUsed) { $vramUsed = $vramArk }
    $vramTotal = $script:VramTotal
    $vramExt = $vramUsed - $vramArk
    $vramFree = [Math]::Max([int64]0, ($vramTotal - $vramUsed))

    $ramTotal = [int64]$script:ComputerInfo.TotalPhysicalMemory
    $ramFree = [int64]$script:ComputerInfo.AvailablePhysicalMemory
    if ($ramFree -gt $ramTotal) { $ramFree = $ramTotal }
    $ramUsed = $ramTotal - $ramFree
    $ramArk = Get-ArkWorkingSet $procs
    if ($ramArk -lt 0) { $ramArk = 0 }
    $ramExt = $ramUsed - $ramArk
    if ($ramExt -lt 0) {
        $ramExt = 0
        if ($ramArk -gt $ramTotal) { $ramArk = $ramTotal }
        $ramFree = $ramTotal - $ramArk
        if ($ramFree -lt 0) { $ramFree = 0 }
    }

    $memoryValid = $adapterOk -and $script:VramReadOk -and $script:NonLocalReadOk -and $script:SmiHealthy
    Update-SwapState ($procs.Count -gt 0) $vramUsed $vramTotal $vramNonLocal $vramArk $memoryValid
    $stateText = @{ idle = (Get-Text 'idle'); warming = (Get-Text 'warming'); normal = (Get-Text 'normal'); pressure = (Get-Text 'pressure'); suspected = (Get-Text 'suspected'); unknown = (Get-Text 'unknown') }
    $swapText = $stateText[$script:SwapState]

    $main = @($procs | Where-Object { $_.ProcessName -eq 'ArkAscended' } | Select-Object -First 1)
    $pidText = ''
    if ($main.Count -gt 0) { $pidText = [string]$main[0].Id }

    $sample = [pscustomobject]@{
        ArkRunning = ($procs.Count -gt 0)
        ArkPid     = $pidText
        CpuArk     = $cpuArk
        CpuExt     = $cpuExt
        CpuTotal   = $cpuTotal
        CpuValid   = $cpuValid
        GpuArk     = $gpuArk
        GpuExt     = $gpuExt
        GpuTotal   = $gpuTotal
        VramArk    = $vramArk
        VramExt    = $vramExt
        VramFree   = $vramFree
        VramTotal  = $vramTotal
        VramUsed   = $vramUsed
        VramNonLocal = $vramNonLocal
        Swap       = [bool]$script:SwapOn
        SwapText   = $swapText
        MemoryState = $script:SwapState
        MemoryReason = $script:SwapReason
        MemoryValid = $memoryValid
        VramValid = (($adapterOk -or $script:SmiVramValid) -and $vramTotal -gt 0)
        VramSplitValid = ($procs.Count -eq 0 -or ($adapterOk -and $script:VramReadOk))
        VramSource = $(if ($adapterOk) { 'Windows' } else { 'NVIDIA' })
        GpuValid = $script:SmiUtilValid
        ArkGpuValid = ($procs.Count -eq 0 -or $script:UtilCounters.Count -gt 0)
        SharedBaseline = $script:SwapBaseline
        RamArk     = $ramArk
        RamExt     = $ramExt
        RamFree    = $ramFree
        RamTotal   = $ramTotal
        RamUsed    = $ramUsed
        GpuName    = $script:GpuName
        SampleTime = [datetime]::Now
    }
    $script:LastSample = $sample
    return $sample
}

function Initialize-CpuSampler {
    if ('ArkResmon.CpuSampler' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace ArkResmon
{
    public static class CpuSampler
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct FileTime { public uint Low; public uint High; }
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetSystemTimes(out FileTime idle, out FileTime kernel, out FileTime user);
        private static ulong lastIdle, lastTotal;
        private static bool ready;

        private static ulong Ticks(FileTime value) { return ((ulong)value.High << 32) | value.Low; }

        public static double Read()
        {
            FileTime idle, kernel, user;
            if (!GetSystemTimes(out idle, out kernel, out user)) { ready = false; return double.NaN; }
            ulong idleNow = Ticks(idle);
            ulong totalNow = Ticks(kernel) + Ticks(user);
            double result = double.NaN;
            if (ready && totalNow > lastTotal && idleNow >= lastIdle)
            {
                ulong totalDelta = totalNow - lastTotal;
                ulong idleDelta = idleNow - lastIdle;
                result = Math.Max(0.0, Math.Min(100.0, 100.0 * (1.0 - (double)idleDelta / totalDelta)));
            }
            lastIdleUsage = idleNow; lastTotal = totalNow; ready = true;
            return result;
        }
    }
}
'@
}

function Initialize-Counters {
    try { Initialize-CpuSampler; [void][ArkResmon.CpuSampler]::Read() } catch { }
    try { Initialize-Gpu } catch { $script:AdapterCounter = $null; $script:LastGpuInitError = $_.Exception.Message }
    [void](Update-NvidiaInfo)
}

function Enable-DoubleBuffer($control) {
    $flags = [System.Reflection.BindingFlags]'Instance,NonPublic'
    $prop = $control.GetType().GetProperty('DoubleBuffered', $flags)
    if ($prop) { $prop.SetValue($control, $true, $null) }
}

function New-BarPanel {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size(592, 14)
    $panel.BackColor = $script:ColorCard
    $panel.Tag = @{ Ark = 0.0; Ext = 0.0; Total = 100.0 }
    Enable-DoubleBuffer $panel
    $panel.Add_Paint({
        param($sender, $eventArgs)
        $g = $eventArgs.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $data = $sender.Tag
        $total = [double]$data.Total
        $ark = [double]$data.Ark
        $ext = [double]$data.Ext
        $width = [Math]::Max(1, $sender.ClientSize.Width)
        $height = [Math]::Max(1, $sender.ClientSize.Height)
        $rect = New-Object System.Drawing.RectangleF(0.5, 0.5, ($width - 1), ($height - 1))
        $path = Get-RoundedPath $rect 2
        $arkPx = 0
        $extPx = 0
        if ($total -gt 0) {
            $arkPx = [int][Math]::Round($width * ($ark / $total))
            $extPx = [int][Math]::Round($width * ($ext / $total))
            if ($arkPx -lt 0) { $arkPx = 0 }
            if ($extPx -lt 0) { $extPx = 0 }
            if (($arkPx + $extPx) -gt $width) { $extPx = $width - $arkPx }
        }
        $g.SetClip($path)
        $g.FillRectangle($script:BrushTrack, 0, 0, $width, $height)
        if ($arkPx -gt 0) { $g.FillRectangle($script:BrushArk, 0, 0, $arkPx, $height) }
        $otherBrush = $script:BrushExt
        if ($data.Unassigned) { $otherBrush = $script:BrushUnknown }
        if ($extPx -gt 0) { $g.FillRectangle($otherBrush, $arkPx, 0, $extPx, $height) }
        $g.ResetClip()
        $g.DrawPath($script:PenLine, $path)
        $path.Dispose()
    })
    return $panel
}

function New-TextLabel([string]$text, [single]$size, [bool]$bold, $color) {
    $label = New-Object System.Windows.Forms.Label
    $style = [System.Drawing.FontStyle]::Regular
    if ($bold) { $style = [System.Drawing.FontStyle]::Bold }
    $label.Font = New-Object System.Drawing.Font('Malgun Gothic', $size, $style)
    $label.UseCompatibleTextRendering = $false
    $label.ForeColor = $color
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label.AutoSize = $false
    $label.Text = $text
    return $label
}

function Set-Bar($panel, [double]$ark, [double]$ext, [double]$total, [bool]$unassigned = $false) {
    $panel.Tag = @{ Ark = $ark; Ext = $ext; Total = $total; Unassigned = $unassigned }
    $panel.Invalidate()
}

function New-Card([string]$title, [string]$thirdCaption) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Size = New-Object System.Drawing.Size(476, 54)
    $card.BackColor = $script:ColorBg
    Enable-DoubleBuffer $card
    $card.Add_Paint({ param($sender, $eventArgs); $eventArgs.Graphics.DrawLine($script:PenLine, 0, ($sender.Height - 1), $sender.Width, ($sender.Height - 1)) })
    $titleLabel = New-TextLabel $title 8.5 $true $script:ColorText
    $titleLabel.SetBounds(0, 1, 160, 23)
    $totalLabel = New-TextLabel '' 12 $false $script:ColorText
    $totalLabel.Font = New-Object System.Drawing.Font('Segoe UI', 12)
    $totalLabel.TextAlign = 'MiddleRight'
    $totalLabel.SetBounds(190, 0, 286, 25)
    $bar = New-BarPanel
    $bar.BackColor = $script:ColorBg
    $bar.SetBounds(0, 27, 476, 5)
    $arkLabel = New-TextLabel '' 8 $false $script:ColorArk
    $arkLabel.SetBounds(0, 35, 152, 18)
    $extLabel = New-TextLabel '' 8 $false $script:ColorExt
    $extLabel.SetBounds(162, 35, 156, 18)
    $freeLabel = New-TextLabel '' 8 $false $script:ColorMuted
    $freeLabel.TextAlign = 'MiddleRight'
    $freeLabel.SetBounds(324, 35, 152, 18)
    $card.Controls.AddRange(@($titleLabel, $totalLabel, $bar, $arkLabel, $extLabel, $freeLabel))
    return [pscustomobject]@{ Panel = $card; Title = $titleLabel; Total = $totalLabel; Bar = $bar; Ark = $arkLabel; Ext = $extLabel; Free = $freeLabel; Third = $thirdCaption }
}

function Update-Ui($sample) {
    $script:UiSample = $sample
    $ui.GpuLine.Text = $sample.GpuName
    $ui.Status.ForeColor = $script:ColorText
    if ($sample.ArkRunning) {
        $ui.Status.Text = (Get-Text 'Running')
        $ui.Session.Text = ((Get-Text 'Session') -f $sample.ArkPid, $sample.SampleTime.ToString('HH:mm:ss'))
    } else {
        $ui.Status.Text = (Get-Text 'Waiting')
        $ui.Session.Text = ((Get-Text 'AutoConnect') -f $sample.SampleTime.ToString('HH:mm:ss'))
    }
    $ui.MemoryState.Text = Get-Text $sample.MemoryState
    $ui.MemoryState.ForeColor = $script:ColorMuted
    if ($sample.MemoryState -eq 'normal') { $ui.MemoryState.ForeColor = $script:ColorOk }
    if ($sample.MemoryState -eq 'pressure') { $ui.MemoryState.ForeColor = $script:ColorWarn }
    if ($sample.MemoryState -eq 'suspected') { $ui.MemoryState.ForeColor = $script:ColorSwapBad }
    $ui.Reason.Text = Get-Text ('Reason_' + $sample.MemoryState)
    $ui.Shared.Text = "$(Get-Text 'Shared')   $(Format-MB $sample.VramNonLocal)"
    if ($sample.ArkRunning -and -not $sample.MemoryValid) { $ui.Shared.Text = "$(Get-Text 'Shared')   $(Get-Text 'unknown')" }
    Set-AvatarState $sample
    $ui.Cpu.Total.Text = Format-Pct $sample.CpuTotal
    Set-Bar $ui.Cpu.Bar $sample.CpuArk $sample.CpuExt 100
    $ui.Cpu.Ark.Text = "ARK   $(Format-Pct $sample.CpuArk)"
    $ui.Cpu.Ext.Text = "$(Get-Text 'External')   $(Format-Pct $sample.CpuExt)"
    $ui.Cpu.Free.Text = "$(Get-Text 'IdleUsage')   $(Format-Pct ([Math]::Max(0.0, (100.0 - $sample.CpuTotal))))"
    if (-not $sample.CpuValid) {
        $ui.Cpu.Total.Text = '—'
        $ui.Cpu.Ext.Text = "$(Get-Text 'External')   $(Get-Text 'unknown')"
        $ui.Cpu.Free.Text = ''
        Set-Bar $ui.Cpu.Bar $sample.CpuArk 0 100
    }
    $ui.Gpu.Total.Text = Format-Pct $sample.GpuTotal
    Set-Bar $ui.Gpu.Bar $sample.GpuArk $sample.GpuExt 100
    $ui.Gpu.Ark.Text = "ARK   $(Format-Pct $sample.GpuArk)"
    $ui.Gpu.Ext.Text = "$(Get-Text 'External') ≈ $(Format-Pct $sample.GpuExt)"
    $ui.Gpu.Free.Text = "$(Get-Text 'IdleUsage')   $(Format-Pct ([Math]::Max(0.0, (100.0 - $sample.GpuTotal))))"
    if ($sample.GpuValid -and -not $sample.ArkGpuValid) {
        $ui.Gpu.Ark.Text = "ARK   $(Get-Text 'unknown')"
        $ui.Gpu.Ext.Text = "$(Get-Text 'External')   $(Get-Text 'unknown')"
        Set-Bar $ui.Gpu.Bar 0 $sample.GpuTotal 100 $true
    }
    if (-not $sample.GpuValid) {
        $ui.Gpu.Total.Text = '—'
        $ui.Gpu.Ark.Text = "ARK   $(Get-Text 'unknown')"
        $ui.Gpu.Ext.Text = "$(Get-Text 'External')   $(Get-Text 'unknown')"
        $ui.Gpu.Free.Text = ''
        Set-Bar $ui.Gpu.Bar 0 0 100
    }
    $vramParts = Split-Capacity $sample.VramArk $sample.VramExt $sample.VramTotal
    $ui.GpuMem.Total.Text = ('{0:N1} / {1:N1} GB' -f ($sample.VramUsed / 1GB), ($sample.VramTotal / 1GB))
    Set-Bar $ui.GpuMem.Bar $vramParts.Ark $vramParts.Ext ([Math]::Max(1, $vramParts.Total))
    $ui.GpuMem.Ark.Text = "ARK   $(Format-MB $sample.VramArk)"
    $ui.GpuMem.Ext.Text = "$(Get-Text 'External') ≈ $(Format-MB $sample.VramExt)"
    $ui.GpuMem.Free.Text = "$(Get-Text 'Free')   $(Format-MB $sample.VramFree)"
    if ($sample.VramValid -and -not $sample.VramSplitValid) {
        $ui.GpuMem.Ark.Text = "ARK   $(Get-Text 'unknown')"
        $ui.GpuMem.Ext.Text = "$(Get-Text 'External')   $(Get-Text 'unknown')"
        Set-Bar $ui.GpuMem.Bar 0 $sample.VramUsed $sample.VramTotal $true
    }
    if (-not $sample.VramValid -or $sample.VramTotal -le 0) {
        $ui.GpuMem.Total.Text = '—'
        $ui.GpuMem.Ark.Text = "ARK   $(Get-Text 'unknown')"
        $ui.GpuMem.Ext.Text = "$(Get-Text 'External')   $(Get-Text 'unknown')"
        $ui.GpuMem.Free.Text = ''
        Set-Bar $ui.GpuMem.Bar 0 0 1
    }
    $ramParts = Split-Capacity $sample.RamArk $sample.RamExt $sample.RamTotal
    $ui.Ram.Total.Text = ('{0:N1} / {1:N1} GB' -f ($sample.RamUsed / 1GB), ($sample.RamTotal / 1GB))
    Set-Bar $ui.Ram.Bar $ramParts.Ark $ramParts.Ext ([Math]::Max(1, $ramParts.Total))
    $ui.Ram.Ark.Text = "ARK   $(Format-MB $sample.RamArk)"
    $ui.Ram.Ext.Text = "$(Get-Text 'External')   $(Format-MB $sample.RamExt)"
    $ui.Ram.Free.Text = "$(Get-Text 'Free')   $(Format-MB $sample.RamFree)"
}

function Load-AvatarImages {
    $gifFolder = Join-Path $script:CharacterRoot 'gifs'
    $legacyFolder = Join-Path $script:CharacterRoot 'assets\character'
    $names = @{ idle = 'fun'; running = 'cheer'; pressure = 'sick'; suspected = 'dizzy'; unknown = 'unknown' }
    foreach ($state in @('idle', 'running', 'pressure', 'suspected', 'unknown')) {
        $name = $names[$state]
        $paths = @(
            (Join-Path $gifFolder "${name}_64x64.gif"),
            (Join-Path $gifFolder "${name}_64x64.png"),
            (Join-Path $legacyFolder "$state.gif"),
            (Join-Path $legacyFolder "$state.png")
        )
        foreach ($path in $paths) {
            if (Test-Path -LiteralPath $path) {
                try {
                    $asset = [System.Drawing.Image]::FromFile($path)
                    if ($asset.Width -ne 64 -or $asset.Height -ne 64) { $asset.Dispose(); continue }
                    $asset.Tag = $path
                    $script:AvatarImages[$state] = $asset
                    break
                } catch { }
            }
        }
    }
}

function Set-AvatarState($sample) {
    $state = 'idle'
    if ($sample.ArkRunning) {
        $state = 'running'
        if ($sample.MemoryState -in @('pressure', 'suspected', 'unknown')) { $state = $sample.MemoryState }
    }
    if ($state -eq $script:AvatarState) { return }
    $script:AvatarState = $state
    $asset = $script:AvatarImages[$state]
    if (-not $asset -and $state -ne 'idle') { $asset = $script:AvatarImages['running'] }
    if (-not $asset) { $asset = $script:AvatarImages['idle'] }
    $ui.Avatar.Image = $asset
    $ui.Avatar.Invalidate()
}

function New-AvatarSlot {
    $slot = New-Object System.Windows.Forms.PictureBox
    $slot.Size = New-Object System.Drawing.Size(64, 64)
    $slot.SizeMode = 'Normal'
    $slot.BackColor = $script:ColorCard
    Enable-DoubleBuffer $slot
    $slot.AccessibleName = '64 x 64 상태 캐릭터'
    $slot.Add_Paint({
        param($sender, $eventArgs)
        if ($sender.Image) { return }
        $g = $eventArgs.Graphics
        $g.DrawRectangle($script:PenLine, 0, 0, 63, 63)
        $font = New-Object System.Drawing.Font('Segoe UI', 8)
        $brush = New-Object System.Drawing.SolidBrush $script:ColorMuted
        $format = New-Object System.Drawing.StringFormat
        $format.Alignment = 'Center'; $format.LineAlignment = 'Center'
        $g.DrawString("64 × 64", $font, $brush, (New-Object System.Drawing.RectangleF(0, 0, 64, 64)), $format)
        $font.Dispose(); $brush.Dispose(); $format.Dispose()
    })
    return $slot
}

function Get-DiagnosticReport {
    $os = [ordered]@{ ReportedVersion = [Environment]::OSVersion.VersionString; Build = ''; Product = '' }
    try {
        $os.Build = [Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion', 'CurrentBuildNumber', '')
        $os.Product = [Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion', 'ProductName', '')
    } catch { }
    $appVersion = 'PowerShell source'
    $entry = [Reflection.Assembly]::GetEntryAssembly()
    if ($entry -and $entry.GetName().Name -eq 'ARK_Resmon') { $appVersion = $entry.GetName().Version.ToString() }
    return [pscustomobject][ordered]@{
        AppVersion = $appVersion
        OS = $os
        Process64Bit = [Environment]::Is64BitProcess
        GpuName = $script:GpuName
        DriverVersion = $script:DriverVersion
        Nvidia = [ordered]@{
            Path = $script:Smi
            LastError = $script:LastSmiError
            QueryValid = $script:SmiHealthy
            LoadValid = $script:SmiUtilValid
            UsedMemoryValid = $script:SmiVramValid
            TotalMB = (Convert-MB $script:VramTotal)
            UsedMB = (Convert-MB $script:SmiVramUsed)
        }
        WindowsGpuCounters = [ordered]@{
            AdapterValid = ($null -ne $script:AdapterCounter)
            AdapterInitError = $script:LastGpuInitError
            ProcessQueryError = $script:LastGpuSyncError
            Luid = $script:NvLuid
            ArkPids = $script:ArkKey
            EngineCounters = $script:UtilCounters.Count
            DedicatedCounters = $script:VramCounters.Count
            NonLocalCounters = $script:NonLocalCounters.Count
        }
        Sample = $script:LastSample
    }
}

function Show-DiagnosticDialog {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = (Get-Text 'DiagnosticTitle')
    $dialog.StartPosition = 'CenterParent'
    $dialog.ClientSize = New-Object System.Drawing.Size(680, 490)
    $dialog.BackColor = $script:ColorBg
    $text = New-Object System.Windows.Forms.TextBox
    $text.Multiline = $true; $text.ReadOnly = $true; $text.ScrollBars = 'Both'; $text.WordWrap = $false
    $text.Font = New-Object System.Drawing.Font('Consolas', 9)
    $text.ForeColor = $script:ColorText; $text.BackColor = $script:ColorCard
    $text.SetBounds(16, 16, 648, 416)
    $text.Anchor = 'Top,Bottom,Left,Right'
    $text.Text = (Get-DiagnosticReport | ConvertTo-Json -Depth 6)
    $copy = New-Object System.Windows.Forms.Button
    $copy.Text = (Get-Text 'Copy'); $copy.SetBounds(516, 447, 148, 28)
    $copy.Anchor = 'Bottom,Right'; $copy.ForeColor = $script:ColorText; $copy.FlatStyle = 'Flat'
    $copy.Tag = $text
    $copy.Add_Click({
        try { [Windows.Forms.Clipboard]::SetText($this.Tag.Text); $this.Text = (Get-Text 'Copied') }
        catch { $this.Text = (Get-Text 'Retry') }
    })
    $note = New-TextLabel (Get-Text 'DiagnosticNote') 8 $false $script:ColorMuted
    $note.SetBounds(16, 450, 450, 24); $note.Anchor = 'Bottom,Left'
    $dialog.Controls.AddRange(@($text, $copy, $note))
    try { [void]$dialog.ShowDialog($script:Ui.Form) } finally { $dialog.Dispose() }
}

function New-MonitorForm {
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'ARK Resmon'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedSingle'
    $form.MaximizeBox = $false
    $form.AutoScaleMode = 'None'
    $form.ClientSize = New-Object System.Drawing.Size(500, 446)
    $form.BackColor = $script:ColorBg
    $form.Font = New-Object System.Drawing.Font('Malgun Gothic', 9)
    $form.KeyPreview = $true
    Enable-DoubleBuffer $form
    $title = New-TextLabel "Chomiles's ASA Resource Monitor" 12 $true $script:ColorText
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $title.SetBounds(12, 5, 310, 25)
    $gpuLine = New-TextLabel '' 8 $false $script:ColorMuted
    $gpuLine.SetBounds(12, 34, 300, 20)
    $topMost = New-Object System.Windows.Forms.CheckBox
    $topMost.Text = (Get-Text 'TopMost')
    $topMost.ForeColor = $script:ColorMuted
    $topMost.BackColor = $script:ColorBg
    $topMost.FlatStyle = 'Flat'
    $topMost.Font = New-Object System.Drawing.Font('Malgun Gothic', 8)
    $topMost.SetBounds(380, 32, 108, 22)
    $topMost.Add_CheckedChanged({ $this.FindForm().TopMost = $this.Checked })
    $statusPanel = New-Object System.Windows.Forms.Panel
    $statusPanel.BackColor = $script:ColorCard
    $statusPanel.SetBounds(12, 60, 476, 76)
    $avatar = New-AvatarSlot
    $avatar.Location = New-Object System.Drawing.Point(6, 6)
    $status = New-TextLabel (Get-Text 'warming') 10 $true $script:ColorText
    $status.SetBounds(82, 9, 226, 23)
    $session = New-TextLabel '' 8 $false $script:ColorMuted
    $session.SetBounds(82, 39, 382, 22)
    $memoryState = New-TextLabel (Get-Text 'idle') 8.5 $true $script:ColorMuted
    $memoryState.TextAlign = 'MiddleRight'
    $memoryState.SetBounds(320, 11, 144, 21)
    $statusPanel.Controls.AddRange(@($avatar, $status, $session, $memoryState))
    $legendArk = New-TextLabel '● ARK' 8 $false $script:ColorArk
    $legendArk.SetBounds(12, 140, 48, 18)
    $legendExt = New-TextLabel ('● ' + (Get-Text 'External')) 8 $false $script:ColorExt
    $legendExt.SetBounds(66, 140, 82, 18)
    $legend = New-TextLabel (Get-Text 'Legend') 7.5 $false $script:ColorMuted
    $legend.SetBounds(152, 140, 254, 18)
    $units = New-TextLabel (Get-Text 'Total') 8 $false $script:ColorMuted
    $units.TextAlign = 'MiddleRight'
    $units.SetBounds(412, 140, 76, 18)
    $cpu = New-Card 'CPU' (Get-Text 'IdleUsage'); $cpu.Panel.Location = New-Object System.Drawing.Point(12, 160)
    $gpu = New-Card 'GPU' (Get-Text 'IdleUsage'); $gpu.Panel.Location = New-Object System.Drawing.Point(12, 214)
    $gpuMem = New-Card (Get-Text 'GpuMemory') (Get-Text 'Free'); $gpuMem.Panel.Location = New-Object System.Drawing.Point(12, 268)
    $ram = New-Card (Get-Text 'SystemMemory') (Get-Text 'Free'); $ram.Panel.Location = New-Object System.Drawing.Point(12, 322)
    $shared = New-TextLabel '' 8 $false $script:ColorText
    $shared.SetBounds(12, 384, 476, 20)
    $reason = New-TextLabel '' 7.5 $false $script:ColorMuted
    $reason.SetBounds(12, 409, 476, 34)
    $tips = New-Object System.Windows.Forms.ToolTip
    $languageButtons = @{}
    $languageNames = @{ KOR = '한국어'; JPN = '日本語'; ENG = 'English' }
    $index = 0
    foreach ($code in @('KOR', 'JPN', 'ENG')) {
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $code
        $button.Tag = $code
        $button.AccessibleName = $languageNames[$code]
        $button.Font = New-Object System.Drawing.Font('Segoe UI', 8)
        $button.FlatStyle = 'Flat'
        $button.SetBounds((332 + $index * 54), 6, 48, 24)
        $button.Anchor = 'Top,Right'
        $button.Add_Click({ Set-UiLanguage ([string]$this.Tag) })
        $tips.SetToolTip($button, $languageNames[$code])
        $languageButtons[$code] = $button
        $form.Controls.Add($button)
        $index++
    }
    $form.Controls.AddRange(@($title, $gpuLine, $topMost, $statusPanel, $legendArk, $legendExt, $legend, $units, $cpu.Panel, $gpu.Panel, $gpuMem.Panel, $ram.Panel, $shared, $reason))
    $tips.SetToolTip($title, "Chomiles's ASA Resource Monitor")
    $tips.SetToolTip($gpuLine, $script:GpuName)
    $form.Add_KeyDown({ param($sender, $eventArgs); if ($eventArgs.KeyCode -eq 'Escape') { $sender.Close() } })
    $script:Ui = [pscustomobject]@{ Form = $form; Title = $title; GpuLine = $gpuLine; Status = $status; Session = $session; MemoryState = $memoryState; Avatar = $avatar; Shared = $shared; Reason = $reason; Cpu = $cpu; Gpu = $gpu; GpuMem = $gpuMem; Ram = $ram; Tips = $tips; TopMost = $topMost; LegendExt = $legendExt; Legend = $legend; Units = $units; LanguageButtons = $languageButtons }
    Set-UiLanguage $script:Language
    Load-AvatarImages
    return $form
}


function Invoke-MemoryLogicTests {
    $start = [datetime]'2026-01-01T00:00:00Z'
    function Assert-State([string]$expected, [string]$name) {
        if ($script:SwapState -ne $expected) { throw "$name expected $expected, got $($script:SwapState)" }
        Write-Host "PASS $name"
    }
    Reset-SwapTracking
    Update-SwapState $false 0 16GB 0 0 $true $start
    Assert-State 'idle' 'game-absent'
    Update-SwapState $true 15GB 16GB 1GB 12GB $false $start
    Assert-State 'unknown' 'missing-counters-not-normal'
    Reset-SwapTracking
    for ($i = 0; $i -le 20; $i++) { Update-SwapState $true 6GB 16GB 1GB 5GB $true ($start.AddSeconds($i)) }
    Assert-State 'normal' 'normal-shared-allocation'
    Reset-SwapTracking
    for ($i = 0; $i -le 20; $i++) { Update-SwapState $true 15GB 16GB 2GB 12GB $true ($start.AddSeconds($i)) }
    Assert-State 'pressure' 'high-static-shared-is-not-swap'
    Reset-SwapTracking
    for ($i = 0; $i -le 25; $i++) { Update-SwapState $true 15GB 16GB (500MB + $i * 24MB) (12GB + $i * 24MB) $true ($start.AddSeconds($i)) }
    Assert-State 'pressure' 'ordinary-concurrent-upload'
    Reset-SwapTracking
    for ($i = 0; $i -le 10; $i++) { Update-SwapState $true 6GB 16GB 300MB 5GB $true ($start.AddSeconds($i)) }
    for ($i = 11; $i -le 35; $i++) { Update-SwapState $true 15GB 16GB (300MB + ($i - 10) * 32MB) 12GB $true ($start.AddSeconds($i)) }
    Assert-State 'suspected' 'pressure-and-shared-growth-with-plateau'
    for ($i = 36; $i -le 65; $i++) { Update-SwapState $true 15GB 16GB 1100MB 12GB $true ($start.AddSeconds($i)) }
    Assert-State 'pressure' 'static-tail-clears-suspicion'
    for ($i = 66; $i -le 80; $i++) { Update-SwapState $true 6GB 16GB 300MB 5GB $true ($start.AddSeconds($i)) }
    Assert-State 'normal' 'recovery'
    Reset-SwapTracking
    for ($i = 0; $i -le 20; $i++) { Update-SwapState $true 15GB 16GB (400MB + $i * 32MB) 12GB $true ($start.AddSeconds($i)) }
    Assert-State 'suspected' 'start-under-pressure-no-baseline'
    Reset-SwapTracking
    for ($i = 0; $i -le 4; $i++) { Update-SwapState $true 15GB 16GB 400MB 12GB $true ($start.AddSeconds($i)) }
    Update-SwapState $true 15GB 16GB 600MB 12GB $true ($start.AddSeconds(5))
    Assert-State 'warming' 'initial-suspicion-requires-persistence'
    Reset-SwapTracking
    Update-SwapState $true 15GB 16GB 2GB 12GB $true $start
    Update-SwapState $true 15GB 16GB 3GB 12GB $true ($start.AddSeconds(30))
    Assert-State 'warming' 'long-gap-restarts-window'
    Reset-SwapTracking
    Write-Host 'MEMORY_LOGIC_OK (11 scenarios)'
}

function Set-PreviewSample($sample) {
    if ($PreviewState -eq 'Live') { return $sample }
    # Explicit snapshot-only fixtures. They never enter live monitoring.
    $sample.ArkRunning = $true; $sample.ArkPid = '12345'
    $sample.CpuArk = 18.4; $sample.CpuExt = 4.2; $sample.CpuTotal = 22.6
    $sample.GpuArk = 89.1; $sample.GpuExt = 3.3; $sample.GpuTotal = 92.4
    $sample.VramArk = 12GB; $sample.VramExt = 1GB; $sample.VramTotal = 16GB
    $sample.VramUsed = 13GB; $sample.VramFree = 3GB; $sample.VramNonLocal = 400MB
    $sample.RamArk = 18GB; $sample.RamExt = 10GB; $sample.RamTotal = 64GB
    $sample.RamUsed = 28GB; $sample.RamFree = 36GB
    $sample.MemoryValid = $true; $sample.GpuValid = $true; $sample.ArkGpuValid = $true
    $sample.CpuValid = $true; $sample.VramValid = $true
    $sample.VramSplitValid = $true; $sample.VramSource = 'Windows'
    switch ($PreviewState) {
        'Running' { $sample.MemoryState = 'normal'; $sample.SwapText = (Get-Text 'normal'); $sample.MemoryReason = (Get-Text 'Reason_normal') }
        'Pressure' { $sample.MemoryState = 'pressure'; $sample.SwapText = (Get-Text 'pressure'); $sample.MemoryReason = (Get-Text 'Reason_pressure'); $sample.VramUsed = 15GB; $sample.VramExt = 3GB; $sample.VramFree = 1GB }
        'Suspected' { $sample.MemoryState = 'suspected'; $sample.SwapText = (Get-Text 'suspected'); $sample.MemoryReason = (Get-Text 'Reason_suspected'); $sample.VramUsed = 15GB; $sample.VramExt = 3GB; $sample.VramFree = 1GB; $sample.VramNonLocal = 1100MB }
        'Unknown' { $sample.MemoryState = 'unknown'; $sample.SwapText = (Get-Text 'unknown'); $sample.MemoryReason = (Get-Text 'Reason_unknown'); $sample.MemoryValid = $false; $sample.GpuValid = $false; $sample.VramValid = $false; $sample.VramSplitValid = $false }
    }
    return $sample
}

if ($PreviewState -ne 'Live' -and -not $SnapshotPath) { throw 'PreviewState requires SnapshotPath' }
if ($LogicTest) { Invoke-MemoryLogicTests; exit 0 }

Initialize-Counters
$procsAtStart = @(Get-ArkProcesses)
$script:CpuProcessKey = (@($procsAtStart | ForEach-Object { $_.Id } | Sort-Object) -join ',')
$script:LastCpuTime = Get-ArkCpuTime $procsAtStart
$script:LastCpuStamp = [datetime]::UtcNow
try { Sync-ArkCounters $procsAtStart } catch { }

if ($SelfTest) {
    Start-Sleep -Milliseconds 1100
    $sample = Get-Sample
    Write-Host ("GPU={0}" -f $sample.GpuName)
    Write-Host ("ARK_RUNNING={0} PID={1}" -f $sample.ArkRunning, $sample.ArkPid)
    Write-Host ("CPU ark={0:N1} ext={1:N1} total={2:N1}" -f $sample.CpuArk, $sample.CpuExt, $sample.CpuTotal)
    Write-Host ("GPU ark={0:N1} ext={1:N1} total={2:N1}" -f $sample.GpuArk, $sample.GpuExt, $sample.GpuTotal)
    Write-Host ("VRAM ark={0:N0} ext={1:N0} free={2:N0} total={3:N0}" -f ($sample.VramArk/1MB), ($sample.VramExt/1MB), ($sample.VramFree/1MB), ($sample.VramTotal/1MB))
    Write-Host ("RAM ark={0:N0} ext={1:N0} free={2:N0} total={3:N0}" -f ($sample.RamArk/1MB), ($sample.RamExt/1MB), ($sample.RamFree/1MB), ($sample.RamTotal/1MB))
    Write-Host ("SWAP={0} TEXT={1} NONLOCAL_MB={2:N0} BASELINE_MB={3}" -f $sample.Swap, $sample.SwapText, ($sample.VramNonLocal/1MB), $(if ($script:SwapBaseline -ge 0) { [string](Convert-MB $script:SwapBaseline) } else { 'none' }))
    Invoke-MemoryLogicTests
    exit 0
}

$form = New-MonitorForm
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    if ($script:Busy) { return }
    $script:Busy = $true
    try {
        Update-Ui (Get-Sample)
    } catch {
        $script:Ui.Status.ForeColor = $script:ColorWarn
        $script:Ui.Status.Text = ((Get-Text 'MeasurementError') -f $_.Exception.Message)
    } finally {
        $script:Busy = $false
    }
})
$form.Add_Shown({
    try { Update-Ui (Get-Sample) } catch { $script:Ui.Status.Text = ((Get-Text 'MeasurementError') -f $_.Exception.Message) }
    $timer.Start()
})
$form.Add_FormClosed({
    $timer.Stop()
    $script:Ui.Avatar.Image = $null
    foreach ($asset in $script:AvatarImages.Values) { $asset.Dispose() }
    $script:Ui.Tips.Dispose()
    $timer.Dispose()
    Clear-ArkCounters
    if ($script:AdapterCounter) { $script:AdapterCounter.Dispose() }
    if ($script:CpuCounter) { $script:CpuCounter.Dispose() }
    $script:BrushArk.Dispose()
    $script:BrushExt.Dispose()
    $script:BrushTrack.Dispose()
    $script:BrushUnknown.Dispose()
    $script:BrushSwapOk.Dispose()
    $script:BrushSwapBad.Dispose()
    $script:PenLine.Dispose()
})

if ($SnapshotPath) {
    $form.Add_Shown({
        Start-Sleep -Milliseconds 1100
        try {
            Update-Ui (Set-PreviewSample (Get-Sample))
            $form.Refresh()
            # DrawToBitmap includes window chrome. Crop it instead of truncating the footer.
            $wholeBitmap = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
            $form.DrawToBitmap($wholeBitmap, (New-Object System.Drawing.Rectangle(0, 0, $wholeBitmap.Width, $wholeBitmap.Height)))
            $origin = $form.PointToScreen([System.Drawing.Point]::Empty)
            $crop = New-Object System.Drawing.Rectangle(($origin.X - $form.Left), ($origin.Y - $form.Top), $form.ClientSize.Width, $form.ClientSize.Height)
            $bitmap = $wholeBitmap.Clone($crop, $wholeBitmap.PixelFormat)
            $bitmap.Save($SnapshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $bitmap.Dispose()
            $wholeBitmap.Dispose()
        } finally {
            $form.Close()
        }
    })
}

[void]$form.ShowDialog()
exit 0
