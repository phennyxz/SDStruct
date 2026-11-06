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
