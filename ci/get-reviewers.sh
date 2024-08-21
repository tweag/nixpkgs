#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p codeowners jq gitMinimal cacert

# This script gets the list of codeowning users and teams based on a codeowners file
# from a base commit and all files that have been changed since then.
# The result is suitable as input to the GitHub REST API call to request reviewers for a PR.
# This can be used to simulate the automatic codeowner review requests

set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' exit

if (( "$#" < 3 )); then
    echo "Usage: $0 LOCAL_REPO BASE_REF HEAD_REF OWNERS_FILE" >&2
    exit 1
fi
localRepo=$1
baseRef=$2
headRef=$3
ownersFile=$4

readarray -d '' -t touchedFiles < \
    <(
      # The names of all files, null-delimited, starting from HEAD, stopping before the base
      git -C "$localRepo" diff --name-only -z --merge-base "$baseRef" "$headRef" |
      # Remove duplicates
      sort -z --unique
    )

#echo "These files were touched: ${touchedFiles[*]}" >&2

# Get the owners file from the base, because we don't want to allow PRs to
# remove code owners to avoid pinging them
git show "$baseRef":"$ownersFile" > "$tmp"/codeowners

# Associative array, where the key is the team/user, while the value is "1"
# This makes it very easy to get deduplication
declare -A teams users

for file in "${touchedFiles[@]}"; do
    read -r file owners <<< "$(codeowners --file "$tmp"/codeowners "$file")"
    if [[ "$owners" == "(unowned)" ]]; then
        #echo "File $file doesn't have an owner" >&2
        continue
    fi
    #echo "Owner of $file is $owners" >&2

    # Split up multiple owners, separated by arbitrary amounts of spaces
    IFS=" " read -r -a entries <<< "$owners"

    for entry in "${entries[@]}"; do
        # GitHub technically also supports Emails as code owners,
        # but we can't easily support that, so let's not
        if [[ ! "$entry" =~ @(.*) ]]; then
            echo -e "\e[33mCodeowner \"$entry\" for file $file is not valid: Must start with \"@\"\e[0m" >&2
            # Don't fail, because the PR for which this script runs can't fix it,
            # it has to be fixed in the base branch
            continue
        fi
        # The first regex match is everything after the @
        entry=${BASH_REMATCH[1]}
        if [[ "$entry" == */* ]]; then
            # Only teams have a /
            teams[$entry]=1
        else
            # Everything else is a user
            users[$entry]=1
        fi
    done

done

# Turn it into a JSON for the GitHub API call to request PR reviewers
jq -n \
    --arg users "${!users[*]}" \
    --arg teams "${!teams[*]}" \
    '{
      reviewers: $users | split(" "),
      team_reviewers: $teams | split(" ")
    }'
