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
