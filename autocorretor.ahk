; Autocorretor: corrige palavras em português enquanto você digita, em qualquer programa, sem
; mexer em palavras que existem em inglês. Ao terminar uma palavra (espaço ou pontuação):
;   0. se está em minhas-correcoes.txt, faz a troca fixa ("concerteza" -> "com certeza");
;   1. se está em acentos.txt, põe o acento ("nao" -> "não");
;   2. se existe em português ou inglês (validas.txt), não mexe;
;   3. senão, troca pela palavra portuguesa mais usada a um erro de distância ("querewndo" ->
;      "querendo") ou, em palavras longas, a dois ("interresante" -> "interessante").
; A palavra que começa uma frase (depois de . ! ? e espaço ou Enter) ganha a primeira letra
; maiúscula. Backspace logo depois de uma troca devolve o que foi digitado; se era uma
; correção, a palavra não é mais corrigida até o programa fechar. Não mexe em campo de senha,
; nos programas de programas-ignorados.txt, nem em e-mails, links, nomes de arquivo, siglas e
; nomes próprios. Nada do que é digitado vai para arquivo.
;
; Testes sem ligar o teclado (ver README.md):
;   AutoHotkey64.exe autocorretor.ahk /teste entrada.txt saida.txt      só as regras, palavra por palavra
;   AutoHotkey64.exe autocorretor.ahk /simular casos.txt saida.txt      a digitação inteira, simulada
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
SendMode "Input"
SetWorkingDir A_ScriptDir

global VALIDAS := Map(), CANDIDATAS := Map(), ACENTOS := Map(), BALDES := Map()
global MINHAS := Map(), FIXAS := Map(), IGNORADAS := Map(), PROGRAMAS := Map(), TITULOS := []
global ATALHO_PAUSA := "#^a"     ; Win+Ctrl+A: liga/desliga
global ATALHO_IGNORAR := "#^i"   ; Win+Ctrl+I: põe/tira o programa em foco de programas-ignorados.txt
global SIM := 0                  ; no teste simulado: { texto, exe, titulo, senha, janela }

; Estado da digitação: a palavra em andamento e o que se sabe do entorno.
global buf := "", sujo := false, aposPonto := false, inicioDeFrase := true
global pendente := 0             ; palavra seguida de "." ou ":" esperando a próxima tecla
; Maiúscula no começo. `proxima` diz se a próxima palavra começa uma frase, e por quê:
;   "ponto"  = veio um ponto final e depois um espaço;
;   "comeco" = a pessoa está começando a digitar (depois de Enter ou Tab, ou ao chegar numa
;              janela em que não estava no meio de um texto);
;   ""       = não, ou não se sabe (o programa não enxerga o que já está escrito no campo).
; fimVisto: acabou de vir um ponto final, falta o espaço. pontos: pontos seguidos (reticências
; não encerram a frase). iniciaFrase: a palavra em andamento começou com `proxima` ligado.
; ESTADOS guarda o `proxima` de cada janela, para voltar a ela sem perder o fio.
global proxima := "", fimVisto := false, pontos := 0, iniciaFrase := false, ESTADOS := Map()
global janela := 0, janelaIgnorada := false, ultima := 0, ligado := true, ih := 0

CarregarDados()

if A_Args.Length >= 3 && A_Args[1] = "/teste" {
    RodarTeste(A_Args[2], A_Args[3])
    ExitApp
}
if A_Args.Length >= 3 && A_Args[1] = "/simular"
    ExitApp(RodarSimulacao(A_Args[2], A_Args[3]))

MontarBandeja()
Hotkey ATALHO_PAUSA, (*) => Alternar()
Hotkey ATALHO_IGNORAR, (*) => AlternarProgramaAtual()
Hotkey "~*LButton", (*) => AoClicar(true)
Hotkey "~*RButton", (*) => AoClicar(false)
Hotkey "~*MButton", (*) => AoClicar(false)
LigarTeclado()

; ---- dados ------------------------------------------------------------------------------

