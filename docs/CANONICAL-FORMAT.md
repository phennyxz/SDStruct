# Formato canônico

**Status:** princípios de tipagem integral do caminho, valores especiais e contêineres vazios aprovados; sintaxe física e codificação definitivas ainda não aprovadas.

## Objetivo

Todas as interfaces e conversores devem compartilhar uma representação canônica. O formato precisa preservar caminhos, tipos, valores e contêineres vazios sem materializar registros redundantes para cada nó intermediário.

## Registros terminais

A representação utiliza registros que identificam caminhos até valores terminais. A tipagem ao longo do caminho permite inferir a hierarquia.

Um registro também pode terminar em um contêiner vazio. Nesse caso, o próprio contêiner é o nó terminal registrado; não é necessário criar registros artificiais para seus descendentes.

## Tipagem integral do caminho

A tipagem cobre todo o caminho, desde a estrutura raiz até o valor terminal. Deve haver um tipificador para cada nível correspondente, inclusive para o valor terminal. Não se tipa apenas o valor final.

Exemplo conceitual:

```text
oln:rua/1 = ''
```

Leitura: o caminho parte de um objeto (`o`), atravessa uma lista (`l`) e termina em um valor null (`n`). A sequência de tipificadores descreve os níveis estruturais e o valor terminal.

Outros exemplos:

```text
olu:rua/1 = ''
ols:rua/1 = ''
```

O primeiro termina em undefined; o segundo termina em uma string vazia. Os exemplos fixam a semântica pretendida, mas não aprovam ainda os separadores, a gramática ou a codificação física.

## Tipos com payload vazio

Os tipos `u` (undefined) e `n` (null) possuem payload vazio (`''`). O tipo, e não o conteúdo do payload, determina o significado.

Uma string vazia também possui payload vazio, mas é identificada pelo tipo `s`. Assim, undefined, null e string vazia permanecem distinguíveis.

Contêineres vazios seguem o mesmo princípio: o registro termina no próprio contêiner, identificado pelo tipo `o` (objeto) ou `l` (lista), com payload vazio.

## Compactação estrutural

A proposta é não criar registros redundantes para todos os nós intermediários. A hierarquia deve ser inferível a partir dos caminhos e de sua tipagem integral.

Registros terminais explícitos são necessários para preservar valores terminais e contêineres vazios.

## Codificação segura

Caracteres de controle foram considerados como possíveis delimitadores para reduzir colisões com texto comum. Nenhum byte ou delimitador foi aprovado.

A implementação deve aguardar a definição de:

- codificação de segmentos;
- escaping;
- tratamento de Unicode e bytes;
- limites de tamanho;
- separação entre metadados, caminho, sequência de tipos e valor;
- serialização segura para transporte entre processos.

Lembrete: variáveis Bash não podem conter byte NUL. Qualquer proposta de codificação deve respeitar as limitações reais do Bash.

## Critérios de aceitação do formato

- Não há colisões entre caminhos distintos.
- Chaves e strings especiais podem ser preservadas.
- A tipagem de todos os níveis do caminho, inclusive do valor terminal, é recuperável.
- Contêineres vazios são preservados como registros cujo caminho termina no próprio contêiner.
- Ausente, undefined, null e string vazia são distinguíveis.
- Undefined e null podem ser representados com payload vazio, sem ambiguidade porque possuem tipos distintos.
- O formato pode ser lido e escrito sem executar dados.
- As quatro interfaces produzem a mesma semântica.
