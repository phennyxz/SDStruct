# Modelo de dados

**Status:** estrutura básica, tipos do núcleo e semântica central aprovados; detalhes de codificação e limites de interoperabilidade ainda em especificação.

## Tipos estruturais e terminais

O núcleo inicial contempla:

- **Objeto (`o`):** coleção de propriedades identificadas por chaves.
- **Lista (`l`):** coleção ordenada de posições indexadas.
- **String (`s`):** valor textual, inclusive string vazia.
- **Inteiro (`i`):** número inteiro, mantido em representação decimal textual legível para Bash.
- **Float (`f`):** número JSON com parte fracionária e/ou expoente. O lexema numérico original é mantido textualmente; não se exige conversão para um float nativo do Bash.
- **Booleano (`b`):** valor lógico.
- **Null (`n`):** valor nulo explícito.
- **Undefined (`u`):** posição ou propriedade existente, mas ainda não definida/preenchida.

Float32, Float64/Double como precisões distintas, Decimal128, BigInteger como tipo separado e outros tipos especializados ficam fora do núcleo inicial. `f` representa a categoria de número de ponto flutuante recebida, não uma promessa de precisão IEEE específica.

## Estados que não podem ser confundidos

O modelo distingue explicitamente:

1. **Ausente:** não há propriedade/elemento declarado no caminho.
2. **Undefined (`u`):** a posição ou propriedade existe, mas não recebeu um valor definido.
3. **Null (`n`):** existe explicitamente um valor nulo.
4. **String vazia (`s`):** existe uma string de comprimento zero.
5. **Contêiner vazio (`o` ou `l`):** existe um objeto ou lista sem elementos.

`undefined` e `null` são tipos distintos. Ambos possuem payload vazio (`''`); a semântica é determinada pelo tipo, não pelo conteúdo do payload. Uma string vazia também possui payload vazio, mas é identificada pelo tipo `s`.

Não assuma que Bash possui valores nativos null ou undefined. O modelo SDStruct representa esses estados explicitamente.

## Raiz e caminhos

Toda estrutura possui um nó raiz. A raiz não recebe uma chave ou índice artificial: seu caminho é vazio. Seu tipo é informado pelo primeiro (e, no caso de uma raiz escalar, único) tipificador.

Chaves de objetos são sempre strings. Índices de listas são posições numéricas não negativas.

## Tipagem integral do caminho

A tipagem não se limita ao valor terminal. Ela cobre todo o caminho, desde a raiz até o valor terminal, com um tipificador para cada nível correspondente.

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

O primeiro termina em undefined; o segundo termina em uma string vazia. Os exemplos ilustram a semântica, não a sintaxe física definitiva.

## Contêineres vazios

Objetos vazios e listas vazias são dados estruturais existentes e precisam sobreviver à importação, armazenamento e exportação.

Um contêiner vazio é representado por um registro terminal cujo caminho termina no próprio contêiner. Seu tipo terminal identifica o contêiner (`o` ou `l`) e o payload é vazio (`''`).

## Listas

Listas SDStruct são sempre sequenciais e contíguas. Não existem lacunas de índices no modelo lógico.

Ao inserir um elemento em um índice mais alto, as posições intermediárias faltantes são criadas como `undefined` (`u`). Isso mantém a lista contígua sem transformar automaticamente essas posições em `null` ou strings vazias.

Ao remover um elemento de uma lista, os elementos posteriores avançam uma posição para preservar a sequência contígua. A remoção de uma propriedade de objeto, por sua vez, não desloca outras propriedades.

## Números e interoperabilidade

O núcleo inicial reconhece `i` e `f`:

- Um número JSON sem fração e sem expoente, como `10`, é classificado como `i`.
- Um número JSON com fração ou expoente, como `10.5`, `10.0` ou `1e3`, é classificado como `f`.
- O lexema numérico é preservado como texto decimal ASCII, sem arredondamento, truncamento ou conversão silenciosa para string.
- A classificação lexical não afirma que o valor seja IEEE Float32 ou Float64. Precisões específicas poderão ser acrescentadas futuramente.

## Chaves e strings

Chaves de objetos e valores string podem conter caracteres especiais. O formato canônico define o escaping dos bytes separadores no campo de chave/caminho. O payload é armazenado separadamente do campo de chave, portanto não precisa de um separador chave/valor embutido.
