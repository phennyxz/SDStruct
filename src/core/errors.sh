# SDStruct core — códigos de retorno e mensagens de erro.
# Contrato PROVISÓRIO (docs/API.md ainda não aprovou o contrato de erros).
# Requer Bash 4.3+.

SDS_OK=0
SDS_E_NOTFOUND=1     # caminho ausente (também "falso" nos predicados)
SDS_E_USAGE=2        # argumentos ausentes/inválidos, nome de variável inválido
SDS_E_PATH=3         # segmento inválido (bytes reservados, índice não canônico)
SDS_E_TYPE=4         # tipificação inválida ou inconsistente; payload incompatível
SDS_E_CONFLICT=5     # conflito estrutural com dados existentes
SDS_E_CORRUPT=6     # estrutura de dados malformada
SDS_E_LIMIT=7        # limite excedido
SDS_E_NOTTERMINAL=8  # operação exige nó terminal
SDS_E_ENV=9          # ambiente/delimitadores inválidos

# sds__fail CODE MESSAGE... — escreve em stderr e retorna CODE.
sds__fail() {
  local code=$1
  shift
  printf 'sds: %s\n' "$*" >&2
  return "$code"
}