CarregarDados() {
    global VALIDAS, CANDIDATAS, ACENTOS, BALDES
    if !FileExist("dados\validas.txt") {
        MsgBox("Faltam os dicionários (pasta dados).`n`nRode uma vez, nesta pasta:`n`n    python montar_dicionarios.py", "Autocorretor", "Icon!")
        ExitApp(1)
    }
    VALIDAS := Map(), CANDIDATAS := Map(), ACENTOS := Map(), BALDES := Map()
    VALIDAS.Capacity := 900000
    loop parse FileRead("dados\validas.txt", "UTF-8"), "`n", "`r"
        if A_LoopField != ""
            VALIDAS[A_LoopField] := 1
    loop parse FileRead("dados\acentos.txt", "UTF-8"), "`n", "`r" {
        par := StrSplit(A_LoopField, "`t")
        if par.Length = 2
            ACENTOS[par[1]] := par[2]
    }
    ; Candidatas a correção com a frequência. As mais usadas e longas também vão para "baldes"
    ; (primeira letra + tamanho), usados na busca a dois erros de distância.
    loop parse FileRead("dados\candidatas.txt", "UTF-8"), "`n", "`r" {
        par := StrSplit(A_LoopField, "`t")
        if par.Length != 2
            continue
        palavra := par[1], usos := Integer(par[2])
        CANDIDATAS[palavra] := usos
        if usos >= 2000 && StrLen(palavra) >= 6 {
            chave := SubStr(palavra, 1, 1) . StrLen(palavra)
            if !BALDES.Has(chave)
                BALDES[chave] := []
            BALDES[chave].Push(palavra)
        }
    }
    CarregarListasDoUsuario()
}

; Arquivos que a pessoa edita: palavras a nunca corrigir, trocas fixas (errado=certo) e programas
; em que o corretor fica quieto.
CarregarListasDoUsuario() {
    global MINHAS, PROGRAMAS, TITULOS, FIXAS
    MINHAS := LerLista("minhas-palavras.txt")
    ; programas-ignorados.txt: nome do .exe, ou "titulo: texto" para ignorar pela janela/aba.
    PROGRAMAS := Map(), TITULOS := []
    for linha in LerLista("programas-ignorados.txt") {
        if RegExMatch(linha, "^t[ií]tulo\s*:\s*(.+)$", &m)
            TITULOS.Push(m[1])
        else
            PROGRAMAS[linha] := 1
    }
    FIXAS := Map()
    for linha in LerLista("minhas-correcoes.txt") {
        par := StrSplit(linha, "=", " `t", 2)
        if par.Length = 2 && par[1] != "" && par[2] != ""
            FIXAS[par[1]] := par[2]
    }
}

LerLista(arquivo) {
    lista := Map()
    if !FileExist(arquivo)
        return lista
    loop parse FileRead(arquivo, "UTF-8"), "`n", "`r" {
        linha := Trim(A_LoopField)
        if linha != "" && SubStr(linha, 1, 1) != "#"
            lista[StrLower(linha)] := 1
    }
    return lista
}

; ---- regras de correção -----------------------------------------------------------------

; Recebe a palavra em minúsculas; devolve a correção (minúsculas) ou "" para não mexer.
Corrigir(p) {
    if IGNORADAS.Has(p) || MINHAS.Has(p)
        return ""
    if FIXAS.Has(p)
        return FIXAS[p]
    if ACENTOS.Has(p)
        return ACENTOS[p]
    if VALIDAS.Has(p)
        return ""
    ; Acento no lugar errado ("voçe", "tambêm"): tira todos e vê se sobra algo conhecido.
    pelada := ""
    loop parse p
        pelada .= SemAcento(A_LoopField)
    if pelada !== p {
        if ACENTOS.Has(pelada)
            return ACENTOS[pelada]
        if CANDIDATAS.Has(pelada)
            return pelada
    }
    n := StrLen(p)
    if n < 4                      ; palavra curta desconhecida costuma ser sigla ou abreviação
        return ""
    vizinha := MelhorVizinha(p)
    if vizinha != ""
        return vizinha
    return n >= 7 ? MelhorADoisErros(p) : ""
}

