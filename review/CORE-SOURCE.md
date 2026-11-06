# Código-fonte completo do núcleo e dos testes

Conteúdo integral, gerado por script a partir dos arquivos do repositório.

## `review/example.sh`

````bash
#!/usr/bin/env bash
# Exemplos executáveis do núcleo SDStruct: bash review/example.sh
here=${BASH_SOURCE[0]}
if [[ $here == */* ]]; then here=${here%/*}; else here=.; fi
# shellcheck source=/dev/null
source "$here/../src/sdstruct.sh" || exit 2

show() { # mostra as chaves de forma legível (LT -> '|', LP -> '/') e o payload
  local -n _d=$1
  local k line
  for k in "${!_d[@]}"; do
    line=${k//"$sds_LT"/|}
    line=${line//"$sds_LP"/\/}
    printf '  %s = [%s]\n' "$line" "${_d[$k]}"
  done | LC_ALL=C sort
}

sds_init && echo "init ok (Bash $BASH_VERSION)"
sds_core_init_data data

echo "# 1. inserção tipada (um tipificador por nível, incluindo a raiz)"
sds_core_assign data oooli 80 servidores web1 portas 0
sds_core_assign data oooli 443 servidores web1 portas 1
sds_core_assign data ooos ativo servidores web2 estado
show data

echo "# 2. consulta"
sds_core_get data v servidores web1 portas 1 && echo "get portas/1 = $v"
sds_core_type data t servidores web1 portas && echo "type portas = $t"
sds_core_exists data servidores web9; echo "exists web9 -> rc=$?"
sds_core_get data v servidores web1; echo "get web1 (contêiner) -> rc=$?"

echo "# 3. undefined / null / string vazia / contêineres vazios"
declare -A est=()
sds_core_assign est ou '' u
sds_core_assign est on '' n
sds_core_assign est os '' s
sds_core_assign est oo '' o
sds_core_assign est ol '' l
show est

echo "# 4. preenchimento intermediário de lista"
declare -A lst=()
sds_core_assign lst ls fim 3
show lst

echo "# 5. u/n substituídos e promovidos"
sds_core_assign est oi 7 u        # u -> i
sds_core_assign est oos x n a     # n -> objeto com propriedade
show est

echo "# 6. remoção de elemento de lista desloca os seguintes"
declare -A l2=()
for i in 0 1 2 3; do sds_core_assign l2 ls "v$i" "$i"; done
sds_core_delete l2 1
for i in 0 1 2 3; do
  if sds_core_get l2 v "$i" 2>/dev/null; then echo "  [$i]=$v"; else echo "  [$i] ausente"; fi
done

echo "# 7. remoção de propriedade de objeto não desloca nada"
declare -A ob=()
sds_core_assign ob os 1 a; sds_core_assign ob os 2 b; sds_core_assign ob os 3 c
sds_core_delete ob b
show ob

echo "# 8. atribuir escalar sobre contêiner com descendentes é recusado (mudança de tipo só por set)"
sds_core_assign data os texto servidores; echo "rc=$?"

echo "# 9. byte reservado em segmento é recusado (escaping não aprovado)"
sds_core_assign data os x $'a\xfeb'; echo "rc=$?"

echo "# 10. payload com 0xFE/0xFF é aceito (campo separado)"
sds_core_assign data os $'\xfe\xff' bin && sds_core_get data v bin && printf '%s' "$v" | od -An -tx1

mk() { local o; sds_core_make_key o "$@" && printf '%s' "$o"; }

echo "# 11. atribuição cria vários níveis ausentes sem tocar nos demais registros"
declare -A srv=()
sds_core_assign srv ooos web1 servidor web1 nome
sds_core_assign srv oooli 80 servidor web1 porta 0
sds_core_assign srv oooli 443 servidor web1 porta 1
sds_core_assign srv oools admin servidor web1 user 0
show srv

echo "# 12. atribuição de mesmo tipo muda só o payload"
sds_core_assign srv oooli 8080 servidor web1 porta 0
show srv

echo "# 13. set: renomear escalar"
sds_core_set srv "$(mk ooos servidor web1 nome)" "$(mk ooos servidor web1 identificacao)"; echo "rc=$?"

echo "# 14. set: renomear e mudar o tipo terminal (porta/0 i -> servico/porta s); porta/1 desloca"
sds_core_set srv "$(mk oooli servidor web1 porta 0)" "$(mk oooos servidor web1 servico porta)"; echo "rc=$?"
show srv

echo "# 15. set: renomear contêiner preserva os descendentes"
sds_core_set srv "$(mk ooo servidor web1)" "$(mk ooo servidor web3)"; echo "rc=$?"
show srv

echo "# 16. set recusado: colisão, tipo de contêiner com descendentes, tipo intermediário, ausente"
sds_core_set srv "$(mk ooo servidor web3)" "$(mk oos servidor web3)"; echo "contêiner->s rc=$?"
sds_core_set srv "$(mk ooos servidor web3 identificacao)" "$(mk oooos servidor web3 servico porta)"; echo "colisão rc=$?"
sds_core_set srv "$(mk ooos servidor web3 identificacao)" "$(mk ools servidor web3 0)"; echo "intermediário (web3 objeto -> lista) rc=$?"
sds_core_set srv "$(mk ooos servidor web3 nada)" "$(mk ooos servidor web3 outro)"; echo "caminho atual ausente rc=$?"
show srv
````

## `src/core/api.sh`

````bash
# SDStruct core — API pública (nomes PROVISÓRIOS; ver docs/CORE.md).
# Cada função pública é um invólucro sobre sds__impl_*: o invólucro desliga
# `shopt nocasematch` durante a operação (ele tornaria case-insensitive as
# comparações de segmentos e de payloads) e o restaura ao final.

sds__guard() {
  local __sds_ncm=0 __sds_rc
  local __sds_aeo=0
  if shopt -q nocasematch; then
    __sds_ncm=1
    shopt -u nocasematch
  fi
  # assoc_expand_once (Bash 5.x) quebraria `unset -v 'a[$k]'` em chaves arbitrárias
  if shopt -q assoc_expand_once 2>/dev/null; then
    __sds_aeo=1
    shopt -u assoc_expand_once
  fi
  "$@"
  __sds_rc=$?
  if (( __sds_ncm )); then shopt -s nocasematch; fi
  if (( __sds_aeo )); then shopt -s assoc_expand_once; fi
  return "$__sds_rc"
}

sds_check_delims() { sds__guard sds__impl_check_delims "$@"; }
sds_core_assign() { sds__guard sds__impl_core_assign "$@"; }
sds_core_decode_key() { sds__guard sds__impl_core_decode_key "$@"; }
sds_core_delete() { sds__guard sds__impl_core_delete "$@"; }
sds_core_exists() { sds__guard sds__impl_core_exists "$@"; }
sds_core_get() { sds__guard sds__impl_core_get "$@"; }
sds_core_init_data() { sds__guard sds__impl_core_init_data "$@"; }
sds_core_is_list() { sds__guard sds__impl_core_is_list "$@"; }
sds_core_is_object() { sds__guard sds__impl_core_is_object "$@"; }
sds_core_is_terminal() { sds__guard sds__impl_core_is_terminal "$@"; }
sds_core_make_key() { sds__guard sds__impl_core_make_key "$@"; }
sds_core_set() { sds__guard sds__impl_core_set "$@"; }
sds_core_type() { sds__guard sds__impl_core_type "$@"; }
sds_core_validate() { sds__guard sds__impl_core_validate "$@"; }
sds_init() { sds__guard sds__impl_init "$@"; }
````

## `src/core/delims.sh`

````bash
# SDStruct core — delimitadores globais e verificação do ambiente.

# Padrões documentados em docs/CANONICAL-FORMAT.md. Só definidos se ainda não
# existirem, de forma análoga ao IFS.
[[ -v sds_LT ]] || sds_LT=$'\xff'   # separa tipificadores do caminho
[[ -v sds_LP ]] || sds_LP=$'\xfe'   # separa segmentos do caminho

# Limite PROVISÓRIO de posições "undefined" criadas por um único preenchimento
# de lista (proteção contra exaustão de memória). Os limites oficiais ainda
# não foram especificados.
[[ -v sds_MAX_FILL ]] || sds_MAX_FILL=100000

# sds_check_delims — valida sds_LT, sds_LP e sds_MAX_FILL.
sds__impl_check_delims() {
  local LC_ALL=C
  if [[ ! -v sds_LT || ! -v sds_LP ]]; then
    sds__fail "$SDS_E_ENV" "sds_LT/sds_LP não definidos"
    return
  fi
  if (( ${#sds_LT} != 1 || ${#sds_LP} != 1 )); then
    sds__fail "$SDS_E_ENV" "sds_LT e sds_LP devem conter exatamente um byte"
    return
  fi
  if [[ $sds_LT == "$sds_LP" ]]; then
    sds__fail "$SDS_E_ENV" "sds_LT e sds_LP devem ser distintos"
    return
  fi
  if [[ $sds_LT == [olsifbnu] || $sds_LP == [olsifbnu] ]]; then
    sds__fail "$SDS_E_ENV" "delimitadores não podem coincidir com tipificadores"
    return
  fi
  if [[ ! $sds_MAX_FILL =~ ^[0-9]+$ ]]; then
    sds__fail "$SDS_E_ENV" "sds_MAX_FILL deve ser um inteiro não negativo"
    return
  fi
  return 0
}

# sds_init — verifica a versão do Bash e os delimitadores.
sds__impl_init() {
  if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    sds__fail "$SDS_E_ENV" "Bash 4.3 ou superior é necessário (atual: $BASH_VERSION)"
    return
  fi
  sds_check_delims
}
````

## `src/core/errors.sh`

````bash
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
````

## `src/core/index.sh`

````bash
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
````

## `src/core/key.sh`

````bash
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
````

## `src/core/set.sh`

````bash
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
````

## `src/core/store.sh`

````bash
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
````

## `src/core/types.sh`

````bash
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
````

## `src/core/validate.sh`

````bash
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
````

## `src/sdstruct.sh`

````bash
# SDStruct — carregador do núcleo (Bash 4.3+).
# Uso: source src/sdstruct.sh

if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
  printf 'sds: Bash 4.3 ou superior é necessário (atual: %s)\n' "$BASH_VERSION" >&2
  return 9 2>/dev/null || exit 9
fi

__sds_dir=${BASH_SOURCE[0]%/*}
[[ $__sds_dir == "${BASH_SOURCE[0]}" ]] && __sds_dir=.

# Ordem = dependências: errors <- delims <- types <- key <- index <- store <- set <- validate <- api
for __sds_mod in errors delims types key index store set validate api; do
  # shellcheck source=/dev/null
  source "$__sds_dir/core/$__sds_mod.sh" || return
done
unset __sds_dir __sds_mod
````

## `tests/bench.sh`

````bash
#!/usr/bin/env bash
# Benchmark do núcleo: bash tests/bench.sh
# Metodologia: cada item usa um armazenamento novo e é cronometrado com
# $EPOCHREALTIME (tempo de parede) em uma única execução; o custo por operação
# é derivado. Não há metas de velocidade; os números dependem da máquina.
set -u
here=${BASH_SOURCE[0]}
if [[ $here == */* ]]; then here=${here%/*}; else here=.; fi
# shellcheck source=/dev/null
source "$here/../src/sdstruct.sh" || exit 2

now() { local t=${EPOCHREALTIME/[.,]/}; printf '%s' "$t"; }
report() { # TÍTULO INÍCIO FIM OPS
  local us=$(($3 - $2))
  printf '%-58s %7d ms %8d us/op (%d ops)\n' "$1" $((us / 1000)) $((us / $4)) "$4"
}
fill() { # NAME N — N escalares na raiz objeto
  local i
  for ((i = 0; i < $2; i++)); do sds_core_assign "$1" os "v$i" "k$i" || exit 1; done
}
K() { local o; sds_core_make_key o "$@" && printf '%s' "$o"; }

printf 'Bash %s | %s | LC_ALL=%s\n' "$BASH_VERSION" "$(uname -sr)" "${LC_ALL-<não definido>}"
sds_init || exit 2

for n in 100 500 1000 5000; do
  sds_core_init_data d
  a=$(now); fill d "$n"; b=$(now)
  report "1. inserir $n caminhos novos (1 nível)" "$a" "$b" "$n"
done

sds_core_init_data d; fill d 1000
a=$(now)
for ((i = 0; i < 1000; i++)); do sds_core_assign d os "novo$i" "k$i" || exit 1; done
b=$(now)
report "2. atualizar 1000 payloads existentes (loja de 1000)" "$a" "$b" 1000

# 3. profundidade: N ancestrais já existentes + folha nova; depois ancestrais novos.
for depth in 1 3 6 10; do
  segs=() types=o
  for ((j = 0; j < depth; j++)); do segs+=("n$j"); types+=o; done
  sds_core_init_data d
  a=$(now)
  for ((i = 0; i < 200; i++)); do
    sds_core_assign d "${types}s" v "${segs[@]}" "x$i" || exit 1
  done
  b=$(now)
  report "3a. 200 folhas sob ancestrais existentes, prof. $((depth + 1))" "$a" "$b" 200
  sds_core_init_data d
  a=$(now)
  for ((i = 0; i < 200; i++)); do
    sds_core_assign d "${types}os" v "t$i" "${segs[@]}" "x" || exit 1
  done
  b=$(now)
  report "3b. 200 caminhos com $((depth + 1)) níveis novos cada" "$a" "$b" 200
done

sds_core_init_data d; fill d 1000
a=$(now)
for ((i = 0; i < 100; i++)); do sds_core_delete d "k$i" || exit 1; done
b=$(now)
report "4. remover 100 escalares (loja de 1000)" "$a" "$b" 100

for n in 10 1000; do
  sds_core_init_data d
  for ((i = 0; i < n; i++)); do sds_core_assign d ls "v$i" "$i" || exit 1; done
  a=$(now); sds_core_delete d 0 || exit 1; b=$(now)
  report "5. remover o 1o elemento de lista de $n (desloca $((n - 1)))" "$a" "$b" 1
  a=$(now); sds_core_delete d $((n - 2)) || exit 1; b=$(now)
  report "5. remover o penúltimo de lista de $n (desloca 1)" "$a" "$b" 1
done

sds_core_init_data d; fill d 1000
a=$(now)
for ((i = 0; i < 100; i++)); do
  sds_core_set d "$(K os "k$i")" "$(K os "r$i")" || exit 1
done
b=$(now)
report "6a. set: renomear 100 escalares (loja de 1000)" "$a" "$b" 100
a=$(now)
for ((i = 100; i < 200; i++)); do
  sds_core_set d "$(K os "k$i")" "$(K ol "k$i")" 2>/dev/null
done
b=$(now)
report "6b. set: tipo terminal s->l (rejeitado: payload não vazio, 100 tentativas)" "$a" "$b" 100

# 7. renomeação de subárvore: contêiner com N descendentes dentro de loja de 1000.
for n in 10 100 500; do
  sds_core_init_data d; fill d 1000
  for ((i = 0; i < n; i++)); do sds_core_assign d oos v sub "k$i" || exit 1; done
  a=$(now); sds_core_set d "$(K oo sub)" "$(K oo sub2)" || exit 1; b=$(now)
  report "7. renomear subárvore de $n descendentes (loja de $((1000 + n)))" "$a" "$b" 1
done
````

## `tests/lib/assert.sh`

````bash
# Mini-framework de testes para SDStruct (Bash puro).
# Cada função test_* roda em subshell isolado; falhas são contadas por FAILS.

FAILS=0
RC=0
ERR=

_fail() {
  printf '    FAIL: %s\n' "$*" >&2
  FAILS=$((FAILS + 1))
}

assert_eq() { # expected actual [msg]
  [[ $1 == "$2" ]] || _fail "${3:-valores diferentes}: esperado [$(printf %q "$1")] obtido [$(printf %q "$2")]"
}

_PENDING=0
# Uma chamada a run que retorna != 0 precisa ser conferida por assert_rc antes
# da próxima chamada; caso contrário a suíte acusa falha silenciosa.
_check_pending() {
  if (( _PENDING )); then
    _fail "chamada anterior retornou $RC sem ser verificada por assert_rc (stderr: $ERR)"
    _PENDING=0
  fi
}

assert_rc() { # expected_rc [msg]  (usa RC da última chamada a run)
  _PENDING=0
  (( RC == $1 )) || _fail "${2:-código de retorno}: esperado $1 obtido $RC (stderr: $ERR)"
}

skip() { # MOTIVO — encerra o teste como ignorado (código 77)
  printf '    SKIP: %s\n' "$*" >&2
  exit 77
}

# run CMD ARGS... — executa no shell atual (sem subshell), guarda RC e ERR.
run() {
  local errf=$_TMPDIR/err
  _check_pending
  "$@" 2>"$errf"
  RC=$?
  ERR=$(<"$errf")
  (( RC == 0 )) || _PENDING=1
  if [[ -n ${SDS_TEST_TRACE-} ]] && (( RC != 0 )); then
    printf '    trace: rc=%d %s\n' "$RC" "${*:1:3}" >&2
  fi
}

# Cópia de uma coleção e comparação (para provar que falhas não alteram dados).
snap() { # src dst
  local -n _s=$1 _d=$2
  local k
  _d=()
  for k in "${!_s[@]}"; do _d[$k]=${_s[$k]}; done
}

assert_same() { # a b — mesmos pares chave/valor
  local -n _a=$1 _b=$2
  local k
  (( ${#_a[@]} == ${#_b[@]} )) || { _fail "tamanhos diferentes: ${#_a[@]} vs ${#_b[@]}"; return; }
  for k in "${!_a[@]}"; do
    [[ -n ${_b[$k]+x} && ${_a[$k]} == "${_b[$k]}" ]] || { _fail "registro diferente"; return; }
  done
}

# Leitura com asserções: expect_get EXPECTED_PAYLOAD EXPECTED_TYPE NAME seg...
expect_get() {
  local want=$1 wtype=$2 name=$3 got= gtype=
  shift 3
  run sds_core_get "$name" got "$@"; assert_rc 0 "get $*"
  assert_eq "$want" "$got" "payload de [$*]"
  run sds_core_type "$name" gtype "$@"; assert_rc 0 "type $*"
  assert_eq "$wtype" "$gtype" "tipo de [$*]"
}

# assert_consistent NAME — os dados são válidos e o índice derivado mantido
# incrementalmente pelas operações é idêntico ao reconstruído do zero.
assert_consistent() {
  local name=$1 k
  local -n _ix=SDS_IX_$name _dd=$name
  local -A before=()
  for k in "${!_ix[@]}"; do before[$k]=${_ix[$k]}; done
  unset -v 'before[Z]' # sentinela de plant_sentinel
  [[ ${before[M]-} == "${#_dd[@]}" ]] || _fail "índice de $name não está sincronizado (M=${before[M]-?} registros=${#_dd[@]})"
  run sds_core_validate "$name"; assert_rc 0 "validate $name"
  (( ${#before[@]} == ${#_ix[@]} )) || _fail "índice incremental difere do reconstruído (tamanho ${#before[@]} vs ${#_ix[@]})"
  for k in "${!_ix[@]}"; do
    [[ $k == L ]] && continue
    [[ ${before[$k]-<ausente>} == "${_ix[$k]}" ]] || _fail "índice incremental difere do reconstruído em [$(printf %q "$k")]"
  done
}

# diff_counts SAVED CURRENT — define ADDED, REMOVED, CHANGED (nº de registros).
diff_counts() {
  local -n _o=$1 _n=$2
  local k
  ADDED=0 REMOVED=0 CHANGED=0
  for k in "${!_n[@]}"; do
    if [[ -z ${_o[$k]+x} ]]; then ADDED=$((ADDED + 1)); elif [[ ${_o[$k]} != "${_n[$k]}" ]]; then CHANGED=$((CHANGED + 1)); fi
  done
  for k in "${!_o[@]}"; do [[ -n ${_n[$k]+x} ]] || REMOVED=$((REMOVED + 1)); done
}

# assert_diff SAVED CURRENT ADDED REMOVED CHANGED — alteração exata do armazenamento.
assert_diff() {
  diff_counts "$1" "$2"
  assert_eq "$3/$4/$5" "$ADDED/$REMOVED/$CHANGED" "registros adicionados/removidos/alterados"
}

# Prova de que não houve reconstrução global: a reconstrução do índice o
# esvazia, então uma chave sentinela plantada nele desapareceria.
plant_sentinel() { local -n _px=SDS_IX_$1; _px[Z]=sentinela; }
assert_no_rebuild() {
  local -n _px=SDS_IX_$1
  assert_eq sentinela "${_px[Z]-}" "o índice foi reconstruído globalmente"
}
````

## `tests/run.sh`

````bash
#!/usr/bin/env bash
# Executa a suíte do SDStruct.
#   bash tests/run.sh [arquivo_de_teste...]
# Retorna 0 se todos os testes passarem; 1 se algum falhar; 2 em erro de
# ambiente. Um teste pode se declarar ignorado com `skip MOTIVO` (conta como
# "ignorado", nunca como aprovado).
set -u
here=${BASH_SOURCE[0]}
if [[ $here == */* ]]; then here=${here%/*}; else here=.; fi
here=$(cd "$here" && pwd) || exit 2
# shellcheck source=/dev/null
source "$here/../src/sdstruct.sh" || exit 2
# shellcheck source=/dev/null
source "$here/lib/assert.sh" || exit 2

_TMPDIR=$(mktemp -d) || exit 2
trap 'rm -rf "$_TMPDIR"' EXIT

files=("$@")
(( ${#files[@]} )) || files=("$here"/test_*.sh)

total=0 passed=0 failed=0 skipped=0
declare -a failed_names=()

for f in "${files[@]}"; do
  before=$(compgen -A function test_ | sort)
  # shellcheck source=/dev/null
  source "$f" || { printf 'erro ao carregar %s\n' "$f" >&2; exit 2; }
  after=$(compgen -A function test_ | sort)
  mapfile -t names < <(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))
  gp=0 gf=0 gs=0
  printf '== %s\n' "${f##*/}"
  for t in "${names[@]}"; do
    [[ -n $t ]] || continue
    total=$((total + 1))
    ( FAILS=0; "$t"; _check_pending; (( FAILS == 0 )) )
    rc=$?
    if (( rc == 77 )); then
      gs=$((gs + 1)); printf 'skip  %s\n' "$t"
    elif (( rc == 0 )); then
      gp=$((gp + 1)); printf 'ok    %s\n' "$t"
    else
      gf=$((gf + 1)); failed_names+=("$t"); printf 'FAIL  %s\n' "$t"
    fi
  done
  passed=$((passed + gp)); failed=$((failed + gf)); skipped=$((skipped + gs))
  printf '   grupo %s: %d aprovados, %d reprovados, %d ignorados\n' "${f##*/}" "$gp" "$gf" "$gs"
