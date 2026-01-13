#!/usr/bin/env nix-shell
#!nix-shell -i bash -p yj

set -euo pipefail

for shard in pkgs/by-name/*; do
  if [[ -f "$shard" ]]; then
    continue
  fi
  for package in "$shard"/*; do
    attr=$(basename "$package")
    echo "Processing $attr"
    meta=$(nix-instantiate --eval --strict --json . -A "$attr".meta)
    jq 'pick(.description, .longDescription)' <<< "$meta" | yj -jt > "$package"/meta.toml
  done
done