; Todas as palavras a UM erro de distância (letra a mais, letras trocadas, letra errada, letra
; faltando); ganha a mais usada, com peso maior para os erros mais comuns de digitação.
MelhorVizinha(p) {
    static LETRAS := StrSplit("abcdefghijklmnopqrstuvwxyzáàâãéêíóôõúç")
    n := StrLen(p), m := { palavra: "", nota: 0, segunda: 0 }
    loop n + 1 {
        i := A_Index, antes := SubStr(p, 1, i - 1), letra := SubStr(p, i, 1), depois := SubStr(p, i + 1)
        if i <= n {
            ; letra a mais: mais provável quando é vizinha, no teclado, de uma das letras ao lado
            esbarrao := SaoVizinhas(letra, SubStr(p, i - 1, 1)) || SaoVizinhas(letra, SubStr(depois, 1, 1))
            Pesar(m, antes . depois, i > 1 && esbarrao ? 4 : 2)
            if i < n
                Pesar(m, antes . SubStr(depois, 1, 1) . letra . SubStr(depois, 2), 3)   ; duas letras trocadas
            for l in LETRAS
                if l !== letra
                    Pesar(m, antes . l . depois, SemAcento(l) == SemAcento(letra) ? 20 : SaoVizinhas(l, letra) ? 2 : 1)
        }
        for l in LETRAS
            Pesar(m, antes . l . letra . depois, 1)                                      ; letra faltando
    }
    ; Em palavra curta há muitas vizinhas plausíveis: só corrige quando uma domina.
    if m.palavra = "" || (n <= 5 && m.nota < 3 * m.segunda)
        return ""
    return m.palavra
}

Pesar(m, candidata, peso) {
    if !CANDIDATAS.Has(candidata)
        return
    nota := CANDIDATAS[candidata] * peso
    if candidata == m.palavra {
        m.nota := Max(m.nota, nota)
    } else if nota > m.nota {
        m.segunda := m.nota, m.nota := nota, m.palavra := candidata
    } else if nota > m.segunda {
        m.segunda := nota
    }
}

; A DOIS erros: compara só com palavras bem usadas, da mesma primeira letra e tamanho parecido.
; Exige que a melhor seja bem mais usada que a segunda, para não chutar.
MelhorADoisErros(p) {
    n := StrLen(p), inicial := SubStr(p, 1, 1), melhor := "", nota := 0, segunda := 0
    loop 5 {
        chave := inicial . (n - 3 + A_Index)
        if !BALDES.Has(chave)
            continue
        for candidata in BALDES[chave] {
            if Distancia(p, candidata, 2) > 2
                continue
            usos := CANDIDATAS[candidata]
            if usos > nota
                segunda := nota, nota := usos, melhor := candidata
            else if usos > segunda
                segunda := usos
        }
    }
    return (melhor != "" && nota >= 3 * segunda) ? melhor : ""
}

; Distância de edição com troca de letras vizinhas; desiste (limite + 1) assim que passa do limite.
Distancia(a, b, limite) {
    la := StrLen(a), lb := StrLen(b)
    if Abs(la - lb) > limite
        return limite + 1
    ca := StrSplit(a), cb := StrSplit(b), ant2 := [], ant := []
    loop lb + 1
        ant.Push(A_Index - 1)
    loop la {
        i := A_Index, atual := [i], menor := i
        loop lb {
            j := A_Index
            v := Min(ant[j + 1] + 1, atual[j] + 1, ant[j] + (ca[i] == cb[j] ? 0 : 1))
            if i > 1 && j > 1 && ca[i] == cb[j - 1] && ca[i - 1] == cb[j]
                v := Min(v, ant2[j - 1] + 1)
            atual.Push(v), menor := Min(menor, v)
        }
        if menor > limite
            return limite + 1
        ant2 := ant, ant := atual
    }
    return ant[lb + 1]
}

SemAcento(l) {
    static TROCA := Map("á", "a", "à", "a", "â", "a", "ã", "a", "é", "e", "ê", "e", "í", "i", "ó", "o", "ô", "o", "õ", "o", "ú", "u", "ç", "c")
    return TROCA.Has(l) ? TROCA[l] : l
}

; Teclas encostadas no teclado ABNT2 (o dedo esbarra na do lado).
SaoVizinhas(a, b) {
    static PERTO := Map("q", "wa", "w", "qeas", "e", "wrsd", "r", "etdf", "t", "ryfg", "y", "tugh", "u", "yihj", "i", "uojk",
        "o", "ipkl", "p", "olç", "a", "qwsz", "s", "awedzx", "d", "serfxc", "f", "drtgcv", "g", "ftyhvb", "h", "gyujbn",
        "j", "huiknm", "k", "jiolm", "l", "kopç", "ç", "lp", "z", "asx", "x", "zsdc", "c", "xdfv", "v", "cfgb", "b", "vghn",
        "n", "bhjm", "m", "njk")
    return a != "" && b != "" && PERTO.Has(a) && InStr(PERTO[a], b, true)
}

