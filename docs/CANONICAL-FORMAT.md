# Formato canônico

**Status:** semântica dos caminhos, tipagem, tipos básicos e separadores de caminho/tipagem aprovados conceitualmente; gramática completa, separação do payload e escaping ainda pendentes.

## Objetivo

Todas as interfaces e conversores devem compartilhar uma representação canônica. O formato precisa preservar caminhos, tipos, valores e contêineres vazios sem materializar registros redundantes para cada nó intermediário.

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
- `b`: booleano.
- `n`: null.
- `u`: undefined.

`u` e `n` possuem payload vazio (`''`), mas são distintos pelo tipificador. String vazia também possui payload vazio e é identificada por `s`. Contêineres vazios são identificados por `o` ou `l`, com o caminho terminando no próprio contêiner e payload vazio.

Tipos float/double, decimais especializados e outros tipos numéricos ficam fora do núcleo inicial.

## Separadores conceituais aprovados

Foram escolhidos dois bytes de controle:

- `0xFE`: separador entre segmentos sucessivos do caminho.
- `0xFF`: separador entre a sequência de tipificadores e o caminho.

Esses bytes são escolhas conceituais aprovadas para o formato. A gramática completa ainda precisa definir a posição exata desses campos, como o payload é separado do cabeçalho, e como representar/escapar ocorrências desses bytes dentro de chaves e valores.

A representação do inteiro `i` será textual em base 10, legível para Bash; não será armazenada como inteiro binário nativo.

## Codificação segura e limitações do Bash

A implementação deve tratar o formato como sequência de bytes, não presumir que os registros são UTF-8 válido. Os bytes `0xFE` e `0xFF` não são bytes válidos isoladamente em UTF-8, o que precisa ser considerado ao ler, escrever, transportar e testar os registros.

Variáveis Bash não podem conter byte NUL (`0x00`). Qualquer proposta de codificação deve respeitar essa limitação. Também será necessário especificar escaping ou outra estratégia para impedir que dados contendo os bytes separadores sejam confundidos com a estrutura.

## Decisões ainda pendentes

- gramática exata e ordem dos campos do registro;
- separador entre cabeçalho e payload;
- escaping de `0xFE` e `0xFF` em chaves e valores;
- codificação de segmentos, Unicode e bytes arbitrários;
- limites de tamanho;
- política para números JSON decimais ou em notação exponencial;
- validação de registros malformados e duplicados.

## Critérios de aceitação do formato

- Não há colisões entre caminhos distintos.
- Chaves e strings especiais podem ser preservadas.
- A tipagem de todos os níveis do caminho, inclusive do valor terminal, é recuperável.
- A raiz é representada por caminho vazio, sem índice artificial.
- Contêineres vazios são preservados como registros cujo caminho termina no próprio contêiner.
- Ausente, undefined, null e string vazia são distinguíveis.
- Listas são sequenciais; remoções deslocam os elementos posteriores.
- O formato pode ser lido e escrito sem executar dados.
- As quatro interfaces produzem a mesma semântica.
