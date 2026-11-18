"""Monta os arquivos de dados do autocorretor a partir de listas de palavras públicas.

    python montar_dicionarios.py

Na primeira vez baixa as listas para fontes/ (uns 22 MB; ver FONTES_NA_INTERNET). Rodar de
novo só quando as regras deste arquivo ou as listas mudarem.

Saída (pasta dados/):
  validas.txt     palavras em que o corretor NÃO mexe (português + inglês), uma por linha
  candidatas.txt  palavras portuguesas que podem ser usadas como correção: palavra<TAB>frequência
  acentos.txt     correções diretas de acento: sem_acento<TAB>com_acento
"""
import io
import os
import re
import shutil
import unicodedata
import urllib.request

AQUI = os.path.dirname(os.path.abspath(__file__))
FONTES = os.path.join(AQUI, 'fontes')
DADOS = os.path.join(AQUI, 'dados')

# As listas não vão no repositório (cada uma tem a própria licença; ver o README): são
# baixadas daqui quando faltam em fontes/.
FONTES_NA_INTERNET = {
    # dicionário br.ispell em UTF-8 (formas flexionadas)
    'br-utf8.txt': 'https://www.ime.usp.br/~pf/dicios/br-utf8.txt',
    # VERO, o dicionário pt_BR do LibreOffice (só os radicais)
    'pt_BR.dic': 'https://raw.githubusercontent.com/LibreOffice/dictionaries/master/pt_BR/pt_BR.dic',
    # frequência das palavras em legendas (OpenSubtitles 2018)
    'pt_freq.txt': 'https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/pt_br/pt_br_full.txt',
    'en_freq.txt': 'https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt',
    # dicionário de inglês
    'en_alpha.txt': 'https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt',
}


def baixar_fontes():
    os.makedirs(FONTES, exist_ok=True)
    for nome, url in FONTES_NA_INTERNET.items():
        destino = os.path.join(FONTES, nome)
        if os.path.exists(destino) and os.path.getsize(destino) > 0:
            continue
        print(f'baixando {nome}...')
        pedido = urllib.request.Request(url, headers={'User-Agent': 'autocorretor'})
        with urllib.request.urlopen(pedido, timeout=120) as resposta, open(destino + '.parte', 'wb') as f:
            shutil.copyfileobj(resposta, f)
        os.replace(destino + '.parte', destino)

SO_LETRAS = re.compile(r'^[a-záàâãéêíóôõúüç]+$')

# Uso mínimo (nas legendas) para uma palavra fora dos dicionários contar como válida: nomes
# próprios e gírias ("vc", "paulo"). Abaixo disso é mais provável ser erro de digitação.
MINIMO_PARA_VALER = 100
# Uso mínimo para uma palavra do dicionário servir de correção.
MINIMO_PARA_CORRIGIR = 200
# Palavra inglesa entre as N mais usadas nunca recebe acento ("so", "ate", "resume").
INGLES_COMUM = 20000

# Pares que a regra do inglês barraria, mas em que a forma sem acento só aparece em inglês como
# nome próprio ou estrangeirismo ("Mae", "tres"): quem escreve em português quer o acento.
ACENTOS_A_MAO = {'ja': 'já', 'tao': 'tão', 'mae': 'mãe', 'tres': 'três', 'mao': 'mão', 'irma': 'irmã', 'chao': 'chão',
                 'cao': 'cão', 'cha': 'chá', 'cade': 'cadê', 'sera': 'será'}
# Sem acento de propósito: abreviações e termos que as regras confundiriam.
NUNCA_ACENTUAR = {'pais', 'esta', 'este', 'ai', 'la', 'ha', 'vos', 'nos', 'de', 'da', 'do', 'por', 'e', 'a', 'o'}


def sem_acento(p):
    return ''.join(c for c in unicodedata.normalize('NFD', p) if unicodedata.category(c) != 'Mn')


def ler_frequencias(nome):
    """palavra -> (contagem, posição no ranking)"""
    freq = {}
    with io.open(os.path.join(FONTES, nome), encoding='utf-8') as f:
        for pos, linha in enumerate(f, 1):
            partes = linha.split()
            if len(partes) == 2 and SO_LETRAS.match(partes[0]):
                freq[partes[0]] = (int(partes[1]), pos)
    return freq