; Devolve a correção com as maiúsculas do que foi digitado ("Nao" -> "Não", "NAO" -> "NÃO").
ComACaixaDe(original, corrigida) {
    if StrLen(original) > 1 && original == StrUpper(original)
        return StrUpper(corrigida)
    if SubStr(original, 1, 1) !== StrLower(SubStr(original, 1, 1))
        return StrUpper(SubStr(corrigida, 1, 1)) . SubStr(corrigida, 2)
    return corrigida
}

; A palavra como foi digitada -> como deve ficar (correção com as maiúsculas do original e, se
; `comecaFrase`, a primeira letra maiúscula), ou "" para não mexer.
CorrecaoPara(palavra, noInicioDaFrase, capsLock, comecaFrase := false) {
    todaMaiuscula := StrLen(palavra) > 1 && palavra == StrUpper(palavra)
    if todaMaiuscula {
        if !capsLock                               ; sigla ("CNPJ"); com Caps Lock ligado é texto normal
            return ""
    } else {
        resto := SubStr(palavra, 2)
        if resto !== StrLower(resto)               ; maiúscula no meio ("iPhone", "GitHub")
            return ""
        if !noInicioDaFrase && SubStr(palavra, 1, 1) !== StrLower(SubStr(palavra, 1, 1))
            return ""                              ; maiúscula no meio da frase: nome próprio
    }
    corrigida := Corrigir(StrLower(palavra))
    nova := corrigida = "" ? palavra : ComACaixaDe(palavra, corrigida)
    if comecaFrase
        nova := StrUpper(SubStr(nova, 1, 1)) . SubStr(nova, 2)
    return nova == palavra ? "" : nova
}

; O ponto depois desta palavra não encerra a frase? Abreviações comuns ("sr.", "ex.") e letras
; soltas ("p. ex.", "J. K."), menos as que são palavras ("Pois é. Depois...").
EhAbreviacao(palavra) {
    static LISTA := Map("sr", 1, "sra", 1, "srta", 1, "dr", 1, "dra", 1, "prof", 1, "profa", 1, "eng", 1, "av", 1,
        "ex", 1, "obs", 1, "pág", 1, "pag", 1, "tel", 1, "art", 1, "cap", 1, "vol", 1, "núm", 1, "num", 1, "vs", 1,
        "aprox", 1, "ltda", 1, "cia", 1, "depto", 1, "ref", 1)
    p := StrLower(palavra)
    if StrLen(p) = 1
        return !InStr("aeoéàáó", p)
    return LISTA.Has(p)
}

; ---- teclado ----------------------------------------------------------------------------

LigarTeclado() {
    global ih
    ; V: as teclas seguem para o programa; I1: ignora o que o próprio corretor envia;
    ; L0: não acumula texto (a palavra em andamento fica em `buf`).
    ih := InputHook("V I1 L0")
    ih.NotifyNonText := true
    ih.KeyOpt("{Backspace}", "N")
    ih.OnChar := AoDigitar
    ih.OnKeyDown := AoApertar
    ih.Start()
}

; Esquece a palavra em andamento e o entorno (o cursor ou o texto mudou de um jeito que o
; programa não acompanha).
Zerar(*) {
    global buf := "", sujo := false, aposPonto := false, inicioDeFrase := true, ultima := 0, pendente := 0
    global proxima := "", fimVisto := false, pontos := 0, iniciaFrase := false
}

; Clique do mouse: o cursor pode ter mudado de lugar. Se a pessoa ainda não digitou nada desde
; o começo (clicou no campo ou na conversa antes de escrever), continua sendo começo; clique
; no meio do que está escrevendo não vira começo.
AoClicar(esquerdo) {
    global proxima
    Critical
    comeco := esquerdo && proxima = "comeco"
    Zerar()
    if comeco
        proxima := "comeco"
}

; Mudou a janela em que se digita: guarda como ficou a que saiu, retoma a que chegou e descobre
; se é um programa em que o corretor fica quieto. Janela em que ainda não se digitou: começo.
ConferirJanela() {
    global janela, janelaIgnorada, proxima
    atual := IsObject(SIM) ? SIM.janela : WinExist("A")
    if atual = janela
        return
    if janela
        ESTADOS[janela] := (buf = "" && !sujo) ? proxima : ""
    if ESTADOS.Count > 300
        ESTADOS.Clear()
    janela := atual
    Zerar()
    proxima := ESTADOS.Has(atual) ? ESTADOS[atual] : "comeco"
    janelaIgnorada := IsObject(SIM) ? PROGRAMAS.Has(SIM.exe) : ProgramaIgnorado(atual)
}

