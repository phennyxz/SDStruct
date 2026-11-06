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
