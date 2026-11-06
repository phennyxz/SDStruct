# SDStruct core — tipos, validação de payloads e de argumentos.
# Tipificadores: o l s i f b n u (docs/DATA-MODEL.md).

# Nomes iniciados por __sds_, SDS_ ou sds_ são reservados e rejeitados como
# nomes de variáveis do chamador. Todas as variáveis locais internas usam o
# prefixo __sds_, de modo que qualquer outro nome (n, i, out, name...) é seguro.
sds__check_name() {
  if [[ ! $1 =~ ^[A-Za-z_][A-Za-z_0-9]*$ || $1 == __sds_* || $1 == SDS_* || $1 == sds_* ]]; then
    sds__fail "$SDS_E_USAGE" "nome de variável inválido: '$1'"
    return
  fi
  return 0
}

sds__is_assoc() {
  local __sds_decl
  __sds_decl=$(declare -p "$1" 2>/dev/null) || return 1
  [[ $__sds_decl =~ ^declare\ -[a-zA-Z]*A ]]
}

# sds__check_ready NAME — delimitadores válidos e NAME é um associative array.
sds__check_ready() {
  sds_check_delims || return
  sds__check_name "$1" || return
  if ! sds__is_assoc "$1"; then
    sds__fail "$SDS_E_USAGE" "'$1' não é um associative array (declare -A)"
    return
  fi
  return 0
}

# sds__valid_payload TYPE PAYLOAD
# Payload de b (true|false) é decisão PROVISÓRIA: a documentação ainda não
# especifica a codificação de booleanos.
sds__valid_payload() {
  local __sds_t=$1 __sds_p=$2
  local __sds_re_int='^-?(0|[1-9][0-9]*)$'
  local __sds_re_num='^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$'
  case $__sds_t in
    s) return 0 ;;
    i) [[ $__sds_p =~ $__sds_re_int ]] ;;
    f) [[ $__sds_p =~ $__sds_re_num && $__sds_p == *[.eE]* ]] ;;
    b) [[ $__sds_p == true || $__sds_p == false ]] ;;
    n | u | o | l) [[ -z $__sds_p ]] ;;
    *) return 1 ;;
  esac
}

sds__check_payload() {
  if ! sds__valid_payload "$1" "$2"; then
    sds__fail "$SDS_E_TYPE" "payload inválido para o tipo '$1'"
    return
  fi
  return 0
}

# sds__check_types TYPES N — N+1 tipificadores; os N primeiros são o ou l.
sds__check_types() {
  local __sds_types=$1 __sds_n=$2
  if [[ ! $__sds_types =~ ^[olsifbnu]+$ ]]; then
    sds__fail "$SDS_E_TYPE" "sequência de tipificadores inválida: '$__sds_types'"
    return
  fi
  if (( ${#__sds_types} != __sds_n + 1 )); then
    sds__fail "$SDS_E_TYPE" "são necessários $((__sds_n + 1)) tipificadores para $__sds_n segmentos (recebidos ${#__sds_types})"
    return
  fi
  if [[ ! ${__sds_types:0:__sds_n} =~ ^[ol]*$ ]]; then
    sds__fail "$SDS_E_TYPE" "níveis intermediários devem ser o ou l: '$__sds_types'"
    return
  fi
  return 0
}

# Índice de lista canônico: decimal sem zeros à esquerda, até 9 dígitos.
sds__is_index() {
  [[ $1 =~ ^(0|[1-9][0-9]{0,8})$ ]]
}

# sds__check_seg_bytes SEG... — rejeita os bytes reservados (escaping pendente).
sds__check_seg_bytes() {
  local __sds_seg
  for __sds_seg in "$@"; do
    if [[ $__sds_seg == *"$sds_LT"* || $__sds_seg == *"$sds_LP"* ]]; then
      sds__fail "$SDS_E_PATH" "segmento contém byte reservado (escaping de sds_LT/sds_LP ainda não aprovado)"
      return
    fi
  done
  return 0
}

# sds__check_segments TYPES SEG... — bytes reservados e índices de lista.
sds__check_segments() {
  local __sds_types=$1 __sds_i
  shift
  sds__check_seg_bytes "$@" || return
  for ((__sds_i = 1; __sds_i <= $#; __sds_i++)); do
    if [[ ${__sds_types:__sds_i-1:1} == l ]] && ! sds__is_index "${!__sds_i}"; then
      sds__fail "$SDS_E_PATH" "índice de lista inválido: '${!__sds_i}'"
      return
    fi
  done
  return 0
}