; O programa dono da janela está em programas-ignorados.txt?
ProgramaIgnorado(hwnd) {
    try return PROGRAMAS.Has(StrLower(WinGetProcessName("ahk_id " hwnd)))
    return false
}

; O título da janela em foco contém algum "titulo: ..." de programas-ignorados.txt? Conferido
; na hora de trocar (e não por janela) porque, no navegador, cada aba muda o título.
TituloIgnorado() {
    titulo := ""
    try titulo := StrLower(IsObject(SIM) ? SIM.titulo : WinGetTitle("A"))
    for trecho in TITULOS
        if InStr(titulo, trecho)
            return true
    return false
}

; Põe o programa na lista de ignorados, ou tira dela; devolve true se ele ficou ignorado.
AlternarPrograma(exe, arquivo := "programas-ignorados.txt") {
    novo := "", achou := false
    if FileExist(arquivo) {
        loop parse FileRead(arquivo, "UTF-8"), "`n", "`r" {
            if StrLower(Trim(A_LoopField)) == exe
                achou := true
            else
                novo .= A_LoopField "`n"
        }
        FileDelete(arquivo)
    }
    novo := RTrim(novo, "`n") "`n"
    if !achou
        novo .= exe "`n"
    FileAppend(novo, arquivo, "UTF-8-RAW")
    return !achou
}

; Win+Ctrl+I: o programa em foco entra ou sai da lista, e a mudança já vale.
AlternarProgramaAtual() {
    global janela
    try
        exe := StrLower(WinGetProcessName("A"))
    catch
        return
    ignorado := AlternarPrograma(exe)
    CarregarListasDoUsuario()
    janela := 0                                    ; reavalia a janela na próxima tecla
    Zerar()
    TrayTip(ignorado ? "Não corrijo mais em " exe "." : "Voltei a corrigir em " exe ".", "Autocorretor")
}

; Chamado a cada caractere que o teclado produz (acentos já compostos: "´" + "a" chega "á").
AoDigitar(hook, texto) {
    global buf, sujo, aposPonto, inicioDeFrase, ultima, pendente, proxima, fimVisto, pontos, iniciaFrase
    Critical                                       ; uma tecla por vez, na ordem em que chegaram
    ConferirJanela()
    ultima := 0
    if !ligado || janelaIgnorada
        return
    loop parse texto {
        c := A_LoopField
        ; Palavra seguida de "." ou ":" à espera desta tecla: só era fim de frase se agora vier um
        ; espaço ("relatorio.pdf", "reuniao.com" e "localhost:8080" ficam como foram digitados).
        espera := pendente, pendente := 0
        if c != "."
            pontos := 0
        if c ~= "^\p{L}$" {
            if aposPonto                           ; letra colada num ponto: "site.com", "arquivo.txt"
                sujo := true, aposPonto := false
            if buf = ""
                iniciaFrase := proxima != "" && !sujo
            proxima := "", fimVisto := false
            buf .= c
        } else if c = " " || c = "`n" || c = "`r" || c = "`t" {
            palavra := buf, estavaSujo := sujo, noInicio := inicioDeFrase, comecaFrase := iniciaFrase
            buf := "", sujo := false, aposPonto := false, iniciaFrase := false
            if palavra != ""
                inicioDeFrase := false
            if c = " " {
                if fimVisto                        ; ponto final e espaço: a próxima palavra começa outra frase
                    proxima := "ponto"
                fimVisto := false
                if IsObject(espera)
                    Trocar(espera.palavra, espera.fim . c, espera.noInicio, espera.comecaFrase)
                else if palavra != "" && !estavaSujo
                    Trocar(palavra, c, noInicio, comecaFrase)
            } else {
                ; Enter e Tab: o texto já foi enviado ou o campo mudou, não dá para corrigir o que
                ; ficou para trás; o que vier agora é começo de digitação. Menos quando o Enter só
                ; aceitou uma sugestão ("@fulano", ":emoji", endereço de site): aí a frase continua.
                proxima := (fimVisto || !estavaSujo) ? "comeco" : ""
                fimVisto := false, inicioDeFrase := true
            }
        } else if c = "." || c = ":" {
            palavra := buf, comecaFrase := iniciaFrase
            buf := "", aposPonto := true, iniciaFrase := false, proxima := ""
            if c = "." && palavra = "" && IsObject(espera)
                espera.fim .= c, pendente := espera                ; reticências: continua esperando
            else if palavra != "" && !sujo
                pendente := { palavra: palavra, fim: c, noInicio: inicioDeFrase, comecaFrase: comecaFrase }
            if c = "." {
                ; Ponto final de verdade: um só (não reticências) e não depois de abreviação.
                pontos += 1
                fimVisto := pontos = 1 && !EhAbreviacao(palavra)
                inicioDeFrase := true
            } else {
                fimVisto := false
                if palavra != ""
                    inicioDeFrase := false
            }
        } else if InStr(",;!?)", c) || (c = '"' && buf != "") {
            palavra := buf, comecaFrase := iniciaFrase
            buf := "", iniciaFrase := false, proxima := ""
            if palavra != "" && !sujo
                Trocar(palavra, c, inicioDeFrase, comecaFrase)
            ; Fecha parênteses logo depois do ponto, "(isso.) Depois": o ponto continua valendo.
            if !(c = ")" && palavra = "" && fimVisto)
                fimVisto := false
            inicioDeFrase := InStr("!?", c) ? true : (palavra != "" ? false : inicioDeFrase)
        } else if c = "(" || c = '"' {
            ; Abre parênteses ou aspas (ou fecha aspas depois do ponto): começa outra palavra, e o
            ; começo de frase continua valendo ('disse. "Sim', '"sim." Depois').
            buf := "", iniciaFrase := false
        } else {
            ; número, @, /, _, -, apóstrofo...: o que vier colado não é palavra comum (e-mail,
            ; código, link, "don't")
            buf := "", sujo := true, proxima := "", fimVisto := false, iniciaFrase := false
        }
    }
}

