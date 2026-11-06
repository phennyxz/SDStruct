#!/usr/bin/env bash
# Exemplos executáveis do núcleo SDStruct: bash review/example.sh
here=${BASH_SOURCE[0]}
if [[ $here == */* ]]; then here=${here%/*}; else here=.; fi
# shellcheck source=/dev/null
source "$here/../src/sdstruct.sh" || exit 2

show() { # mostra as chaves de forma legível (LT -> '|', LP -> '/') e o payload
  local -n _d=$1
  local k line
  for k in "${!_d[@]}"; do
    line=${k//"$sds_LT"/|}
    line=${line//"$sds_LP"/\/}
    printf '  %s = [%s]\n' "$line" "${_d[$k]}"
  done | LC_ALL=C sort
}

sds_init && echo "init ok (Bash $BASH_VERSION)"
sds_core_init_data data

echo "# 1. inserção tipada (um tipificador por nível, incluindo a raiz)"
sds_core_assign data oooli 80 servidores web1 portas 0
sds_core_assign data oooli 443 servidores web1 portas 1
sds_core_assign data ooos ativo servidores web2 estado
show data

echo "# 2. consulta"
sds_core_get data v servidores web1 portas 1 && echo "get portas/1 = $v"
sds_core_type data t servidores web1 portas && echo "type portas = $t"
sds_core_exists data servidores web9; echo "exists web9 -> rc=$?"
sds_core_get data v servidores web1; echo "get web1 (contêiner) -> rc=$?"

echo "# 3. undefined / null / string vazia / contêineres vazios"
declare -A est=()
sds_core_assign est ou '' u
sds_core_assign est on '' n
sds_core_assign est os '' s
sds_core_assign est oo '' o
sds_core_assign est ol '' l
show est

echo "# 4. preenchimento intermediário de lista"
declare -A lst=()
sds_core_assign lst ls fim 3
show lst

echo "# 5. u/n substituídos e promovidos"
sds_core_assign est oi 7 u        # u -> i
sds_core_assign est oos x n a     # n -> objeto com propriedade
show est

echo "# 6. remoção de elemento de lista desloca os seguintes"
declare -A l2=()
for i in 0 1 2 3; do sds_core_assign l2 ls "v$i" "$i"; done
sds_core_delete l2 1
for i in 0 1 2 3; do
  if sds_core_get l2 v "$i" 2>/dev/null; then echo "  [$i]=$v"; else echo "  [$i] ausente"; fi
done

echo "# 7. remoção de propriedade de objeto não desloca nada"
declare -A ob=()
sds_core_assign ob os 1 a; sds_core_assign ob os 2 b; sds_core_assign ob os 3 c
sds_core_delete ob b
show ob

echo "# 8. atribuir escalar sobre contêiner com descendentes é recusado (mudança de tipo só por set)"
sds_core_assign data os texto servidores; echo "rc=$?"

echo "# 9. byte reservado em segmento é recusado (escaping não aprovado)"
sds_core_assign data os x $'a\xfeb'; echo "rc=$?"

echo "# 10. payload com 0xFE/0xFF é aceito (campo separado)"
sds_core_assign data os $'\xfe\xff' bin && sds_core_get data v bin && printf '%s' "$v" | od -An -tx1

mk() { local o; sds_core_make_key o "$@" && printf '%s' "$o"; }

echo "# 11. atribuição cria vários níveis ausentes sem tocar nos demais registros"
declare -A srv=()
sds_core_assign srv ooos web1 servidor web1 nome
sds_core_assign srv oooli 80 servidor web1 porta 0
sds_core_assign srv oooli 443 servidor web1 porta 1
sds_core_assign srv oools admin servidor web1 user 0
show srv

echo "# 12. atribuição de mesmo tipo muda só o payload"
sds_core_assign srv oooli 8080 servidor web1 porta 0
show srv

echo "# 13. set: renomear escalar"
sds_core_set srv "$(mk ooos servidor web1 nome)" "$(mk ooos servidor web1 identificacao)"; echo "rc=$?"

echo "# 14. set: renomear e mudar o tipo terminal (porta/0 i -> servico/porta s); porta/1 desloca"
sds_core_set srv "$(mk oooli servidor web1 porta 0)" "$(mk oooos servidor web1 servico porta)"; echo "rc=$?"
show srv

echo "# 15. set: renomear contêiner preserva os descendentes"
sds_core_set srv "$(mk ooo servidor web1)" "$(mk ooo servidor web3)"; echo "rc=$?"
show srv

echo "# 16. set recusado: colisão, tipo de contêiner com descendentes, tipo intermediário, ausente"
sds_core_set srv "$(mk ooo servidor web3)" "$(mk oos servidor web3)"; echo "contêiner->s rc=$?"
sds_core_set srv "$(mk ooos servidor web3 identificacao)" "$(mk oooos servidor web3 servico porta)"; echo "colisão rc=$?"
sds_core_set srv "$(mk ooos servidor web3 identificacao)" "$(mk ools servidor web3 0)"; echo "intermediário (web3 objeto -> lista) rc=$?"
sds_core_set srv "$(mk ooos servidor web3 nada)" "$(mk ooos servidor web3 outro)"; echo "caminho atual ausente rc=$?"
show srv
