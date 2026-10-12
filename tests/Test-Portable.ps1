$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$archivePath = Join-Path $projectRoot 'dist\ARK_RESMON_Portable.zip'
$stage = Join-Path $PSScriptRoot ('portable-check 한글 ' + [guid]::NewGuid().ToString('N'))
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $stage)
try {
    $relocatedRoot = Join-Path $stage 'ARK_RESMON_Portable'
    $runtimePath = Join-Path $relocatedRoot 'monitor.ps1'
    $runtime = [IO.File]::ReadAllText($runtimePath)
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($runtimePath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    $sourceAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $projectRoot 'monitor.ps1'), [ref]$tokens, [ref]$errors)
    $logicTests = $sourceAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-MemoryLogicTests' }, $true).Extent.Text
    $verifyCode = @'
Invoke-MemoryLogicTests
$expectedFiles = @{ idle='fun_64x64.gif'; running='cheer_64x64.gif'; pressure='sick_64x64.gif'; suspected='dizzy_64x64.gif' }
foreach ($state in $expectedFiles.Keys) {
    $sample = [pscustomobject]@{ ArkRunning=($state -ne 'idle'); MemoryState=$state }
    Set-AvatarState $sample
    if ((Split-Path $ui.Avatar.Image.Tag -Leaf) -ne $expectedFiles[$state]) { throw "Portable character mapping failed: $state" }
    if (-not [Drawing.ImageAnimator]::CanAnimate($ui.Avatar.Image)) { throw "Animation missing: $state" }
    Write-Host "PASS portable-$state-gif"
}
$script:AvatarState = ''
Update-Ui (Get-Sample)
$script:FrameHashes = New-Object 'System.Collections.Generic.HashSet[string]'
$script:CheckError = ''
$script:CheckTicks = 0
$checkTimer = New-Object Windows.Forms.Timer
$checkTimer.Interval = 125
$checkTimer.Add_Tick({
    try {
        $script:CheckTicks++
        $frameBitmap = New-Object Drawing.Bitmap(64,64)
        $ui.Avatar.DrawToBitmap($frameBitmap, (New-Object Drawing.Rectangle(0,0,64,64)))
        $stream = New-Object IO.MemoryStream
        $frameBitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
        $sha = [Security.Cryptography.SHA256]::Create()
        [void]$script:FrameHashes.Add([BitConverter]::ToString($sha.ComputeHash($stream.ToArray())))
        $sha.Dispose(); $stream.Dispose(); $frameBitmap.Dispose()
        if ($script:CheckTicks -ge 24) {
            if ($script:FrameHashes.Count -lt 2) { throw 'GIF did not advance while the monitor was running' }
            if ($ui.Status.Text -like '*Measurement error:*') { throw $ui.Status.Text }
            if (-not $script:SmiHealthy) { throw 'Live NVIDIA query failed' }
            Write-Host ("PASS animated-frame-changes={0}" -f $script:FrameHashes.Count)
            Write-Host ("PASS live-ui-status={0}" -f $ui.Status.Text)
            $checkTimer.Stop(); $form.Close()
        }
    } catch { $script:CheckError = $_.Exception.Message; $checkTimer.Stop(); $form.Close() }
})
$form.Add_Shown({ $checkTimer.Start() })
[void]$form.ShowDialog()
$checkTimer.Dispose()
if ($script:CheckError) { throw $script:CheckError }
Write-Host 'PORTABLE_TEST_OK (ZIP extraction, Korean/spaced path, actual counters, GIF playback)'
'@
    $marker = '[void]$form.ShowDialog()'
    if (-not $runtime.Contains($marker)) { throw 'Runtime dialog boundary missing' }
    $verification = $runtime.Replace($marker + "`r`nexit 0", ($logicTests + "`r`n" + $verifyCode))
    if ($verification -eq $runtime) { throw 'Failed to construct verification harness' }
    $verificationPath = Join-Path $relocatedRoot 'verify-runtime.ps1'
    [IO.File]::WriteAllText($verificationPath, $verification, (New-Object Text.UTF8Encoding $true))
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File $verificationPath
    if ($LASTEXITCODE -ne 0) { throw "Portable verification failed with exit code $LASTEXITCODE" }
} finally {
    # Validate the complete recursive-delete target against this test's directory.
    $fullStage = [IO.Path]::GetFullPath($stage)
    $allowed = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
    if (-not $fullStage.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $fullStage -Leaf) -notlike 'portable-check 한글 *') { throw 'Refusing unexpected cleanup target' }
    Remove-Item -LiteralPath $fullStage -Recurse -Force
}
