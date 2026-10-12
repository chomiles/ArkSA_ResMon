# Runs without GPU counters. Temporary test images never enter the character folder.
$ErrorActionPreference = 'Stop'
$monitorPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'monitor.ps1'
$source = [IO.File]::ReadAllText($monitorPath)
$boundary = $source.IndexOf("if (`$PreviewState -ne 'Live' -and -not `$SnapshotPath)")
if ($boundary -lt 0) { throw 'Startup boundary missing' }
. ([scriptblock]::Create($source.Substring(0, $boundary)))
$fixtureFolder = Join-Path ([IO.Path]::GetTempPath()) ('ark-resmon-ui-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureFolder)
$fixtureLegacy = Join-Path $fixtureFolder 'assets\character'
$fixtureGifs = Join-Path $fixtureFolder 'gifs'
[void][IO.Directory]::CreateDirectory($fixtureLegacy)
[void][IO.Directory]::CreateDirectory($fixtureGifs)

function Assert-Ui([bool]$ok, [string]$name) {
    if (-not $ok) { throw $name }
    Write-Host "PASS $name"
}

try {
    # GIF canvas is 64x64 with two independently timed 1x1 frames.
    # Tests image loading and animated format preservation without drawing a character.
    $gif = [byte[]](71,73,70,56,57,97,64,0,64,0,128,0,0,216,180,111,116,143,163)
    $frame = [byte[]](33,249,4,0,10,0,0,0,44,0,0,0,0,1,0,1,0,0,2,2,68,1,0)
    $gif = $gif + $frame + $frame + [byte[]](59)
    [IO.File]::WriteAllBytes((Join-Path $fixtureLegacy 'idle.gif'), $gif)
    [IO.File]::WriteAllBytes((Join-Path $fixtureGifs 'fun_64x64.gif'), $gif)
    foreach ($spec in @(@('running', 64), @('pressure', 32))) {
        $image = New-Object Drawing.Bitmap($spec[1], $spec[1])
        $image.Save((Join-Path $fixtureLegacy ($spec[0] + '.png')), [Drawing.Imaging.ImageFormat]::Png)
        $image.Dispose()
    }
    $script:CharacterRoot = Split-Path $monitorPath -Parent
    Load-AvatarImages
    $expectedFiles = @{ idle='fun_64x64.gif'; running='cheer_64x64.gif'; pressure='sick_64x64.gif'; suspected='dizzy_64x64.gif' }
    foreach ($state in $expectedFiles.Keys) {
        $asset = $script:AvatarImages[$state]
        Assert-Ui ($null -ne $asset -and (Split-Path $asset.Tag -Leaf) -eq $expectedFiles[$state]) "actual-$state-file-mapping"
        Assert-Ui ([Drawing.ImageAnimator]::CanAnimate($asset)) "actual-$state-animated"
    }
    foreach ($asset in $script:AvatarImages.Values) { $asset.Dispose() }
    $script:AvatarImages = @{}
    $script:CharacterRoot = $fixtureFolder
    $form = New-MonitorForm
    Assert-Ui ($ui.Avatar.Width -eq 64 -and $ui.Avatar.Height -eq 64) 'character-slot-exactly-64x64'
    Assert-Ui ($script:AvatarImages.ContainsKey('idle')) 'gif-loaded'
    Assert-Ui ((Split-Path $script:AvatarImages['idle'].Tag -Leaf) -eq 'fun_64x64.gif') 'mapped-gif-takes-priority-over-legacy'
    Assert-Ui ([Drawing.ImageAnimator]::CanAnimate($script:AvatarImages['idle'])) 'animated-gif-preserved'
    Assert-Ui ($script:AvatarImages.ContainsKey('running')) 'png-loaded'
    Assert-Ui (-not $script:AvatarImages.ContainsKey('pressure')) 'wrong-size-asset-skipped'
    $sample = [pscustomobject]@{
        ArkRunning=$false; ArkPid=''; CpuArk=0.0; CpuExt=0.0; CpuTotal=0.0
        GpuArk=0.0; GpuExt=0.0; GpuTotal=0.0; VramArk=0L; VramExt=0L
        VramTotal=16GB; VramUsed=0L; VramFree=16GB; VramNonLocal=0L
        RamArk=0L; RamExt=0L; RamTotal=64GB; RamUsed=0L; RamFree=64GB
        MemoryValid=$true; GpuValid=$true; ArkGpuValid=$true; CpuValid=$true; VramValid=$true; VramSplitValid=$true; VramSource='Windows'
        MemoryState='idle'; MemoryReason='대기'; SwapText='대기'
        GpuName='UI TEST GPU'; SampleTime=[datetime]::Now
    }
    Update-Ui $sample
    Assert-Ui ([object]::ReferenceEquals($ui.Avatar.Image, $script:AvatarImages['idle'])) 'idle-asset-selected'
    foreach ($state in @('Running', 'Pressure', 'Suspected', 'Unknown')) {
        $PreviewState = $state
        Update-Ui (Set-PreviewSample $sample)
        Assert-Ui ([object]::ReferenceEquals($ui.Avatar.Image, $script:AvatarImages['running'])) "$state-asset-or-fallback"
        Assert-Ui ($ui.Reason.Bottom -le $form.ClientSize.Height) "$state-footer-inside-window"
    }
    $PreviewState = 'Running'
    Update-Ui (Set-PreviewSample $sample)
    Assert-Ui ($ui.Gpu.Free.Text -eq 'Idle   7.6%') 'gpu-idle-retains-decimals'
    Assert-Ui ($ui.Cpu.Free.Text -eq 'Idle   77.4%') 'cpu-idle-retains-decimals'
    $sample.ArkGpuValid = $false
    $sample.VramSplitValid = $false
    $sample.MemoryState = 'unknown'
    $sample.MemoryValid = $false
    Update-Ui $sample
    Assert-Ui ($ui.Gpu.Total.Text -eq '92.4%' -and $ui.Gpu.Ark.Text -like '*Unavailable*') 'gpu-total-kept-when-process-counter-fails'
    Assert-Ui ($ui.GpuMem.Total.Text -eq '13.0 / 16.0 GB' -and $ui.GpuMem.Ark.Text -like '*Unavailable*') 'vram-total-kept-when-process-counter-fails'
    Assert-Ui ($ui.Gpu.Bar.Tag.Unassigned -and $ui.GpuMem.Bar.Tag.Unassigned) 'unknown-split-uses-neutral-bar'
    $sample.GpuValid = $false; $sample.VramValid = $false
    Update-Ui $sample
    Assert-Ui ($ui.Gpu.Total.Text -eq '—' -and $ui.GpuMem.Total.Text -eq '—') 'failed-total-not-presented-as-zero'
    $diagnostics = Get-DiagnosticReport
    Assert-Ui ($null -ne $diagnostics.Nvidia -and $null -ne $diagnostics.WindowsGpuCounters) 'diagnostic-sources-separated'
    Assert-Ui ($script:Language -eq 'ENG' -and $ui.TopMost.Text -eq 'Always on top') 'english-default'
    $PreviewState = 'Pressure'
    Update-Ui (Set-PreviewSample $sample)
    $before = $ui.GpuMem.Total.Text
    $form.Show()
    foreach ($code in @('KOR', 'JPN', 'ENG')) {
        # Exercise the actual click handlers, using the cached sample (no new GPU query).
        $ui.LanguageButtons[$code].PerformClick()
        Assert-Ui ($script:Language -eq $code) "$code-button-switches-language"
        Assert-Ui ($ui.MemoryState.Text -eq $script:Translations[$code]['pressure']) "$code-cached-state-translated"
        Assert-Ui ($ui.Reason.Text -eq $script:Translations[$code]['Reason_pressure']) "$code-cached-reason-translated"
        Assert-Ui ($ui.GpuMem.Title.Text -eq $script:Translations[$code]['GpuMemory']) "$code-card-title-translated"
        Assert-Ui ($ui.Tips.GetToolTip($ui.Shared) -eq $script:Translations[$code]['SharedTip']) "$code-tooltip-translated"
        Assert-Ui ($ui.GpuMem.Total.Text -eq $before) "$code-measurements-preserved"
        Assert-Ui ($ui.LanguageButtons[$code].ForeColor -eq $script:ColorArk) "$code-selection-highlighted"
        foreach ($state in @('idle', 'warming', 'normal', 'pressure', 'suspected', 'unknown')) {
            $sample.MemoryState = $state
            Update-Ui $sample
            Assert-Ui ($ui.MemoryState.Text -eq $script:Translations[$code][$state]) "$code-$state-translated"
        }
        $sample.MemoryState = 'pressure'
        Update-Ui $sample
        $image = New-Object Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($image, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $out = Join-Path (Split-Path $monitorPath -Parent) 'dist'
        [void][IO.Directory]::CreateDirectory($out)
        $image.Save((Join-Path $out ("language-$code.png")), [Drawing.Imaging.ImageFormat]::Png)
        $image.Dispose()
    }
    Assert-Ui ($ui.LanguageButtons['ENG'].Right -eq ($form.ClientSize.Width - 12)) 'language-buttons-right-aligned'
    Assert-Ui ($ui.LanguageButtons['KOR'].Left -gt $ui.Title.Right -and $ui.LanguageButtons['ENG'].Bottom -lt $ui.TopMost.Top) 'language-buttons-fit-header-without-overlap'
    Assert-Ui ($form.ClientSize.Height -eq 446 -and $ui.Reason.Bottom -le $form.ClientSize.Height) 'compact-window-keeps-footer'
    Assert-Ui (@($form.Controls | Where-Object { $_ -is [Windows.Forms.Button] }).Count -eq 3) 'only-language-buttons-no-diagnostics-button'
    Write-Host 'UI_TEST_OK' 
} finally {
    if ($ui) { $ui.Avatar.Image = $null; $ui.Tips.Dispose(); $ui.Form.Dispose() }
    foreach ($asset in $script:AvatarImages.Values) { $asset.Dispose() }
    # Delete only files created by this test in its freshly generated temp directory.
    foreach ($name in @('idle.gif', 'running.png', 'pressure.png')) {
        $path = Join-Path $fixtureLegacy $name
        if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
    }
    [IO.File]::Delete((Join-Path $fixtureGifs 'fun_64x64.gif'))
    [IO.Directory]::Delete($fixtureLegacy)
    [IO.Directory]::Delete((Join-Path $fixtureFolder 'assets'))
    [IO.Directory]::Delete($fixtureGifs)
    [IO.Directory]::Delete($fixtureFolder)
}
