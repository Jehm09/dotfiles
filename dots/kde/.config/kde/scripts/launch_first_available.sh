#!/usr/bin/env bash
# Lanza el primer comando cuyo binario esté disponible.
# Cada arg se ejecuta vía `bash -c` para que respete variables ($qsConfig, ~) y
# operadores ($'&& || ;'). Caso especial: "command -v X && Y" verifica X
# (en vez del literal "command") y ejecuta Y.
for cmd in "$@"; do
    [[ -z "$cmd" ]] && continue
    if [[ "$cmd" == "command -v "*" && "* ]]; then
        after="${cmd#command -v }"
        bin="${after%% *}"
        rest="${after#* && }"
    else
        bin="${cmd%% *}"
        rest="$cmd"
    fi
    command -v "$bin" >/dev/null 2>&1 || continue
    exec bash -c "$rest"
done
exit 1
