#!/usr/bin/env nix-shell
#!nix-shell -i bash -p coreutils moreutils -I nixpkgs=channel:nixpkgs-unstable

set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
NIXPKGS_PATH="$(readlink -f "$SCRIPT_DIR"/..)"

system="x86_64-linux"
quick_test=0
CORES=$(nproc)

parseArgs() {
    while [[ $# -gt 0 ]]; do
        arg=$1
        shift
        case "$arg" in
        --system)
            system=$1
            shift 1
            ;;
        --cores)
            CORES=$1
            shift 1
            ;;
        --quick-test)
            quick_test=1
            ;;
        *)
            echo "Unknown argument: $arg"
            exit 1
            ;;
        esac
    done
}

main() {
    parseArgs "$@"
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    nix-instantiate --eval --strict --json --arg enableWarnings false "$NIXPKGS_PATH"/pkgs/top-level/release-attrpaths-superset.nix -A paths >"$tmpdir/paths.json"

    # Originally @amjoseph: note that the number of processes spawned is four times
    # the number of cores -- this helps in two ways:
    # 1. Keeping cores busy while I/O operations are in flight
    # 2. Since the amount of time needed for the jobs is *not* balanced
    # this minimizes the "tail latency" for the very last job to finish
    # (on one core) by making the job size smaller.
    local num_chunks=$((4 * CORES))
    local seq_end=$((num_chunks - 1))
    if [[ $quick_test -eq 1 ]]; then
        seq_end=0
    fi

    (
        set +e
        seq 0 $seq_end | xargs -P "$CORES" -I {} nix-env -qaP --no-name --out-path --arg checkMeta true --arg includeBroken true \
            --arg systems "[\"$system\"]" \
            -f "$NIXPKGS_PATH"/ci/parallel.nix --arg attrPathFile "$tmpdir"/paths.json \
            --arg numChunks "$num_chunks" --show-trace --arg myChunk {} >"$tmpdir/paths"
        echo $? >"$tmpdir/exit-code"
    ) &
    pid=$!
    while kill -0 "$pid"; do
        free -g >&2
        sleep 20
    done
    jq --raw-input --slurp 'split("\n") | map(select(. != "") | split(" ") | map(select(. != "")) | { key: .[0], value: .[1] }) | from_entries' "$tmpdir/paths"
    exit "$(cat "$tmpdir/exit-code")"
}

main "$@"
