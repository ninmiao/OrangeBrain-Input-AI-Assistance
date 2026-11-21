# Compatibility alias; use test-orangecell.ps1 for OrangeCell.
& "$PSScriptRoot\test-orangecell.ps1" @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
