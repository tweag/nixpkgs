#!/usr/bin/env bash

set -euo pipefail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' exit
SCRIPT_DIR=$(dirname "$0")

baseRepo=$1
prNumber=$2
ownersFile=$3

prInfo=$(gh api \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/$baseRepo/pulls/$prNumber")

baseBranch=$(jq -r .base.ref <<< "$prInfo")
prRepo=$(jq -r .head.repo.full_name <<< "$prInfo")
prBranch=$(jq -r .head.ref <<< "$prInfo")

headRef=refs/remotes/fork/pr

git clone --bare --filter=tree:0 --no-tags --origin upstream https://github.com/"$baseRepo".git "$tmp"/nixpkgs.git
# Fetch the PR
git -C "$tmp/nixpkgs.git" remote add fork https://github.com/"$prRepo".git
# Make sure we only fetch the commit history, nothing else
git -C "$tmp/nixpkgs.git" config remote.fork.promisor true
git -C "$tmp/nixpkgs.git" config remote.fork.partialclonefilter tree:0
# Only fetch into a remote ref, because the local ref namespace is used by Nixpkgs, don't want any conflicts
git -C "$tmp/nixpkgs.git" fetch --no-tags fork "$prBranch":"$headRef"


"$SCRIPT_DIR"/verify-base-branch.sh "$tmp/nixpkgs.git" "$headRef" "$baseRepo" "$baseBranch" "$prRepo" "$prBranch"

reviewersJSON=$("$SCRIPT_DIR"/get-reviewers.sh "$tmp/nixpkgs.git" "$baseBranch" "$headRef" "$ownersFile")

echo "$reviewersJSON"
exit 0

curl -L \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/"$baseRepo"/pulls/"$prNumber"/requested_reviewers \
  -d "$reviewersJSON"
