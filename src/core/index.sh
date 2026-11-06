# SDStruct core — índice derivado (cache) dos nós de uma coleção.
#
# O array de dados guarda apenas registros terminais; a chave depende dos
# tipificadores de TODOS os níveis, que uma consulta por caminho não conhece.
# Para que consulta, atribuição e remoção custem O(profundidade) — e não
# O(registros) — mantém-se, por coleção, um índice auxiliar global
# SDS_IX_<NAME> (associative array). Ele é DERIVADO: a única fonte de verdade
# é o array de dados e o índice pode ser descartado e reconstruído a qualquer
# momento. Não altera o formato canônico dos registros.
#
#   chave : PROFUNDIDADE sds_LT CAMINHO        (raiz: "0" sds_LT)
#   valor : TIPIFICADORES            nó terminal escalar (s i f b n u)
#           TIPIFICADORES,N          contêiner (o|l) com N filhos; N=0 indica
#                                    contêiner vazio (registro terminal)
#   M     : nº de registros do array de dados quando o índice foi sincronizado
#   L     : última chave gravada pelo núcleo (verificação de obsolescência)
#
# Obsolescência: se o array de dados foi alterado fora da API, o nº de
# registros (ou a chave L) deixa de bater e o índice é reconstruído com uma
# varredura completa. Alterações externas que preservem o nº de registros e L
# não são detectáveis (limitação documentada).

# sds__ix_corrupt MSG — descarta o índice e falha com SDS_E_CORRUPT.
sds__ix_corrupt() {
  local -n __sds_cx=SDS_IX_$1
  __sds_cx=()
  sds__fail "$SDS_E_CORRUPT" "$2"
}

