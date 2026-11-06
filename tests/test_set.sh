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
