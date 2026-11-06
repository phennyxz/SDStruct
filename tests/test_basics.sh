# Delimitadores, inicialização, chaves e validação de payloads.

test_delims_defaults() {
  assert_eq $'\xff' "$sds_LT" "sds_LT"
  assert_eq $'\xfe' "$sds_LP" "sds_LP"
  run sds_init; assert_rc 0
}

test_delims_invalid() {
  local old=$sds_LT
  sds_LT=; run sds_check_delims; assert_rc "$SDS_E_ENV" "vazio"
  sds_LT=ab; run sds_check_delims; assert_rc "$SDS_E_ENV" "2 bytes"
  sds_LT=$sds_LP; run sds_check_delims; assert_rc "$SDS_E_ENV" "iguais"
  sds_LT=o; run sds_check_delims; assert_rc "$SDS_E_ENV" "igual a tipificador"
  sds_LT=$old
  unset sds_LP; run sds_check_delims; assert_rc "$SDS_E_ENV" "indefinido"
}

test_delims_checked_by_operations() {
  declare -A d=(); sds_LP=; 
  run sds_core_assign d o '' ; assert_rc "$SDS_E_ENV"
  (( ${#d[@]} == 0 )) || _fail "não deveria gravar"
}

test_init_data() {
  run sds_core_init_data dd; assert_rc 0
  [[ $(declare -p dd) == "declare -A dd"* ]] || _fail "dd deveria ser associativo"
  dd[x]=1
  run sds_core_init_data dd; assert_rc 0
  assert_eq 0 "${#dd[@]}" "reinicialização esvazia"
  plain=1
  run sds_core_init_data plain; assert_rc "$SDS_E_USAGE" "variável não associativa"
  run sds_core_init_data '1bad'; assert_rc "$SDS_E_USAGE"
  run sds_core_init_data '__sds_x'; assert_rc "$SDS_E_USAGE" "prefixo reservado"
}

test_make_key_and_decode() {
  local key
  run sds_core_make_key key oooli servidores web1 portas 0; assert_rc 0
  assert_eq "oooli${sds_LT}servidores${sds_LP}web1${sds_LP}portas${sds_LP}0" "$key"
  run sds_core_decode_key "$key"; assert_rc 0
  assert_eq oooli "$SDS_D_TYPES"; assert_eq 4 "$SDS_D_N"
  assert_eq "servidores|web1|portas|0" "$(IFS='|'; echo "${SDS_D_SEGS[*]}")"
}

test_make_key_root() {
  local key
  run sds_core_make_key key s; assert_rc 0
  assert_eq "s$sds_LT" "$key" "raiz tem tipificador e LT"
  run sds_core_decode_key "$key"; assert_rc 0
  assert_eq 0 "$SDS_D_N"; assert_eq 0 "${#SDS_D_SEGS[@]}"
}

test_make_key_empty_segment() {
  local key
  run sds_core_make_key key os ""; assert_rc 0
  run sds_core_decode_key "$key"; assert_rc 0
  assert_eq 1 "${#SDS_D_SEGS[@]}"; assert_eq "" "${SDS_D_SEGS[0]}"
  run sds_core_make_key key oos "" ""; assert_rc 0
  run sds_core_decode_key "$key"; assert_rc 0
  assert_eq 2 "${#SDS_D_SEGS[@]}"
}

test_make_key_invalid() {
  local key=orig
  run sds_core_make_key key ol; assert_rc "$SDS_E_TYPE" "tipos sem segmentos"
  run sds_core_make_key key osx a; assert_rc "$SDS_E_TYPE" "tipos a mais"
  run sds_core_make_key key ss a; assert_rc "$SDS_E_TYPE" "nível intermediário escalar"
  run sds_core_make_key key xs a; assert_rc "$SDS_E_TYPE" "tipificador desconhecido"
  run sds_core_make_key key ls 01; assert_rc "$SDS_E_PATH" "índice com zero à esquerda"
  run sds_core_make_key key ls -1; assert_rc "$SDS_E_PATH" "índice negativo"
  run sds_core_make_key key ls abc; assert_rc "$SDS_E_PATH" "índice não numérico"
  run sds_core_make_key key os "a${sds_LP}b"; assert_rc "$SDS_E_PATH" "LP no segmento"
  run sds_core_make_key key os "a${sds_LT}b"; assert_rc "$SDS_E_PATH" "LT no segmento"
  assert_eq orig "$key" "saída intocada em erro"
}

test_decode_malformed() {
  run sds_core_decode_key "semlt"; assert_rc "$SDS_E_CORRUPT"
  run sds_core_decode_key "${sds_LT}x"; assert_rc "$SDS_E_CORRUPT" "sem tipificador"
  run sds_core_decode_key "os${sds_LT}a${sds_LP}b"; assert_rc "$SDS_E_CORRUPT" "segmentos a mais"
  run sds_core_decode_key "o${sds_LT}a"; assert_rc "$SDS_E_CORRUPT" "segmentos a mais (raiz)"
  run sds_core_decode_key "ss${sds_LT}a"; assert_rc "$SDS_E_CORRUPT" "intermediário escalar"
  run sds_core_decode_key "ls${sds_LT}x"; assert_rc "$SDS_E_CORRUPT" "índice inválido"
  run sds_core_decode_key "os${sds_LT}a${sds_LT}b"; assert_rc "$SDS_E_CORRUPT" "dois LT"
  run sds_core_decode_key; assert_rc "$SDS_E_USAGE"
}

test_payload_validation() {
  declare -A d=()
  run sds_core_assign d i 1.5; assert_rc "$SDS_E_TYPE" "int com fração"
  run sds_core_assign d i 01; assert_rc "$SDS_E_TYPE" "int com zero à esquerda"
  run sds_core_assign d i ""; assert_rc "$SDS_E_TYPE" "int vazio"
  run sds_core_assign d i "1 "; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d i $'1\n2'; assert_rc "$SDS_E_TYPE" "int multilinha"
  run sds_core_assign d f 10; assert_rc "$SDS_E_TYPE" "float sem fração/expoente"
  run sds_core_assign d f 1.; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d f .5; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d b yes; assert_rc "$SDS_E_TYPE"
  run sds_core_assign d n x; assert_rc "$SDS_E_TYPE" "null com payload"
  run sds_core_assign d u x; assert_rc "$SDS_E_TYPE" "undefined com payload"
  run sds_core_assign d o x; assert_rc "$SDS_E_TYPE" "objeto com payload"
  run sds_core_assign d l x; assert_rc "$SDS_E_TYPE" "lista com payload"
  assert_eq 0 "${#d[@]}" "nada gravado"
}
