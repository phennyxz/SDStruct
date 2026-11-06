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