; Chamado para teclas que não produzem texto (setas, Backspace, Ctrl+algo...).
AoApertar(hook, vk, sc) {
    global buf, sujo, ultima, pendente, aposPonto, inicioDeFrase, proxima, fimVisto, pontos, iniciaFrase
    Critical
    nome := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if nome ~= "i)shift|control|alt|win|capslock|numlock|scrolllock"
        return
    ConferirJanela()
    if nome != "Backspace" || (GetKeyState("Ctrl") && !IsObject(SIM)) {
        Zerar()                                    ; seta, atalho, Delete...: o cursor ou o texto mudou
        return
    }
    espera := pendente, pendente := 0, pontos := 0
    if IsObject(ultima) {
        Desfazer()
    } else if IsObject(espera) && StrLen(espera.fim) = 1 {
        ; apagou o ponto que tinha acabado de digitar: a palavra volta a estar em andamento
        buf := espera.palavra, aposPonto := false, inicioDeFrase := espera.noInicio
        iniciaFrase := espera.comecaFrase, fimVisto := false
    } else if buf != "" {
        buf := SubStr(buf, 1, -1)
        if buf = "" && iniciaFrase                 ; apagou a palavra toda: a que vier continua começando a frase
            proxima := "ponto", iniciaFrase := false
    } else if proxima = "ponto" {
        proxima := "", fimVisto := true            ; apagou o espaço depois do ponto
    } else {
        proxima := "", fimVisto := false, sujo := true     ; apagou para trás: não sei mais o que há ali
    }
}

; Troca a palavra recém-terminada pela versão corrigida (e com maiúscula, se `comecaFrase`).
Trocar(palavra, fim, noInicio, comecaFrase := false) {
    global ultima
    nova := CorrecaoPara(palavra, noInicio, GetKeyState("CapsLock", "T"), comecaFrase)
    if nova = "" || nova == palavra || TituloIgnorado() || EhCampoDeSenha()
        return
    Escrever(StrLen(palavra) + StrLen(fim), nova . fim)         ; `fim` pode ser ". " (ponto + espaço)
    ultima := { original: palavra, corrigida: nova, fim: fim }
}

; Apaga `apagar` caracteres antes do cursor e escreve `texto` (no teste simulado, numa cadeia).
Escrever(apagar, texto) {
    if IsObject(SIM)
        SIM.texto := SubStr(SIM.texto, 1, StrLen(SIM.texto) - apagar) . texto
    else
        SendInput "{BS " apagar "}{Text}" texto
}

; O campo em foco é de senha? Pergunta ao Windows (UI Automation), só quando há algo a trocar.
; Vale para campos de senha de programas e de sites; na dúvida (erro), responde que não.
EhCampoDeSenha() {
    static uia := 0
    if IsObject(SIM)
        return SIM.senha
    try {
        if !uia
            uia := ComObject("{FF48DBA4-60EF-4201-AA87-54103EEF594E}", "{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")
        ComCall(8, uia, "Ptr*", &elemento := 0)              ; IUIAutomation::GetFocusedElement
        if !elemento
            return false
        ComCall(35, elemento, "Int*", &senha := 0)           ; IUIAutomationElement::get_CurrentIsPassword
        ObjRelease(elemento)
        return senha != 0
    } catch {
        return false
    }
}