# sds__ix_rebuild NAME — reconstrói o índice a partir dos registros.
sds__ix_rebuild() {
  local __sds_xn=SDS_IX_$1
  declare -gA "$__sds_xn"
  local -n __sds_rd=$1 __sds_rx=$__sds_xn
  local __sds_k __sds_lv __sds_n __sds_t __sds_pp __sds_id __sds_v __sds_pid __sds_pv
  local -a __sds_pf=()
  local -A __sds_isrec=()
  __sds_rx=()
  for __sds_k in "${!__sds_rd[@]}"; do
    sds__decode_full "$__sds_k" || {
      __sds_n=$?
      __sds_rx=()
      return "$__sds_n"
    }
    __sds_n=$SDS_D_N __sds_t=$SDS_D_TYPES __sds_pp=
    for ((__sds_lv = 0; __sds_lv <= __sds_n; __sds_lv++)); do
      if (( __sds_lv == 1 )); then
        __sds_pp=${SDS_D_SEGS[0]}
      elif (( __sds_lv > 1 )); then
        __sds_pp+=$sds_LP${SDS_D_SEGS[__sds_lv-1]}
      fi
      __sds_pf[__sds_lv]=$__sds_pp
      __sds_id=$__sds_lv$sds_LT$__sds_pp
      __sds_v=${__sds_rx[$__sds_id]-}
      if (( __sds_lv == __sds_n )); then
        if [[ -n $__sds_v ]]; then
          sds__ix_corrupt "$1" "nó com registro duplicado, ou terminal com descendentes"
          return
        fi
        __sds_isrec[$__sds_id]=1
        case ${__sds_t:__sds_lv:1} in
          o | l) __sds_rx[$__sds_id]=$__sds_t,0 ;;
          *) __sds_rx[$__sds_id]=$__sds_t ;;
        esac
      elif [[ -z $__sds_v ]]; then
        __sds_rx[$__sds_id]=${__sds_t:0:__sds_lv+1},0
      elif [[ $__sds_v != "${__sds_t:0:__sds_lv+1},"* || -n ${__sds_isrec[$__sds_id]+x} ]]; then
        sds__ix_corrupt "$1" "tipificação inconsistente em nó compartilhado ou contêiner vazio com descendentes"
        return
      fi
      if [[ -z $__sds_v && $__sds_lv -gt 0 ]]; then
        __sds_pid=$((__sds_lv - 1))$sds_LT${__sds_pf[__sds_lv-1]}
        __sds_pv=${__sds_rx[$__sds_pid]}
        __sds_rx[$__sds_pid]=${__sds_pv%%,*},$(( ${__sds_pv#*,} + 1 ))
      fi
    done
  done
  __sds_rx[M]=${#__sds_rd[@]}
  __sds_rx[L]=${__sds_k-}
}

# sds__ix_sync NAME — garante índice coerente com o array de dados.
sds__ix_sync() {
  local __sds_xn=SDS_IX_$1
  declare -gA "$__sds_xn"
  local -n __sds_sd=$1 __sds_sx=$__sds_xn
  local __sds_last=${__sds_sx[L]-}
  if [[ ${__sds_sx[M]-} == "${#__sds_sd[@]}" ]] &&
    { [[ -z $__sds_last ]] || [[ -n ${__sds_sd[$__sds_last]+x} ]]; }; then
    return 0
  fi
  sds__ix_rebuild "$1"
}

# sds__walk — percorre os ancestrais do caminho-alvo e monta o PLANO de
# criação dos níveis ausentes. Não altera nenhum armazenamento.
# Entradas (variáveis do chamador, escopo dinâmico): __sds_ix (índice),
#   __sds_types, __sds_segs[], __sds_n, __sds_pref[] (prefixos do caminho),
#   __sds_payload, __sds_mode (leaf|move).
# Saídas: __sds_tgt (valor de índice do nó-alvo se já existir, senão vazio);
#   planos __sds_rm[] (chaves a remover), __sds_add[] (chave→payload),
#   __sds_xs[] (nó de índice→valor).
# Regras: ancestral contêiner existente deve ter o mesmo tipo (nunca é
# retipado); ancestral u/n é promovido; contêiner vazio é consumido; ancestral
# escalar é erro. Índice de lista acima do fim preenche com u (sds_MAX_FILL).
sds__walk() {
  local __sds_wl __sds_wid __sds_wv __sds_wet __sds_wch __sds_wc __sds_wpc=0
  local __sds_wl0=-1 __sds_wj __sds_wi __sds_wbase __sds_wnc __sds_widx __sds_wfp
  local __sds_wfill=0 __sds_wpt
  __sds_tgt=
  for ((__sds_wl = 0; __sds_wl <= __sds_n; __sds_wl++)); do
    __sds_wid=$__sds_wl$sds_LT${__sds_pref[__sds_wl]}
    __sds_wv=${__sds_ix[$__sds_wid]-}
    if [[ -z $__sds_wv ]]; then
      __sds_wl0=$__sds_wl
      break
    fi
    if (( __sds_wl == __sds_n )); then
      __sds_tgt=$__sds_wv
      return 0
    fi
    __sds_wet=${__sds_wv%%,*}
    __sds_wch=${__sds_wet: -1}
    case $__sds_wch in
      o | l)
        if [[ $__sds_wch != "${__sds_types:__sds_wl:1}" ]]; then
          sds__fail "$SDS_E_TYPE" "tipificação inconsistente no nível $__sds_wl (existente '$__sds_wch', solicitado '${__sds_types:__sds_wl:1}'); tipos intermediários não são alterados"
          return
        fi
        __sds_wc=${__sds_wv#*,}
        if (( __sds_wc == 0 )); then
          __sds_rm+=("$__sds_wet$sds_LT${__sds_pref[__sds_wl]}")
        fi
        __sds_wpc=$__sds_wc
        ;;
      u | n)
        __sds_rm+=("$__sds_wv$sds_LT${__sds_pref[__sds_wl]}")
        __sds_wpc=0
        ;;
      *)
        sds__fail "$SDS_E_TYPE" "ancestral escalar ('$__sds_wch') no nível $__sds_wl não pode ter descendentes"
        return
        ;;
    esac
  done

  __sds_wj=0
  (( __sds_wl0 > 0 )) && __sds_wj=$((__sds_wl0 - 1))
  for (( ; __sds_wj < __sds_n; __sds_wj++)); do
    __sds_wbase=0
    (( __sds_wj == __sds_wl0 - 1 )) && __sds_wbase=$__sds_wpc
    __sds_wpt=${__sds_types:0:__sds_wj+1}
    if [[ ${__sds_types:__sds_wj:1} == l ]]; then
      __sds_widx=${__sds_segs[__sds_wj]}
      if (( __sds_widx < __sds_wbase )); then
        sds__fail "$SDS_E_CORRUPT" "lista inconsistente: índice $__sds_widx ausente com $__sds_wbase elementos"
        return
      fi
      (( __sds_wfill += __sds_widx - __sds_wbase ))
      if (( __sds_wfill > sds_MAX_FILL )); then
        sds__fail "$SDS_E_LIMIT" "preenchimento de lista excede sds_MAX_FILL ($sds_MAX_FILL)"
        return
      fi
      for ((__sds_wi = __sds_wbase; __sds_wi < __sds_widx; __sds_wi++)); do
        if (( __sds_wj == 0 )); then __sds_wfp=$__sds_wi; else __sds_wfp=${__sds_pref[__sds_wj]}$sds_LP$__sds_wi; fi
        __sds_add[${__sds_wpt}u$sds_LT$__sds_wfp]=
        __sds_xs[$((__sds_wj + 1))$sds_LT$__sds_wfp]=${__sds_wpt}u
      done
      __sds_wnc=$((__sds_widx + 1))
    else
      __sds_wnc=$((__sds_wbase + 1))
    fi
    __sds_xs[$__sds_wj$sds_LT${__sds_pref[__sds_wj]}]=$__sds_wpt,$__sds_wnc
  done
  if [[ $__sds_mode == leaf ]]; then
    __sds_add[$__sds_types$sds_LT${__sds_pref[__sds_n]}]=$__sds_payload
    case ${__sds_types:__sds_n:1} in
      o | l) __sds_xs[$__sds_n$sds_LT${__sds_pref[__sds_n]}]=$__sds_types,0 ;;
      *) __sds_xs[$__sds_n$sds_LT${__sds_pref[__sds_n]}]=$__sds_types ;;
    esac
  fi
  return 0
}

