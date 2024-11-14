#!/usr/bin/env nix-shell
#!nix-shell -i bash -p moreutils -I nixpkgs=channel:nixpkgs-unstable

set -euxo pipefail

system="x86_64-linux"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
NIXPKGS_PATH="$(readlink -f "$SCRIPT_DIR"/..)"

parseArgs() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --system)
        system=$2
        shift 2
        ;;
      *)
        echo "Unknown argument: $1"
        exit 1
        ;;
    esac
  done
}

main() {
    parseArgs "$@"
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    nix-instantiate --eval --strict --json --arg enableWarnings false "$NIXPKGS_PATH"/pkgs/top-level/release-attrpaths-superset.nix -A paths > "$tmpdir/paths.json"

    CORES=$(nproc)
    # Originally @amjoseph: note that the number of processes spawned is four times
    # the number of cores -- this helps in two ways:
    # 1. Keeping cores busy while I/O operations are in flight
    # 2. Since the amount of time needed for the jobs is *not* balanced
    # this minimizes the "tail latency" for the very last job to finish
    # (on one core) by making the job size smaller.
    NUM_CHUNKS=$(( 4 * CORES ))


    (
      set +e
      parallel -j "$CORES" \
          nix-env -qaP --no-name --out-path --arg checkMeta true --arg includeBroken true \
          --arg systems "[\"$system\"]" \
          -f "$NIXPKGS_PATH"/ci/parallel.nix --arg attrPathFile "$tmpdir"/paths.json \
          --arg numChunks "$NUM_CHUNKS" --show-trace --arg myChunk \
          -- $(seq 0 $(( NUM_CHUNKS - 1 ))) > "$tmpdir/paths"
      echo $? > "$tmpdir/exit-code"
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
