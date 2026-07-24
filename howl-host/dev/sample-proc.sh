#!/usr/bin/env bash
set -euo pipefail

if (($# < 1 || $# > 3)) || [[ ! $1 =~ ^[1-9][0-9]*$ ]]; then
    echo "usage: dev/sample-proc.sh <howl-host-pid> [warmup-seconds [sample-seconds]]" >&2
    exit 2
fi

pid=$1
warmup=${2:-10}
sample=${3:-60}
if [[ ! $warmup =~ ^[0-9]+$ || ! $sample =~ ^[1-9][0-9]*$ ]]; then
    echo "warmup must be nonnegative and sample must be positive" >&2
    exit 2
fi
if [[ ! -r /proc/$pid/stat || ! -r /proc/$pid/status ]]; then
    echo "process $pid is not readable" >&2
    exit 1
fi

output=.zig/work/howl-proc.tsv
mkdir -p .zig/work
printf 'second\tphase\tkind\ttid\tstate\tutime\tstime\tminflt\tmajflt\trss_kib\tvoluntary\tinvoluntary\tthreads\n' >"$output"

end=$((warmup + sample))
read -r started _ </proc/uptime
for ((second = 0; second <= end; second++)); do
    [[ -r /proc/$pid/stat ]] || break
    phase=warmup
    ((second >= warmup)) && phase=sample
    status=/proc/$pid/status
    stat=/proc/$pid/stat
    read -r minflt majflt utime stime state < <(
        awk '{print $10, $12, $14, $15, $3}' "$stat"
    )
    read -r rss voluntary involuntary threads < <(
        awk '
            /^VmRSS:/ { rss=$2 }
            /^voluntary_ctxt_switches:/ { voluntary=$2 }
            /^nonvoluntary_ctxt_switches:/ { involuntary=$2 }
            /^Threads:/ { threads=$2 }
            END { print rss+0, voluntary+0, involuntary+0, threads+0 }
        ' "$status"
    )
    printf '%d\t%s\tprocess\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$second" "$phase" "$pid" "$state" "$utime" "$stime" "$minflt" "$majflt" \
        "$rss" "$voluntary" "$involuntary" "$threads" >>"$output"

    for task in /proc/"$pid"/task/[0-9]*; do
        [[ -r $task/stat && -r $task/status ]] || continue
        tid=${task##*/}
        read -r task_utime task_stime task_state < <(
            awk '{print $14, $15, $3}' "$task/stat"
        )
        read -r task_voluntary task_involuntary < <(
            awk '
                /^voluntary_ctxt_switches:/ { voluntary=$2 }
                /^nonvoluntary_ctxt_switches:/ { involuntary=$2 }
                END { print voluntary+0, involuntary+0 }
            ' "$task/status"
        )
        printf '%d\t%s\tthread\t%d\t%s\t%s\t%s\t0\t0\t0\t%s\t%s\t0\n' \
            "$second" "$phase" "$tid" "$task_state" "$task_utime" "$task_stime" \
            "$task_voluntary" "$task_involuntary" >>"$output"
    done
    if ((second != end)); then
        read -r now _ </proc/uptime
        delay=$(awk -v start="$started" -v elapsed="$((second + 1))" -v now="$now" \
            'BEGIN { delay = start + elapsed - now; print (delay > 0 ? delay : 0) }')
        sleep "$delay"
    fi
done

echo "$output"
