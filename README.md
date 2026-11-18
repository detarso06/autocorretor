# Autocorretor

Corretor automático de digitação para Windows, como o do celular: corrige palavras em português
enquanto você digita, em qualquer programa, **sem mexer em palavras que existem em inglês**.
Feito em [AutoHotkey v2](https://www.autohotkey.com).

    nao sei se voce esta querewndo a reuniao. depois eu vejo
    Não sei se você esta querendo a reunião. Depois eu vejo

## Instalar

Precisa de Windows, [AutoHotkey v2](https://www.autohotkey.com) e, só para montar os
dicionários, [Python 3](https://www.python.org).

1. Instale o AutoHotkey v2 (`winget install AutoHotkey.AutoHotkey`).
2. Baixe ou clone este repositório.
3. Na pasta dele, monte os dicionários (baixa uns 22 MB de listas de palavras, uma vez só):

       python montar_dicionarios.py

4. Dois cliques em `autocorretor.ahk`. Aparece um ícone "H" verde na bandeja, perto do relógio.

## Usar

- **Pausar / retomar:** `Win+Ctrl+A`, ou clique no ícone (fica vermelho quando pausado).
- **Desfazer uma troca:** `Backspace` logo depois dela. A palavra volta como você digitou; se
  era uma correção, ela não é mais corrigida até fechar o programa.
- **Tirar ou pôr um programa da lista de ignorados:** com ele em foco, `Win+Ctrl+I`.
- **Iniciar com o Windows:** botão direito no ícone → "Iniciar com o Windows".
- **Sair:** botão direito no ícone → "Sair".

## O que ele faz

Ao terminar uma palavra com espaço ou pontuação:

1. Troca fixa de `minhas-correcoes.txt` ("concerteza" → "com certeza").
2. Acento que falta ("nao" → "não", "possivel" → "possível").
3. Se a palavra existe em português ou em inglês, não mexe.
4. Senão, troca pela palavra portuguesa mais usada a um erro de distância ("querewndo" →
   "querendo") ou, em palavras de 7 letras ou mais, a dois ("interresante" → "interessante").

E põe **maiúscula na primeira letra** em dois casos:

- **Depois de fim de frase:** ponto final, `!` ou `?` ("fim. depois" → "fim. Depois").
  Reticências, abreviações ("sr.", "ex.") e números ("3.5") não contam como fim de frase.
- **Quando você começa a digitar:** depois de Enter ou Tab, ou ao chegar numa janela em que não
  estava no meio de um texto.

Não mexe em: campos de senha, e-mails, links, nomes de arquivo, palavras com número, siglas em
maiúsculas, nomes próprios (maiúscula no meio da frase) e palavras com maiúscula no meio
("iPhone"). Depois de ponto ou dois-pontos, só troca se vier um espaço (assim "relatorio.pdf" e
"localhost:8080" ficam como foram digitados).

Nada do que você digita é gravado em arquivo.

## Onde ele funciona

Em todo programa, menos nos de `programas-ignorados.txt`. A lista já vem com terminais,
gerenciadores de senha, editores de código (VS Code, IntelliJ e outros) e clientes de banco de
dados (pgAdmin, MySQL Workbench e outros).

- **Tirar ou pôr um programa:** com ele em foco, `Win+Ctrl+I`. Um aviso confirma, e já vale.
- **Sites:** uma linha `titulo: texto` ignora qualquer janela ou aba cujo título contenha o
  texto. Já vem com `titulo: supabase` (o SQL Editor fica dentro do navegador).
- A lista vale para o programa inteiro: no VS Code, por exemplo, o corretor fica quieto também
  nos painéis de conversa.

## Ajustar

Arquivos de texto, um item por linha. Depois de editar: botão direito no ícone → "Recarregar
listas".

| Arquivo | Para quê |
|---|---|
| `minhas-palavras.txt` | Palavras que nunca devem ser corrigidas (marcas, termos técnicos). |
| `minhas-correcoes.txt` | Trocas fixas, no formato `errado=certo`. |
| `programas-ignorados.txt` | Onde o corretor fica quieto: nome do `.exe` ou `titulo: texto`. |

## Limites conhecidos

- Quando as duas formas existem, ele não escolhe: "esta"/"está", "e"/"é". Palavras que também
  são inglês ficam sem acento ("so", "ate").
- A palavra digitada logo antes de Enter ou Tab não é trocada: o texto já foi enviado.
- O programa não enxerga o que já está escrito no campo. Por isso o "começo da digitação" é
  deduzido (Enter, Tab, janela nova) e pode falhar: se você trocar de conversa sem dar Enter, a
  primeira palavra fica minúscula.
- Quem digita muito rápido pode, raramente, ver uma troca sair embaralhada se apertar a
  próxima tecla no instante exato em que ela acontece.
- Testado no Windows 11 com teclado ABNT2.

## Testes

    powershell -File testes\rodar-testes.ps1                 (simulado: não toca no teclado)
    powershell -File testes\rodar-e2e.ps1 -ComCorretor       (com teclas de verdade)

O primeiro passa os casos de `testes\casos.txt` pela lógica de digitação (correções, maiúsculas,
programas ignorados, senha, Backspace) e mostra o que o corretor enxerga nas janelas abertas. O
segundo abre uma janela e digita sozinho por alguns segundos: não digite enquanto isso.

Para ver a correção de uma lista de palavras soltas (`=` quer dizer que não mexe):

    AutoHotkey64.exe autocorretor.ahk /teste testes\entrada.txt testes\saida.txt

## Listas de palavras

Os dicionários (`dados/`) são montados por `montar_dicionarios.py` a partir destas listas, que
não fazem parte deste repositório e são baixadas na montagem. Cada uma tem a própria licença:

- [br.ispell](https://www.ime.usp.br/~pf/dicios/), dicionário do português do Brasil de Ricardo
  Ueda Karpischek, na versão em UTF-8 publicada por Paulo Feofiloff (IME-USP). GPL.
- [VERO](https://github.com/LibreOffice/dictionaries/tree/master/pt_BR), o verificador
  ortográfico pt_BR do LibreOffice. LGPL/MPL.
- [FrequencyWords](https://github.com/hermitdave/FrequencyWords), de Hermit Dave: frequência das
  palavras em legendas do OpenSubtitles (português e inglês). Conteúdo em CC BY-SA 4.0.
- [english-words](https://github.com/dwyl/english-words), da dwyl: lista de palavras do inglês.
  Unlicense.

## Licença

O código deste repositório está sob a licença [MIT](LICENSE). Ela não cobre as listas de
palavras acima, que seguem as licenças de cada projeto.