done

printf '\nAmbiente: Bash %s | LC_ALL=%s | %s\n' "$BASH_VERSION" "${LC_ALL-<não definido>}" "$(uname -sr)"
printf 'TOTAL: %d testes, %d aprovados, %d reprovados, %d ignorados\n' "$total" "$passed" "$failed" "$skipped"
if (( failed )); then
  printf 'Reprovados:\n'
  printf '  - %s\n' "${failed_names[@]}"
  exit 1
fi
(( total > 0 )) || { printf 'nenhum teste executado\n' >&2; exit 2; }
exit 0
````

## `tests/test_assign.sh`

````bash
# Atribuição de u/n, escalares e contêineres (sds_core_assign).
# Contrato PROVISÓRIO (docs/CORE.md): a atribuição nunca descarta uma subárvore;
# mudar o tipo de um valor significativo é papel de sds_core_set.

_count() { local -n _c=$1; echo "${#_c[@]}"; }

test_u_and_n_replaced_by_any_type() {
  local from to payload t
  for from in u n; do
    for to in s i f b o l; do
      case $to in
        s) payload=txt ;; i) payload=42 ;; f) payload=4.2 ;; b) payload=true ;; *) payload= ;;
      esac
      declare -A d=()
      run sds_core_assign d "o$from" '' k; assert_rc 0 "$from inicial"
      run sds_core_assign d "o$to" "$payload" k; assert_rc 0 "$from -> $to"
      run sds_core_type d t k; assert_eq "$to" "$t" "tipo após $from -> $to"
      assert_eq 1 "$(_count d)" "um único registro após $from -> $to"
      run sds_core_validate d; assert_rc 0 "estrutura válida após $from -> $to"
    done
  done
}

test_u_to_string_keeps_payload() {
  declare -A d=()
  run sds_core_assign d ou '' k
  run sds_core_assign d os valor k; assert_rc 0
  expect_get valor s d k
}

test_n_to_integer() {
  declare -A d=()
  run sds_core_assign d on '' k
  run sds_core_assign d oi 7 k; assert_rc 0
  expect_get 7 i d k
}

test_root_u_and_n_replaced() {
  declare -A d=()
  run sds_core_assign d u ''; assert_rc 0
  run sds_core_assign d o ''; assert_rc 0
  expect_get "" o d
  run sds_core_assign d n ''; assert_rc "$SDS_E_TYPE" "raiz contêiner vazio não vira null por atribuição"
  run sds_core_assign d l ''; assert_rc "$SDS_E_TYPE"
  expect_get "" o d
  run sds_core_set d "o$sds_LT" "l$sds_LT"; assert_rc 0
  expect_get "" l d
  assert_eq 1 "$(_count d)"
}