; Backspace logo após a correção: o programa já apagou o último caractere do `fim`; devolve a
; palavra original com o `fim` inteiro.
Desfazer() {
    global ultima, buf
    u := ultima, ultima := 0
    Escrever(StrLen(u.corrigida) + StrLen(u.fim) - 1, u.original . u.fim)
    if StrLower(u.corrigida) !== StrLower(u.original)       ; só maiúscula desfeita: nada a lembrar
        IGNORADAS[StrLower(u.original)] := 1
    buf := ""
}

; ---- bandeja ----------------------------------------------------------------------------

MontarBandeja() {
    A_IconTip := "Autocorretor`nWin+Ctrl+A: liga/desliga`nWin+Ctrl+I: ignora o programa em foco"
    m := A_TrayMenu
    m.Delete()
    m.Add("Corrigir enquanto digito", (*) => Alternar())
    m.Add("Iniciar com o Windows", (*) => AlternarInicio())
    m.Add()
    m.Add("Minhas palavras (nunca corrigir)", (*) => Run('notepad.exe "' A_ScriptDir '\minhas-palavras.txt"'))
    m.Add("Programas ignorados", (*) => Run('notepad.exe "' A_ScriptDir '\programas-ignorados.txt"'))
    m.Add("Recarregar listas", (*) => (CarregarListasDoUsuario(), Zerar(), TrayTip("Listas recarregadas.", "Autocorretor")))
    m.Add()
    m.Add("Sair", (*) => ExitApp())
    m.Default := "Corrigir enquanto digito"
    AtualizarBandeja()
}

AtualizarBandeja() {
    A_TrayMenu.%(ligado ? "Check" : "Uncheck")%("Corrigir enquanto digito")
    A_TrayMenu.%(FileExist(AtalhoDeInicio()) ? "Check" : "Uncheck")%("Iniciar com o Windows")
    TraySetIcon(A_AhkPath, ligado ? 1 : 4)        ; pausado: ícone vermelho
}

Alternar() {
    global ligado := !ligado
    Zerar()
    AtualizarBandeja()
    TrayTip(ligado ? "Ligado." : "Pausado.", "Autocorretor")
}

AtalhoDeInicio() => A_Startup "\Autocorretor.lnk"

AlternarInicio() {
    if FileExist(AtalhoDeInicio())
        FileDelete(AtalhoDeInicio())
    else
        FileCreateShortcut(A_AhkPath, AtalhoDeInicio(), A_ScriptDir, '"' A_ScriptFullPath '"', "Autocorretor")
    AtualizarBandeja()
}

; ---- teste ------------------------------------------------------------------------------

; Cada linha da entrada é uma palavra como digitada (no meio da frase; prefixo "^" = início de
; frase). A saída traz "palavra<TAB>correção" (ou "=" quando não mexe) e o tempo gasto.
RodarTeste(entrada, saida) {
    linhas := "", inicio := A_TickCount, n := 0
    loop parse FileRead(entrada, "UTF-8"), "`n", "`r" {
        palavra := Trim(A_LoopField)
        if palavra = ""
            continue
        noInicio := SubStr(palavra, 1, 1) = "^"
        if noInicio
            palavra := SubStr(palavra, 2)
        nova := CorrecaoPara(palavra, noInicio, false)
        linhas .= palavra "`t" (nova = "" ? "=" : nova) "`n", n++
    }
    linhas .= "# " n " palavras em " (A_TickCount - inicio) " ms`n"
    if FileExist(saida)
        FileDelete(saida)
    FileAppend(linhas, saida, "UTF-8-RAW")
}

