# SDStruct

**SDStruct (Shell Data Structures)** é uma biblioteca Bash para representar, consultar, manipular e percorrer estruturas de dados hierárquicas, multidimensionais e tipadas.

O projeto busca oferecer uma API de Shell para trabalhar com estruturas compostas sem exigir ferramentas externas como Python, Node.js ou `jq`.

> **Status:** planejamento e fundação documental; núcleo canônico inicial em implementação (ver [notas do núcleo](docs/CORE.md); contratos provisórios). `tests/run.sh` executa a suíte; `tests/bench.sh` mede desempenho. Atribuição ordinária cria caminhos e atualiza valores; `set` é operação estrutural excepcional (renomear / mudar tipo terminal).
>
> **Plataforma inicial:** Bash 4.3 ou superior.

## Objetivos

- Representar objetos e listas aninhados.
- Preservar tipos e valores, incluindo strings vazias e valores nulos.
- Oferecer caminhos para acessar elementos.
- Disponibilizar diferentes interfaces de armazenamento sobre um modelo canônico comum.
- Importar e exportar formatos de dados, começando por JSON.
- Manter uma implementação Bash modular, testável e sem dependências externas obrigatórias.

## Escopo inicial

O primeiro alvo é Bash 4.3+. Compatibilidade POSIX/Dash e adaptadores para outras linguagens são possibilidades futuras, não compromissos da primeira versão.

O primeiro componente executável planejado é `takarr.sh`, responsável por interpretar formatos de entrada e produzir a representação canônica do SDStruct. Ele não será um motor de armazenamento independente.

## Estado do projeto

Consulte:

- [Missão e visão](docs/PROJECT.md)
- [Escopo e limites](docs/SCOPE.md)
- [Arquitetura](docs/ARCHITECTURE.md)
- [Modelo de dados](docs/DATA-MODEL.md)
- [Formato canônico](docs/CANONICAL-FORMAT.md)
- [Contratos da API](docs/API.md)
- [Núcleo: notas de implementação](docs/CORE.md)
- [Roadmap](docs/ROADMAP.md)
- [Decisões arquiteturais](docs/decisions/ADR-0001.md)
- [Instruções para agentes](AGENTS.md)
- [Instruções do GitHub Copilot](.github/copilot-instructions.md)

## Princípio de governança

A documentação distingue decisões aprovadas, propostas e questões em aberto. Uma proposta ou exemplo não se torna contrato técnico até ser explicitamente aprovado e registrado.

Nenhuma implementação deve antecipar decisões arquiteturais pendentes.

## Licença

A licença ainda não foi definida. Não presuma permissão de redistribuição ou uso até que uma licença seja escolhida e adicionada ao repositório.