def ler_palavras(nome, encoding='utf-8'):
    palavras = set()
    with io.open(os.path.join(FONTES, nome), encoding=encoding) as f:
        for linha in f:
            p = linha.strip().split('/')[0].split('\t')[0].lower()
            if SO_LETRAS.match(p):
                palavras.add(p)
    return palavras


def main():
    baixar_fontes()
    pt_freq = ler_frequencias('pt_freq.txt')
    en_freq = ler_frequencias('en_freq.txt')
    dicionario_pt = ler_palavras('br-utf8.txt') | ler_palavras('pt_BR.dic', 'utf-8-sig')
    ingles = ler_palavras('en_alpha.txt') | {p for p, (_, pos) in en_freq.items() if pos <= INGLES_COMUM}
    extras = ler_palavras_do_usuario()

    def usos(p):
        return pt_freq.get(p, (0, 10 ** 9))[0]

    # A forma mais usada de cada "esqueleto" sem acento, entre as palavras do dicionário.
    melhor_acentuada = {}
    for p in dicionario_pt:
        base = sem_acento(p)
        if base != p and usos(p) > usos(melhor_acentuada.get(base, '')):
            melhor_acentuada[base] = p

    # 1) Correções de acento.
    acentos = dict(ACENTOS_A_MAO)
    for base, acentuada in melhor_acentuada.items():
        if base in acentos or base in NUNCA_ACENTUAR or base in extras:
            continue
        if len(base) < 3:
            continue                                  # duas letras: só as escolhidas à mão
        n_acentuada, n_base = usos(acentuada), usos(base)
        if n_acentuada < MINIMO_PARA_VALER:
            continue
        if base in en_freq and en_freq[base][1] <= INGLES_COMUM:
            continue                                  # inglês comum: não mexe
        if base in ingles and n_acentuada < 1000:
            continue                                  # inglês raro: só se a portuguesa for bem usada
        if base in dicionario_pt:
            if n_acentuada < 20 * max(n_base, 1):     # as duas existem ("esta"/"está"): só se uma domina
                continue
        elif n_acentuada < 5 * max(n_base, 1):
            continue
        acentos[base] = acentuada

    # 2) Palavras válidas: dicionário + as bem usadas nas legendas que não são só falta de acento.
    validas_pt = set(dicionario_pt)
    for p, (n, _) in pt_freq.items():
        if n < MINIMO_PARA_VALER or p in validas_pt:
            continue
        acentuada = melhor_acentuada.get(sem_acento(p))
        if acentuada and acentuada != p and usos(acentuada) >= 5 * n:
            continue                                  # "nao", "voce", "tambem": erro frequente, não palavra
        validas_pt.add(p)
    validas = (validas_pt | ingles | extras) - set(acentos)

    # 3) Candidatas a correção: só palavras do dicionário, com uso razoável.
    candidatas = {p: usos(p) for p in dicionario_pt if usos(p) >= MINIMO_PARA_CORRIGIR}

    os.makedirs(DADOS, exist_ok=True)
    gravar('validas.txt', sorted(validas))
    gravar('candidatas.txt', [f'{p}\t{n}' for p, n in sorted(candidatas.items(), key=lambda x: -x[1])])
    gravar('acentos.txt', [f'{b}\t{a}' for b, a in sorted(acentos.items())])
    print(f'validas: {len(validas)} (pt {len(validas_pt)}, en {len(ingles)})  candidatas: {len(candidatas)}  acentos: {len(acentos)}')


def ler_palavras_do_usuario():
    caminho = os.path.join(AQUI, 'minhas-palavras.txt')
    if not os.path.exists(caminho):
        return set()
    with io.open(caminho, encoding='utf-8-sig') as f:
        return {l.strip().lower() for l in f if l.strip() and not l.startswith('#')}


def gravar(nome, linhas):
    with io.open(os.path.join(DADOS, nome), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(linhas) + '\n')


if __name__ == '__main__':
    main()