test_u_promoted_to_object_by_path() {
  declare -A d=()
  run sds_core_assign d ou '' cfg; assert_rc 0
  run sds_core_assign d oos v cfg a; assert_rc 0 "u promovido a objeto"
  assert_eq 1 "$(_count d)" "terminal u consumido"
  run sds_core_is_object d cfg; assert_rc 0
  expect_get v s d cfg a
  run sds_core_validate d; assert_rc 0
}

test_n_promoted_to_list_by_path() {
  declare -A d=()
  run sds_core_assign d on '' cfg; assert_rc 0
  run sds_core_assign d ols v cfg 0; assert_rc 0 "n promovido a lista"
  assert_eq 1 "$(_count d)"
  run sds_core_is_list d cfg; assert_rc 0
  expect_get v s d cfg 0
  run sds_core_validate d; assert_rc 0
}

test_undefined_list_position_becomes_object_with_properties() {
  declare -A d=()
  run sds_core_assign d ls last 3; assert_rc 0
  run sds_core_assign d los 1 2 x; assert_rc 0 "posição u -> objeto"
  run sds_core_assign d los 2 2 y; assert_rc 0
  expect_get "" u d 0
  expect_get "" u d 1
  run sds_core_is_object d 2; assert_rc 0
  expect_get 1 s d 2 x
  expect_get 2 s d 2 y
  expect_get last s d 3
  assert_eq 5 "$(_count d)" "u,u,x,y,last"
  run sds_core_validate d; assert_rc 0
}

test_undefined_list_position_becomes_list() {
  declare -A d=()
  run sds_core_assign d ls last 2
  run sds_core_assign d lls v 1 0; assert_rc 0
  run sds_core_is_list d 1; assert_rc 0
  expect_get "" u d 0
  expect_get v s d 1 0
  run sds_core_validate d; assert_rc 0
}

test_promotion_chain_through_levels() {
  declare -A d=()
  run sds_core_assign d ou '' a
  run sds_core_assign d ooi 1 a b; assert_rc 0
  run sds_core_assign d on '' c
  run sds_core_assign d oolu '' c d 1; assert_rc 0 "n promovido a objeto e ganha lista com preenchimento"
  expect_get "" u d c d 0
  expect_get "" u d c d 1
  run sds_core_validate d; assert_rc 0
}

test_object_with_descendants_cannot_become_string() {
  declare -A d=() saved=()
  run sds_core_assign d oos 1 obj a
  run sds_core_assign d oos 2 obj b
  run sds_core_assign d os keep other
  snap d saved
  run sds_core_assign d os texto obj; assert_rc "$SDS_E_CONFLICT"
  assert_same d saved
  run sds_core_assign d oi 5 obj; assert_rc "$SDS_E_CONFLICT"
  run sds_core_assign d on '' obj; assert_rc "$SDS_E_CONFLICT"
  run sds_core_assign d ou '' obj; assert_rc "$SDS_E_CONFLICT"
  run sds_core_assign d oo '' obj; assert_rc 0 "mesmo tipo de contêiner: nada é descartado"
  assert_same d saved
  run sds_core_validate d; assert_rc 0
}

test_list_with_elements_cannot_become_integer() {
  declare -A d=() saved=()
  run sds_core_assign d ols a l 0
  run sds_core_assign d ols b l 1
  snap d saved
  run sds_core_assign d oi 9 l; assert_rc "$SDS_E_CONFLICT"
  run sds_core_assign d of 9.5 l; assert_rc "$SDS_E_CONFLICT"
  run sds_core_assign d ob true l; assert_rc "$SDS_E_CONFLICT"
  assert_same d saved
  expect_get a s d l 0
  expect_get b s d l 1
}

test_root_with_descendants_cannot_be_replaced() {
  declare -A d=() saved=()
  run sds_core_assign d ls x 0; assert_rc 0
  snap d saved
  run sds_core_assign d s texto; assert_rc "$SDS_E_CONFLICT"
  run sds_core_assign d o ''; assert_rc "$SDS_E_CONFLICT"
  assert_same d saved
}

test_replacement_requires_explicit_delete_then_set() {
  declare -A d=()
  run sds_core_assign d oos 1 obj a
  run sds_core_assign d os texto obj; assert_rc "$SDS_E_CONFLICT"
  run sds_core_delete d obj; assert_rc 0
  expect_get "" o d
  run sds_core_assign d os texto obj; assert_rc 0
  expect_get texto s d obj
  assert_eq 1 "$(_count d)"
  run sds_core_validate d; assert_rc 0
}

test_list_element_subtree_replacement_has_no_inplace_operation() {
  # delete desloca a lista; portanto não existe, nesta etapa, substituição
  # in-place de um elemento que possui descendentes (decisão pendente).
  declare -A d=() saved=()
  run sds_core_assign d los 1 0 a
  run sds_core_assign d ls z 1
  snap d saved
  run sds_core_assign d ls novo 0; assert_rc "$SDS_E_CONFLICT"
  assert_same d saved
}

test_scalar_ancestors_never_promoted() {
  declare -A d=() saved=()
  local t
  for t in "s:x" "i:1" "f:1.5" "b:true"; do
    d=()
    run sds_core_assign d "o${t%%:*}" "${t#*:}" k
    snap d saved
    run sds_core_assign d "oos" v k a; assert_rc "$SDS_E_TYPE" "ancestral ${t%%:*}"
    run sds_core_assign d "ols" v k 0; assert_rc "$SDS_E_TYPE" "ancestral ${t%%:*} (lista)"
    assert_same d saved
  done
}

test_empty_container_type_mismatch_not_promoted() {
  declare -A d=() saved=()
  run sds_core_assign d oo '' k
  snap d saved
  run sds_core_assign d ols v k 0; assert_rc "$SDS_E_TYPE" "objeto vazio não vira lista por descendente"
  assert_same d saved
  run sds_core_assign d ol '' k; assert_rc "$SDS_E_TYPE" "atribuição não troca o tipo de um contêiner vazio"
  assert_same d saved
  run sds_core_set d "oo${sds_LT}k" "ol${sds_LT}k"; assert_rc 0 "a troca explícita é feita por set"
  run sds_core_is_list d k; assert_rc 0
}

test_empty_container_replaced_by_scalar() {
  declare -A d=()
  run sds_core_assign d oo '' k
  run sds_core_assign d os x k; assert_rc "$SDS_E_TYPE" "contêiner vazio não vira string por atribuição"
  expect_get "" o d k
  run sds_core_set d "oo${sds_LT}k" "os${sds_LT}k"; assert_rc 0 "set altera o tipo terminal"
  expect_get "" s d k
  assert_eq 1 "$(_count d)"
}

test_no_parallel_structure_after_assignments() {
  declare -A d=()
  run sds_core_assign d ou '' a
  run sds_core_assign d oos v a b
  run sds_core_assign d oi 1 c
  run sds_core_assign d oi 2 c
  local k
  for k in "${!d[@]}"; do
    sds_core_decode_key "$k" || _fail "chave inválida"
  done
  run sds_core_validate d; assert_rc 0
  assert_eq 2 "$(_count d)"
}
````

## `tests/test_assignment.sh`

````bash
# Contrato de atribuição ordinária (sds_core_assign): cria caminhos ausentes,
# atualiza valores compatíveis, localiza as alterações e preserva a integridade.
# Contrato PROVISÓRIO; ver docs/CORE.md.

# K TYPES SEG... — chave canônica (para sds_core_set).
K() { local __o; sds_core_make_key __o "$@" && printf '%s' "$__o"; }

# Estrutura do exemplo do projeto.
fixture() { # NAME
  sds_core_init_data "$1" || return
  sds_core_assign "$1" ooos web1 servidor web1 nome &&
    sds_core_assign "$1" ooos http servidor web1 service &&
    sds_core_assign "$1" oooli 80 servidor web1 porta 0 &&
    sds_core_assign "$1" oooli 443 servidor web1 porta 1 &&
    sds_core_assign "$1" ooos web2 servidor web2 nome
}

test_fixture_is_valid() {
  fixture d; assert_rc 0
  assert_eq 5 "${#d[@]}"
  assert_consistent d
}

test_assign_entirely_new_path() {
  sds_core_init_data d
  run sds_core_assign d oolos admin a b 0 c; assert_rc 0
  expect_get admin s d a b 0 c
  run sds_core_is_object d a; assert_rc 0
  run sds_core_is_list d a b; assert_rc 0
  assert_eq 1 "${#d[@]}" "apenas o registro terminal é gravado"
  assert_consistent d
}

test_assign_user_list_under_existing_ancestors() {
  declare -A d=() saved=()
  fixture d
  snap d saved
  plant_sentinel d
  run sds_core_assign d ooolS admin servidor web1 user 0; assert_rc "$SDS_E_TYPE" "tipo S inválido"
  run sds_core_assign d oools admin servidor web1 user 0; assert_rc 0
  expect_get admin s d servidor web1 user 0
  run sds_core_is_list d servidor web1 user; assert_rc 0 "contêiner user criado como lista"
  assert_diff saved d 1 0 0
  assert_no_rebuild d
  expect_get web1 s d servidor web1 nome
  expect_get 443 i d servidor web1 porta 1
  assert_consistent d
}

test_assign_creates_several_intermediate_levels() {
  declare -A d=() saved=()
  fixture d
  snap d saved
  run sds_core_assign d ooolos x servidor web3 a 0 b; assert_rc 0
  assert_diff saved d 1 0 0
  run sds_core_is_object d servidor web3; assert_rc 0
  run sds_core_is_list d servidor web3 a; assert_rc 0
  run sds_core_is_object d servidor web3 a 0; assert_rc 0
  expect_get x s d servidor web3 a 0 b
  assert_consistent d
}

test_update_same_type_changes_only_payload() {
  declare -A d=() saved=()
  fixture d
  snap d saved
  plant_sentinel d
  run sds_core_assign d oooli 8080 servidor web1 porta 0; assert_rc 0
  assert_diff saved d 0 0 1
  expect_get 8080 i d servidor web1 porta 0
  expect_get 443 i d servidor web1 porta 1
  assert_no_rebuild d
  assert_consistent d
}

test_update_to_empty_string_payload() {
  declare -A d=()
  fixture d
  run sds_core_assign d ooos '' servidor web1 nome; assert_rc 0
  expect_get "" s d servidor web1 nome
}

test_assign_over_undefined_in_list_with_object() {
  declare -A d=() saved=()
  sds_core_init_data d
  run sds_core_assign d lu '' 0
  run sds_core_assign d lu '' 1
  snap d saved
  run sds_core_assign d los admin 1 nome; assert_rc 0 "posição u vira objeto com propriedade"
  run sds_core_is_object d 1; assert_rc 0
  expect_get admin s d 1 nome
  expect_get "" u d 0
  assert_eq 2 "${#d[@]}"
  assert_consistent d
}

test_assign_over_null_and_undefined_keeps_siblings() {
  declare -A d=() saved=()
  sds_core_init_data d
  run sds_core_assign d lu '' 0
  run sds_core_assign d ln '' 1
  run sds_core_assign d li 7 2
  snap d saved
  run sds_core_assign d ls admin 0; assert_rc 0
  run sds_core_assign d li 42 1; assert_rc 0
  expect_get admin s d 0
  expect_get 42 i d 1
  expect_get 7 i d 2
  assert_diff saved d 2 2 0
  assert_consistent d
}

test_implicit_type_change_of_significant_value_rejected() {
  declare -A d=() saved=()
  fixture d
  snap d saved
  run sds_core_assign d oooli x servidor web1 porta 0; assert_rc "$SDS_E_TYPE" "payload inválido"
  run sds_core_assign d oools 80 servidor web1 porta 0; assert_rc "$SDS_E_TYPE" "i -> s"
  run sds_core_assign d ooof 1.5 servidor web1 nome; assert_rc "$SDS_E_TYPE" "s -> f"
  run sds_core_assign d ooon '' servidor web1 nome; assert_rc "$SDS_E_TYPE" "s -> n"
  run sds_core_assign d ooou '' servidor web1 nome; assert_rc "$SDS_E_TYPE" "s -> u"
  run sds_core_assign d oooo '' servidor web1 nome; assert_rc "$SDS_E_TYPE" "s -> o"
  assert_same d saved
  assert_consistent d
}

test_container_with_descendants_rejects_other_types() {
  declare -A d=() saved=()
  fixture d
  snap d saved
  run sds_core_assign d os x servidor; assert_rc "$SDS_E_CONFLICT"
  run sds_core_assign d ol '' servidor; assert_rc "$SDS_E_CONFLICT"
  run sds_core_assign d oou '' servidor web1; assert_rc "$SDS_E_CONFLICT"
  assert_same d saved
}

test_ancestor_type_never_changed_or_scalar() {
  declare -A d=() saved=()
  fixture d
  snap d saved
  run sds_core_assign d oooos v servidor web1 porta x; assert_rc "$SDS_E_TYPE" "porta é lista, não objeto"
  run sds_core_assign d olos v servidor 0 x; assert_rc "$SDS_E_TYPE" "servidor é objeto, não lista"
  run sds_core_assign d oooos v servidor web1 nome x; assert_rc "$SDS_E_TYPE" "nome é escalar"
  run sds_core_assign d ooolo "" servidor web1 nome 0; assert_rc "$SDS_E_TYPE"
  assert_same d saved
  assert_consistent d
}

