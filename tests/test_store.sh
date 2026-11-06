# Armazenamento e recuperação de valores, estados e caminhos.

test_root_object() {
  declare -A d=()
  run sds_core_assign d o ''; assert_rc 0
  expect_get "" o d
  run sds_core_is_object d; assert_rc 0
  run sds_core_is_list d; assert_rc 1
  run sds_core_is_terminal d; assert_rc 1 "contêiner vazio não é escalar"
  run sds_core_validate d; assert_rc 0
}

test_root_list() {
  declare -A d=()
  run sds_core_assign d l ''; assert_rc 0
  expect_get "" l d
  run sds_core_is_list d; assert_rc 0
  run sds_core_is_object d; assert_rc 1
}

test_root_scalar() {
  declare -A d=()
  run sds_core_assign d s 'olá'; assert_rc 0
  expect_get 'olá' s d
  run sds_core_is_terminal d; assert_rc 0
  run sds_core_validate d; assert_rc 0
  local key="s$sds_LT"
  assert_eq 'olá' "${d[$key]}" "chave da raiz escalar"
}

test_string() {
  declare -A d=()
  run sds_core_assign d os 'hello world' nome; assert_rc 0
  expect_get 'hello world' s d nome
  assert_eq 1 "${#d[@]}" "um único registro, sem nós intermediários"
  run sds_core_validate d; assert_rc 0
}

test_integer_preserves_text() {
  declare -A d=()
  run sds_core_assign d oi 12345678901234567890123 big; assert_rc 0
  expect_get 12345678901234567890123 i d big
  run sds_core_assign d oi -0 negzero; assert_rc 0
  expect_get -0 i d negzero
  run sds_core_assign d oi 0 zero; assert_rc 0
  expect_get 0 i d zero
}

test_float_preserves_text() {
  declare -A d=()
  local v
  for v in 10.0 10.50 -1.5e+10 1E3 0.1 3.14159265358979323846264338327950288; do
    run sds_core_assign d of "$v" x; assert_rc 0 "$v"
    expect_get "$v" f d x
  done
}

test_booleans() {
  declare -A d=()
  run sds_core_assign d ob true a; assert_rc 0
  run sds_core_assign d ob false b; assert_rc 0
  expect_get true b d a
  expect_get false b d b
}

test_null_undefined_empty_string_distinct() {
  declare -A d=()
  run sds_core_assign d on '' n; assert_rc 0
  run sds_core_assign d ou '' u; assert_rc 0
  run sds_core_assign d os '' s; assert_rc 0
  run sds_core_assign d oo '' o; assert_rc 0
  run sds_core_assign d ol '' l; assert_rc 0
  expect_get "" n d n
  expect_get "" u d u
  expect_get "" s d s
  expect_get "" o d o
  expect_get "" l d l
  run sds_core_exists d u; assert_rc 0 "undefined existe"
  run sds_core_exists d ausente; assert_rc 1 "ausente não existe"
  run sds_core_get d x ausente; assert_rc "$SDS_E_NOTFOUND"
  run sds_core_is_terminal d n; assert_rc 0
  run sds_core_is_terminal d u; assert_rc 0
  run sds_core_is_object d o; assert_rc 0
  run sds_core_is_list d l; assert_rc 0
  run sds_core_validate d; assert_rc 0
}

test_missing_path() {
  declare -A d=()
  run sds_core_assign d oos '1' a b; assert_rc 0
  run sds_core_exists d a; assert_rc 0 "ancestral existe"
  run sds_core_exists d a b; assert_rc 0
  run sds_core_exists d a c; assert_rc 1
  run sds_core_exists d a b c; assert_rc 1 "abaixo de escalar"
  run sds_core_exists d b; assert_rc 1
  run sds_core_exists d ""; assert_rc 1 "chave vazia ausente"
  local x=keep
  run sds_core_get d x a c; assert_rc "$SDS_E_NOTFOUND"
  assert_eq keep "$x" "saída não alterada"
  run sds_core_type d x a c; assert_rc "$SDS_E_NOTFOUND"
}

test_get_container_not_terminal() {
  declare -A d=()
  run sds_core_assign d oos '1' a b; assert_rc 0
  local x
  run sds_core_get d x a; assert_rc "$SDS_E_NOTTERMINAL"
  run sds_core_type d x a; assert_rc 0
  assert_eq o "$x"
  run sds_core_get d x; assert_rc "$SDS_E_NOTTERMINAL" "raiz não vazia"
}

