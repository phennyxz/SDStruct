# API pública

**Status:** inventário inicial de operações; nomes, assinaturas, retornos e contratos ainda não aprovados.

## Objetivo

A API deve oferecer operações previsíveis para manipular estruturas SDStruct em scripts Bash.

## Operações candidatas

| Operação | Responsabilidade |
|---|---|
| `sd_get` | Obter valor em um caminho |
| `sd_set` | Criar ou alterar valor |
| `sd_exists` | Verificar existência |
| `sd_type` | Consultar tipo |
| `sd_delete` | Remover dado ou subestrutura |
| `sd_paths` | Listar caminhos |
| `sd_children` | Listar filhos diretos |
| `sd_tree` | Reconstruir/visualizar árvore |
| `sd_shape` | Descrever dimensões e irregularidades |
| `sd_each` | Iterar sobre elementos |
| `sd_import` | Importar dados de um formato |
| `sd_export` | Exportar dados para um formato |

Os nomes são candidatos, não contratos.

## Iteração

O projeto anterior continha ideias de iteração por elemento, tipo e caminho. A nova API deve avaliar essas capacidades e definir como callbacks, comandos, escopo de variáveis e erros serão tratados.

Não usar `eval` para executar callbacks ou interpretar nomes de comandos fornecidos como dados sem um contrato seguro e explícito.

## Contrato de erros

Ainda precisa ser definido:
- códigos de saída;
- mensagens em stderr;
- separação entre valor retornado e status;
- comportamento em caminho inexistente;
- comportamento em tipo incompatível;
- atomicidade de operações compostas.

## Requisitos da API

- Ser consistente entre as interfaces.
- Não perder distinções de tipo.
- Ter comportamento documentado para entradas inválidas.
- Ser segura para chaves e valores arbitrários suportados.
- Ser testável em Bash 4.3+.

Nenhuma função deve ser implementada apenas porque aparece nesta lista. A assinatura e o comportamento precisam ser aprovados antes de integrar a API pública.
