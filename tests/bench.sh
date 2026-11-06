#!/usr/bin/env bash
# Benchmark do núcleo: bash tests/bench.sh
# Metodologia: cada item usa um armazenamento novo e é cronometrado com
# $EPOCHREALTIME (tempo de parede) em uma única execução; o custo por operação
# é derivado. Não há metas de velocidade; os números dependem da máquina.
set -u
here=${BASH_SOURCE[0]}
if [[ $here == */* ]]; then here=${here%/*}; else here=.; fi
# shellcheck source=/dev/null
source "$here/../src/sdstruct.sh" || exit 2

now() { local t=${EPOCHREALTIME/[.,]/}; printf '%s' "$t"; }
report() { # TÍTULO INÍCIO FIM OPS
  local us=$(($3 - $2))
  printf '%-58s %7d ms %8d us/op (%d ops)\n' "$1" $((us / 1000)) $((us / $4)) "$4"
}
fill() { # NAME N — N escalares na raiz objeto
  local i
  for ((i = 0; i < $2; i++)); do sds_core_assign "$1" os "v$i" "k$i" || exit 1; done
}
K() { local o; sds_core_make_key o "$@" && printf '%s' "$o"; }

printf 'Bash %s | %s | LC_ALL=%s\n' "$BASH_VERSION" "$(uname -sr)" "${LC_ALL-<não definido>}"
sds_init || exit 2

for n in 100 500 1000 5000; do
  sds_core_init_data d
  a=$(now); fill d "$n"; b=$(now)
  report "1. inserir $n caminhos novos (1 nível)" "$a" "$b" "$n"
done

sds_core_init_data d; fill d 1000
a=$(now)
for ((i = 0; i < 1000; i++)); do sds_core_assign d os "novo$i" "k$i" || exit 1; done
b=$(now)
report "2. atualizar 1000 payloads existentes (loja de 1000)" "$a" "$b" 1000

# 3. profundidade: N ancestrais já existentes + folha nova; depois ancestrais novos.
for depth in 1 3 6 10; do
  segs=() types=o
  for ((j = 0; j < depth; j++)); do segs+=("n$j"); types+=o; done
  sds_core_init_data d
  a=$(now)
  for ((i = 0; i < 200; i++)); do
    sds_core_assign d "${types}s" v "${segs[@]}" "x$i" || exit 1
  done
  b=$(now)
  report "3a. 200 folhas sob ancestrais existentes, prof. $((depth + 1))" "$a" "$b" 200
  sds_core_init_data d
  a=$(now)
  for ((i = 0; i < 200; i++)); do
    sds_core_assign d "${types}os" v "t$i" "${segs[@]}" "x" || exit 1
  done
  b=$(now)
  report "3b. 200 caminhos com $((depth + 1)) níveis novos cada" "$a" "$b" 200
done

sds_core_init_data d; fill d 1000
a=$(now)
for ((i = 0; i < 100; i++)); do sds_core_delete d "k$i" || exit 1; done
b=$(now)
report "4. remover 100 escalares (loja de 1000)" "$a" "$b" 100

for n in 10 1000; do
  sds_core_init_data d
  for ((i = 0; i < n; i++)); do sds_core_assign d ls "v$i" "$i" || exit 1; done
  a=$(now); sds_core_delete d 0 || exit 1; b=$(now)
  report "5. remover o 1o elemento de lista de $n (desloca $((n - 1)))" "$a" "$b" 1
  a=$(now); sds_core_delete d $((n - 2)) || exit 1; b=$(now)
  report "5. remover o penúltimo de lista de $n (desloca 1)" "$a" "$b" 1
done

sds_core_init_data d; fill d 1000
a=$(now)
for ((i = 0; i < 100; i++)); do
  sds_core_set d "$(K os "k$i")" "$(K os "r$i")" || exit 1
done
b=$(now)
report "6a. set: renomear 100 escalares (loja de 1000)" "$a" "$b" 100
a=$(now)
for ((i = 100; i < 200; i++)); do
  sds_core_set d "$(K os "k$i")" "$(K ol "k$i")" 2>/dev/null
done
b=$(now)
report "6b. set: tipo terminal s->l (rejeitado: payload não vazio, 100 tentativas)" "$a" "$b" 100

# 7. renomeação de subárvore: contêiner com N descendentes dentro de loja de 1000.
for n in 10 100 500; do
  sds_core_init_data d; fill d 1000
  for ((i = 0; i < n; i++)); do sds_core_assign d oos v sub "k$i" || exit 1; done
  a=$(now); sds_core_set d "$(K oo sub)" "$(K oo sub2)" || exit 1; b=$(now)
  report "7. renomear subárvore de $n descendentes (loja de $((1000 + n)))" "$a" "$b" 1
done
