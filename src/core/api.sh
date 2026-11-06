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