test_list_fill_and_contiguity_on_assignment() {
  declare -A d=() saved=()
  fixture d
  snap d saved
  run sds_core_assign d oools admin servidor web1 user 3; assert_rc 0
  assert_diff saved d 4 0 0
  local i t
  for i in 0 1 2; do
    run sds_core_type d t servidor web1 user "$i"; assert_eq u "$t" "preenchimento $i"
  done
  expect_get admin s d servidor web1 user 3
  assert_consistent d
}

test_assignment_is_localised_in_a_large_store() {
  declare -A d=() saved=()
  sds_core_init_data d
  local i
  for ((i = 0; i < 300; i++)); do sds_core_assign d os "v$i" "k$i" || _fail "carga $i"; done
  snap d saved
  plant_sentinel d
  run sds_core_assign d os novo k300; assert_rc 0
  run sds_core_assign d os mudado k7; assert_rc 0
  run sds_core_assign d ooos fundo n1 n2 n3; assert_rc 0
  run sds_core_exists d k5; assert_rc 0
  run sds_core_exists d nada; assert_rc 1
  local v; run sds_core_get d v k299; assert_rc 0
  assert_diff saved d 2 0 1
  assert_no_rebuild d
  assert_consistent d
}

test_all_core_types_assignable() {
  declare -A d=()
  sds_core_init_data d
  run sds_core_assign d lolsifbnu "" 0 0; assert_rc "$SDS_E_TYPE" "tipificadores demais"
  run sds_core_assign d lls s 0 0; assert_rc 0
  run sds_core_assign d lli 10 1 0; assert_rc 0
  run sds_core_assign d llf 1.5e3 2 0; assert_rc 0
  run sds_core_assign d llb false 3 0; assert_rc 0
  run sds_core_assign d lln '' 4 0; assert_rc 0
  run sds_core_assign d llu '' 5 0; assert_rc 0
  run sds_core_assign d llo '' 6 0; assert_rc 0
  run sds_core_assign d lll '' 7 0; assert_rc 0
  local i want=(s i f b n u o l) t
  for i in 0 1 2 3 4 5 6 7; do
    run sds_core_type d t "$i" 0; assert_eq "${want[i]}" "$t" "tipo do elemento $i"
  done
  assert_consistent d
}

test_root_remains_valid_across_operations() {
  declare -A d=()
  sds_core_init_data d
  run sds_core_assign d o ''; assert_rc 0
  run sds_core_is_object d; assert_rc 0
  run sds_core_assign d os x a; assert_rc 0
  assert_eq 1 "${#d[@]}" "raiz objeto vazio consumida pelo primeiro filho"
  run sds_core_delete d a; assert_rc 0
  run sds_core_is_object d; assert_rc 0 "raiz volta a ser objeto vazio"
  assert_eq 1 "${#d[@]}"
  assert_consistent d
}

test_empty_payloads_and_empty_containers_roundtrip() {
  declare -A d=()
  sds_core_init_data d
  run sds_core_assign d oos '' a b; assert_rc 0
  run sds_core_assign d oon '' a c; assert_rc 0
  run sds_core_assign d oou '' a d; assert_rc 0
  run sds_core_assign d ooo '' a e; assert_rc 0
  run sds_core_assign d ool '' a f; assert_rc 0
  expect_get "" s d a b
  expect_get "" n d a c
  expect_get "" u d a d
  expect_get "" o d a e
  expect_get "" l d a f
  assert_eq 5 "${#d[@]}"
  assert_consistent d
}

test_scalar_never_gets_descendants() {
  declare -A d=() saved=()
  sds_core_init_data d
  run sds_core_assign d os x a
  run sds_core_assign d oi 1 b
  run sds_core_assign d of 1.5 c
  run sds_core_assign d ob true e
  snap d saved
  local t=(s i f b) p=(x 1 1.5 true) k=(a b c e) j
  for j in 0 1 2 3; do
    run sds_core_assign d "oo${t[j]}" "${p[j]}" "${k[j]}" y; assert_rc "$SDS_E_TYPE" "escalar ${t[j]} não aceita descendentes"
  done
  assert_same d saved
}

test_failed_assignments_never_change_index_or_data() {
  declare -A d=() saved=()
  fixture d
  snap d saved
  run sds_core_assign d ooolx v servidor web1 user 0; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d oooli v servidor web1 user 0; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d ooolo '' servidor web1 user 00; assert_rc "$SDS_E_PATH" "índice não canônico"
  run sds_core_assign d ooos v servidor web1 "a${sds_LP}b"; assert_rc "$SDS_E_PATH"
  run sds_core_assign d oooli 1 servidor web1 porta 99999999999; assert_rc "$SDS_E_PATH"
  assert_same d saved
  assert_consistent d
}

# --- Remoção localizada ---------------------------------------------------

test_delete_scalar_removes_only_that_record() {
  declare -A d=() saved=()
  fixture d
  snap d saved
  plant_sentinel d
  run sds_core_delete d servidor web2 nome; assert_rc 0
  assert_diff saved d 1 1 0
  run sds_core_exists d servidor web2; assert_rc 0 "web2 vira objeto vazio"
  run sds_core_is_object d servidor web2; assert_rc 0
  assert_no_rebuild d
  assert_consistent d
}

test_delete_container_removes_subtree_only() {
  declare -A d=() saved=()
  fixture d
  snap d saved
  run sds_core_delete d servidor web1; assert_rc 0
  assert_eq 1 "${#d[@]}" "só web2/nome permanece"
  run sds_core_exists d servidor web1; assert_rc 1
  expect_get web2 s d servidor web2 nome
  assert_consistent d
}

test_delete_list_element_shifts_only_later_siblings() {
  declare -A d=() saved=()
  fixture d
  local i
  for i in 0 1 2 3 4; do run sds_core_assign d oooli "$((100 + i))" servidor web1 portas "$i"; done
  sds_core_assign d oooo '' servidor web1 vazia
  snap d saved
  plant_sentinel d
  run sds_core_delete d servidor web1 portas 1; assert_rc 0
  assert_diff saved d 0 1 3
  expect_get 100 i d servidor web1 portas 0
  expect_get 102 i d servidor web1 portas 1
  expect_get 103 i d servidor web1 portas 2
  expect_get 104 i d servidor web1 portas 3
  run sds_core_exists d servidor web1 portas 4; assert_rc 1
  expect_get 80 i d servidor web1 porta 0
  assert_no_rebuild d
  assert_consistent d
}

test_delete_list_element_with_object_descendants_shifts_subtrees() {
  declare -A d=()
  sds_core_init_data d
  local i
  for i in 0 1 2; do
    sds_core_assign d los "n$i" "$i" nome
    sds_core_assign d loli "$((i + 10))" "$i" tags 0
  done
  assert_eq 6 "${#d[@]}"
  run sds_core_delete d 0; assert_rc 0
  assert_eq 4 "${#d[@]}"
  expect_get n1 s d 0 nome
  expect_get 11 i d 0 tags 0
  expect_get n2 s d 1 nome
  expect_get 12 i d 1 tags 0
  run sds_core_exists d 2; assert_rc 1
  assert_consistent d
}

test_delete_last_list_element_leaves_empty_list() {
  declare -A d=()
  sds_core_init_data d
  run sds_core_assign d ls a 0
  run sds_core_delete d 0; assert_rc 0
  run sds_core_is_list d; assert_rc 0
  assert_eq 1 "${#d[@]}"
  assert_consistent d
}

test_delete_object_property_does_not_shift_others() {
  declare -A d=() saved=()
  sds_core_init_data d
  sds_core_assign d os 1 a; sds_core_assign d os 2 b; sds_core_assign d os 3 c
  snap d saved
  run sds_core_delete d b; assert_rc 0
  assert_diff saved d 0 1 0
  expect_get 1 s d a
  expect_get 3 s d c
  assert_consistent d
}

test_delete_missing_path_changes_nothing() {
  declare -A d=() saved=()
  fixture d
  snap d saved
  run sds_core_delete d servidor web9; assert_rc 1
  run sds_core_delete d servidor web1 nome x; assert_rc 1
  assert_same d saved
}
````

## `tests/test_basics.sh`

````bash
# Delimitadores, inicialização, chaves e validação de payloads.

test_delims_defaults() {
  assert_eq $'\xff' "$sds_LT" "sds_LT"
  assert_eq $'\xfe' "$sds_LP" "sds_LP"
  run sds_init; assert_rc 0
}

test_delims_invalid() {
  local old=$sds_LT
  sds_LT=; run sds_check_delims; assert_rc "$SDS_E_ENV" "vazio"
  sds_LT=ab; run sds_check_delims; assert_rc "$SDS_E_ENV" "2 bytes"
  sds_LT=$sds_LP; run sds_check_delims; assert_rc "$SDS_E_ENV" "iguais"
  sds_LT=o; run sds_check_delims; assert_rc "$SDS_E_ENV" "igual a tipificador"
  sds_LT=$old
  unset sds_LP; run sds_check_delims; assert_rc "$SDS_E_ENV" "indefinido"
}

