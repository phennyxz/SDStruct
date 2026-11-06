# Relatório de testes do núcleo

## Ambiente

- Data: 2026-11-06
- Sistema: Ubuntu 24.04.3 LTS, Linux 6.12.8+ x86_64
- Bash: 5.2.21(1)-release (única versão disponível)
- Comando: `bash tests/run.sh` (também com `LC_ALL=C`, `LC_ALL=C.UTF-8`, `LC_ALL=en_US.utf8` e `BASH_COMPAT=43|44|50`); benchmark: `bash tests/bench.sh`
- Dependências dos testes: `mktemp`, `sort`, `comm`. `shellcheck` não está instalado (não executado).

## Resultado por grupo (execução com o locale padrão do ambiente)

| Grupo | Testes | Aprovados | Reprovados | Ignorados |
|---|---|---|---|---|
| test_assign.sh | 18 | 18 | 0 | 0 |
| test_assignment.sh (novo) | 25 | 25 | 0 | 0 |
| test_basics.sh | 10 | 10 | 0 | 0 |
| test_environment.sh | 7 | 7 | 0 | 0 |
| test_integrity.sh | 20 | 20 | 0 | 0 |
| test_lists.sh | 24 | 24 | 0 | 0 |
| test_set.sh (novo) | 20 | 20 | 0 | 0 |
| test_store.sh | 23 | 23 | 0 | 0 |
| **Total** | **147** | **147** | **0** | **0** |

Os 102 testes anteriores permanecem (todos com o mesmo nome); 45 são novos (`test_assignment.sh` e `test_set.sh`). Os novos testes verificam o resultado **e** o estado integral do armazenamento (snapshot antes/depois, contagem exata de registros adicionados/removidos/alterados, `assert_consistent`: validação + índice incremental idêntico ao reconstruído) e a localidade (sentinela no índice sobrevive: nenhuma reconstrução global).

## Matriz de configurações

| Configuração | Resultado |
|---|---|
| locale padrão (`LC_ALL` não definido) | 147/147 |
| `LC_ALL=C` | 147/147 |
| `LC_ALL=C.UTF-8` | 147/147 |
| `LC_ALL=en_US.utf8` | 147/147 |
| `BASH_COMPAT=43`, `44`, `50` | 147/147 (modo de emulação no Bash 5.2.21; **não** prova Bash 4.3) |

`bash -n` passou em todos os `.sh` (`src`, `tests`, `review`).

## Mudanças de contrato nos testes antigos (nenhuma escondida)

A função `sds_core_set` (insere/substitui) foi renomeada mecanicamente para `sds_core_assign` em todos os testes antigos; `sds_core_set` agora é a operação estrutural. Depois disso, 94 dos 102 testes passaram sem outra alteração. Os 8 restantes (em 8 testes) mudaram **expectativas** por mudança explícita de contrato (pedida pela direção):

| Teste | Antes | Agora |
|---|---|---|
| `test_assign.sh::test_root_u_and_n_replaced` | raiz objeto vazio → `n`/`l` por atribuição | `SDS_E_TYPE`; troca explícita por `set` |
| `test_assign.sh::test_object_with_descendants_cannot_become_string` | `oo ''` sobre objeto com descendentes: `SDS_E_CONFLICT` | retorno 0, no-op (mesmo tipo de contêiner; nada descartado); conflito continua para escalar |
| `test_assign.sh::test_empty_container_type_mismatch_not_promoted` | `ol ''` sobre objeto vazio: retipagem direta | `SDS_E_TYPE`; troca por `set` |
| `test_assign.sh::test_empty_container_replaced_by_scalar` | `os x` sobre objeto vazio: permitido | `SDS_E_TYPE`; troca por `set` |
| `test_assign.sh::test_no_parallel_structure_after_assignments` | usava `ou` (undefined) como segundo valor | usa `oi 2` (a verificação de estrutura paralela é mantida) |
| `test_lists.sh::test_descendants_conflict` | `oo ''` sobre contêiner com descendentes: conflito | `oi 1` continua `SDS_E_CONFLICT`; `oo ''` é no-op com 0 |
| `test_store.sh::test_overwrite_and_retype` | retipagem direta `s` → `i` | `SDS_E_TYPE` por atribuição; `set` com payload válido faz a troca |
| `test_store.sh::test_empty_container_becomes_nonempty` | raiz `o ''` com descendentes: `SDS_E_CONFLICT` | escalar `s` → `SDS_E_CONFLICT`; `o ''` → 0 (no-op) |

## Falhas encontradas e correções

Turno de auditoria anterior:
1. Colisão de nomes de locais internos com variáveis do chamador → locais `__sds_*` e rejeição de nomes `__sds_*`, `SDS_*`, `sds_*`.
2. `shopt -s nocasematch` (`A`/`a`, `TRUE`) → wrappers `sds__guard`.
3. Promoção `u`/`n` de ancestral → implementada e testada.
4. Testes frágeis (falha não verificada) → mecanismo `_PENDING`.

