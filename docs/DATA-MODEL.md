# Modelo de dados

**Status:** conceitos fundamentais aprovados; semântica detalhada ainda em especificação.

## Tipos estruturais

O modelo contempla, no mínimo:
- **Objeto:** coleção de propriedades identificadas por chaves.
- **Lista:** coleção ordenada de posições indexadas.
- **Valores terminais:** strings, números, booleanos e null, além de eventuais tipos adicionais aprovados.

Objetos podem ser esparsos: propriedades não declaradas não existem.

Listas do SDStruct devem obedecer à regra de índices contíguos. A política exata para criação automática de posições intermediárias e remoção de posições ainda precisa ser aprovada.

## Estados que não podem ser confundidos

O modelo deve distinguir:
1. **Ausente:** não há propriedade/elemento declarado.
2. **String vazia:** valor textual de comprimento zero.
3. **Null:** valor nulo explícito.
4. **Posição não preenchida:** estado potencialmente necessário para representar uma posição intermediária de lista; semântica e nome ainda pendentes.

Não assuma que Bash possui um valor null nativo. O modelo deve representar esse estado explicitamente.

## Contêineres vazios

Objetos vazios e listas vazias são dados estruturais existentes e precisam sobreviver a importação, armazenamento e exportação. Como o projeto pretende evitar registros redundantes de nós intermediários, a representação de um contêiner vazio precisa ser definida no formato canônico.

## Listas

A regra conceitual aprovada é que listas SDStruct sejam contíguas: não deve existir uma posição posterior sem que as posições anteriores estejam representadas.

Ainda é necessário decidir:
- se inserir índice alto cria posições não preenchidas intermediárias;
- qual é a semântica dessas posições;
- se remover uma posição desloca as seguintes;
- como importar arrays esparsos de formatos externos.

## Tipos numéricos

A distinção entre inteiro e decimal, limites numéricos, notação científica e preservação lexical do número precisam ser especificadas no contrato de tipos e parser.

## Chaves e strings

Chaves de objetos e valores string podem conter caracteres especiais. O formato canônico deve definir codificação e escaping sem colisões. Não presumir que separadores escolhidos estarão ausentes dos dados.
