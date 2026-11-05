# Roadmap

**Status:** sequência de fases aprovada como planejamento inicial; critérios e entregas podem ser refinados.

## Fase 0 — Governança e especificação

- [x] Criar repositório.
- [x] Criar documentação inicial de missão, escopo e arquitetura.
- [ ] Aprovar modelo de dados detalhado.
- [ ] Aprovar formato canônico e codificação.
- [ ] Definir convenções de código, testes e erros.

**Saída:** contratos suficientes para iniciar o primeiro componente sem decisões estruturais implícitas.

## Fase 1 — takarr e parsing

- [ ] Definir gramática JSON suportada e requisitos de conformidade.
- [ ] Especificar gramática Vector.
- [ ] Implementar parser JSON.
- [ ] Implementar parser Vector.
- [ ] Converter entradas para o modelo canônico.
- [ ] Testar valores, estruturas vazias, escapes, erros e limites.

**Saída:** entrada estruturada convertida sem perda para a representação aprovada.

## Fase 2 — Núcleo canônico

- [ ] Implementar armazenamento Bash.
- [ ] Implementar leitura e escrita por caminho.
- [ ] Implementar existência e consulta de tipo.
- [ ] Implementar remoção.
- [ ] Implementar contêineres vazios e regras de lista.
- [ ] Criar testes de consistência.

**Saída:** motor canônico funcional e testado.

## Fase 3 — Interfaces de usuário

- [ ] Definir contratos das quatro interfaces.
- [ ] Implementar `multarr`.
- [ ] Implementar `planarr`.
- [ ] Implementar `strucarr`.
- [ ] Implementar `typarr`.
- [ ] Testar equivalência semântica entre interfaces.

**Saída:** diferentes formas de uso sobre o mesmo motor.

## Fase 4 — Navegação, iteração e modificadores

- [ ] Implementar listagem de caminhos e filhos.
- [ ] Implementar reconstrução de árvore e shape.
- [ ] Implementar iteração.
- [ ] Implementar modificadores aprovados.
- [ ] Medir desempenho em cenários representativos.

**Saída:** conjunto de ferramentas de consulta e manipulação.

## Fase 5 — Exportação, robustez e publicação

- [ ] Implementar exportação JSON.
- [ ] Validar round-trip de importação/exportação.
- [ ] Documentar exemplos e limitações.
- [ ] Revisar segurança e compatibilidade Bash.
- [ ] Definir licença.
- [ ] Preparar versão inicial.

## Fora do roadmap inicial

POSIX/Dash e adaptadores para outras linguagens só entram após a estabilização do núcleo Bash e aprovação de escopo específico.