test_delims_checked_by_operations() {
  declare -A d=(); sds_LP=; 
  run sds_core_assign d o '' ; assert_rc "$SDS_E_ENV"
  (( ${#d[@]} == 0 )) || _fail "não deveria gravar"
}

test_init_data() {
  run sds_core_init_data dd; assert_rc 0
  [[ $(declare -p dd) == "declare -A dd"* ]] || _fail "dd deveria ser associativo"
  dd[x]=1
  run sds_core_init_data dd; assert_rc 0
  assert_eq 0 "${#dd[@]}" "reinicialização esvazia"
  plain=1
  run sds_core_init_data plain; assert_rc "$SDS_E_USAGE" "variável não associativa"
  run sds_core_init_data '1bad'; assert_rc "$SDS_E_USAGE"
  run sds_core_init_data '__sds_x'; assert_rc "$SDS_E_USAGE" "prefixo reservado"
}

test_make_key_and_decode() {
  local key
  run sds_core_make_key key oooli servidores web1 portas 0; assert_rc 0
  assert_eq "oooli${sds_LT}servidores${sds_LP}web1${sds_LP}portas${sds_LP}0" "$key"
  run sds_core_decode_key "$key"; assert_rc 0
  assert_eq oooli "$SDS_D_TYPES"; assert_eq 4 "$SDS_D_N"
  assert_eq "servidores|web1|portas|0" "$(IFS='|'; echo "${SDS_D_SEGS[*]}")"
}

test_make_key_root() {
  local key
  run sds_core_make_key key s; assert_rc 0
  assert_eq "s$sds_LT" "$key" "raiz tem tipificador e LT"
  run sds_core_decode_key "$key"; assert_rc 0
  assert_eq 0 "$SDS_D_N"; assert_eq 0 "${#SDS_D_SEGS[@]}"
}

test_make_key_empty_segment() {
  local key
  run sds_core_make_key key os ""; assert_rc 0
  run sds_core_decode_key "$key"; assert_rc 0
  assert_eq 1 "${#SDS_D_SEGS[@]}"; assert_eq "" "${SDS_D_SEGS[0]}"
  run sds_core_make_key key oos "" ""; assert_rc 0
  run sds_core_decode_key "$key"; assert_rc 0
  assert_eq 2 "${#SDS_D_SEGS[@]}"
}

test_make_key_invalid() {
  local key=orig
  run sds_core_make_key key ol; assert_rc "$SDS_E_TYPE" "tipos sem segmentos"
  run sds_core_make_key key osx a; assert_rc "$SDS_E_TYPE" "tipos a mais"
  run sds_core_make_key key ss a; assert_rc "$SDS_E_TYPE" "nível intermediário escalar"
  run sds_core_make_key key xs a; assert_rc "$SDS_E_TYPE" "tipificador desconhecido"
  run sds_core_make_key key ls 01; assert_rc "$SDS_E_PATH" "índice com zero à esquerda"
  run sds_core_make_key key ls -1; assert_rc "$SDS_E_PATH" "índice negativo"
  run sds_core_make_key key ls abc; assert_rc "$SDS_E_PATH" "índice não numérico"
  run sds_core_make_key key os "a${sds_LP}b"; assert_rc "$SDS_E_PATH" "LP no segmento"
  run sds_core_make_key key os "a${sds_LT}b"; assert_rc "$SDS_E_PATH" "LT no segmento"
  assert_eq orig "$key" "saída intocada em erro"
}

test_decode_malformed() {
  run sds_core_decode_key "semlt"; assert_rc "$SDS_E_CORRUPT"
  run sds_core_decode_key "${sds_LT}x"; assert_rc "$SDS_E_CORRUPT" "sem tipificador"
  run sds_core_decode_key "os${sds_LT}a${sds_LP}b"; assert_rc "$SDS_E_CORRUPT" "segmentos a mais"
  run sds_core_decode_key "o${sds_LT}a"; assert_rc "$SDS_E_CORRUPT" "segmentos a mais (raiz)"
  run sds_core_decode_key "ss${sds_LT}a"; assert_rc "$SDS_E_CORRUPT" "intermediário escalar"
  run sds_core_decode_key "ls${sds_LT}x"; assert_rc "$SDS_E_CORRUPT" "índice inválido"
  run sds_core_decode_key "os${sds_LT}a${sds_LT}b"; assert_rc "$SDS_E_CORRUPT" "dois LT"
  run sds_core_decode_key; assert_rc "$SDS_E_USAGE"
}

test_payload_validation() {
  declare -A d=()
  run sds_core_assign d i 1.5; assert_rc "$SDS_E_TYPE" "int com fração"
  run sds_core_assign d i 01; assert_rc "$SDS_E_TYPE" "int com zero à esquerda"
  run sds_core_assign d i ""; assert_rc "$SDS_E_TYPE" "int vazio"
  run sds_core_assign d i "1 "; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d i $'1\n2'; assert_rc "$SDS_E_TYPE" "int multilinha"
  run sds_core_assign d f 10; assert_rc "$SDS_E_TYPE" "float sem fração/expoente"
  run sds_core_assign d f 1.; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d f .5; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d b yes; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d n x; assert_rc "$SDS_E_TYPE" "null com payload"
  run sds_core_assign d u x; assert_rc "$SDS_E_TYPE" "undefined com payload"
  run sds_core_assign d o x; assert_rc "$SDS_E_TYPE" "objeto com payload"
  run sds_core_assign d l x; assert_rc "$SDS_E_TYPE" "lista com payload"
  assert_eq 0 "${#d[@]}" "nada gravado"
}
````

## `tests/test_environment.sh`

````bash
# Robustez frente a opções de shell do chamador (IFS, glob, nocasematch...).

test_nocasematch_does_not_merge_keys() {
  declare -A d=()
  shopt -s nocasematch
  run sds_core_assign d os um A; assert_rc 0
  run sds_core_assign d os dois a; assert_rc 0
  assert_eq 2 "${#d[@]}" "A e a são chaves distintas"
  expect_get um s d A
  expect_get dois s d a
  run sds_core_exists d B; assert_rc 1
  run sds_core_assign d ob TRUE b; assert_rc "$SDS_E_TYPE" "TRUE não é booleano"
  run sds_core_assign d of 1E3 e; assert_rc 0
  run sds_core_delete d A; assert_rc 0
  expect_get dois s d a
  run sds_core_validate d; assert_rc 0
  shopt -q nocasematch || _fail "nocasematch deveria ser restaurado"
}

test_nocasematch_restored_state_when_off() {
  shopt -u nocasematch
  declare -A d=()
  run sds_core_assign d os v k; assert_rc 0
  shopt -q nocasematch && _fail "nocasematch não deveria ser ligado"
}

test_hostile_ifs_and_glob_options() {
  declare -A d=()
  IFS=$'\n,:a *'
  set -f
  shopt -s nullglob failglob extglob
  run sds_core_assign d ols '*' l 1; assert_rc 0
  run sds_core_assign d oos 'a b' k 'x,y:z'; assert_rc 0
  expect_get '*' s d l 1
  expect_get 'a b' s d k 'x,y:z'
  run sds_core_delete d l 0; assert_rc 0
  expect_get '*' s d l 0
  run sds_core_validate d; assert_rc 0
  assert_eq 2 "${#d[@]}"
}

test_set_f_off_with_glob_chars_in_keys() {
  declare -A d=()
  set +f
  run sds_core_assign d os 1 '*'; assert_rc 0
  run sds_core_assign d os 2 '?'; assert_rc 0
  run sds_core_assign d os 3 '[a-z]'; assert_rc 0
  expect_get 1 s d '*'; expect_get 2 s d '?'; expect_get 3 s d '[a-z]'
  run sds_core_delete d '*'; assert_rc 0
  assert_eq 2 "${#d[@]}"
}

test_set_u_and_set_e_do_not_break() {
  set -u
  declare -A d=()
  run sds_core_assign d ls x 2; assert_rc 0
  run sds_core_delete d 0; assert_rc 0
  run sds_core_validate d; assert_rc 0
  set -e
  sds_core_exists d 0
  sds_core_assign d ls y 0
  sds_core_delete d 0
  true
}

test_trailing_newline_payload_preserved() {
  declare -A d=()
  run sds_core_assign d os $'a\n\n' k; assert_rc 0
  expect_get $'a\n\n' s d k
}

test_sourcing_twice_is_idempotent() {
  declare -A d=()
  run sds_core_assign d os v k; assert_rc 0
  # shellcheck source=/dev/null
  source "$here/../src/sdstruct.sh"
  expect_get v s d k
  assert_eq $'\xff' "$sds_LT"
}
````

## `tests/test_integrity.sh`

````bash
# Integridade: nomes de variáveis do chamador, bytes reservados, preservação
# de registros, reconstrução do array e atomicidade.

# Nomes comuns de variáveis que NÃO podem colidir com os locais internos.
_COLLIDING=(name out n i j k t p path types payload segs seg idx rn lv np P key
            rest found pat decl add rm pref lmax code d data)

test_caller_variable_names_do_not_collide_with_internals() {
  local v
  for v in "${_COLLIDING[@]}"; do
    declare -gA "$v=()"
    run sds_core_assign "$v" oos val a b; assert_rc 0 "set com array '$v'"
    run sds_core_assign "$v" ols x l 1; assert_rc 0 "set lista com array '$v'"
    local -n _r=$v; local sz=${#_r[@]}; unset -n _r
    assert_eq 3 "$sz" "registros em '$v'"
    run sds_core_validate "$v"; assert_rc 0 "validate '$v'"
    run sds_core_exists "$v" a b; assert_rc 0 "exists '$v'"
    run sds_core_delete "$v" a b; assert_rc 0 "delete '$v'"
    unset "$v"
  done
}

test_caller_output_names_do_not_collide_with_internals() {
  declare -A data=()
  run sds_core_assign data os valor k
  local v
  for v in "${_COLLIDING[@]}"; do
    [[ $v == data ]] && continue
    printf -v "$v" '%s' sentinela
    run sds_core_get data "$v" k; assert_rc 0 "get -> '$v'"
    assert_eq valor "${!v}" "valor em '$v'"
    run sds_core_type data "$v" k; assert_rc 0 "type -> '$v'"
    assert_eq s "${!v}" "tipo em '$v'"
  done
}

test_reserved_caller_names_rejected() {
  declare -A data=()
  local x
  run sds_core_get data __sds_x k; assert_rc "$SDS_E_USAGE"
  run sds_core_get data SDS_F_TYPE k; assert_rc "$SDS_E_USAGE"
  run sds_core_get data sds_LT k; assert_rc "$SDS_E_USAGE" "não pode sobrescrever delimitadores"
  run sds_core_assign __sds_d s x; assert_rc "$SDS_E_USAGE"
  assert_eq $'\xff' "$sds_LT"
}

test_reserved_bytes_in_segments_each_operation() {
  declare -A d=() saved=()
  local got= key= b seg
  run sds_core_assign d os ok a
  snap d saved
  for b in $'\xff' $'\xfe'; do
    for seg in "${b}" "x${b}" "${b}x" "x${b}y"; do
      run sds_core_assign d os v "$seg"; assert_rc "$SDS_E_PATH" "set"
      run sds_core_get d got "$seg"; assert_rc "$SDS_E_PATH" "get"
      run sds_core_exists d "$seg"; assert_rc "$SDS_E_PATH" "exists"
      run sds_core_delete d "$seg"; assert_rc "$SDS_E_PATH" "delete"
      run sds_core_is_object d "$seg"; assert_rc "$SDS_E_PATH" "is_object"
      run sds_core_make_key key os "$seg"; assert_rc "$SDS_E_PATH" "make_key"
    done
  done
  assert_same d saved
}

test_reserved_bytes_in_nested_segment_position() {
  declare -A d=() saved=()
  run sds_core_assign d oos ok a b
  snap d saved
  run sds_core_assign d oos v a "b${sds_LP}"; assert_rc "$SDS_E_PATH"
  run sds_core_assign d oos v "${sds_LT}a" b; assert_rc "$SDS_E_PATH"
  assert_same d saved
}

test_payload_with_fe_ff_all_types() {
  declare -A d=()
  local v=$'\xfe\xff\xfe' got
  run sds_core_assign d os "$v" a; assert_rc 0
  run sds_core_get d got a; assert_rc 0
  assert_eq "$v" "$got" "payload FE/FF"
  run sds_core_assign d os $'\xff' b; assert_rc 0
  run sds_core_assign d os $'\xfe' c; assert_rc 0
  expect_get $'\xff' s d b
  expect_get $'\xfe' s d c
  run sds_core_assign d oi $'1\xff' x; assert_rc "$SDS_E_TYPE" "FF não é inteiro"
  run sds_core_assign d ob $'true\xfe' x; assert_rc "$SDS_E_TYPE"
  run sds_core_validate d; assert_rc 0
  # o payload nunca aparece na chave
  local k
  for k in "${!d[@]}"; do
    sds_core_decode_key "$k" || _fail "chave inválida"
    [[ $k == *"$v"* ]] && _fail "payload vazou para a chave"
  done
}

test_payload_fe_ff_survives_list_shift() {
  declare -A d=()
  run sds_core_assign d ls $'a\xff' 0
  run sds_core_assign d ls $'b\xfe' 1
  run sds_core_assign d ls $'' 2
  run sds_core_delete d 0; assert_rc 0
  expect_get $'b\xfe' s d 0
  expect_get "" s d 1
}

test_empty_payloads_all_types() {
  declare -A d=()
  run sds_core_assign d os '' s; run sds_core_assign d on '' n; run sds_core_assign d ou '' u
  run sds_core_assign d oo '' o; run sds_core_assign d ol '' l
  local t k
  for k in s n u o l; do
    run sds_core_type d t "$k"; assert_eq "$k" "$t" "tipo de $k"
    local -n _p=d
    local key
    run sds_core_make_key key "o$k" "$k"
    [[ -n ${_p[$key]+x} && -z ${_p[$key]} ]] || _fail "payload de $k deveria existir e ser vazio"
    unset -n _p
  done
  assert_eq 5 "${#d[@]}"
}

test_special_keys_survive_writes_and_deletes() {
  declare -A d=() before=()
  local -a keys=('' ' ' 'a]b' 'a[b' '$x' '$(id)' '`id`' '"q"' "'s'" '\' '\\n' '*' '?' '@' '-n' '--' '[' ']' $'nl\nnl' $'\t' 'ação' $'\x80\x81' '0' '00' 'a b c')
  local k i=0
  for k in "${keys[@]}"; do
    run sds_core_assign d os "v$i" "$k"; assert_rc 0 "set chave $i"
    i=$((i + 1))
  done
  assert_eq "${#keys[@]}" "${#d[@]}" "todas as chaves distintas gravadas"
  i=0
  for k in "${keys[@]}"; do expect_get "v$i" s d "$k"; i=$((i + 1)); done
  run sds_core_validate d; assert_rc 0
  snap d before
  # remove cada chave e confere que só ela desapareceu
  i=0
  for k in "${keys[@]}"; do
    run sds_core_delete d "$k"; assert_rc 0 "delete chave $i"
    run sds_core_exists d "$k"; assert_rc 1 "chave $i removida"
    local j=0 k2
    for k2 in "${keys[@]}"; do
      if (( j > i )); then
        run sds_core_exists d "$k2"; assert_rc 0 "chave $j preservada após remover $i"
      fi
      j=$((j + 1))
    done
    i=$((i + 1))
  done
  expect_get "" o d
}

test_all_records_preserved_after_unrelated_write() {
  declare -A d=() before=()
  local i
  for i in 0 1 2 3 4; do
    run sds_core_assign d oooli "$i" servidores "s$i" portas 0; assert_rc 0
    run sds_core_assign d oooi "$i" servidores "s$i" id; assert_rc 0
  done
  snap d before
  run sds_core_assign d os novo extra; assert_rc 0
  local -n _b=before
  local k
  for k in "${!_b[@]}"; do
    [[ -n ${d[$k]+x} && ${d[$k]} == "${_b[$k]}" ]] || _fail "registro perdido/alterado"
  done
  assert_eq $(( ${#before[@]} + 1 )) "${#d[@]}"
  run sds_core_validate d; assert_rc 0
}

test_all_records_preserved_after_unrelated_delete() {
  declare -A d=() before=()
  local i
  for i in 0 1 2; do run sds_core_assign d oos "v$i" "a$i" x; assert_rc 0; done
  snap d before
  run sds_core_delete d a1; assert_rc 0
  local k
  for k in "${!before[@]}"; do
    sds_core_decode_key "$k"
    [[ ${SDS_D_SEGS[0]} == a1 ]] && continue
    [[ -n ${d[$k]+x} && ${d[$k]} == "${before[$k]}" ]] || _fail "registro perdido/alterado"
  done
  assert_eq 2 "${#d[@]}"
}

test_list_shift_with_nested_lists() {
  declare -A d=()
  local i
  for i in 0 1 2 3; do
    run sds_core_assign d los "n$i" "$i" nome; assert_rc 0
    run sds_core_assign d loli "$i" "$i" notas 0; assert_rc 0
    run sds_core_assign d loli "$((i * 10))" "$i" notas 1; assert_rc 0
  done
  run sds_core_delete d 1; assert_rc 0
  expect_get n0 s d 0 nome
  expect_get n2 s d 1 nome
  expect_get n3 s d 2 nome
  expect_get 20 i d 1 notas 1
  expect_get 30 i d 2 notas 1
  run sds_core_exists d 3; assert_rc 1
  run sds_core_validate d; assert_rc 0
  assert_eq 9 "${#d[@]}"
}

test_list_index_edge_cases() {
  declare -A d=()
  run sds_core_assign d ls a 0; assert_rc 0
  run sds_core_assign d ls a 1e3; assert_rc "$SDS_E_PATH"
  run sds_core_assign d ls a '+1'; assert_rc "$SDS_E_PATH"
  run sds_core_assign d ls a ' 1'; assert_rc "$SDS_E_PATH"
  run sds_core_assign d ls a ''; assert_rc "$SDS_E_PATH" "índice vazio"
  run sds_core_assign d ls a 1234567890; assert_rc "$SDS_E_PATH" "10 dígitos"
  run sds_core_assign d ls a $'1\n'; assert_rc "$SDS_E_PATH"
  assert_eq 1 "${#d[@]}"
}

test_object_numeric_looking_keys_are_strings() {
  declare -A d=()
  run sds_core_assign d os a 007; assert_rc 0
  run sds_core_assign d os b -1; assert_rc 0
  run sds_core_assign d os c 1e3; assert_rc 0
  expect_get a s d 007; expect_get b s d -1; expect_get c s d 1e3
}

test_root_scalar_each_type() {
  local t p
  for t in "s:txt" "i:1" "f:1.0" "b:false" "n:" "u:"; do
    declare -A d=()
    run sds_core_assign d "${t%%:*}" "${t#*:}"; assert_rc 0 "raiz ${t%%:*}"
    expect_get "${t#*:}" "${t%%:*}" d
    run sds_core_validate d; assert_rc 0
    run sds_core_exists d; assert_rc 0
  done
}

test_failed_operations_never_corrupt_complex_structure() {
  declare -A d=() saved=()
  run sds_core_assign d ols $'x\xff' lista 3
  run sds_core_assign d oos '' o 'a]b'
  run sds_core_assign d ou '' u
  snap d saved
  run sds_core_assign d ols x lista 3 extra; assert_rc "$SDS_E_TYPE" "tipos insuficientes"
  run sds_core_assign d ols x lista; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d olo x lista 4; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d os x lista; assert_rc "$SDS_E_CONFLICT"
  run sds_core_assign d oos x u a; assert_rc 0 "u promovido (operação válida)"
  # restaura e prova que as falhas anteriores não deixaram vestígios
  d=(); local k
  for k in "${!saved[@]}"; do d[$k]=${saved[$k]}; done
  run sds_core_delete d inexistente; assert_rc "$SDS_E_NOTFOUND"
  run sds_core_delete d lista 9; assert_rc "$SDS_E_NOTFOUND"
  run sds_core_delete d lista "x${sds_LP}"; assert_rc "$SDS_E_PATH"
  assert_same d saved
  run sds_core_validate d; assert_rc 0
}

test_failed_set_with_fill_leaves_no_fill() {
  declare -A d=() saved=()
  run sds_core_assign d os x k
  snap d saved
  local old=$sds_MAX_FILL; sds_MAX_FILL=3
  run sds_core_assign d ls v 9; assert_rc "$SDS_E_TYPE" "raiz divergente"
  run sds_core_assign d ols v k 9; assert_rc "$SDS_E_TYPE"
  sds_MAX_FILL=$old
  assert_same d saved
}

test_array_rebuild_keeps_all_unremoved_records() {
  declare -A d=() before=()
  local i
  for i in $(seq 0 49); do run sds_core_assign d os "v$i" "k$i"; done
  snap d before
  run sds_core_delete d k25; assert_rc 0
  assert_eq 49 "${#d[@]}"
  for i in $(seq 0 49); do
    (( i == 25 )) && continue
    expect_get "v$i" s d "k$i"
  done
  run sds_core_assign d os w k10; assert_rc 0
  assert_eq 49 "${#d[@]}"
}

test_operations_work_with_local_array_and_set_u() {
  set -u
  local -A loc=()
  run sds_core_assign loc os v a; assert_rc 0
  expect_get v s loc a
  run sds_core_delete loc a; assert_rc 0
  run sds_core_get loc x a; assert_rc "$SDS_E_NOTFOUND"
}

test_functions_do_not_leak_globals_or_change_locale() {
  declare -A d=()
  local before after
  before=$(compgen -v | sort | grep -v '^_\|^BASH_\|^FUNCNAME\|^SDS_\|^RC$\|^ERR$\|^LINENO\|^PIPESTATUS\|^OLDPWD\|^PWD')
  run sds_core_assign d ols v a 2
  run sds_core_delete d a 0
  run sds_core_validate d
  after=$(compgen -v | sort | grep -v '^_\|^BASH_\|^FUNCNAME\|^SDS_\|^RC$\|^ERR$\|^LINENO\|^PIPESTATUS\|^OLDPWD\|^PWD')
  assert_eq "$before" "$after" "variáveis globais"
}
````

## `tests/test_lists.sh`

````bash
# Listas (contiguidade, preenchimento, remoção), objetos e atomicidade.

list_values() { # NAME OUTVAR [seg...] -> "v0,v1,..." lendo índices 0..N-1
  local name=$1
  local -n _lv=$2
  shift 2
  local i=0 v acc=
  while sds_core_exists "$name" "$@" "$i" 2>/dev/null; do
    v='<container>'
    sds_core_get "$name" v "$@" "$i" 2>/dev/null
    if (( i > 0 )); then acc+=,; fi
    acc+=$v
    i=$((i + 1))
  done
  _lv=$acc
}

test_contiguous_list() {
  declare -A d=()
  local i
  for i in 0 1 2; do run sds_core_assign d ls "v$i" "$i"; assert_rc 0; done
  local out=; list_values d out
  assert_eq "v0,v1,v2" "$out"
  run sds_core_validate d; assert_rc 0
}

test_list_insert_beyond_end_fills_undefined() {
  declare -A d=()
  run sds_core_assign d ls last 3; assert_rc 0
  expect_get "" u d 0
  expect_get "" u d 1
  expect_get "" u d 2
  expect_get last s d 3
  run sds_core_exists d 2; assert_rc 0 "posição preenchida existe"
  run sds_core_exists d 4; assert_rc 1
  assert_eq 4 "${#d[@]}"
  run sds_core_validate d; assert_rc 0
}

test_list_fill_after_existing() {
  declare -A d=()
  run sds_core_assign d ls a 0
  run sds_core_assign d ls z 4; assert_rc 0
  expect_get a s d 0
  expect_get "" u d 1; expect_get "" u d 3
  expect_get z s d 4
  run sds_core_assign d ls m 2; assert_rc 0 "substitui undefined"
  expect_get m s d 2
  assert_eq 5 "${#d[@]}"
  run sds_core_validate d; assert_rc 0
}

test_nested_list_fill() {
  declare -A d=()
  run sds_core_assign d olls x lista 2 1; assert_rc 0
  expect_get "" u d lista 0
  expect_get "" u d lista 1
  run sds_core_is_list d lista 2; assert_rc 0
  expect_get "" u d lista 2 0
  expect_get x s d lista 2 1
  run sds_core_validate d; assert_rc 0
}

test_list_fill_limit() {
  declare -A d=() saved=()
  run sds_core_assign d ls a 0
  snap d saved
  local old=$sds_MAX_FILL
  sds_MAX_FILL=10
  run sds_core_assign d ls z 12; assert_rc "$SDS_E_LIMIT"
  run sds_core_assign d ls z 11000000000; assert_rc "$SDS_E_PATH" "índice enorme"
  sds_MAX_FILL=$old
  assert_same d saved
}

test_list_delete_shifts() {
  declare -A d=()
  local i
  for i in 0 1 2 3; do run sds_core_assign d ls "v$i" "$i"; done
  run sds_core_delete d 1; assert_rc 0
  local out=; list_values d out
  assert_eq "v0,v2,v3" "$out"
  assert_eq 3 "${#d[@]}"
  run sds_core_exists d 3; assert_rc 1
  run sds_core_validate d; assert_rc 0
  run sds_core_delete d 0; assert_rc 0
  list_values d out; assert_eq "v2,v3" "$out"
  run sds_core_delete d 1; assert_rc 0
  list_values d out; assert_eq "v2" "$out"
}

test_list_delete_shifts_subtrees() {
  declare -A d=()
  run sds_core_assign d los 10 0 a; assert_rc 0
  run sds_core_assign d los 20 1 a; assert_rc 0
  run sds_core_assign d los 30 2 a; assert_rc 0
  run sds_core_assign d loli 7 2 b 0; assert_rc 0
  run sds_core_delete d 0; assert_rc 0
  expect_get 20 s d 0 a
  expect_get 30 s d 1 a
  expect_get 7 i d 1 b 0
  run sds_core_exists d 2; assert_rc 1
  run sds_core_validate d; assert_rc 0
}

test_list_delete_last_leaves_empty_list() {
  declare -A d=()
  run sds_core_assign d ls only 0
  run sds_core_delete d 0; assert_rc 0
  expect_get "" l d
  assert_eq 1 "${#d[@]}"
  run sds_core_validate d; assert_rc 0
  run sds_core_assign d ls again 0; assert_rc 0 "reutilizável após esvaziar"
  expect_get again s d 0
}

test_nested_list_delete_last_leaves_empty_list() {
  declare -A d=()
  run sds_core_assign d ols x xs 0
  run sds_core_delete d xs 0; assert_rc 0
  expect_get "" l d xs
  run sds_core_is_list d xs; assert_rc 0
  run sds_core_validate d; assert_rc 0
}

test_object_delete_property_no_shift() {
  declare -A d=()
  run sds_core_assign d os 1 a; run sds_core_assign d os 2 b; run sds_core_assign d os 3 c
  run sds_core_delete d b; assert_rc 0
  run sds_core_exists d b; assert_rc 1
  expect_get 1 s d a
  expect_get 3 s d c
  assert_eq 2 "${#d[@]}"
}

test_object_delete_last_leaves_empty_object() {
  declare -A d=()
  run sds_core_assign d os 1 a
  run sds_core_delete d a; assert_rc 0
  expect_get "" o d
  run sds_core_validate d; assert_rc 0
}

test_object_numeric_keys_not_shifted() {
  declare -A d=()
  run sds_core_assign d os a 0; run sds_core_assign d os b 1; run sds_core_assign d os c 2
  run sds_core_delete d 0; assert_rc 0
  expect_get b s d 1
  expect_get c s d 2
  run sds_core_exists d 0; assert_rc 1
}

test_delete_subtree() {
  declare -A d=()
  run sds_core_assign d oos 1 a x; run sds_core_assign d oos 2 a y; run sds_core_assign d oos 3 b z
  run sds_core_delete d a; assert_rc 0
  run sds_core_exists d a; assert_rc 1
  run sds_core_exists d a x; assert_rc 1
  expect_get 3 s d b z
  assert_eq 1 "${#d[@]}"
}

test_delete_root_and_missing() {
  declare -A d=()
  run sds_core_delete d; assert_rc "$SDS_E_NOTFOUND" "estrutura vazia"
  run sds_core_assign d oos 1 a x
  run sds_core_delete d nada; assert_rc "$SDS_E_NOTFOUND"
  run sds_core_delete d a x y; assert_rc "$SDS_E_NOTFOUND"
  run sds_core_delete d; assert_rc 0
  assert_eq 0 "${#d[@]}"
}

test_delete_prefix_lookalike_not_removed() {
  declare -A d=()
  run sds_core_assign d os 1 ab; run sds_core_assign d os 2 a
  run sds_core_delete d a; assert_rc 0
  expect_get 1 s d ab
}

test_delete_noncanonical_index_is_not_found() {
  declare -A d=()
  run sds_core_assign d ls x 0
  run sds_core_delete d 00; assert_rc "$SDS_E_NOTFOUND"
  run sds_core_delete d abc; assert_rc "$SDS_E_NOTFOUND"
  expect_get x s d 0
}

# --- Tipificação inconsistente e conflitos -------------------------------

test_inconsistent_typing_rejected() {
  declare -A d=() saved=()
  run sds_core_assign d os 1 a; assert_rc 0
  snap d saved
  run sds_core_assign d ls 1 0; assert_rc "$SDS_E_TYPE" "raiz lista sobre raiz objeto"
  run sds_core_assign d ols x a 0; assert_rc "$SDS_E_TYPE" "a é terminal s, não lista"
  run sds_core_assign d oos x a b; assert_rc "$SDS_E_TYPE" "ancestral escalar"
  assert_same d saved
  run sds_core_assign d oos 1 m n; assert_rc 0
  snap d saved
  run sds_core_assign d ols 1 m 0; assert_rc "$SDS_E_TYPE" "m já é objeto"
  assert_same d saved
}

test_scalar_ancestor_conflict() {
  declare -A d=() saved=()
  run sds_core_assign d oi 1 a
  snap d saved
  run sds_core_assign d ooi 1 a b; assert_rc "$SDS_E_TYPE"
  assert_same d saved
}

test_descendants_conflict() {
  declare -A d=() saved=()
  run sds_core_assign d oos v a b
  snap d saved
  run sds_core_assign d os x a; assert_rc "$SDS_E_CONFLICT"
  run sds_core_assign d oi 1 a; assert_rc "$SDS_E_CONFLICT"
  run sds_core_assign d oo '' a; assert_rc 0 "mesmo tipo de contêiner: nada é descartado"
  assert_same d saved
}

test_root_scalar_blocks_children() {
  declare -A d=() saved=()
  run sds_core_assign d s x
  snap d saved
  run sds_core_assign d os y k; assert_rc "$SDS_E_TYPE"
  assert_same d saved
}

# --- Atomicidade ---------------------------------------------------------

test_failed_set_does_not_modify() {
  declare -A d=() saved=()
  run sds_core_assign d olos 1 a 0 x
  run sds_core_assign d olos 2 a 1 x
  snap d saved
  run sds_core_assign d olos 9 a 5 'x'"$sds_LP"; assert_rc "$SDS_E_PATH"
  run sds_core_assign d olls 9 a 1 0; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d oloX 9 a 5 x; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d oloi notnum a 5 x; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d oloi 9 a 05 x; assert_rc "$SDS_E_PATH"
  assert_same d saved
  run sds_core_validate d; assert_rc 0
}

test_failed_fill_does_not_leave_partial_fill() {
  declare -A d=() saved=()
  run sds_core_assign d ls a 0
  snap d saved
  # preenchimento válido seguido de payload inválido: nada pode ser gravado
  run sds_core_assign d li notnum 5; assert_rc "$SDS_E_TYPE"
  assert_same d saved
}

test_failed_delete_does_not_modify() {
  declare -A d=() saved=()
  run sds_core_assign d ls a 0; run sds_core_assign d ls b 1
  snap d saved
  run sds_core_delete d 7; assert_rc "$SDS_E_NOTFOUND"
  run sds_core_delete d "x${sds_LP}"; assert_rc "$SDS_E_PATH"
  assert_same d saved
}

test_set_replace_keeps_other_records() {
  declare -A d=()
  run sds_core_assign d os 1 a; run sds_core_assign d os 2 b
  run sds_core_assign d os 3 a; assert_rc 0
  expect_get 3 s d a
  expect_get 2 s d b
  assert_eq 2 "${#d[@]}"
}
````

## `tests/test_set.sh`

````bash
# Contrato de sds_core_set: operação ESTRUTURAL excepcional (renomear caminho
# existente e/ou mudar o tipo terminal). Não cria caminhos nem atualiza payload.
# Contrato PROVISÓRIO; ver docs/CORE.md.

K() { local __o; sds_core_make_key __o "$@" && printf '%s' "$__o"; }

fixture() { # NAME
  sds_core_init_data "$1" || return
  sds_core_assign "$1" ooos web1 servidor web1 nome &&
    sds_core_assign "$1" ooos http servidor web1 service &&
    sds_core_assign "$1" oooli 80 servidor web1 porta 0 &&
    sds_core_assign "$1" oooli 443 servidor web1 porta 1 &&
    sds_core_assign "$1" ooos web2 servidor web2 nome
}

# Falha de set: código esperado, armazenamento idêntico e índice coerente.
expect_set_fails() { # RC SAVED NAME OLDKEY NEWKEY
  run sds_core_set "$3" "$4" "$5"; assert_rc "$1"
  assert_same "$2" "$3"
  assert_consistent "$3"
}

test_rename_scalar() {
  declare -A d=() saved=()
  fixture d; snap d saved; plant_sentinel d
  run sds_core_set d "$(K ooos servidor web1 nome)" "$(K ooos servidor web1 identificacao)"; assert_rc 0
  expect_get web1 s d servidor web1 identificacao
  run sds_core_exists d servidor web1 nome; assert_rc 1
  assert_diff saved d 1 1 0
  assert_eq 5 "${#d[@]}"
  assert_no_rebuild d
  assert_consistent d
}

test_change_terminal_type_only() {
  declare -A d=() saved=()
  fixture d; snap d saved
  run sds_core_set d "$(K oooli servidor web1 porta 0)" "$(K oools servidor web1 porta 0)"; assert_rc 0
  expect_get 80 s d servidor web1 porta 0
  expect_get 443 i d servidor web1 porta 1
  assert_diff saved d 1 1 0
  assert_consistent d
}

test_rename_and_change_type_with_list_shift() {
  declare -A d=() saved=()
  fixture d; snap d saved
  run sds_core_set d "$(K oooli servidor web1 porta 0)" "$(K oooos servidor web1 servico porta)"; assert_rc 0
  expect_get 80 s d servidor web1 servico porta
  expect_get 443 i d servidor web1 porta 0
  run sds_core_exists d servidor web1 porta 1; assert_rc 1
  expect_get web1 s d servidor web1 nome
  expect_get web2 s d servidor web2 nome
  assert_eq 5 "${#d[@]}"
  assert_consistent d
}

test_rename_container_preserves_descendants() {
  declare -A d=() saved=()
  fixture d; snap d saved
  run sds_core_set d "$(K ooo servidor web1)" "$(K ooo servidor web3)"; assert_rc 0
  expect_get web1 s d servidor web3 nome
  expect_get http s d servidor web3 service
  expect_get 80 i d servidor web3 porta 0
  expect_get 443 i d servidor web3 porta 1
  expect_get web2 s d servidor web2 nome
  run sds_core_exists d servidor web1; assert_rc 1
  assert_diff saved d 4 4 0
  assert_eq 5 "${#d[@]}"
  assert_consistent d
}

test_rename_list_container() {
  declare -A d=()
  fixture d
  run sds_core_set d "$(K oool servidor web1 porta)" "$(K oool servidor web1 portas)"; assert_rc 0
  expect_get 80 i d servidor web1 portas 0
  expect_get 443 i d servidor web1 portas 1
  run sds_core_exists d servidor web1 porta; assert_rc 1
  assert_consistent d
}

test_reject_collision() {
  declare -A d=() saved=()
  fixture d; snap d saved
  expect_set_fails "$SDS_E_CONFLICT" saved d "$(K ooos servidor web1 nome)" "$(K ooos servidor web1 service)"
  expect_set_fails "$SDS_E_CONFLICT" saved d "$(K ooo servidor web1)" "$(K ooo servidor web2)"
}

test_reject_type_change_incompatible_with_descendants() {
  declare -A d=() saved=()
  fixture d; snap d saved
  expect_set_fails "$SDS_E_CONFLICT" saved d "$(K oool servidor web1 porta)" "$(K oooo servidor web1 porta)"
  expect_set_fails "$SDS_E_CONFLICT" saved d "$(K ooo servidor web1)" "$(K ool servidor web1)"
  expect_set_fails "$SDS_E_CONFLICT" saved d "$(K ooo servidor web1)" "$(K oos servidor web1)"
}

test_reject_intermediate_type_change() {
  declare -A d=() saved=()
  fixture d; snap d saved
  expect_set_fails "$SDS_E_TYPE" saved d "$(K ooos servidor web1 nome)" "$(K olos servidor 0 nome)"
  expect_set_fails "$SDS_E_TYPE" saved d "$(K ooos servidor web1 nome)" "$(K ools servidor web1 0)"
  expect_set_fails "$SDS_E_TYPE" saved d "$(K ooos servidor web1 nome)" "$(K oooos servidor web2 nome x)"
}

test_reject_missing_current_path() {
  declare -A d=() saved=()
  fixture d; snap d saved
  expect_set_fails "$SDS_E_NOTFOUND" saved d "$(K ooos servidor web1 nada)" "$(K ooos servidor web1 outro)"
}

test_reject_mismatched_current_type() {
  declare -A d=() saved=()
  fixture d; snap d saved
  expect_set_fails "$SDS_E_TYPE" saved d "$(K oooi servidor web1 nome)" "$(K ooos servidor web1 outro)"
}

test_reject_invalid_payload_for_new_type() {
  declare -A d=() saved=()
  fixture d; snap d saved
  expect_set_fails "$SDS_E_TYPE" saved d "$(K ooos servidor web1 nome)" "$(K oooi servidor web1 nome)"
  expect_set_fails "$SDS_E_TYPE" saved d "$(K ooos servidor web1 nome)" "$(K oooo servidor web1 nome)"
}

test_reject_same_list_move() {
  declare -A d=() saved=()
  fixture d; snap d saved
  expect_set_fails "$SDS_E_CONFLICT" saved d "$(K oooli servidor web1 porta 0)" "$(K oooli servidor web1 porta 5)"
  expect_set_fails "$SDS_E_CONFLICT" saved d "$(K oooli servidor web1 porta 0)" "$(K oooli servidor web1 porta 1)"
}

test_reject_move_into_own_subtree() {
  declare -A d=() saved=()
  fixture d; snap d saved
  expect_set_fails "$SDS_E_CONFLICT" saved d "$(K ooo servidor web1)" "$(K ooooo servidor web1 x y)"
}

test_rename_into_emptied_parent() {
  declare -A d=()
  sds_core_init_data d
  sds_core_assign d oos x a b
  run sds_core_set d "$(K oos a b)" "$(K ooos a c d)"; assert_rc 0
  expect_get x s d a c d
  run sds_core_exists d a b; assert_rc 1
  run sds_core_is_object d a; assert_rc 0
  assert_consistent d
}

test_rename_into_list_fills_gap() {
  declare -A d=()
  sds_core_init_data d
  sds_core_assign d oli 7 x 0
  sds_core_assign d os v y
  run sds_core_set d "$(K os y)" "$(K ols x 3)"; assert_rc 0
  expect_get 7 i d x 0
  expect_get '' u d x 1
  expect_get '' u d x 2
  expect_get v s d x 3
  run sds_core_exists d y; assert_rc 1
  assert_consistent d
}

test_set_same_key_is_noop() {
  declare -A d=() saved=()
  fixture d; snap d saved
  run sds_core_set d "$(K ooos servidor web1 nome)" "$(K ooos servidor web1 nome)"; assert_rc 0
  assert_same saved d
  assert_consistent d
}

test_change_type_of_empty_containers_and_scalars() {
  declare -A d=()
  sds_core_init_data d
  sds_core_assign d oo '' a
  run sds_core_set d "$(K oo a)" "$(K ol a)"; assert_rc 0
  run sds_core_is_list d a; assert_rc 0
  run sds_core_set d "$(K ol a)" "$(K os a)"; assert_rc 0
  expect_get '' s d a
  assert_consistent d
}

test_set_usage_and_malformed_keys() {
  declare -A d=() saved=()
  fixture d; snap d saved
  run sds_core_set d "$(K ooos servidor web1 nome)"; assert_rc "$SDS_E_USAGE"
  run sds_core_set d a b c; assert_rc "$SDS_E_USAGE"
  run sds_core_set d a b; assert_rc "$SDS_E_PATH"
  run sds_core_set d "$(K ooos servidor web1 nome)" "zzz"; assert_rc "$SDS_E_PATH"
  run sds_core_set nao_existe "$(K oos a b)" "$(K oos a c)"; assert_rc "$SDS_E_USAGE" "estrutura inexistente"
  assert_same saved d
  assert_consistent d
}

test_set_moves_subtree_out_of_list_shifts_siblings() {
  declare -A d=()
  sds_core_init_data d
  local i
  for i in 0 1 2; do sds_core_assign d olos "n$i" x "$i" nome; done
  run sds_core_set d "$(K olo x 1)" "$(K oo y)"; assert_rc 0
  expect_get n1 s d y nome
  expect_get n0 s d x 0 nome
  expect_get n2 s d x 1 nome
  run sds_core_exists d x 2; assert_rc 1
  assert_consistent d
}

test_set_localised() {
  declare -A d=()
  fixture d
  local i
  for i in $(seq 1 300); do sds_core_assign d os "v$i" "k$i"; done
  plant_sentinel d
  run sds_core_set d "$(K os k7)" "$(K os renomeado)"; assert_rc 0
  assert_no_rebuild d
  expect_get v7 s d renomeado
  assert_consistent d
}
````

## `tests/test_store.sh`

````bash
# Armazenamento e recuperação de valores, estados e caminhos.

test_root_object() {
  declare -A d=()
  run sds_core_assign d o ''; assert_rc 0
  expect_get "" o d
  run sds_core_is_object d; assert_rc 0
  run sds_core_is_list d; assert_rc 1
  run sds_core_is_terminal d; assert_rc 1 "contêiner vazio não é escalar"
  run sds_core_validate d; assert_rc 0
}

test_root_list() {
  declare -A d=()
  run sds_core_assign d l ''; assert_rc 0
  expect_get "" l d
  run sds_core_is_list d; assert_rc 0
  run sds_core_is_object d; assert_rc 1
}

test_root_scalar() {
  declare -A d=()
  run sds_core_assign d s 'olá'; assert_rc 0
  expect_get 'olá' s d
  run sds_core_is_terminal d; assert_rc 0
  run sds_core_validate d; assert_rc 0
  local key="s$sds_LT"
  assert_eq 'olá' "${d[$key]}" "chave da raiz escalar"
}

test_string() {
  declare -A d=()
  run sds_core_assign d os 'hello world' nome; assert_rc 0
  expect_get 'hello world' s d nome
  assert_eq 1 "${#d[@]}" "um único registro, sem nós intermediários"
  run sds_core_validate d; assert_rc 0
}

test_integer_preserves_text() {
  declare -A d=()
  run sds_core_assign d oi 12345678901234567890123 big; assert_rc 0
  expect_get 12345678901234567890123 i d big
  run sds_core_assign d oi -0 negzero; assert_rc 0
  expect_get -0 i d negzero
  run sds_core_assign d oi 0 zero; assert_rc 0
  expect_get 0 i d zero
}

test_float_preserves_text() {
  declare -A d=()
  local v
  for v in 10.0 10.50 -1.5e+10 1E3 0.1 3.14159265358979323846264338327950288; do
    run sds_core_assign d of "$v" x; assert_rc 0 "$v"
    expect_get "$v" f d x
  done
}

test_booleans() {
  declare -A d=()
  run sds_core_assign d ob true a; assert_rc 0
  run sds_core_assign d ob false b; assert_rc 0
  expect_get true b d a
  expect_get false b d b
}

test_null_undefined_empty_string_distinct() {
  declare -A d=()
  run sds_core_assign d on '' n; assert_rc 0
  run sds_core_assign d ou '' u; assert_rc 0
  run sds_core_assign d os '' s; assert_rc 0
  run sds_core_assign d oo '' o; assert_rc 0
  run sds_core_assign d ol '' l; assert_rc 0
  expect_get "" n d n
  expect_get "" u d u
  expect_get "" s d s
  expect_get "" o d o
  expect_get "" l d l
  run sds_core_exists d u; assert_rc 0 "undefined existe"
  run sds_core_exists d ausente; assert_rc 1 "ausente não existe"
  run sds_core_get d x ausente; assert_rc "$SDS_E_NOTFOUND"
  run sds_core_is_terminal d n; assert_rc 0
  run sds_core_is_terminal d u; assert_rc 0
  run sds_core_is_object d o; assert_rc 0
  run sds_core_is_list d l; assert_rc 0
  run sds_core_validate d; assert_rc 0
}

test_missing_path() {
  declare -A d=()
  run sds_core_assign d oos '1' a b; assert_rc 0
  run sds_core_exists d a; assert_rc 0 "ancestral existe"
  run sds_core_exists d a b; assert_rc 0
  run sds_core_exists d a c; assert_rc 1
  run sds_core_exists d a b c; assert_rc 1 "abaixo de escalar"
  run sds_core_exists d b; assert_rc 1
  run sds_core_exists d ""; assert_rc 1 "chave vazia ausente"
  local x=keep
  run sds_core_get d x a c; assert_rc "$SDS_E_NOTFOUND"
  assert_eq keep "$x" "saída não alterada"
  run sds_core_type d x a c; assert_rc "$SDS_E_NOTFOUND"
}

test_get_container_not_terminal() {
  declare -A d=()
  run sds_core_assign d oos '1' a b; assert_rc 0
  local x
  run sds_core_get d x a; assert_rc "$SDS_E_NOTTERMINAL"
  run sds_core_type d x a; assert_rc 0
  assert_eq o "$x"
  run sds_core_get d x; assert_rc "$SDS_E_NOTTERMINAL" "raiz não vazia"
}

test_nested_paths() {
  declare -A d=()
  run sds_core_assign d oooli 80 servidores web1 portas 0; assert_rc 0
  run sds_core_assign d oooli 443 servidores web1 portas 1; assert_rc 0
  run sds_core_assign d ooos ok servidores web2 estado; assert_rc 0
  expect_get 80 i d servidores web1 portas 0
  expect_get 443 i d servidores web1 portas 1
  expect_get ok s d servidores web2 estado
  local t
  run sds_core_type d t servidores web1 portas; assert_eq l "$t"
  run sds_core_type d t servidores web1; assert_eq o "$t"
  run sds_core_type d t servidores; assert_eq o "$t"
  run sds_core_type d t; assert_eq o "$t" "raiz"
  run sds_core_is_list d servidores web1 portas; assert_rc 0
  run sds_core_is_object d servidores web1; assert_rc 0
  run sds_core_is_terminal d servidores web1 portas 0; assert_rc 0
  assert_eq 3 "${#d[@]}"
  run sds_core_validate d; assert_rc 0
  local key="oooli${sds_LT}servidores${sds_LP}web1${sds_LP}portas${sds_LP}0"
  assert_eq 80 "${d[$key]}" "formato da chave canônica"
}

test_empty_key_and_special_keys() {
  declare -A d=()
  run sds_core_assign d os v ""; assert_rc 0
  run sds_core_assign d os w 'a]b'; assert_rc 0
  run sds_core_assign d os x '$HOME'; assert_rc 0
  run sds_core_assign d os y '*'; assert_rc 0
  run sds_core_assign d os z $'nova\nlinha'; assert_rc 0
  expect_get v s d ""
  expect_get w s d 'a]b'
  expect_get x s d '$HOME'
  expect_get y s d '*'
  expect_get z s d $'nova\nlinha'
  run sds_core_validate d; assert_rc 0
  run sds_core_delete d 'a]b'; assert_rc 0 "remover chave com ]"
  run sds_core_exists d 'a]b'; assert_rc 1
  expect_get v s d ""
}

test_empty_key_nested_vs_root() {
  declare -A d=()
  run sds_core_assign d oos v "" ""; assert_rc 0
  expect_get v s d "" ""
  run sds_core_exists d ""; assert_rc 0
  run sds_core_get d x; assert_rc "$SDS_E_NOTTERMINAL"
}

test_special_payloads() {
  declare -A d=()
  local -a vals=($'line1\nline2' $'tab\there' '$(echo pwn)' '`id`' '*?[a-z]' '"aspas" e '\''simples'\' $'\xff\xfe' $'inv\x80álido' '\n literal' '  espaços  ' $'fim\n' '-n' '--')
  local i=0 v got
  for v in "${vals[@]}"; do
    run sds_core_assign d os "$v" "k$i"; assert_rc 0 "set $i"
    run sds_core_get d got "k$i"; assert_rc 0
    assert_eq "$v" "$got" "payload especial $i"
    i=$((i + 1))
  done
  run sds_core_validate d; assert_rc 0
}

test_payload_with_delimiters_is_stored_verbatim() {
  declare -A d=()
  local v="a${sds_LT}b${sds_LP}c" got
  run sds_core_assign d os "$v" k; assert_rc 0
  run sds_core_get d got k; assert_eq "$v" "$got"
}

test_overwrite_and_retype() {
  declare -A d=()
  run sds_core_assign d os um k; assert_rc 0
  run sds_core_assign d os dois k; assert_rc 0 "mesmo tipo: atualiza payload"
  expect_get dois s d k
  run sds_core_assign d oi 2 k; assert_rc "$SDS_E_TYPE" "troca de tipo significativo por atribuição"
  expect_get dois s d k
  run sds_core_set d "os${sds_LT}k" "oi${sds_LT}k"; assert_rc "$SDS_E_TYPE" "payload 'dois' inválido como inteiro"
  run sds_core_assign d os 2 k
  run sds_core_set d "os${sds_LT}k" "oi${sds_LT}k"; assert_rc 0 "troca de tipo por set"
  expect_get 2 i d k
  assert_eq 1 "${#d[@]}" "registro antigo removido"
  run sds_core_assign d oi 3 k; assert_rc 0
  run sds_core_assign d s x; assert_rc "$SDS_E_CONFLICT" "raiz com descendentes não vira escalar"
  run sds_core_assign d o ''; assert_rc 0 "raiz objeto com descendentes: nada é descartado"
  expect_get 3 i d k
}

test_empty_container_becomes_nonempty() {
  declare -A d=()
  run sds_core_assign d oo '' cfg; assert_rc 0
  run sds_core_assign d oos v cfg a; assert_rc 0
  assert_eq 1 "${#d[@]}" "registro do contêiner vazio consumido"
  run sds_core_is_object d cfg; assert_rc 0
  expect_get v s d cfg a
  run sds_core_validate d; assert_rc 0
}

test_unicode_and_invalid_utf8_keys_under_utf8_locale() {
  declare -A d=()
  local old=${LC_ALL-}
  export LC_ALL=C.UTF-8
  run sds_core_assign d os 1 'ação'; assert_rc 0
  run sds_core_assign d os 2 $'inv\x80'; assert_rc 0
  expect_get 1 s d 'ação'
  expect_get 2 s d $'inv\x80'
  run sds_core_validate d; assert_rc 0
  [[ -n $old ]] && export LC_ALL=$old || unset LC_ALL
}

test_reserved_bytes_rejected() {
  declare -A d=()
  run sds_core_assign d os v "a${sds_LP}b"; assert_rc "$SDS_E_PATH"
  run sds_core_assign d os v "a${sds_LT}b"; assert_rc "$SDS_E_PATH"
  run sds_core_get d x "a${sds_LP}b"; assert_rc "$SDS_E_PATH"
  run sds_core_delete d "a${sds_LT}b"; assert_rc "$SDS_E_PATH"
  assert_eq 0 "${#d[@]}"
}

test_usage_errors() {
  declare -A d=()
  run sds_core_assign d o; assert_rc "$SDS_E_USAGE"
  run sds_core_get d; assert_rc "$SDS_E_USAGE"
  run sds_core_assign nao_existe s x; assert_rc "$SDS_E_USAGE" "array inexistente"
  run sds_core_get d '1x' ; assert_rc "$SDS_E_USAGE" "nome de saída inválido"
  run sds_core_exists; assert_rc "$SDS_E_USAGE"
  run sds_core_delete; assert_rc "$SDS_E_USAGE"
  run sds_core_validate; assert_rc "$SDS_E_USAGE"
}

test_validate_detects_corruption() {
  declare -A d=()
  d["s${sds_LT}"]=x
  d["os${sds_LT}a"]=y
  run sds_core_validate d; assert_rc "$SDS_E_CORRUPT" "raiz escalar com filhos"
  d=()
  d["os${sds_LT}a"]=1; d["ol${sds_LT}a"]=''
  run sds_core_validate d; assert_rc "$SDS_E_CORRUPT" "terminal e contêiner no mesmo nó"
  d=(); d["oi${sds_LT}a"]=abc
  run sds_core_validate d; assert_rc "$SDS_E_CORRUPT" "payload inválido"
  d=(); d["os${sds_LT}a"]=1; d["ls${sds_LT}a"]=1
  run sds_core_validate d; assert_rc "$SDS_E_CORRUPT" "raiz com tipos divergentes"
  d=(); d["ols${sds_LT}a${sds_LP}1"]=x
  run sds_core_validate d; assert_rc "$SDS_E_CORRUPT" "lista não contígua"
  d=(); d["lollipop"]=x
  run sds_core_validate d; assert_rc "$SDS_E_CORRUPT" "sem LT"
}

test_operations_reject_corrupt_data_without_changes() {
  declare -A d=() saved=()
  d["os${sds_LT}a"]=1
  d["garbage"]=x
  snap d saved
  run sds_core_assign d os 2 b; assert_rc "$SDS_E_CORRUPT"
  run sds_core_delete d a; assert_rc "$SDS_E_CORRUPT"
  run sds_core_exists d a; assert_rc "$SDS_E_CORRUPT"
  assert_same d saved
}

test_iteration_order_independence() {
  declare -A d=()
  local i
  for i in 9 3 7 0 5 1 8 2 6 4 10 11; do
    run sds_core_assign d ls "v$i" "$i"
  done
  # índices fora de ordem em lista que ainda não existe: preenchimento + validação
  run sds_core_validate d; assert_rc 0
  expect_get v10 s d 10
  expect_get v0 s d 0
}
````
