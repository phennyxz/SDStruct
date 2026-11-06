# SDStruct core — operações de armazenamento sobre um associative array.
# Funções públicas do núcleo (nomes provisórios, prefixo sds_core_):
#   sds_core_init_data NAME
#   sds_core_assign NAME TYPES PAYLOAD [SEGMENT...]   atribuição ordinária
#   sds_core_set NAME OLDKEY NEWKEY                   operação estrutural (set.sh)
#   sds_core_get NAME OUTVAR [SEGMENT...]
#   sds_core_type NAME OUTVAR [SEGMENT...]
#   sds_core_exists | sds_core_delete NAME [SEGMENT...]
#   sds_core_is_object | sds_core_is_list | sds_core_is_terminal NAME [SEGMENT...]
# Toda operação valida e monta um plano ANTES de alterar; o plano só toca os
# registros afetados (sem reconstruir o array). Veja index.sh.

# sds_core_init_data NAME — cria (ou esvazia) um associative array global.
sds__impl_core_init_data() {
  local LC_ALL=C
  if (( $# != 1 )); then
    sds__fail "$SDS_E_USAGE" "sds_core_init_data: uso: NAME"
    return
  fi
  sds_check_delims || return
  sds__check_name "$1" || return
  if declare -p "$1" >/dev/null 2>&1 && ! sds__is_assoc "$1"; then
    sds__fail "$SDS_E_USAGE" "'$1' já existe e não é um associative array"
    return
  fi
  declare -gA "$1" "SDS_IX_$1"
  local -n __sds_id=$1 __sds_ii=SDS_IX_$1
  __sds_id=()
  __sds_ii=()
}

# sds_core_assign NAME TYPES PAYLOAD [SEGMENT...]
# Atribuição ordinária. TYPES tem um tipificador por nível (raiz e terminal
# incluídos), logo os tipos dos contêineres intermediários nunca são inferidos.
#  - registro exato existente (mesma tipificação): só o payload é atualizado;
#  - caminho ausente, total ou parcialmente: criam-se apenas os níveis que
#    faltam (índice de lista acima do fim preenche com 'u', sds_MAX_FILL);
#  - terminal existente 'u' ou 'n': recebe o novo tipo e payload;
#  - outro tipo significativo existente: SDS_E_TYPE (use sds_core_set);
#    se houver descendentes: SDS_E_CONFLICT;
#  - contêiner existente do mesmo tipo (payload vazio): nada a fazer;
#  - ancestral 'u'/'n' é promovido a contêiner; contêiner vazio é consumido;
#    ancestral escalar ou de outro tipo: SDS_E_TYPE (nunca retipa ancestrais).
sds__impl_core_assign() {
  local LC_ALL=C
  if (( $# < 3 )); then
    sds__fail "$SDS_E_USAGE" "sds_core_assign: uso: NAME TYPES PAYLOAD [SEGMENT...]"
    return
  fi
  local __sds_name=$1 __sds_types=$2 __sds_payload=$3
  shift 3
  local -a __sds_segs=("$@") __sds_pref=("")
  local __sds_n=${#__sds_segs[@]} __sds_i __sds_key
  sds__check_ready "$__sds_name" || return
  sds__check_types "$__sds_types" "$__sds_n" || return
  sds__check_segments "$__sds_types" "$@" || return
  sds__check_payload "${__sds_types:__sds_n:1}" "$__sds_payload" || return

  local -n __sds_d=$__sds_name
  for ((__sds_i = 0; __sds_i < __sds_n; __sds_i++)); do
    if (( __sds_i == 0 )); then
      __sds_pref[1]=${__sds_segs[0]}
    else
      __sds_pref[__sds_i+1]=${__sds_pref[__sds_i]}$sds_LP${__sds_segs[__sds_i]}
    fi
  done
  __sds_key=$__sds_types$sds_LT${__sds_pref[__sds_n]}
  # Caminho comum: o registro já existe com a mesma tipificação.
  if [[ -n ${__sds_d[$__sds_key]+x} ]]; then
    __sds_d[$__sds_key]=$__sds_payload
    return 0
  fi

  sds__ix_sync "$__sds_name" || return
  local -n __sds_ix=SDS_IX_$__sds_name
  local -a __sds_rm=() __sds_xd=()
  local -A __sds_add=() __sds_xs=()
  local __sds_tgt __sds_mode=leaf __sds_et __sds_cnt
  sds__walk || return
  if [[ -n $__sds_tgt ]]; then
    __sds_rm=() __sds_add=() __sds_xs=()
    __sds_et=${__sds_tgt%%,*}
    __sds_cnt=-1
    [[ $__sds_tgt == *,* ]] && __sds_cnt=${__sds_tgt#*,}
    if [[ $__sds_et == "$__sds_types" ]]; then
      (( __sds_cnt > 0 )) || __sds_d[$__sds_key]=$__sds_payload
      return 0
    fi
    case ${__sds_et: -1} in
      u | n)
        __sds_rm=("$__sds_et$sds_LT${__sds_pref[__sds_n]}")
        __sds_add[$__sds_key]=$__sds_payload
        case ${__sds_types:__sds_n:1} in
          o | l) __sds_xs[$__sds_n$sds_LT${__sds_pref[__sds_n]}]=$__sds_types,0 ;;
          *) __sds_xs[$__sds_n$sds_LT${__sds_pref[__sds_n]}]=$__sds_types ;;
        esac
        ;;
      *)
        if (( __sds_cnt > 0 )); then
          sds__fail "$SDS_E_CONFLICT" "o caminho é um contêiner com descendentes; assinalar outro tipo exigiria descartá-los (use sds_core_delete)"
        else
          sds__fail "$SDS_E_TYPE" "o caminho já existe com outro tipo ('${__sds_et: -1}'); a atribuição não muda tipo de valor significativo (use sds_core_set)"
        fi
        return
        ;;
    esac
  fi
  sds__apply
}

# sds__find NAME [SEGMENT...] — localiza o nó pelo índice (O(profundidade)).
# Define SDS_F_STATE (none|terminal|container), SDS_F_TYPE e SDS_F_KEY (chave
# do registro terminal). Contêiner vazio é terminal do tipo o/l.
sds__find() {
  local __sds_name=$1
  shift
  sds__ix_sync "$__sds_name" || return
  local -n __sds_fx=SDS_IX_$__sds_name
  local __sds_np=$# __sds_P __sds_v __sds_t
  sds__join __sds_P "$@"
  SDS_F_STATE=none SDS_F_TYPE= SDS_F_KEY=
  __sds_v=${__sds_fx[$__sds_np$sds_LT$__sds_P]-}
  [[ -n $__sds_v ]] || return 0
  __sds_t=${__sds_v%%,*}
  SDS_F_TYPE=${__sds_t: -1}
  if [[ $__sds_v == *,* && ${__sds_v#*,} != 0 ]]; then
    SDS_F_STATE=container
  else
    SDS_F_STATE=terminal
    SDS_F_KEY=$__sds_t$sds_LT$__sds_P
  fi
  return 0
}

# Prólogo comum das consultas: sds__query NAME [SEGMENT...]
sds__query() {
  sds__check_ready "$1" || return
  local __sds_name=$1
  shift
  sds__check_seg_bytes "$@" || return
  sds__find "$__sds_name" "$@"
}

# sds_core_get NAME OUTVAR [SEGMENT...] — payload do nó terminal em OUTVAR.
sds__impl_core_get() {
  local LC_ALL=C
  if (( $# < 2 )); then
    sds__fail "$SDS_E_USAGE" "sds_core_get: uso: NAME OUTVAR [SEGMENT...]"
    return
  fi
  local __sds_name=$1 __sds_out=$2
  shift 2
  sds__check_name "$__sds_out" || return
  sds__query "$__sds_name" "$@" || return
  case $SDS_F_STATE in
    none) sds__fail "$SDS_E_NOTFOUND" "caminho inexistente"; return ;;
    container) sds__fail "$SDS_E_NOTTERMINAL" "o caminho é um contêiner não vazio"; return ;;
  esac
  local -n __sds_gd=$__sds_name __sds_go=$__sds_out
  __sds_go=${__sds_gd[$SDS_F_KEY]}
}

# sds_core_type NAME OUTVAR [SEGMENT...] — tipificador do nó em OUTVAR.
sds__impl_core_type() {
  local LC_ALL=C
  if (( $# < 2 )); then
    sds__fail "$SDS_E_USAGE" "sds_core_type: uso: NAME OUTVAR [SEGMENT...]"
    return
  fi
  local __sds_name=$1 __sds_out=$2
  shift 2
  sds__check_name "$__sds_out" || return
  sds__query "$__sds_name" "$@" || return
  if [[ $SDS_F_STATE == none ]]; then
    sds__fail "$SDS_E_NOTFOUND" "caminho inexistente"
    return
  fi
  local -n __sds_to=$__sds_out
  __sds_to=$SDS_F_TYPE
}

# sds_core_exists NAME [SEGMENT...] — 0 se o caminho existe (inclusive com
# valor undefined); 1 se ausente.
sds__impl_core_exists() {
  local LC_ALL=C
  if (( $# < 1 )); then
    sds__fail "$SDS_E_USAGE" "sds_core_exists: uso: NAME [SEGMENT...]"
    return
  fi
  sds__query "$@" || return
  [[ $SDS_F_STATE != none ]] || return "$SDS_E_NOTFOUND"
}

# Predicados: 0 = verdadeiro; 1 = falso ou ausente (use sds_core_exists para
# distinguir). Erros reais retornam outros códigos.
# is_terminal: valor escalar (i f s b n u); contêineres vazios são object/list.
sds__predicate() {
  local __sds_pat=$1
  shift
  sds__query "$@" || return
  [[ $SDS_F_STATE != none && $SDS_F_TYPE == $__sds_pat ]] || return "$SDS_E_NOTFOUND"
}

sds__impl_core_is_object() {
  local LC_ALL=C
  (( $# >= 1 )) || { sds__fail "$SDS_E_USAGE" "uso: NAME [SEGMENT...]"; return; }
  sds__predicate o "$@"
}

sds__impl_core_is_list() {
  local LC_ALL=C
  (( $# >= 1 )) || { sds__fail "$SDS_E_USAGE" "uso: NAME [SEGMENT...]"; return; }
  sds__predicate l "$@"
}

sds__impl_core_is_terminal() {
  local LC_ALL=C
  (( $# >= 1 )) || { sds__fail "$SDS_E_USAGE" "uso: NAME [SEGMENT...]"; return; }
  sds__predicate '[sifbnu]' "$@"
}

# sds_core_delete NAME [SEGMENT...] — remove o nó e sua subárvore.
#  - lista: os elementos seguintes (e seus descendentes) avançam uma posição;
#    só essa lista é tocada;
#  - objeto: demais propriedades não se movem;
#  - se o contêiner pai ficar sem filhos, vira contêiner vazio (registro
#    terminal), preservando sua existência;
#  - sem segmentos: remove a raiz (esvazia a estrutura).
sds__impl_core_delete() {
  local LC_ALL=C
  if (( $# < 1 )); then
    sds__fail "$SDS_E_USAGE" "sds_core_delete: uso: NAME [SEGMENT...]"
    return
  fi
  local __sds_name=$1
  shift
  sds__check_ready "$__sds_name" || return
  sds__check_seg_bytes "$@" || return
  sds__delete_node "$__sds_name" "$@"
}

# sds__delete_node NAME [SEGMENT...] — corpo de delete (argumentos já
# validados); também usado por sds_core_set ao destacar um nó.
sds__delete_node() {
  local __sds_name=$1
  shift
  local -a __sds_segs=("$@") __sds_pref=("")
  local __sds_np=${#__sds_segs[@]} __sds_i
  sds__ix_sync "$__sds_name" || return
  local -n __sds_d=$__sds_name __sds_ix=SDS_IX_$__sds_name

  if (( __sds_np == 0 )); then
    if (( ${#__sds_d[@]} == 0 )); then
      sds__fail "$SDS_E_NOTFOUND" "estrutura vazia"
      return
    fi
    __sds_d=()
    __sds_ix=()
    __sds_ix[M]=0
    return 0
  fi
  for ((__sds_i = 0; __sds_i < __sds_np; __sds_i++)); do
    if (( __sds_i == 0 )); then
      __sds_pref[1]=${__sds_segs[0]}
    else
      __sds_pref[__sds_i+1]=${__sds_pref[__sds_i]}$sds_LP${__sds_segs[__sds_i]}
    fi
  done
  local __sds_id=$__sds_np$sds_LT${__sds_pref[__sds_np]}
  local __sds_xv=${__sds_ix[$__sds_id]-}
  if [[ -z $__sds_xv ]]; then
    sds__fail "$SDS_E_NOTFOUND" "caminho inexistente"
    return
  fi

  local -a __sds_rm=() __sds_xd=()
  local -A __sds_add=() __sds_xs=()
  local __sds_k __sds_sv __sds_sp __sds_dep
  __sds_xd+=("$__sds_id")
  if [[ $__sds_xv != *,* || ${__sds_xv#*,} == 0 ]]; then
    __sds_rm+=("${__sds_xv%%,*}$sds_LT${__sds_pref[__sds_np]}")
  else
    # Subárvore: varre o índice (nós, não registros) filtrando pelo prefixo.
    for __sds_k in "${!__sds_ix[@]}"; do
      [[ $__sds_k == *"$sds_LT"* ]] || continue
      __sds_dep=${__sds_k%%"$sds_LT"*}
      (( __sds_dep > __sds_np )) || continue
      __sds_sp=${__sds_k#*"$sds_LT"}
      [[ $__sds_sp == "${__sds_pref[__sds_np]}$sds_LP"* ]] || continue
      __sds_sv=${__sds_ix[$__sds_k]}
      __sds_xd+=("$__sds_k")
      if [[ $__sds_sv != *,* || ${__sds_sv#*,} == 0 ]]; then
        __sds_rm+=("${__sds_sv%%,*}$sds_LT$__sds_sp")
      fi
    done
  fi

  local __sds_ppath=${__sds_pref[__sds_np-1]}
  local __sds_pid=$((__sds_np - 1))$sds_LT$__sds_ppath
  local __sds_pv=${__sds_ix[$__sds_pid]-}
  if [[ $__sds_pv != *,* ]]; then
    sds__ix_corrupt "$__sds_name" "nó pai ausente no índice"
    return
  fi
  local __sds_ptypes=${__sds_pv%%,*} __sds_pc=${__sds_pv#*,}
  local __sds_idx=${__sds_segs[__sds_np-1]}
  if [[ ${__sds_ptypes: -1} == l ]]; then
    sds__shift_list_plan || return
  fi
  if (( __sds_pc - 1 == 0 )); then
    __sds_add[$__sds_ptypes$sds_LT$__sds_ppath]=
    __sds_xs[$__sds_pid]=$__sds_ptypes,0
  else
    __sds_xs[$__sds_pid]=$__sds_ptypes,$((__sds_pc - 1))
  fi
  sds__apply
}

# sds__shift_list_plan — acrescenta ao plano o avanço dos irmãos posteriores
# de __sds_idx na lista pai (e de seus descendentes). Só toca essa lista.
# Usa as variáveis de sds__impl_core_delete (escopo dinâmico).
sds__shift_list_plan() {
  local __sds_j __sds_sid __sds_spath __sds_scont=0 __sds_r __sds_rest __sds_newp
  local __sds_sk __sds_sdep __sds_pfx
  local -a __sds_ids=()
  if (( __sds_np == 1 )); then __sds_pfx=; else __sds_pfx=$__sds_ppath$sds_LP; fi
  for ((__sds_j = __sds_idx + 1; __sds_j < __sds_pc; __sds_j++)); do
    __sds_spath=$__sds_pfx$__sds_j
    __sds_sid=$__sds_np$sds_LT$__sds_spath
    __sds_sv=${__sds_ix[$__sds_sid]-}
    if [[ -z $__sds_sv ]]; then
      sds__ix_corrupt "$__sds_name" "lista não contígua"
      return
    fi
    if [[ $__sds_sv == *,* && ${__sds_sv#*,} != 0 ]]; then __sds_scont=1; fi
    __sds_ids+=("$__sds_sid")
  done
  if (( __sds_scont )); then
    __sds_ids=()
    for __sds_sk in "${!__sds_ix[@]}"; do
      [[ $__sds_sk == *"$sds_LT"* ]] || continue
      __sds_sdep=${__sds_sk%%"$sds_LT"*}
      (( __sds_sdep >= __sds_np )) || continue
      __sds_spath=${__sds_sk#*"$sds_LT"}
      if (( __sds_np > 1 )); then
        [[ $__sds_spath == "$__sds_pfx"* ]] || continue
      fi
      __sds_r=${__sds_spath#"$__sds_pfx"}
      __sds_j=${__sds_r%%"$sds_LP"*}
      (( __sds_j > __sds_idx )) || continue
      __sds_ids+=("$__sds_sk")
    done
  fi
  for __sds_sid in ${__sds_ids[@]+"${__sds_ids[@]}"}; do
    __sds_sdep=${__sds_sid%%"$sds_LT"*}
    __sds_spath=${__sds_sid#*"$sds_LT"}
    __sds_r=${__sds_spath#"$__sds_pfx"}
    __sds_j=${__sds_r%%"$sds_LP"*}
    __sds_rest=${__sds_r#"$__sds_j"}
    __sds_newp=$__sds_pfx$((__sds_j - 1))$__sds_rest
    __sds_sv=${__sds_ix[$__sds_sid]}
    __sds_xd+=("$__sds_sid")
    __sds_xs[$__sds_sdep$sds_LT$__sds_newp]=$__sds_sv
    if [[ $__sds_sv != *,* || ${__sds_sv#*,} == 0 ]]; then
      __sds_rm+=("${__sds_sv%%,*}$sds_LT$__sds_spath")
      __sds_add[${__sds_sv%%,*}$sds_LT$__sds_newp]=${__sds_d[${__sds_sv%%,*}$sds_LT$__sds_spath]}
    fi
  done
  return 0
}
