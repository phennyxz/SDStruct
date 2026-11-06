# Revisão do núcleo SDStruct

Todas as regras marcadas como *provisórias* aguardam aprovação da direção; nada aqui é decisão arquitetural.

> Ordinary assignment creates missing paths and updates compatible existing values. "set" is an exceptional structural operation used to rename an existing path and/or change its terminal node type.

## 1. Visão geral

Núcleo em Bash (>= 4.3 como objetivo; testado apenas em 5.2.21) que armazena dados tipados em um `declare -A`. Chave = tipificadores + `sds_LT` (0xFF) + segmentos unidos por `sds_LP` (0xFE); valor = payload do nó terminal. Sem dependências externas na biblioteca. Sem `eval`. Fora do escopo: interfaces históricas, `takarr`, serialização.

## 2. Árvore de arquivos

```text
src/sdstruct.sh
src/core/{errors,delims,types,key,index,store,set,validate,api}.sh
tests/run.sh
tests/lib/assert.sh
tests/test_{basics,store,lists,assign,assignment,set,integrity,environment}.sh
tests/bench.sh
docs/CORE.md  docs/TEST-REPORT.md
review/CORE-REVIEW.md  review/CORE-SOURCE.md  review/example.sh
```

## 3. Responsabilidade dos módulos

| Módulo | Responsabilidade |
|---|---|
| `sdstruct.sh` | verifica Bash >= 4.3 e carrega os módulos (`api` por último) |
| `errors.sh` | constantes `SDS_E_*`, `sds__fail` (mensagem em stderr com prefixo `sds:`) |
| `delims.sh` | `sds_LT`, `sds_LP`, `sds_MAX_FILL`, validação dos delimitadores, `sds_init` |
| `types.sh` | validação de nomes, tipos, payloads, segmentos, índices; `sds__is_assoc` |
| `key.sh` | montagem e decodificação de chaves |
| `index.sh` | índice derivado `SDS_IX_<nome>` (reconstrução, verificação de defasagem), `sds__walk` (plano de criação) e `sds__apply` (aplica adições/remoções só nos registros afetados) |
| `store.sh` | `assign`, get, type, exists, delete, deslocamento de lista, predicados |
| `set.sh` | `sds_core_set`: renomear caminho e/ou mudar tipo terminal |
| `validate.sh` | `sds_core_validate`: consistência global |
| `api.sh` | `sds__guard` (desliga `nocasematch`) e funções públicas |

## 4. Funções públicas e contratos (provisórios)

| Função | Contrato |
|---|---|
| `sds_init` | verifica Bash e delimitadores; 0 ou 9 |
| `sds_check_delims` | valida `sds_LT`/`sds_LP` (bytes 0xFF/0xFE, distintos) |
| `sds_core_init_data NAME` | cria/esvazia array associativo **global** |
| `sds_core_make_key OUT TYPES [SEG...]` | monta chave; exige nº de tipos = segmentos + 1 |
| `sds_core_decode_key KEY` | decodifica e valida; resultado em `SDS_D_TYPES/N/PATH/SEGS` |
| `sds_core_assign NAME TYPES PAYLOAD [SEG...]` | atribuição ordinária: cria níveis ausentes, atualiza valor compatível, promove `u`/`n`; valida tudo antes de alterar |
| `sds_core_set NAME CHAVE_ATUAL CHAVE_NOVA` | operação estrutural excepcional: renomeia e/ou muda o tipo terminal de caminho existente |
| `sds_core_get NAME OUT [SEG...]` | payload em `OUT`; 8 se contêiner não vazio |
| `sds_core_type NAME OUT [SEG...]` | tipificador do nó em `OUT` |
| `sds_core_exists NAME [SEG...]` | 0 se existe (inclusive `u`), 1 se ausente |
| `sds_core_delete NAME [SEG...]` | remove subárvore; em lista desloca os seguintes |
| `sds_core_is_object / is_list / is_terminal NAME [SEG...]` | 0 verdadeiro; 1 falso ou ausente (`is_terminal`: só escalares) |
| `sds_core_validate NAME` | verifica chaves, tipos, conflitos e contiguidade de listas |

Funções internas: `sds__impl_*` (corpos), `sds__guard`, `sds__find`, `sds__walk`, `sds__apply`, `sds__ix_*`, `sds__delete_node`, `sds__shift_list_plan`, `sds__join`, `sds__head`, `sds__decode_full`, `sds__check_*`, `sds__fail`.

## 5. Formato real das chaves

Um tipificador por nível (raiz inclusive e terminal); `TIPOS` + 0xFF + `seg1` 0xFE `seg2`... Raiz: `TIPO` + 0xFF e caminho vazio. Segmento vazio é válido. Só terminais são gravados; contêiner vazio é um terminal `o`/`l` com payload vazio. Exemplos (0xFF exibido como `|`, 0xFE como `/`) estão na seção 13.

