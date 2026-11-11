# Compatibility alias; use build-zephyr.ps1 for Zephyr Input.
& "$PSScriptRoot\build-zephyr.ps1" @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