; Teste simulado: passa as teclas pela mesma lógica do teclado (AoDigitar / AoApertar), sem
; teclado nem janela, e confere o texto que ficaria escrito. Cada linha de casos:
;   programa | título da janela | senha (0 ou 1) | "teclas" | "texto esperado"
; Nas teclas: {BS} = Backspace, {ESQ} = seta para a esquerda, {ENTER} = Enter, {TAB} = Tab,
; {CLIQUE} = clique do mouse, {JAN1}...{JAN9} = passa a digitar em outra janela ({JAN0} volta).
; Cada caso começa numa janela em que ainda não se digitou. Devolve o número de falhas (vira o código de saída do processo).
RodarSimulacao(entrada, saida) {
    global SIM, IGNORADAS, janela
    linhas := "", falhas := 0, n := 0
    loop parse FileRead(entrada, "UTF-8"), "`n", "`r" {
        if Trim(A_LoopField) = "" || SubStr(A_LoopField, 1, 1) = "#"
            continue
        c := StrSplit(A_LoopField, "|", " `t")
        if c.Length != 5 {
            linhas .= A_LoopField "`t=> LINHA INVÁLIDA`n", falhas++
            continue
        }
        teclas := Trim(c[4], '"'), esperado := Trim(c[5], '"')
        base := 1000 + A_Index * 10
        SIM := { texto: "", exe: StrLower(c[1]), titulo: c[2], senha: c[3] = "1", janela: base }
        IGNORADAS := Map()
        ESTADOS.Clear()
        pos := 1
        while pos <= StrLen(teclas) {
            if SubStr(teclas, pos, 4) = "{BS}" {
                SIM.texto := SubStr(SIM.texto, 1, -1), AoApertar(0, 0x08, 0x0E), pos += 4
            } else if SubStr(teclas, pos, 5) = "{ESQ}" {
                AoApertar(0, 0x25, 0x14B), pos += 5
            } else if SubStr(teclas, pos, 7) = "{ENTER}" {
                SIM.texto .= "`n", AoDigitar(0, "`n"), pos += 7
            } else if SubStr(teclas, pos, 5) = "{TAB}" {
                SIM.texto .= "`t", AoDigitar(0, "`t"), pos += 5
            } else if SubStr(teclas, pos, 8) = "{CLIQUE}" {
                AoClicar(true), pos += 8
            } else if RegExMatch(SubStr(teclas, pos, 6), "^\{JAN(\d)\}", &m) {
                SIM.janela := base + Integer(m[1]), pos += 6
            } else {
                tecla := SubStr(teclas, pos, 1)
                SIM.texto .= tecla, AoDigitar(0, tecla), pos += 1
            }
        }
        obtido := StrReplace(StrReplace(SIM.texto, "`n", "{ENTER}"), "`t", "{TAB}"), ok := obtido == esperado
        linhas .= (ok ? "OK      " : "FALHOU  ") c[1] " | " teclas "`n" (ok ? "" : "        esperado: " esperado "`n        obtido:   " obtido "`n")
        n++, falhas += ok ? 0 : 1
    }
    ; A lista de programas num arquivo de teste: entra, sai, e o resto do arquivo fica como estava.
    tmp := A_Temp "\autocorretor-teste-programas.txt"
    if FileExist(tmp)
        FileDelete(tmp)
    FileAppend("# comentário`ncmd.exe`n", tmp, "UTF-8-RAW")
    entrou := AlternarPrograma("idea64.exe", tmp), comEla := FileRead(tmp, "UTF-8")
    saiu := !AlternarPrograma("idea64.exe", tmp), semEla := FileRead(tmp, "UTF-8")
    FileDelete(tmp)
    ok := entrou && saiu && comEla == "# comentário`ncmd.exe`nidea64.exe`n" && semEla == "# comentário`ncmd.exe`n"
    linhas .= (ok ? "OK      " : "FALHOU  ") "Win+Ctrl+I põe e tira o programa da lista`n"
    n++, falhas += ok ? 0 : 1
    ; Fora da simulação: o que o corretor enxerga, de verdade, nas janelas abertas agora.
    SIM := 0
    try linhas .= "# janela em foco agora: " StrLower(WinGetProcessName("A")) " -> "
        . (ProgramaIgnorado(WinExist("A")) ? "programa ignorado" : TituloIgnorado() ? "título ignorado" : "corrige") "`n"
    abertos := Map()
    for hwnd in WinGetList() {
        try {
            if WinGetTitle("ahk_id " hwnd) != ""
                abertos[StrLower(WinGetProcessName("ahk_id " hwnd))] := ProgramaIgnorado(hwnd)
        }
    }
    for exe, ignorado in abertos
        linhas .= "#   " exe ": " (ignorado ? "ignorado" : "corrige") "`n"
    linhas .= "# " n " casos, " falhas " falha(s)`n"
    if FileExist(saida)
        FileDelete(saida)
    FileAppend(linhas, saida, "UTF-8-RAW")
    return falhas
}