## 6. Semântica de inserção, consulta e remoção

- **assign** (`sds_core_assign`): caminho existente com mesmo tipo → só o payload muda; `u`/`n` → novo tipo e payload; caminho ausente/parcial → só os níveis ausentes e o terminal são criados (tipos intermediários vêm do argumento TYPES, sem inferência por segmentos numéricos; ancestral existente de tipo diferente → `SDS_E_TYPE`). Mudança de tipo de valor significativo → `SDS_E_TYPE` (use `set`); contêiner com descendentes → `SDS_E_CONFLICT`; mesmo tipo de contêiner → no-op (provisório). Lista: índice acima do fim preenche com `u` (limite `sds_MAX_FILL`). Atomicidade: plano calculado e validado antes de qualquer escrita.
- **set** (`sds_core_set`): só em caminho existente; renomeia e/ou muda o tipo terminal, preservando o payload (válido no novo tipo) e a subárvore (renomeação de contêiner move os descendentes). Nunca altera tipo de nó intermediário (`SDS_E_TYPE`); destino existente / dentro da própria subárvore / reordenação na mesma lista → `SDS_E_CONFLICT`; mudar o tipo de contêiner com descendentes → `SDS_E_CONFLICT` (nada é descartado); origem ausente → `SDS_E_NOTFOUND`. Mover elemento para fora de lista desloca os seguintes. Falha não altera nada.
- **get/type/exists**: O(profundidade) via índice derivado. Caminho ausente (1) difere de `u` existente (0).
- **delete**: remove o nó e descendentes (escalar: só o registro). Em lista, apenas os irmãos seguintes são renumerados. Contêiner esvaziado vira contêiner vazio. Sem segmentos, esvazia a estrutura. Ausente: 1.

## 6a. Índice derivado (decisão de implementação PENDENTE de aprovação)

`SDS_IX_<nome>` é um array associativo global auxiliar: `profundidade + sds_LT + caminho` → tipificadores completos (+ `,N` filhos para contêineres) e chaves de controle `M` (nº de registros) e `L` (última chave). Dá custo O(profundidade) a assign/get/exists/type/delete de escalar. **O array de dados continua sendo a única fonte da verdade, o formato canônico não muda, e o índice é descartável** (reconstruído por varredura quando defasado ou por `sds_core_validate`). Defasagem só é detectada por contagem + última chave. Alternativa sem índice: varredura O(n) por operação.

## 7. Tratamento de `u` e `n`

Posições existentes e substituíveis. Terminal `u`/`n` pode ser substituído diretamente por `s i f b o l`. Como ancestral de um novo caminho, é promovido a contêiner (`o`/`l` conforme o tipificador informado). Escalares `s i f b` como ancestral: `SDS_E_TYPE`. Testes: `tests/test_assign.sh`.

## 8. Objetos e listas

Chaves de objeto são strings; índices de lista são decimais canônicos não negativos (até 9 dígitos); listas contíguas; remoção em objeto não desloca; raiz sem chave/índice e pode ser objeto, lista ou escalar. Contêiner com descendentes não vira terminal silenciosamente: `assign` retorna 5 e `set` retorna 5 ao mudar seu tipo. **Lacuna:** para elemento de lista com descendentes, `delete` desloca a lista, então não há substituição in-place (decisão pendente). Nenhuma operação de substituição de subárvore foi inventada.

## 9. Códigos de retorno

0 ok · 1 ausente/falso · 2 uso · 3 caminho/segmento inválido · 4 tipo/payload · 5 conflito · 6 dados corrompidos · 7 limite · 8 não terminal · 9 ambiente.

## 10. Limitações e decisões pendentes

Escaping de 0xFE/0xFF (segmentos rejeitados com código 3; payloads aceitos); NUL; codificação de booleanos; limites de tamanho e índice; nomes `sds_core_assign`/`sds_core_set` e chaves canônicas como argumentos de `set`; reordenação dentro de lista; assign de mesmo contêiner como no-op; índice derivado; nomes/contrato de erros da API pública; serialização; formato `vector`; desempenho.

## 11. Riscos técnicos conhecidos

- Índice derivado pode ficar defasado por edição externa que preserve contagem e última chave.
- Delete de contêiner e `set` de subárvore varrem o índice (O(n)); delete em lista com irmãos contêineres também.
- Desempenho medido: ≈1–2 ms por operação, ≈linear (1000 inserções ≈ 1,2 s; antes 31 s). Ver `docs/TEST-REPORT.md`.
- Bash 4.3/4.4 não testados; `set -u` com arrays vazios em < 4.4 não verificado.
- `unset -v 'a[$k]'` com chaves especiais funciona no 5.2 (verificado) mas falha com `assoc_expand_once`, que o guard desliga; no 4.3 não foi verificado.
- `declare -p` em subshell a cada chamada para checar o tipo do array.
- Subscritos em `(( ))` são expandidos duas vezes; evitados.
- Funções públicas definem `LC_ALL=C` localmente.

