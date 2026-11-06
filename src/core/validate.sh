# SDStruct core — validação estrutural completa de uma coleção.

# sds_core_validate NAME — verifica:
#  - chaves bem formadas (tipificadores, nº de segmentos, índices canônicos);
#  - payload compatível com o tipo terminal;
#  - tipificação consistente entre registros que compartilham um nó;
#  - nenhum nó é ao mesmo tempo terminal e intermediário (cobre raiz escalar
#    com outros registros e contêiner vazio com descendentes);
#  - listas contíguas (índices 0..N-1 sem lacunas).
# Retorna 0 ou SDS_E_CORRUPT (primeiro problema em stderr).
sds__impl_core_validate() {
  local LC_ALL=C
  if (( $# != 1 )); then
    sds__fail "$SDS_E_USAGE" "sds_core_validate: uso: NAME"
    return
  fi
  sds__check_ready "$1" || return
  local -n __sds_vd=$1
  local -A __sds_ntype=() __sds_inner=() __sds_term=() __sds_lcount=() __sds_lmax=() __sds_seen=()
  local __sds_k __sds_i __sds_rn __sds_nk __sds_pref __sds_idx
  local -a __sds_pr
  for __sds_k in "${!__sds_vd[@]}"; do
    sds__decode_full "$__sds_k" || return
    __sds_rn=$SDS_D_N
    if ! sds__valid_payload "${SDS_D_TYPES:__sds_rn:1}" "${__sds_vd[$__sds_k]}"; then
      sds__fail "$SDS_E_CORRUPT" "payload incompatível com o tipo '${SDS_D_TYPES:__sds_rn:1}'"
      return
    fi
    __sds_pref=
    for ((__sds_i = 0; __sds_i <= __sds_rn; __sds_i++)); do
      if (( __sds_i == 1 )); then __sds_pref=${SDS_D_SEGS[0]}; elif (( __sds_i > 1 )); then __sds_pref+=$sds_LP${SDS_D_SEGS[__sds_i-1]}; fi
      __sds_nk=$__sds_i:$__sds_pref
      if [[ -n ${__sds_ntype[$__sds_nk]+x} && ${__sds_ntype[$__sds_nk]} != "${SDS_D_TYPES:__sds_i:1}" ]]; then
        sds__fail "$SDS_E_CORRUPT" "tipificação inconsistente em nó compartilhado"
        return
      fi
      __sds_ntype[$__sds_nk]=${SDS_D_TYPES:__sds_i:1}
      if (( __sds_i == __sds_rn )); then __sds_term[$__sds_nk]=1; else __sds_inner[$__sds_nk]=1; fi
      if [[ -n ${__sds_term[$__sds_nk]+x} && -n ${__sds_inner[$__sds_nk]+x} ]]; then
        sds__fail "$SDS_E_CORRUPT" "nó terminal com descendentes"
        return
      fi
      if (( __sds_i < __sds_rn )) && [[ ${SDS_D_TYPES:__sds_i:1} == l ]]; then
        __sds_idx=${SDS_D_SEGS[__sds_i]}
        if [[ -z ${__sds_seen[$__sds_nk:$__sds_idx]+x} ]]; then
          __sds_seen[$__sds_nk:$__sds_idx]=1
          __sds_lcount[$__sds_nk]=$(( ${__sds_lcount[$__sds_nk]:-0} + 1 ))
        fi
        if (( __sds_idx > ${__sds_lmax[$__sds_nk]:--1} )); then __sds_lmax[$__sds_nk]=$__sds_idx; fi
      fi
    done
  done
  for __sds_nk in "${!__sds_lcount[@]}"; do
    if (( ${__sds_lcount[$__sds_nk]} != ${__sds_lmax[$__sds_nk]} + 1 )); then
      sds__fail "$SDS_E_CORRUPT" "lista não contígua"
      return
    fi
  done
  sds__ix_rebuild "$1" # descarta qualquer índice obsoleto
}
