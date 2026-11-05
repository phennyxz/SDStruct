# Arquitetura

**Status:** separação de responsabilidades aprovada conceitualmente; interfaces internas e layout definitivo ainda em aberto.

## Camadas

```text
                Aplicações e scripts Bash
                           |
                 Interfaces SDStruct
          (multarr / planarr / strucarr / typarr)
                           |
                    API pública comum
                           |
                  Modelo canônico
                           |
              Motor de armazenamento Bash
                           |
          +----------------+----------------+
          |                                 |
    takarr / parsers                 Serializadores
    JSON / vector                    JSON / outros
```

O diagrama é conceitual. Não determina nomes de funções internas nem formato binário/textual definitivo.

## Responsabilidades

### Modelo de dados
Define a semântica de objetos, listas, tipos, valores, ausência e caminhos.

### Representação canônica
Define como o modelo é codificado internamente. Deve ser única fonte semântica para as interfaces.

### Motor de armazenamento
Mantém e consulta os registros canônicos usando recursos Bash. Não deve ser reimplementado em cada parser ou interface.

### API pública
Oferece operações consistentes para criar, consultar, alterar, remover e percorrer dados.

### Interfaces
Oferecem diferentes formas de o usuário manter e acessar estruturas. Não devem divergir semanticamente sem decisão explícita.

### takarr
Interpreta formatos de entrada e entrega dados ao mecanismo canônico. Não mantém um segundo modelo ou armazenamento independente.

### Serializadores
Convertem dados do modelo canônico para formatos externos, preservando tipos e valores sempre que o formato de destino permitir.

## Estratégia de implementação

O primeiro alvo é Bash 4.3+. Recursos como arrays associativos e namerefs podem ser utilizados quando apropriados. A arquitetura não deve simular portabilidade POSIX que não foi solicitada.

## Desempenho

- Consulta por caminho exato deve evitar reconstruir a árvore inteira.
- Operações que exigem varredura devem ser identificadas como tais.
- A árvore pode ser reconstruída para ferramentas de inspeção, como visualização e listagem de filhos.
- Medições devem preceder otimizações.

## Segurança

Entrada externa nunca pode ser avaliada como código Shell. Parsers devem operar sobre dados, validar sintaxe e retornar erros controlados.

## Questões arquiteturais em aberto

- Layout final dos arquivos de código.
- Mecanismo exato de armazenamento canônico.
- Codificação dos segmentos e separadores.
- Contrato de comunicação entre `takarr` e o motor.
- Política para mutações em listas e posições não preenchidas.
