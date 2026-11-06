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
