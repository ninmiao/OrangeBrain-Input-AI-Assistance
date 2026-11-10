$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$jniRoot = Join-Path $projectRoot 'app\src\main\jni'
function Ensure-Junction([string] $Link, [string] $Target) {
    $fullLink = [IO.Path]::GetFullPath($Link)
    $fullTarget = [IO.Path]::GetFullPath($Target)
    if (-not $fullLink.StartsWith($jniRoot + '\') -or -not $fullTarget.StartsWith($jniRoot + '\')) { throw 'Native path escaped project' }
    if (Test-Path -LiteralPath $fullLink) {
        $item = Get-Item -LiteralPath $fullLink -Force
        if ($item.LinkType) { return }
        # CMake COPY_ON_ERROR on Windows can leave only an empty thirdparty directory.
        $child = Join-Path $fullLink 'thirdparty'
        if ((Test-Path -LiteralPath $child) -and @(Get-ChildItem -LiteralPath $child -Force).Count -eq 0) { Remove-Item -LiteralPath $child }
        if (@(Get-ChildItem -LiteralPath $fullLink -Force).Count -ne 0) { throw "Nonempty native destination: $fullLink" }
        Remove-Item -LiteralPath $fullLink
    }
    New-Item -ItemType Junction -Path $fullLink -Target $fullTarget | Out-Null
}
foreach ($plugin in @('librime-lua', 'librime-octagram', 'librime-predict')) {
    Ensure-Junction (Join-Path $jniRoot "librime\plugins\$plugin") (Join-Path $jniRoot $plugin)
}
Ensure-Junction (Join-Path $jniRoot 'librime-lua\thirdparty') (Join-Path $jniRoot 'librime-lua-deps')
Write-Output 'Native plugin junctions ready.'
