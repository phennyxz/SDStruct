# Instruções do GitHub Copilot — SDStruct

Antes de editar este repositório, leia `AGENTS.md` e os documentos relevantes em `docs/`.

## Papel

Você é o implementador. A direção do projeto define missão, escopo, contratos e decisões arquiteturais. Não assuma autoridade para redefini-los.

## Regras prioritárias

1. Implemente somente tarefas explicitamente solicitadas.
2. Respeite decisões **APROVADAS**.
3. Não converta itens **PROPOSTOS** ou **EM ABERTO** em comportamento definitivo.
4. Se uma decisão pendente bloquear a implementação, pare e apresente alternativas com consequências técnicas.
5. Não adicione dependências externas obrigatórias sem aprovação.
6. Não use `eval` para processar dados, declarações ou entrada externa.
7. Não duplique o motor canônico em parsers, conversores ou interfaces.
8. Não amplie o escopo para outras linguagens ou shells.
9. Escreva testes para todo comportamento novo e execute-os.
10. Informe honestamente o que foi e o que não foi testado.

## Plataforma

O alvo inicial é Bash 4.3 ou superior. Não prometa compatibilidade POSIX/Dash. Use recursos Bash conscientemente e documente a versão mínima necessária.

## Arquitetura

- SDStruct é a biblioteca e o modelo de dados.
- `takarr` é um parser/conversor de entrada; não é um motor de armazenamento.
- O modelo canônico deve ser compartilhado pelas interfaces.
- JSON é o primeiro formato de intercâmbio planejado.
- O formato `vector` ainda precisa de especificação gramatical aprovada.
- As quatro interfaces históricas (`multarr`, `planarr`, `strucarr`, `typarr`) são referências de projeto; não presuma que seus contratos antigos já foram aprovados para a nova versão.

## Ao concluir uma tarefa

Apresente:
- arquivos criados ou alterados;
- decisões e contratos aplicados;
- comandos de teste executados e resultados reais;
- limitações e riscos;
- decisões pendentes que precisam da direção do projeto.

Não comece a implementar `takarr.sh` ou outro código apenas porque leu estas instruções. Aguarde uma tarefa explícita.
