# Escopo e limites

**Status:** escopo inicial aprovado em alto nível. Funcionalidades individuais e contratos ainda dependem de especificação.

## Dentro do escopo inicial

- Biblioteca Bash 4.3+.
- Representação de objetos e listas aninhados.
- Caminhos hierárquicos para acessar dados.
- Tipos explícitos e preservação de valores.
- Modelo canônico compartilhado.
- Diferentes interfaces de armazenamento voltadas ao usuário.
- Parser/conversor de entrada `takarr`.
- JSON como primeiro formato de intercâmbio.
- Formato declarativo `vector`, após especificação própria.
- Operações básicas de leitura, escrita, existência, tipo, remoção e iteração.
- Testes automatizados e documentação.

## Fora do escopo da primeira fase

- Compatibilidade POSIX/Dash.
- Implementações nativas em JavaScript, Python, PHP ou C.
- Adaptadores completos para outras linguagens.
- Persistência em banco de dados.
- Serviço de rede ou API remota.
- Interface gráfica.
- Dependência obrigatória de `jq`, Python, Node.js ou utilitários externos para o funcionamento central.
- Otimizações prematuras antes de testes de correção e desempenho.

## Interfaces históricas

O projeto parte de quatro ideias de interface que existiam no projeto anterior:

- `multarr`: interface com armazenamento global.
- `planarr`: interface baseada em array associativo do usuário, sem tabela de tipos externa.
- `strucarr`: interface baseada em array associativo do usuário e tabela auxiliar de tipos.
- `typarr`: interface que codifica tipo na chave e utiliza índice auxiliar.

Esses nomes e conceitos são referências a preservar e avaliar. A compatibilidade exata com o projeto anterior, a sintaxe pública e os detalhes internos ainda precisam ser especificados.

## Regras de expansão

Uma funcionalidade só entra no escopo quando:
1. resolve uma necessidade identificada;
2. tem comportamento definido;
3. não duplica responsabilidade existente;
4. tem critérios de aceitação e testes;
5. foi aprovada pela direção do projeto.

## Critério de não fazer

Se uma funcionalidade exigir que o núcleo imite regras específicas de outra linguagem, ela deve ser considerada para um adaptador futuro, não incorporada automaticamente ao modelo Bash.
