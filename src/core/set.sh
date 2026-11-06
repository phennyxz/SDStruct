# SDStruct core — sds_core_set: operação ESTRUTURAL e excepcional.
#
# NÃO é atribuição: criar caminhos e atualizar valores é feito por
# sds_core_assign. sds_core_set altera metadados de um registro que já existe:
# renomeia o caminho e/ou muda o tipo terminal (análogo conceitual a um chmod).
#
#   sds_core_set NAME CHAVE_ATUAL CHAVE_NOVA
#
# As duas chaves usam a representação canônica (tipificadores + sds_LT +
# caminho; ver sds_core_make_key). A chave atual precisa coincidir com o
# registro existente (inclusive tipificadores); a nova descreve destino e tipo.
# Regras (PROVISÓRIAS, aguardam aprovação):
#  - o payload é preservado; ao mudar o tipo ele precisa ser válido no novo tipo;
#  - tipificadores de nós intermediários nunca são alterados: ancestrais
#    existentes do destino têm de ter o mesmo tipo (SDS_E_TYPE); ancestrais
#    ausentes são criados, ancestral u/n é promovido, contêiner vazio é
#    consumido; ancestral escalar é erro;
#  - contêiner com descendentes: pode ser renomeado (a subárvore acompanha),
#    mas seu tipo não pode mudar (SDS_E_CONFLICT; nada é descartado);
#  - destino já existente: SDS_E_CONFLICT; destino dentro da própria subárvore:
#    SDS_E_CONFLICT; caminho atual ausente: SDS_E_NOTFOUND;
#  - mover elemento de lista para fora dela equivale a removê-lo (os irmãos
#    seguintes avançam); mover dentro da mesma lista não é suportado (pendente);
#  - toda validação ocorre antes de qualquer escrita (falha = nada muda).

