# Compatibility alias; use build-orangecell.ps1 for OrangeCell.
& "$PSScriptRoot\build-orangecell.ps1" @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
