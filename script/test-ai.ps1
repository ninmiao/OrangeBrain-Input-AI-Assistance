# Compatibility alias; use test-zephyr.ps1 for Zephyr Input.
& "$PSScriptRoot\test-zephyr.ps1" @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
