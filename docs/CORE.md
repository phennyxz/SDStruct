# Núcleo canônico — notas de implementação

**Status:** implementação inicial da Fase 2 (parcial). Todos os nomes de função, códigos de retorno e regras marcadas como *provisórias* **não** são contratos aprovados (ver `docs/API.md`); aguardam decisão da direção do projeto.

## Layout (proposta, não aprovada)

```text
src/sdstruct.sh        carregador (verifica Bash >= 4.3, carrega os módulos)
src/core/errors.sh     códigos SDS_E_* e sds__fail
src/core/delims.sh     sds_LT, sds_LP, sds_MAX_FILL, sds_check_delims, sds_init
src/core/types.sh      validação de nomes, tipos, payloads e segmentos
src/core/key.sh        sds_core_make_key, sds_core_decode_key, sds__join
src/core/index.sh      índice derivado SDS_IX_<nome>, plano de criação (sds__walk) e aplicação (sds__apply)
src/core/store.sh      init_data, assign, get, type, exists, delete, is_*
src/core/set.sh        sds_core_set: operação estrutural (renomear caminho / mudar tipo terminal)
src/core/validate.sh   sds_core_validate (consistência da coleção)
src/core/api.sh        sds__guard e wrappers públicos (carregado por último)
tests/run.sh           executor; tests/test_*.sh; tests/lib/assert.sh
```

Dependências: `errors ← delims ← types ← key ← index ← store ← set ← validate ← api`. Nenhuma dependência externa na biblioteca (os testes usam apenas `mktemp`/`sort`).

Executar: `bash tests/run.sh [arquivo...]` (147 testes em 8 grupos; saída 0 = sucesso, 1 = falha, 2 = erro de ambiente). `SDS_TEST_TRACE=1` ativa rastreamento. Um `run` que retorne não-zero deve ser seguido de `assert_rc`, senão o teste falha. Resultados: `docs/TEST-REPORT.md`. Benchmark: `bash tests/bench.sh`. Pacote de revisão: `review/`.

## Estrutura de funções públicas

Os corpos são `sds__impl_*`; `api.sh` define as funções públicas `sds_*` via `sds__guard`, que desliga `shopt nocasematch` durante a chamada (senão `A`/`a` colidiriam e `TRUE` seria aceito como booleano) e o restaura ao final.

## Modelo

Chave = tipificadores + `sds_LT` + segmentos unidos por `sds_LP`; valor = payload. Há um tipificador por nível, incluindo raiz e terminal (nº de tipificadores = nº de segmentos + 1). Raiz: caminho vazio (`TIPO` + `sds_LT`). Só registros terminais são gravados; contêineres vazios são registros terminais `o`/`l` com payload vazio.

## Atribuição ordinária × `set`

> Ordinary assignment creates missing paths and updates compatible existing values. "set" is an exceptional structural operation used to rename an existing path and/or change its terminal node type.

`sds_core_assign` é a operação normal; `sds_core_set` **não** a substitui. (Os nomes são provisórios; `sd_*` não foi aprovado.)

**`sds_core_assign NAME TYPES PAYLOAD [SEG...]`** (TYPES: um tipificador por nível, raiz e terminal incluídos)
- caminho existente, mesmo tipo: atualiza só o payload (nenhuma chave muda);
- caminho existente `u`/`n`: vira o novo tipo e payload (a chave terminal muda; é remover 1 e adicionar 1 registro);
- caminho ausente ou parcial: cria só os níveis ausentes e o terminal; ancestrais existentes não são reescritos. Os tipos dos intermediários vêm de TYPES (nunca inferidos de segmentos numéricos); um ancestral existente de tipo diferente → `SDS_E_TYPE`;
- terminal existente com outro tipo significativo (`s i f b o l`): `SDS_E_TYPE` (mudança de tipo só por `set`); contêiner com descendentes: `SDS_E_CONFLICT`. Atribuir o mesmo tipo de contêiner a um contêiner existente é no-op com retorno 0 (decisão provisória);
- escalar nunca recebe descendentes; falha deixa o armazenamento idêntico.

**`sds_core_set NAME CHAVE_ATUAL CHAVE_NOVA`** (duas chaves canônicas, ver `sds_core_make_key`; ambas obrigatórias)
- só opera sobre caminho existente (`SDS_E_NOTFOUND` se ausente; `SDS_E_TYPE` se os tipificadores da chave atual não coincidirem com o registro);
- renomeia, muda o tipo terminal, ou ambos; o payload é preservado (precisa ser válido no novo tipo);
- nunca altera o tipo de nó intermediário (ancestral existente do destino com tipo diferente → `SDS_E_TYPE`); ancestrais ausentes são criados;
- contêiner com descendentes: pode ser renomeado (a subárvore acompanha); mudar seu tipo → `SDS_E_CONFLICT` (nada é descartado);
- destino existente ou dentro da própria subárvore → `SDS_E_CONFLICT`; reordenar dentro da mesma lista → `SDS_E_CONFLICT` (pendente de decisão); mover elemento para fora de uma lista desloca os irmãos seguintes;
- toda validação precede a escrita; falha não altera nada.

## Índice derivado e localidade

