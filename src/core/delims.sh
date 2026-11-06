# SDStruct core — delimitadores globais e verificação do ambiente.

# Padrões documentados em docs/CANONICAL-FORMAT.md. Só definidos se ainda não
# existirem, de forma análoga ao IFS.
[[ -v sds_LT ]] || sds_LT=$'\xff'   # separa tipificadores do caminho
[[ -v sds_LP ]] || sds_LP=$'\xfe'   # separa segmentos do caminho

# Limite PROVISÓRIO de posições "undefined" criadas por um único preenchimento
# de lista (proteção contra exaustão de memória). Os limites oficiais ainda
# não foram especificados.
[[ -v sds_MAX_FILL ]] || sds_MAX_FILL=100000

# sds_check_delims — valida sds_LT, sds_LP e sds_MAX_FILL.
sds__impl_check_delims() {
  local LC_ALL=C
  if [[ ! -v sds_LT || ! -v sds_LP ]]; then
    sds__fail "$SDS_E_ENV" "sds_LT/sds_LP não definidos"
    return
  fi
  if (( ${#sds_LT} != 1 || ${#sds_LP} != 1 )); then
    sds__fail "$SDS_E_ENV" "sds_LT e sds_LP devem conter exatamente um byte"
    return
  fi
  if [[ $sds_LT == "$sds_LP" ]]; then
    sds__fail "$SDS_E_ENV" "sds_LT e sds_LP devem ser distintos"
    return
  fi
  if [[ $sds_LT == [olsifbnu] || $sds_LP == [olsifbnu] ]]; then
    sds__fail "$SDS_E_ENV" "delimitadores não podem coincidir com tipificadores"
    return
  fi
  if [[ ! $sds_MAX_FILL =~ ^[0-9]+$ ]]; then
    sds__fail "$SDS_E_ENV" "sds_MAX_FILL deve ser um inteiro não negativo"
    return
  fi
  return 0
}

# sds_init — verifica a versão do Bash e os delimitadores.
sds__impl_init() {
  if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    sds__fail "$SDS_E_ENV" "Bash 4.3 ou superior é necessário (atual: $BASH_VERSION)"
    return
  fi
  sds_check_delims
}