## 12. Resultado dos testes

`bash tests/run.sh`: **147 testes, 147 aprovados, 0 reprovados, 0 ignorados** (Bash 5.2.21, Ubuntu 24.04.3; `LC_ALL` padrão, `C`, `C.UTF-8`, `en_US.utf8`; também `BASH_COMPAT=43/44/50`, apenas emulação). 102 testes anteriores preservados (8 com expectativas alteradas por mudança explícita de contrato, listados em `docs/TEST-REPORT.md`) + 45 novos. Bash 4.3 **não** testado. Benchmark em `docs/TEST-REPORT.md`.

## 13. Exemplos executados

Saída real de `bash review/example.sh` (Bash 5.2.21):

```text
init ok (Bash 5.2.21(1)-release)
# 1. inserção tipada (um tipificador por nível, incluindo a raiz)
  oooli|servidores/web1/portas/0 = [80]
  oooli|servidores/web1/portas/1 = [443]
  ooos|servidores/web2/estado = [ativo]
# 2. consulta
get portas/1 = 443
type portas = l
exists web9 -> rc=1
sds: o caminho é um contêiner não vazio
get web1 (contêiner) -> rc=8
# 3. undefined / null / string vazia / contêineres vazios
  ol|l = []
  on|n = []
  oo|o = []
  os|s = []
  ou|u = []
# 4. preenchimento intermediário de lista
  ls|3 = [fim]
  lu|0 = []
  lu|1 = []
  lu|2 = []
# 5. u/n substituídos e promovidos
  oi|u = [7]
  ol|l = []
  oos|n/a = [x]
  oo|o = []
  os|s = []
# 6. remoção de elemento de lista desloca os seguintes
  [0]=v0
  [1]=v2
  [2]=v3
  [3] ausente
# 7. remoção de propriedade de objeto não desloca nada
  os|a = [1]
  os|c = [3]
# 8. atribuir escalar sobre contêiner com descendentes é recusado (mudança de tipo só por set)
sds: o caminho é um contêiner com descendentes; assinalar outro tipo exigiria descartá-los (use sds_core_delete)
rc=5
# 9. byte reservado em segmento é recusado (escaping não aprovado)
sds: segmento contém byte reservado (escaping de sds_LT/sds_LP ainda não aprovado)
rc=3
# 10. payload com 0xFE/0xFF é aceito (campo separado)
 fe ff
# 11. atribuição cria vários níveis ausentes sem tocar nos demais registros
  oooli|servidor/web1/porta/0 = [80]
  oooli|servidor/web1/porta/1 = [443]
  oools|servidor/web1/user/0 = [admin]
  ooos|servidor/web1/nome = [web1]
# 12. atribuição de mesmo tipo muda só o payload
  oooli|servidor/web1/porta/0 = [8080]
  oooli|servidor/web1/porta/1 = [443]
  oools|servidor/web1/user/0 = [admin]
  ooos|servidor/web1/nome = [web1]
# 13. set: renomear escalar
rc=0
# 14. set: renomear e mudar o tipo terminal (porta/0 i -> servico/porta s); porta/1 desloca
rc=0
  oooli|servidor/web1/porta/0 = [443]
  oools|servidor/web1/user/0 = [admin]
  oooos|servidor/web1/servico/porta = [8080]
  ooos|servidor/web1/identificacao = [web1]
# 15. set: renomear contêiner preserva os descendentes
rc=0
  oooli|servidor/web3/porta/0 = [443]
  oools|servidor/web3/user/0 = [admin]
  oooos|servidor/web3/servico/porta = [8080]
  ooos|servidor/web3/identificacao = [web1]
# 16. set recusado: colisão, tipo de contêiner com descendentes, tipo intermediário, ausente
sds: o nó possui descendentes incompatíveis com o tipo 's'; nada foi alterado
contêiner->s rc=5
sds: o destino já existe
colisão rc=5
sds: tipificação inconsistente no nível 2 (existente 'o', solicitado 'l'); tipos intermediários não são alterados
intermediário (web3 objeto -> lista) rc=4
sds: caminho atual inexistente
caminho atual ausente rc=1
  oooli|servidor/web3/porta/0 = [443]
  oools|servidor/web3/user/0 = [admin]
  oooos|servidor/web3/servico/porta = [8080]
  ooos|servidor/web3/identificacao = [web1]
```
