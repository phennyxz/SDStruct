# Orientações para agentes de programação

Estas regras se aplicam a qualquer agente de IA ou pessoa que implemente código neste repositório.

## Antes de trabalhar

1. Leia este arquivo.
2. Leia `.github/copilot-instructions.md` quando estiver usando GitHub Copilot.
3. Consulte os documentos de `docs/` relevantes para a tarefa.
4. Verifique o estado atual do código e dos testes antes de propor alterações.

## Autoridade das especificações

- Decisões marcadas como **APROVADAS** são contratos do projeto.
- Itens **PROPOSTOS** são hipóteses para avaliação; não os trate como decisões.
- Itens **EM ABERTO** exigem decisão da direção do projeto antes de uma implementação que os torne irreversíveis.
- Exemplos ilustrativos não definem gramática, codificação ou API por si só.

## Regras obrigatórias

- Não altere a missão, o escopo, o modelo de dados ou a arquitetura sem aprovação.
- Não implemente funcionalidades fora do escopo autorizado.
- Não crie motores de armazenamento duplicados.
- Não introduza dependências externas obrigatórias sem aprovação.
- Não use `eval` para interpretar dados ou entrada do usuário.
- Não confunda dado ausente, string vazia, null ou posição não preenchida.
- Não invente semântica para decisões pendentes.
- Não afirme que testes passaram sem executá-los.
- Atualize a documentação quando uma implementação aprovada alterar comportamento ou contrato.

## Processo de implementação

1. Resuma o contrato aplicável.
2. Identifique decisões pendentes que bloqueiam a tarefa.
3. Implemente somente o escopo solicitado.
4. Adicione testes reproduzíveis.
5. Execute os testes e informe os comandos e resultados.
6. Registre limitações, riscos e decisões ainda necessárias.

## Segurança e robustez

Trate todo conteúdo importado como dado não confiável. Faça parsing sem executar conteúdo. Valide entradas, limites, caminhos e tipos. Evite expansão acidental de shell, globbing, word splitting e avaliação indireta.

## Estilo

Prefira funções pequenas, nomes claros, modularidade, comentários sobre decisões não óbvias e compatibilidade explícita com Bash 4.3+. Evite otimizações prematuras.
