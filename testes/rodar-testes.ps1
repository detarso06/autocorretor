# Testes que NÃO tocam no teclado nem abrem janela: as regras de correção (palavra por palavra)
# e a digitação simulada (programas ignorados, senha, Backspace, pontuação).
#   powershell -File testes\rodar-testes.ps1
$raiz = Split-Path $PSScriptRoot -Parent
$ahk = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe", "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe" |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ahk) { "Instale o AutoHotkey v2 (https://www.autohotkey.com)"; exit 1 }

function Rodar($modo, $entrada, $saida) {
    Remove-Item "$PSScriptRoot\$saida", "$PSScriptRoot\erro.txt" -ErrorAction SilentlyContinue
    $p = Start-Process $ahk -ArgumentList '/ErrorStdOut', "`"$raiz\autocorretor.ahk`"", $modo, "`"$PSScriptRoot\$entrada`"", "`"$PSScriptRoot\$saida`"" `
        -PassThru -RedirectStandardError "$PSScriptRoot\erro.txt" -WindowStyle Hidden
    $null = $p.Handle
    if (-not $p.WaitForExit(60000)) { Stop-Process -Id $p.Id -Force; "PASSOU DE 60 s ($modo)"; return 99 }
    if ((Get-Item "$PSScriptRoot\erro.txt").Length -gt 0) { Get-Content "$PSScriptRoot\erro.txt" -Encoding UTF8 | Select-Object -First 20 }
    Remove-Item "$PSScriptRoot\erro.txt" -ErrorAction SilentlyContinue
    return $p.ExitCode
}

$codigo = Rodar '/simular' 'casos.txt' 'casos-saida.txt'
if (Test-Path "$PSScriptRoot\casos-saida.txt") { Get-Content "$PSScriptRoot\casos-saida.txt" -Encoding UTF8 }
"simulacao: codigo de saida $codigo (0 = tudo certo)"
