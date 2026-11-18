; Teste de ponta a ponta: digita numa janela própria, com o autocorretor rodando, e grava o
; que ficou escrito depois de cada trecho. SendLevel 1 para o corretor enxergar as teclas (ele
; ignora o nível 0). Antes de cada trecho confere se a janela de teste está em foco: se não
; estiver, para na hora (nunca digita em outra janela).
;   AutoHotkey64.exe testes\e2e.ahk         -> resultado em testes\e2e-saida.txt
#Requires AutoHotkey v2.0
#SingleInstance Force
SendLevel 1
SendMode "Event"
SetKeyDelay 30, 5

SAIDA := A_ScriptDir "\e2e-saida.txt"
if FileExist(SAIDA)
    FileDelete(SAIDA)
SetTimer(() => Sair("TEMPO ESGOTADO", 2), -40000)

g := Gui("+AlwaysOnTop", "Teste do autocorretor (não digite)")
g.SetFont("s12")
e := g.Add("Edit", "w640 r5")
senha := g.Add("Edit", "w640 Password")          ; campo de senha: o corretor não pode mexer
g.Show()
WinActivate("ahk_id " g.Hwnd)
if !WinWaitActive("ahk_id " g.Hwnd, , 5)
    Sair("SEM FOCO na abertura", 3)
e.Focus()
Sleep 400

; Cada trecho: o que digitar (sintaxe do Send: {!} é o ponto de exclamação).
for trecho in ["nao sei se voce esta querewndo a reuniao. Nao ", "the meeting so ate ", "site.com usuario@email.com arquivo.txt ",
               "possivel, facil{!} ", "tambem ", "{Backspace}", "tambem fim "] {
    if !WinActive("ahk_id " g.Hwnd)
        Sair("SEM FOCO antes de: " trecho, 4)
    Send trecho
    Sleep 350
    FileAppend(trecho "`t=> " e.Value "`n", SAIDA, "UTF-8-RAW")
}
; Campo de senha: as mesmas palavras que seriam corrigidas têm de ficar como digitadas.
senha.Focus()
Sleep 300
if !WinActive("ahk_id " g.Hwnd)
    Sair("SEM FOCO antes da senha", 4)
Send "nao voce. "
Sleep 350
FileAppend("[senha] nao voce. `t=> " senha.Value "`n", SAIDA, "UTF-8-RAW")
Sair("FIM", 0)

Sair(motivo, codigo) {
    FileAppend("# " motivo "`n", SAIDA, "UTF-8-RAW")
    ExitApp(codigo)
}