test_nested_paths() {
  declare -A d=()
  run sds_core_assign d oooli 80 servidores web1 portas 0; assert_rc 0
  run sds_core_assign d oooli 443 servidores web1 portas 1; assert_rc 0
  run sds_core_assign d ooos ok servidores web2 estado; assert_rc 0
  expect_get 80 i d servidores web1 portas 0
  expect_get 443 i d servidores web1 portas 1
  expect_get ok s d servidores web2 estado
  local t
  run sds_core_type d t servidores web1 portas; assert_eq l "$t"
  run sds_core_type d t servidores web1; assert_eq o "$t"
  run sds_core_type d t servidores; assert_eq o "$t"
  run sds_core_type d t; assert_eq o "$t" "raiz"
  run sds_core_is_list d servidores web1 portas; assert_rc 0
  run sds_core_is_object d servidores web1; assert_rc 0
  run sds_core_is_terminal d servidores web1 portas 0; assert_rc 0
  assert_eq 3 "${#d[@]}"
  run sds_core_validate d; assert_rc 0
  local key="oooli${sds_LT}servidores${sds_LP}web1${sds_LP}portas${sds_LP}0"
  assert_eq 80 "${d[$key]}" "formato da chave canônica"
}

test_empty_key_and_special_keys() {
  declare -A d=()
  run sds_core_assign d os v ""; assert_rc 0
  run sds_core_assign d os w 'a]b'; assert_rc 0
  run sds_core_assign d os x '$HOME'; assert_rc 0
  run sds_core_assign d os y '*'; assert_rc 0
  run sds_core_assign d os z $'nova\nlinha'; assert_rc 0
  expect_get v s d ""
  expect_get w s d 'a]b'
  expect_get x s d '$HOME'
  expect_get y s d '*'
  expect_get z s d $'nova\nlinha'
  run sds_core_validate d; assert_rc 0
  run sds_core_delete d 'a]b'; assert_rc 0 "remover chave com ]"
  run sds_core_exists d 'a]b'; assert_rc 1
  expect_get v s d ""
}

test_empty_key_nested_vs_root() {
  declare -A d=()
  run sds_core_assign d oos v "" ""; assert_rc 0
  expect_get v s d "" ""
  run sds_core_exists d ""; assert_rc 0
  run sds_core_get d x; assert_rc "$SDS_E_NOTTERMINAL"
}

