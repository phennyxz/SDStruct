# SDStruct core — construção e decodificação de chaves tipadas.
# Chave = TIPIFICADORES + sds_LT + SEG0 + sds_LP + SEG1 ...
# A raiz tem caminho vazio (chave = TIPO + sds_LT). Nº de tipificadores =
# nº de segmentos + 1.

# sds__join OUTVAR SEG... — junta segmentos com sds_LP.
sds__join() {
  local -n __sds_jo=$1
  shift
  local __sds_jr= __sds_ji
  for ((__sds_ji = 1; __sds_ji <= $#; __sds_ji++)); do
    if (( __sds_ji == 1 )); then
      __sds_jr=${!__sds_ji}
    else
      __sds_jr+=$sds_LP${!__sds_ji}
    fi
  done
  __sds_jo=$__sds_jr
}

# sds_core_make_key OUTVAR TYPES [SEGMENT...]
sds__impl_core_make_key() {
  local LC_ALL=C
  if (( $# < 2 )); then
    sds__fail "$SDS_E_USAGE" "sds_core_make_key: uso: OUTVAR TYPES [SEGMENT...]"
    return
  fi
  sds_check_delims || return
  sds__check_name "$1" || return
  local __sds_out=$1 __sds_types=$2
  shift 2
  sds__check_types "$__sds_types" "$#" || return
  sds__check_segments "$__sds_types" "$@" || return
  local __sds_path
  sds__join __sds_path "$@"
  local -n __sds_mk=$__sds_out
  __sds_mk=$__sds_types$sds_LT$__sds_path
}

# sds__head KEY — preenche SDS_D_TYPES, SDS_D_PATH, SDS_D_N (verificação leve).
sds__head() {
  [[ $1 == *"$sds_LT"* ]] || return 1
  SDS_D_TYPES=${1%%"$sds_LT"*}
  SDS_D_PATH=${1#*"$sds_LT"}
  [[ $SDS_D_TYPES =~ ^[olsifbnu]+$ ]] || return 1
  SDS_D_N=$(( ${#SDS_D_TYPES} - 1 ))
}

# sds__decode_full KEY — valida a chave e preenche SDS_D_TYPES, SDS_D_PATH,
# SDS_D_N e o array SDS_D_SEGS.
sds__decode_full() {
  SDS_D_SEGS=()
  if ! sds__head "$1"; then
    sds__fail "$SDS_E_CORRUPT" "chave malformada"
    return
  fi
  local __sds_n=$SDS_D_N __sds_path=$SDS_D_PATH __sds_i __sds_rest __sds_lps
  if [[ $__sds_path == *"$sds_LT"* ]]; then
    sds__fail "$SDS_E_CORRUPT" "chave com mais de um sds_LT"
    return
  fi
  if [[ ! ${SDS_D_TYPES:0:__sds_n} =~ ^[ol]*$ ]]; then
    sds__fail "$SDS_E_CORRUPT" "tipificador intermediário inválido: '$SDS_D_TYPES'"
    return
  fi
  if (( __sds_n == 0 )); then
    if [[ -n $__sds_path ]]; then
      sds__fail "$SDS_E_CORRUPT" "raiz com caminho não vazio"
      return
    fi
    return 0
  fi
  __sds_lps=${__sds_path//[!"$sds_LP"]/}
  if (( ${#__sds_lps} != __sds_n - 1 )); then
    sds__fail "$SDS_E_CORRUPT" "nº de segmentos incompatível com os tipificadores"
    return
  fi
  __sds_rest=$__sds_path
  for ((__sds_i = 0; __sds_i < __sds_n - 1; __sds_i++)); do
    SDS_D_SEGS[__sds_i]=${__sds_rest%%"$sds_LP"*}
    __sds_rest=${__sds_rest#*"$sds_LP"}
  done
  SDS_D_SEGS[__sds_n-1]=$__sds_rest
  for ((__sds_i = 0; __sds_i < __sds_n; __sds_i++)); do
    if [[ ${SDS_D_TYPES:__sds_i:1} == l ]] && ! sds__is_index "${SDS_D_SEGS[__sds_i]}"; then
      sds__fail "$SDS_E_CORRUPT" "índice de lista inválido na chave"
      return
    fi
  done
  return 0
}

# sds_core_decode_key KEY — resultados em SDS_D_TYPES, SDS_D_N, SDS_D_PATH e
# no array SDS_D_SEGS (variáveis globais sobrescritas a cada chamada).
sds__impl_core_decode_key() {
  local LC_ALL=C
  if (( $# != 1 )); then
    sds__fail "$SDS_E_USAGE" "sds_core_decode_key: uso: KEY"
    return
  fi
  sds_check_delims || return
  sds__decode_full "$1"
}