Esta etapa:
5. **Reconstrução global do array** em cada escrita (`sds__commit`) e varredura global em cada consulta/`set`: substituídas por índice derivado + plano de adições/remoções aplicado só aos registros afetados.
6. Bug durante a refatoração: a reconstrução do índice perdia o código de retorno da decodificação (detectado por teste antigo); corrigido.
7. Erros do próprio código de teste novo (comprimento dos tipificadores, expectativa de diff) corrigidos durante a escrita; nenhum teste foi removido ou enfraquecido.

## Benchmark (Bash 5.2.21, `bash tests/bench.sh`, uma execução)

Metodologia: armazenamento novo por item; tempo de parede com `$EPOCHREALTIME`; custo por operação derivado; sem repetições nem estatística (ruído da máquina compartilhada não foi medido). Baseline anterior: 200 inserções ≈ 1,4 s e 1000 ≈ 31 s (quadrático).

```text
Bash 5.2.21(1)-release | Linux 6.12.8+ | LC_ALL=<não definido>
1. inserir 100 caminhos novos (1 nível)                       107 ms     1071 us/op (100 ops)
1. inserir 500 caminhos novos (1 nível)                       567 ms     1134 us/op (500 ops)
1. inserir 1000 caminhos novos (1 nível)                     1216 ms     1216 us/op (1000 ops)
1. inserir 5000 caminhos novos (1 nível)                     9695 ms     1939 us/op (5000 ops)
2. atualizar 1000 payloads existentes (loja de 1000)          1379 ms     1379 us/op (1000 ops)
3a. 200 folhas sob ancestrais existentes, prof. 2              269 ms     1349 us/op (200 ops)
3b. 200 caminhos com 2 níveis novos cada                      266 ms     1333 us/op (200 ops)
3a. 200 folhas sob ancestrais existentes, prof. 4              275 ms     1375 us/op (200 ops)
3b. 200 caminhos com 4 níveis novos cada                      277 ms     1389 us/op (200 ops)
3a. 200 folhas sob ancestrais existentes, prof. 7              296 ms     1480 us/op (200 ops)
3b. 200 caminhos com 7 níveis novos cada                      297 ms     1488 us/op (200 ops)
3a. 200 folhas sob ancestrais existentes, prof. 11             325 ms     1628 us/op (200 ops)
3b. 200 caminhos com 11 níveis novos cada                     324 ms     1622 us/op (200 ops)
4. remover 100 escalares (loja de 1000)                        143 ms     1432 us/op (100 ops)
5. remover o 1o elemento de lista de 10 (desloca 9)              2 ms     2577 us/op (1 ops)
5. remover o penúltimo de lista de 10 (desloca 1)               1 ms     1999 us/op (1 ops)
5. remover o 1o elemento de lista de 1000 (desloca 999)         58 ms    58634 us/op (1 ops)
5. remover o penúltimo de lista de 1000 (desloca 1)             3 ms     3676 us/op (1 ops)
6a. set: renomear 100 escalares (loja de 1000)                 412 ms     4128 us/op (100 ops)
6b. set: tipo terminal s->l (rejeitado: payload não vazio, 100 tentativas)     361 ms     3613 us/op (100 ops)
7. renomear subárvore de 10 descendentes (loja de 1010)        15 ms    15640 us/op (1 ops)
7. renomear subárvore de 100 descendentes (loja de 1100)       22 ms    22985 us/op (1 ops)
7. renomear subárvore de 500 descendentes (loja de 1500)       54 ms    54290 us/op (1 ops)
```

Leitura: a inserção passou de quadrática a aproximadamente linear (1000 inserções: 31 s → 1,2 s). O custo por inserção sobe de ≈1,0 para ≈1,9 ms de 100 a 5000 registros (não é constante; a causa não foi investigada: pode ser a tabela hash/memória do Bash). Cada operação custa ≈1–1,6 ms mesmo para atualizar um payload (sobrecarga de validação e wrappers em Bash). Remover o 1º elemento de lista de 1000 custa ≈59 ms (desloca 999 elementos) e `set` renomeando subárvore custa proporcionalmente ao nº de descendentes mais uma varredura do índice (≈54 ms para 500 descendentes em loja de 1500). Os resultados do item 6b medem tentativas **rejeitadas**.

## Limitações

- Escaping de `0xFE`/`0xFF` não aprovado: segmentos com esses bytes são rejeitados; payloads são aceitos.
- NUL não suportado.
- O índice derivado detecta defasagem só por contagem + última chave; edição externa que preserve ambas não é detectada (use `sds_core_validate`).
- Não há operação de substituição de subárvore; reordenar dentro da mesma lista via `set` é rejeitado.
- Caminho de contingência de remoção (se `unset` não removesse a chave) existe mas não foi exercido.
- Serialização, interfaces e `takarr` fora do escopo.

## Compatibilidade

- **Comprovada:** Bash 5.2.21 em Ubuntu 24.04, nos locales acima.
- **NÃO comprovada:** Bash 4.3 e 4.4 (sem rede nem pacote; `BASH_COMPAT` é só emulação). Pendente: executar a suíte em 4.3, inclusive `set -u` com arrays vazios (< 4.4), `declare -gA` e `unset` de subscritos com chaves especiais. macOS/Bash 3.2 não suportado.