test_special_payloads() {
  declare -A d=()
  local -a vals=($'line1\nline2' $'tab\there' '$(echo pwn)' '`id`' '*?[a-z]' '"aspas" e '\''simples'\' $'\xff\xfe' $'inv\x80álido' '\n literal' '  espaços  ' $'fim\n' '-n' '--')
  local i=0 v got
  for v in "${vals[@]}"; do
    run sds_core_assign d os "$v" "k$i"; assert_rc 0 "set $i"
    run sds_core_get d got "k$i"; assert_rc 0
    assert_eq "$v" "$got" "payload especial $i"
    i=$((i + 1))
  done
  run sds_core_validate d; assert_rc 0
}

test_payload_with_delimiters_is_stored_verbatim() {
  declare -A d=()
  local v="a${sds_LT}b${sds_LP}c" got
  run sds_core_assign d os "$v" k; assert_rc 0
  run sds_core_get d got k; assert_eq "$v" "$got"
}

test_overwrite_and_retype() {
  declare -A d=()
  run sds_core_assign d os um k; assert_rc 0
  run sds_core_assign d os dois k; assert_rc 0 "mesmo tipo: atualiza payload"
  expect_get dois s d k
  run sds_core_assign d oi 2 k; assert_rc "$SDS_E_TYPE" "troca de tipo significativo por atribuição"
  expect_get dois s d k
  run sds_core_set d "os${sds_LT}k" "oi${sds_LT}k"; assert_rc "$SDS_E_TYPE" "payload 'dois' inválido como inteiro"
  run sds_core_assign d os 2 k
  run sds_core_set d "os${sds_LT}k" "oi${sds_LT}k"; assert_rc 0 "troca de tipo por set"
  expect_get 2 i d k
  assert_eq 1 "${#d[@]}" "registro antigo removido"
  run sds_core_assign d oi 3 k; assert_rc 0
  run sds_core_assign d s x; assert_rc "$SDS_E_CONFLICT" "raiz com descendentes não vira escalar"
  run sds_core_assign d o ''; assert_rc 0 "raiz objeto com descendentes: nada é descartado"
  expect_get 3 i d k
}

test_empty_container_becomes_nonempty() {
  declare -A d=()
  run sds_core_assign d oo '' cfg; assert_rc 0
  run sds_core_assign d oos v cfg a; assert_rc 0
  assert_eq 1 "${#d[@]}" "registro do contêiner vazio consumido"
  run sds_core_is_object d cfg; assert_rc 0
  expect_get v s d cfg a
  run sds_core_validate d; assert_rc 0
}

test_unicode_and_invalid_utf8_keys_under_utf8_locale() {
  declare -A d=()
  local old=${LC_ALL-}
  export LC_ALL=C.UTF-8
  run sds_core_assign d os 1 'ação'; assert_rc 0
  run sds_core_assign d os 2 $'inv\x80'; assert_rc 0
  expect_get 1 s d 'ação'
  expect_get 2 s d $'inv\x80'
  run sds_core_validate d; assert_rc 0
  [[ -n $old ]] && export LC_ALL=$old || unset LC_ALL
}

test_reserved_bytes_rejected() {
  declare -A d=()
  run sds_core_assign d os v "a${sds_LP}b"; assert_rc "$SDS_E_PATH"
  run sds_core_assign d os v "a${sds_LT}b"; assert_rc "$SDS_E_PATH"
  run sds_core_get d x "a${sds_LP}b"; assert_rc "$SDS_E_PATH"
  run sds_core_delete d "a${sds_LT}b"; assert_rc "$SDS_E_PATH"
  assert_eq 0 "${#d[@]}"
}

test_usage_errors() {
  declare -A d=()
  run sds_core_assign d o; assert_rc "$SDS_E_USAGE"
  run sds_core_get d; assert_rc "$SDS_E_USAGE"
  run sds_core_assign nao_existe s x; assert_rc "$SDS_E_USAGE" "array inexistente"
  run sds_core_get d '1x' ; assert_rc "$SDS_E_USAGE" "nome de saída inválido"
  run sds_core_exists; assert_rc "$SDS_E_USAGE"
  run sds_core_delete; assert_rc "$SDS_E_USAGE"
  run sds_core_validate; assert_rc "$SDS_E_USAGE"
}

test_validate_detects_corruption() {
  declare -A d=()
  d["s${sds_LT}"]=x
  d["os${sds_LT}a"]=y
  run sds_core_validate d; assert_rc "$SDS_E_CORRUPT" "raiz escalar com filhos"
  d=()
  d["os${sds_LT}a"]=1; d["ol${sds_LT}a"]=''
  run sds_core_validate d; assert_rc "$SDS_E_CORRUPT" "terminal e contêiner no mesmo nó"
  d=(); d["oi${sds_LT}a"]=abc
  run sds_core_validate d; assert_rc "$SDS_E_CORRUPT" "payload inválido"
  d=(); d["os${sds_LT}a"]=1; d["ls${sds_LT}a"]=1
  run sds_core_validate d; assert_rc "$SDS_E_CORRUPT" "raiz com tipos divergentes"
  d=(); d["ols${sds_LT}a${sds_LP}1"]=x
  run sds_core_validate d; assert_rc "$SDS_E_CORRUPT" "lista não contígua"
  d=(); d["lollipop"]=x
  run sds_core_validate d; assert_rc "$SDS_E_CORRUPT" "sem LT"
}

test_operations_reject_corrupt_data_without_changes() {
  declare -A d=() saved=()
  d["os${sds_LT}a"]=1
  d["garbage"]=x
  snap d saved
  run sds_core_assign d os 2 b; assert_rc "$SDS_E_CORRUPT"
  run sds_core_delete d a; assert_rc "$SDS_E_CORRUPT"
  run sds_core_exists d a; assert_rc "$SDS_E_CORRUPT"
  assert_same d saved
}

test_iteration_order_independence() {
  declare -A d=()
  local i
  for i in 9 3 7 0 5 1 8 2 6 4 10 11; do
    run sds_core_assign d ls "v$i" "$i"
  done
  # índices fora de ordem em lista que ainda não existe: preenchimento + validação
  run sds_core_validate d; assert_rc 0
  expect_get v10 s d 10
  expect_get v0 s d 0
}
