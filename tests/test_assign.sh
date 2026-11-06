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