# sds__apply — executa um plano já validado, tocando só os registros
# afetados. Entradas (escopo dinâmico): __sds_d, __sds_ix, __sds_rm[],
# __sds_add[], __sds_xd[] (nós de índice a remover), __sds_xs[] (nós a gravar),
# __sds_name. Remoções vêm antes das gravações (uma chave pode ser removida e
# regravada). `unset` por chave é verificado; se falhar (ex.: assoc_expand_once
# ou chave especial em versão antiga do Bash), recorre à reconstrução.
sds__apply() {
  local __sds_ak __sds_lastk= __sds_bad=0 __sds_badx=0
  for __sds_ak in ${__sds_rm[@]+"${__sds_rm[@]}"}; do
    unset -v '__sds_d[$__sds_ak]' 2>/dev/null
    [[ -z ${__sds_d[$__sds_ak]+x} ]] || __sds_bad=1
  done
  if (( __sds_bad )); then
    sds__apply_rebuild_data "$__sds_name" __sds_rm
  fi
  for __sds_ak in "${!__sds_add[@]}"; do
    __sds_d[$__sds_ak]=${__sds_add[$__sds_ak]}
    __sds_lastk=$__sds_ak
  done
  for __sds_ak in ${__sds_xd[@]+"${__sds_xd[@]}"}; do
    unset -v '__sds_ix[$__sds_ak]' 2>/dev/null
    [[ -z ${__sds_ix[$__sds_ak]+x} ]] || __sds_badx=1
  done
  for __sds_ak in "${!__sds_xs[@]}"; do
    __sds_ix[$__sds_ak]=${__sds_xs[$__sds_ak]}
  done
  if (( __sds_badx )); then
    sds__ix_rebuild "$__sds_name"
    return
  fi
  __sds_ix[M]=${#__sds_d[@]}
  if [[ -n $__sds_lastk ]]; then
    __sds_ix[L]=$__sds_lastk
  elif [[ -n ${__sds_ix[L]-} && -z ${__sds_d[${__sds_ix[L]}]+x} ]]; then
    __sds_ix[L]=
  fi
}

# Plano B de remoção quando `unset` por chave não funciona (caminho raro).
sds__apply_rebuild_data() {
  local -n __sds_bd=$1 __sds_br=$2
  local -A __sds_bkeep=() __sds_bdrop=()
  local __sds_bk
  for __sds_bk in "${__sds_br[@]}"; do __sds_bdrop[$__sds_bk]=1; done
  for __sds_bk in "${!__sds_bd[@]}"; do
    [[ -n ${__sds_bdrop[$__sds_bk]+x} ]] || __sds_bkeep[$__sds_bk]=${__sds_bd[$__sds_bk]}
  done
  __sds_bd=()
  for __sds_bk in "${!__sds_bkeep[@]}"; do __sds_bd[$__sds_bk]=${__sds_bkeep[$__sds_bk]}; done
}
