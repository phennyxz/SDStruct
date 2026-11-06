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