sds__impl_core_set() {
  local LC_ALL=C
  if (( $# != 3 )); then
    sds__fail "$SDS_E_USAGE" "sds_core_set: uso: NAME CHAVE_ATUAL CHAVE_NOVA"
    return
  fi
  local __sds_name=$1 __sds_okey=$2 __sds_nkey=$3
  sds__check_ready "$__sds_name" || return
  local __sds_ot __sds_on __sds_op __sds_nt __sds_nn __sds_np
  local -a __sds_osegs=() __sds_segs=() __sds_pref=("")
  sds__decode_full "$__sds_okey" 2>/dev/null || {
    sds__fail "$SDS_E_PATH" "chave atual malformada"
    return
  }
  __sds_ot=$SDS_D_TYPES __sds_on=$SDS_D_N __sds_op=$SDS_D_PATH
  __sds_osegs=(${SDS_D_SEGS[@]+"${SDS_D_SEGS[@]}"})
  sds__decode_full "$__sds_nkey" 2>/dev/null || {
    sds__fail "$SDS_E_PATH" "chave nova malformada (tipificadores, segmentos ou índices inválidos)"
    return
  }
  __sds_nt=$SDS_D_TYPES __sds_nn=$SDS_D_N __sds_np=$SDS_D_PATH
  __sds_segs=(${SDS_D_SEGS[@]+"${SDS_D_SEGS[@]}"})
  sds__check_segments "$__sds_nt" ${__sds_segs[@]+"${__sds_segs[@]}"} || return

  sds__ix_sync "$__sds_name" || return
  local -n __sds_d=$__sds_name __sds_ix=SDS_IX_$__sds_name
  local __sds_oid=$__sds_on$sds_LT$__sds_op __sds_ov=${__sds_ix[$__sds_on$sds_LT$__sds_op]-}
  if [[ -z $__sds_ov ]]; then
    sds__fail "$SDS_E_NOTFOUND" "caminho atual inexistente"
    return
  fi
  if [[ ${__sds_ov%%,*} != "$__sds_ot" ]]; then
    sds__fail "$SDS_E_TYPE" "a tipificação da chave atual não confere com o registro existente ('${__sds_ov%%,*}')"
    return
  fi
  local __sds_leaf=0 __sds_ocnt=0 __sds_payload=
  if [[ $__sds_ov == *,* ]]; then __sds_ocnt=${__sds_ov#*,}; fi
  if (( __sds_ocnt == 0 )); then
    __sds_leaf=1
    if [[ -z ${__sds_d[$__sds_okey]+x} ]]; then
      sds__fail "$SDS_E_CORRUPT" "índice sem registro correspondente"
      return
    fi
    __sds_payload=${__sds_d[$__sds_okey]}
  fi
  local __sds_olast=${__sds_ot: -1} __sds_nlast=${__sds_nt: -1}
  if (( __sds_leaf )); then
    sds__check_payload "$__sds_nlast" "$__sds_payload" || return
  elif [[ $__sds_olast != "$__sds_nlast" ]]; then
    sds__fail "$SDS_E_CONFLICT" "o nó possui descendentes incompatíveis com o tipo '$__sds_nlast'; nada foi alterado"
    return
  fi

  local -a __sds_rm=() __sds_xd=()
  local -A __sds_add=() __sds_xs=()

  # Mesmo caminho: apenas mudança de tipo terminal.
  if (( __sds_on == __sds_nn )) && [[ $__sds_op == "$__sds_np" ]]; then
    if [[ ${__sds_ot:0:__sds_on} != "${__sds_nt:0:__sds_nn}" ]]; then
      sds__fail "$SDS_E_TYPE" "tipificadores intermediários não podem ser alterados por set"
      return
    fi
    [[ $__sds_ot != "$__sds_nt" ]] || return 0
    __sds_rm=("$__sds_okey")
    __sds_add[$__sds_nkey]=$__sds_payload
    case $__sds_nlast in
      o | l) __sds_xs[$__sds_oid]=$__sds_nt,0 ;;
      *) __sds_xs[$__sds_oid]=$__sds_nt ;;
    esac
    sds__apply
    return
  fi

  sds__set_rename || return
}

# sds__set_rename — renomeação (com ou sem mudança de tipo). Usa as variáveis
# de sds__impl_core_set (escopo dinâmico). Valida tudo no estado atual, destaca
# o nó (como delete) e o reinsere no destino.
sds__set_rename() {
  local __sds_i __sds_pp
  # destino dentro da própria subárvore
  if (( __sds_on == 0 )) || { (( __sds_nn > __sds_on )) && [[ $__sds_np == "$__sds_op$sds_LP"* ]]; }; then
    sds__fail "$SDS_E_CONFLICT" "o destino está dentro da subárvore do caminho atual"
    return
  fi
  # mover dentro da mesma lista (renumeração) não é suportado
  if [[ ${__sds_ot:__sds_on-1:1} == l ]]; then
    if (( __sds_on == 1 )); then
      (( __sds_nn < 1 )) || { sds__fail "$SDS_E_CONFLICT" "reordenar dentro da mesma lista não é suportado por set"; return; }
    else
      local __sds_ppath=${__sds_op%"$sds_LP"*}
      if (( __sds_nn >= __sds_on )) && [[ $__sds_np == "$__sds_ppath$sds_LP"* ]]; then
        sds__fail "$SDS_E_CONFLICT" "reordenar dentro da mesma lista não é suportado por set"
        return
      fi
    fi
  fi
  for ((__sds_i = 0; __sds_i < __sds_nn; __sds_i++)); do
    if (( __sds_i == 0 )); then
      __sds_pref[1]=${__sds_segs[0]}
    else
      __sds_pref[__sds_i+1]=${__sds_pref[__sds_i]}$sds_LP${__sds_segs[__sds_i]}
    fi
  done
  local __sds_types=$__sds_nt __sds_n=$__sds_nn __sds_mode=move __sds_tgt
  local __sds_payload_keep=$__sds_payload
  sds__walk || return
  if [[ -n $__sds_tgt ]]; then
    sds__fail "$SDS_E_CONFLICT" "o destino já existe"
    return
  fi
  __sds_rm=() __sds_add=() __sds_xs=()

  # captura da subárvore (relativa ao caminho atual)
  local -a __sds_crest=() __sds_csfx=() __sds_ccnt=() __sds_cpl=() __sds_cleaf=()
  local __sds_k __sds_sv __sds_sp __sds_dep
  if (( ! __sds_leaf )); then
    for __sds_k in "${!__sds_ix[@]}"; do
      [[ $__sds_k == *"$sds_LT"* ]] || continue
      __sds_dep=${__sds_k%%"$sds_LT"*}
      (( __sds_dep > __sds_on )) || continue
      __sds_sp=${__sds_k#*"$sds_LT"}
      [[ $__sds_sp == "$__sds_op$sds_LP"* ]] || continue
      __sds_sv=${__sds_ix[$__sds_k]}
      __sds_crest+=("${__sds_sp#"$__sds_op"}")
      __sds_csfx+=("${__sds_sv%%,*}")
      if [[ $__sds_sv == *,* ]]; then
        __sds_ccnt+=("${__sds_sv#*,}")
      else
        __sds_ccnt+=(-1)
      fi
      if [[ $__sds_sv != *,* || ${__sds_sv#*,} == 0 ]]; then
        __sds_cleaf+=(1)
        __sds_cpl+=("${__sds_d[${__sds_sv%%,*}$sds_LT$__sds_sp]}")
      else
        __sds_cleaf+=(0)
        __sds_cpl+=("")
      fi
    done
  fi

  # destaca o nó antigo (remove registros, ajusta o pai e a lista)
  sds__delete_node "$__sds_name" ${__sds_osegs[@]+"${__sds_osegs[@]}"} || return

  # reinsere no destino
  __sds_rm=() __sds_add=() __sds_xd=() __sds_xs=()
  sds__walk || return
  local __sds_j __sds_t __sds_rel
  if (( __sds_leaf )); then
    __sds_add[$__sds_nkey]=$__sds_payload_keep
    case $__sds_nlast in
      o | l) __sds_xs[$__sds_nn$sds_LT$__sds_np]=$__sds_nt,0 ;;
      *) __sds_xs[$__sds_nn$sds_LT$__sds_np]=$__sds_nt ;;
    esac
  else
    __sds_xs[$__sds_nn$sds_LT$__sds_np]=$__sds_nt,$__sds_ocnt
    for ((__sds_j = 0; __sds_j < ${#__sds_crest[@]}; __sds_j++)); do
      __sds_t=$__sds_nt${__sds_csfx[__sds_j]:__sds_on+1}
      __sds_sp=$__sds_np${__sds_crest[__sds_j]}
      __sds_rel=${__sds_crest[__sds_j]//[!"$sds_LP"]/}
      if (( __sds_ccnt[__sds_j] >= 0 )); then
        __sds_xs[$((__sds_nn + ${#__sds_rel}))$sds_LT$__sds_sp]=$__sds_t,${__sds_ccnt[__sds_j]}
      else
        __sds_xs[$((__sds_nn + ${#__sds_rel}))$sds_LT$__sds_sp]=$__sds_t
      fi
      if (( __sds_cleaf[__sds_j] )); then
        __sds_add[$__sds_t$sds_LT$__sds_sp]=${__sds_cpl[__sds_j]}
      fi
    done
  fi
  sds__apply
}
