function pss
    for p in (pgrep -f $argv[1])
        grep '^Pss:' /proc/$p/smaps_rollup 2>/dev/null
    end | awk '{s+=$2} END {printf "%.1f MB\n", s/1024}'
end
