# Formato canônico

**Status:** semântica dos caminhos, tipagem, tipos básicos, separadores e escaping por duplicação aprovados conceitualmente. A gramática completa de serialização externa e os limites de bytes ainda precisam de especificação.

## Objetivo

Todas as interfaces e conversores devem compartilhar uma representação canônica. O formato precisa preservar caminhos, tipos, valores e contêineres vazios sem materializar registros redundantes para cada nó intermediário.

## Registros como pares chave/valor

O armazenamento canônico em memória é uma coleção associativa de pares chave/valor:

- **Chave:** sequência de tipificadores + separador de tipagem + caminho codificado.
- **Valor:** payload do nó terminal.

Como chave e valor já ocupam campos distintos da estrutura associativa, não é necessário inserir um separador adicional entre chave e valor. O payload não faz parte da chave nem da sequência de bytes usada para codificar o caminho.

A chave não fica vazia mesmo quando representa a raiz: ela contém ao menos o tipificador da raiz e o separador entre tipagem e caminho.

## Registros terminais

A representação utiliza registros que identificam caminhos até valores terminais. A tipagem ao longo do caminho permite inferir a hierarquia.

Um registro também pode terminar em um contêiner vazio. Nesse caso, o próprio contêiner é o nó terminal registrado; não é necessário criar registros artificiais para seus descendentes.

## Raiz e caminhos

A raiz é um nó especial cujo caminho é vazio. Não se acrescenta índice `0` nem chave artificial à raiz, independentemente de ela ser objeto, lista ou valor escalar.

Chaves de objetos são sempre strings. Índices de listas são numéricos e não negativos.

## Tipagem integral do caminho

A tipagem cobre todo o caminho, desde a raiz até o valor terminal. Deve haver um tipificador para cada nível correspondente, inclusive para o valor terminal. Não se tipa apenas o valor final.

Exemplo semântico:

```text
oln:rua/1 = ''
```

Leitura: o caminho parte de um objeto (`o`), atravessa uma lista (`l`) e termina em um valor null (`n`).

## Tipos do núcleo inicial

- `o`: objeto.
- `l`: lista.
- `s`: string.
- `i`: inteiro.
- `f`: número JSON com fração e/ou expoente.
- `b`: booleano.
- `n`: null.
- `u`: undefined.

`u` e `n` possuem payload vazio (`''`), mas são distintos pelo tipificador. String vazia também possui payload vazio e é identificada por `s`. Contêineres vazios são identificados por `o` ou `l`, com o caminho terminando no próprio contêiner e payload vazio.

Os números `i` e `f` são armazenados como texto decimal ASCII. `f` não fixa precisão IEEE Float32 ou Float64; o lexema numérico recebido é preservado. Precisões específicas ficam para versões futuras.

## Separadores e escaping

Foram escolhidos dois bytes de controle:

- `0xFE`: separador entre segmentos sucessivos do caminho.
- `0xFF`: separador entre a sequência de tipificadores e o caminho.

Quando um byte `0xFE` ou `0xFF` ocorrer literalmente dentro de um segmento do caminho, será escapado por duplicação:

- byte literal `0xFE` no dado → `0xFE 0xFE`;
- byte literal `0xFF` no dado → `0xFF 0xFF`.

Um único `0xFE` não duplicado separa segmentos do caminho. Um único `0xFF` não duplicado separa a sequência de tipificadores do caminho. O decodificador deve reconhecer pares duplicados como bytes literais e bytes simples como delimitadores estruturais.

A regra de duplicação aplica-se aos bytes do campo de chave/caminho. Não há separador chave/valor nem necessidade de escapar esses delimitadores no payload por causa da estrutura do registro, pois o payload é armazenado no campo de valor separado.

## Codificação segura e limitações do Bash

A implementação deve tratar chaves e payloads como sequências de bytes, sem presumir que todo conteúdo é UTF-8 válido. Os bytes `0xFE` e `0xFF` não são bytes válidos isoladamente em UTF-8.

Variáveis Bash não podem conter byte NUL (`0x00`). A representação de strings JSON que contenham U+0000 precisa de uma decisão específica de codificação/limitação antes de alegar suporte integral a todo JSON.

## Decisões ainda pendentes

- codificação externa para gravar/transportar a coleção de pares;
- representação de U+0000 em strings JSON, considerando a limitação do Bash;
- limites de tamanho de chaves e payloads;
- validação de registros malformados, chaves duplicadas e conflitos entre caminho ancestral e descendente;
- detalhes de gramática para importação e exportação.

## Critérios de aceitação do formato

- Não há colisões entre caminhos distintos.
- Chaves e strings especiais podem ser preservadas dentro dos limites documentados.
- A tipagem de todos os níveis do caminho, inclusive do valor terminal, é recuperável.
- A raiz é representada por caminho vazio, sem índice artificial.
- Contêineres vazios são preservados como registros cujo caminho termina no próprio contêiner.
- Ausente, undefined, null e string vazia são distinguíveis.
- Listas são sequenciais; remoções deslocam os elementos posteriores.
- Chave e payload são campos distintos; nenhum separador chave/valor é inserido no registro em memória.
- O formato pode ser lido e escrito sem executar dados.
- As quatro interfaces produzem a mesma semântica.