Para que as operações custem O(profundidade) em vez de O(registros), cada coleção tem um índice auxiliar global `SDS_IX_<nome>` (chave `profundidade+sds_LT+caminho` → tipificadores completos e, em contêineres, nº de filhos; chaves de controle `M` e `L`). **O array de dados continua sendo a única fonte da verdade e o formato canônico não muda**; o índice é cache descartável, reconstruível por `sds_core_validate`/varredura. É uma **decisão de implementação PENDENTE de aprovação**. Limitação: edição externa do array que preserve a contagem e a última chave não é detectada (o índice só é verificado por contagem + última chave). Nunca há reconstrução do array de dados.

| Operação | Custo |
|---|---|
| assign / get / type / exists / delete de escalar | O(profundidade) |
| delete de elemento de lista | O(irmãos seguintes) (+ uma varredura do índice se algum irmão seguinte for contêiner não vazio) |
| delete de contêiner / `set` de subárvore | uma varredura simples do índice (O(n)), sem reconstruir nada |

## Funções (provisórias)

| Função | Função |
|---|---|
| `sds_init`, `sds_check_delims` | versão do Bash e delimitadores |
| `sds_core_init_data NAME` | cria/esvazia array associativo global |
| `sds_core_make_key OUT TYPES [SEG...]`, `sds_core_decode_key KEY` | monta/decodifica chave (resultado em `SDS_D_TYPES`, `SDS_D_N`, `SDS_D_PATH`, `SDS_D_SEGS`) |
| `sds_core_assign NAME TYPES PAYLOAD [SEG...]` | atribuição ordinária (ver acima) |
| `sds_core_set NAME CHAVE_ATUAL CHAVE_NOVA` | operação estrutural excepcional (ver acima) |
| `sds_core_get / sds_core_type NAME OUT [SEG...]` | payload / tipificador em `OUT` |
| `sds_core_exists NAME [SEG...]` | 0 existe (inclusive `u`), 1 ausente |
| `sds_core_delete NAME [SEG...]` | remove subárvore; desloca listas |
| `sds_core_is_object / is_list / is_terminal` | 0 verdadeiro, 1 falso ou ausente |
| `sds_core_validate NAME` | valida a coleção inteira |

A consulta por segmentos usa o índice derivado para obter os tipificadores (a chave de dados depende deles).

## Códigos de retorno (provisório)

0 ok · 1 ausente/falso · 2 uso · 3 caminho inválido · 4 tipo/payload inválido ou inconsistente · 5 conflito · 6 dados corrompidos · 7 limite · 8 não terminal · 9 ambiente. Mensagens em stderr, prefixo `sds:`. Valores retornam por variável (nameref); nomes de variáveis do chamador iniciados por `__sds_`, `SDS_` ou `sds_` são rejeitados (internamente, locais usam `__sds_`, evitando colisão com nameref).

## Regras adotadas além da especificação (provisórias)

- Payload de booleano: `true` / `false`.
- `i`: `-?(0|[1-9][0-9]*)`; `f`: número JSON com `.` e/ou expoente; texto preservado sem conversão.
- Índices de lista: decimal canônico, até 9 dígitos. Preenchimento com `u` limitado por `sds_MAX_FILL` (padrão 100000).
- Terminal `u`/`n` (e contêiner vazio de mesmo tipo, ou ancestral `u`/`n`) pode ser promovido por atribuição; ancestral escalar (`s i f b`) ou contêiner vazio de tipo diferente → `SDS_E_TYPE`. Não há operação de substituição de subárvore (não especificada); para elemento de lista com descendentes, `delete` desloca a lista (decisão pendente).
- `delete` que esvazia um contêiner o preserva como contêiner vazio. `delete` sem segmentos esvazia a estrutura.
- Atomicidade: cada operação monta um plano (adições/remoções) após validar tudo e só então o aplica com `unset`/atribuição nativos, apenas nos registros afetados. `unset 'a[$k]'` com chaves especiais é verificado em Bash 5.2; o guard desliga `assoc_expand_once`; se a remoção falhar, há retorno à reconstrução (caminho de contingência, não exercido nos testes). Chaves nunca são avaliadas como código.
- Locale: funções públicas usam `LC_ALL=C` localmente; bytes inválidos em UTF-8 são aceitos.

## Limitações e lacunas (bloqueios para a direção do projeto)

1. **Escaping de `0xFE`/`0xFF`**: não aprovado. Segmentos que os contenham são **rejeitados** (`SDS_E_PATH`). Payloads podem contê-los (campo separado). Não há suporte integral a chaves JSON arbitrárias.
2. NUL não é representável em variáveis Bash; não tratado.
3. Codificação de booleanos e limites de tamanho/índice não especificados.
4. Semântica de `set` (renomear/mudar tipo), nome `sds_core_assign`, reordenação dentro de lista, mover elemento para fora de lista, assign de mesmo contêiner como no-op e o índice derivado: provisórios, aguardam aprovação.
5. Contrato de erros/API pública (`sd_*`) e serialização externa: pendentes.
6. Testado apenas com Bash 5.2.21; compatibilidade com 4.3 é objetivo (evitou-se `${var@a}`, `-v` com subscritos, `declare -g` apenas onde 4.2+), mas **não foi verificada**.
7. Desempenho (medido em `tests/bench.sh`, ver `docs/TEST-REPORT.md`): ≈ 1–2 ms por operação; atribuição não depende do tamanho da loja, mas delete de contêiner/`set` de subárvore e remoção em lista com contêineres varrem o índice (O(n)).
8. `set -u` com arrays vazios em Bash < 4.4 não foi verificado.
9. Interfaces (`multarr`, ...), `takarr`, importação/exportação, `sd_paths/children/tree/shape/each`: não implementados.
