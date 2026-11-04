$base=Join-Path $PSScriptRoot '鲸鱼娘\DeepSeek鲸鱼娘桌宠'
Start-Process (Join-Path $base 'runtime\pythonw.exe') -ArgumentList ('"'+(Join-Path $base 'src\deepseek_pet.py')+'"') -WorkingDirectory $base -WindowStyle Hidden
