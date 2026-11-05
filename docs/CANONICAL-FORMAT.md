# Formato canônico

**Status:** direção conceitual aprovada; sintaxe e codificação definitivas ainda não aprovadas.

## Objetivo

Todas as interfaces e conversores devem compartilhar uma representação canônica. O formato precisa preservar caminhos, tipos, valores e contêineres vazios sem materializar registros redundantes para cada nó intermediário.

## Registros terminais

A proposta atual é armazenar registros que identifiquem caminhos até valores terminais. Os tipos estruturais ao longo do caminho permitem inferir a hierarquia.

Exemplo puramente ilustrativo:

```text
os:servidor/nome = web1
oai:servidor/portas/0 = 80
oai:servidor/portas/1 = 477
```

A notação acima **não é contrato**: os códigos, separadores, ordem dos tipificadores e escaping ainda precisam ser definidos.

## Caminhos e tipificadores

A ideia em avaliação é que a tipagem descreva cada nível do caminho, e não apenas o valor final. Assim, um caminho pode informar que um segmento é objeto, o seguinte é lista e o último é um valor inteiro.

## Compactação estrutural

A proposta é não criar registros redundantes para todos os nós intermediários. A hierarquia deve ser inferível a partir dos caminhos e tipos.

Exceções necessárias, como contêineres vazios, precisam ser representadas explicitamente sem violar o objetivo de compactação.

## Codificação segura

Caracteres de controle foram considerados como possíveis delimitadores para reduzir colisões com texto comum. Nenhum byte ou delimitador foi aprovado.

A implementação deve aguardar a definição de:
- codificação de segmentos;
- escaping;
- tratamento de Unicode e bytes;
- limites de tamanho;
- separação entre metadados, caminho, tipo e valor;
- serialização segura para transporte entre processos.

Lembrete: variáveis Bash não podem conter byte NUL. Qualquer proposta de codificação deve respeitar as limitações reais do Bash.

## Critérios de aceitação do formato

- Não há colisões entre caminhos distintos.
- Chaves e strings especiais podem ser preservadas.
- Tipos estruturais são recuperáveis.
- Contêineres vazios são preservados.
- Ausência, string vazia, null e posição não preenchida são distinguíveis.
- O formato pode ser lido e escrito sem executar dados.
- As quatro interfaces produzem a mesma semântica.
