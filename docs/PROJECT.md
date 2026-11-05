# SDStruct — Missão e visão

**Status:** missão aprovada em nível conceitual; detalhes de posicionamento podem evoluir com validação.

## O que é

SDStruct (Shell Data Structures) é uma biblioteca Bash para representar, consultar, manipular e percorrer estruturas de dados hierárquicas, multidimensionais e tipadas.

Seu propósito é tornar estruturas compostas utilizáveis diretamente em scripts Shell, com uma interface consistente e sem exigir que o usuário delegue o processamento a outra linguagem ou ferramenta externa.

## Problema que pretende resolver

Scripts Shell frequentemente precisam lidar com dados compostos — configurações, respostas JSON, inventários, registros, listas de objetos e estruturas aninhadas. As ferramentas tradicionais do Shell são excelentes para fluxos de texto e processos, mas oferecem recursos limitados para representar e manipular essas estruturas de maneira uniforme.

SDStruct pretende fornecer:
- um modelo de dados explícito;
- caminhos para localizar elementos;
- operações de consulta, alteração, remoção e iteração;
- tipagem preservada;
- importação e exportação;
- interfaces adequadas ao ambiente Shell.

## Público inicial

Desenvolvedores e administradores que escrevem scripts Bash e precisam trabalhar com dados estruturados, sem introduzir uma aplicação auxiliar em outra linguagem.

## Princípios

1. **Shell primeiro:** o produto inicial é uma biblioteca Bash.
2. **Semântica explícita:** ausência, vazio, null e tipos não devem ser confundidos.
3. **Consistência:** interfaces diferentes devem operar sobre o mesmo modelo semântico.
4. **Modularidade:** parser, modelo, armazenamento, API e conversores têm responsabilidades distintas.
5. **Portabilidade realista:** declarar claramente Bash mínimo e dependências; não prometer compatibilidade não testada.
6. **Segurança:** dados importados são dados, nunca código a executar.
7. **Evolução controlada:** extensões futuras não devem comprometer o núcleo.

## O que não é

- Não é uma implementação de Python, JavaScript, PHP ou C.
- Não é um substituto geral de `jq`.
- Não é um banco de dados persistente ou servidor.
- Não é um framework de execução de aplicações.
- Não é, na primeira fase, uma biblioteca POSIX universal.

## Visão de evolução

A primeira versão deve consolidar um núcleo Bash coerente, interfaces de armazenamento e importação/exportação. Adaptadores para outros ecossistemas poderão ser avaliados depois, caso exista necessidade concreta.
