# Roda o teste de ponta a ponta (testes\e2e.ahk). Com -ComCorretor, liga o autocorretor antes
# e sempre o encerra no fim. Abre uma janela de teste por alguns segundos: não digite enquanto isso.
#   powershell -File testes\rodar-e2e.ps1 -ComCorretor
param([switch]$ComCorretor)

$raiz = Split-Path $PSScriptRoot -Parent
$ahk = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe", "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe" |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ahk) { "Instale o AutoHotkey v2 (https://www.autohotkey.com)"; exit 1 }
Remove-Item "$PSScriptRoot\e2e-saida.txt" -ErrorAction SilentlyContinue

$corretor = $null
try {
    if ($ComCorretor) {
        $corretor = Start-Process $ahk -ArgumentList '/ErrorStdOut', "`"$raiz\autocorretor.ahk`"" -PassThru
        Start-Sleep 3   # carga dos dicionários
        if ($corretor.HasExited) { "o corretor fechou sozinho (codigo $($corretor.ExitCode))"; return }
    }
    $teste = Start-Process $ahk -ArgumentList '/ErrorStdOut', "`"$PSScriptRoot\e2e.ahk`"" -PassThru
    $null = $teste.Handle
    if (-not $teste.WaitForExit(50000)) { Stop-Process -Id $teste.Id -Force; "o teste passou de 50 s e foi encerrado" }
    else { "teste: codigo $($teste.ExitCode)" }
}
finally {
    if ($corretor -and -not $corretor.HasExited) { Stop-Process -Id $corretor.Id -Force }
    if ($teste -and -not $teste.HasExited) { Stop-Process -Id $teste.Id -Force }
}
if (Test-Path "$PSScriptRoot\e2e-saida.txt") { Get-Content "$PSScriptRoot\e2e-saida.txt" -Encoding UTF8 }
