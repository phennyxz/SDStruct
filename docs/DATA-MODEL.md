# Modelo de dados

**Status:** tipos básicos e semântica estrutural aprovados em nível conceitual; regras de remoção, semântica numérica detalhada e interoperabilidade ainda em especificação.

## Tipos estruturais e terminais

O modelo contempla, no mínimo:

- **Objeto (`o`):** coleção de propriedades identificadas por chaves.
- **Lista (`l`):** coleção ordenada de posições indexadas.
- **String (`s`):** valor textual, inclusive string vazia.
- **Inteiro (`i`):** valor numérico inteiro.
- **Decimal (`d`):** valor numérico decimal.
- **Booleano (`b`):** valor lógico.
- **Null (`n`):** valor nulo explícito.
- **Undefined (`u`):** posição ou propriedade existente, mas ainda não definida/preenchida.

Os códigos acima registram a convenção conceitual aprovada até aqui. A sintaxe física e a codificação dos registros pertencem ao contrato do formato canônico.

Objetos podem ser esparsos: propriedades não declaradas não existem.

## Estados que não podem ser confundidos

O modelo distingue explicitamente:

1. **Ausente:** não há propriedade/elemento declarado no caminho.
2. **Undefined (`u`):** a posição ou propriedade existe, mas não recebeu um valor definido.
3. **Null (`n`):** existe explicitamente um valor nulo.
4. **String vazia (`s`):** existe uma string de comprimento zero.
5. **Contêiner vazio (`o` ou `l`):** existe um objeto ou lista sem elementos.

`undefined` e `null` são tipos distintos. Ambos possuem payload vazio (`''`). a semântica é determinada pelo tipo, não pelo conteúdo do payload. Uma string vazia também possui payload vazio, mas é identificada pelo tipo `s`.

Não assuma que Bash possui valores nativos null ou undefined. O modelo SDStruct representa esses estados explicitamente.

## Tipagem integral do caminho

A tipagem não se limita ao valor terminal. Ela cobre todo o caminho, desde a estrutura raiz até o valor terminal, com um tipificador para cada nível correspondente.

Exemplo conceitual:

```text
oln:rua/1 = ''
```

Leitura: o caminho parte de um objeto (`o`), atravessa uma lista (`l`) e termina em um valor null (`n`). O payload do valor terminal é vazio.

Da mesma forma:

```text
olu:rua/1 = ''
ols:rua/1 = ''
```

O primeiro termina em undefined; o segundo termina em uma string vazia. Os exemplos ilustram a semântica e não fixam, por si só, a sintaxe definitiva do formato.

A sequência de tipificadores deve permitir recuperar a natureza de cada nível do caminho, além do tipo do valor terminal.

## Contêineres vazios

Objetos vazios e listas vazias são dados estruturais existentes e precisam sobreviver à importação, armazenamento e exportação.

Um contêiner vazio é representado por um registro terminal cujo caminho termina no próprio contêiner. Seu tipo terminal identifica o contêiner (`o` ou `l`) e o payload é vazio (`''`). Portanto, não se deve confundir um contêiner vazio com um caminho ausente ou com uma string vazia.

## Listas

Listas SDStruct devem ser contíguas no modelo lógico: não deve existir uma posição posterior sem que as posições anteriores estejam representadas.

Ao inserir um elemento em um índice mais alto, as posições intermediárias faltantes são criadas como `undefined` (`u`). Isso mantém a organização contígua sem transformar automaticamente essas posições em `null` ou em strings vazias.

A política para remoção de uma posição — deslocar os elementos seguintes ou preservar a posição como `undefined` — ainda precisa ser aprovada. Também precisa ser definida a política de importação de arrays esparsos de formatos externos.

## Tipos numéricos

O núcleo inicial reconhece dois tipos numéricos:

- **Inteiro (`i`):** valor numérico inteiro.
- **Decimal (`d`):** valor numérico decimal.

Float32, Float64/Double, BigInteger e outros tipos numéricos especializados ficam fora do núcleo inicial e poderão ser avaliados futuramente.

Ainda precisam ser especificados: limites aceitos, notação científica, tratamento de números muito grandes e se a representação lexical original deve ser preservada. O parser não deve introduzir perda silenciosa de precisão; essa regra precisa ser definida antes da implementação.

## Chaves e strings

Chaves de objetos e valores string podem conter caracteres especiais. O formato canônico deve definir codificação e escaping sem colisões. Não presumir que separadores escolhidos estarão ausentes dos dados.
