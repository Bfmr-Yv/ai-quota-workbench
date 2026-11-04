# Backward-compatible launcher name. The route now also includes clearly labeled
# subscription and paid models; expanded WorkBuddy models may consume credits.
Write-Warning 'This launcher name is retained for compatibility. Use 启动Cursor多来源模型.ps1 for the current multi-provider catalog.'
& (Join-Path $PSScriptRoot '启动Cursor多来源模型.ps1')

