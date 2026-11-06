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
