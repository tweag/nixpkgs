#!/usr/bin/env nix-shell
#!nix-shell -i bash --pure -p gitMinimal cacert

# This script Checks that a PR doesn't include commits that are already in other development branches
# This commonly happens when users pick the wrong base branch for a PR

set -euo pipefail

# Small helper to check whether an element is in a list
# Usage: `elementIn foo "${list[@]}"`
elementIn() {
    local e match=$1
    shift
    for e; do
        if [[ "$e" == "$match" ]]; then
            return 0
        fi
    done
    return 1
}

if (( $# < 5 )); then
    echo "Usage: $0 LOCAL_REPO PR_HEAD_REF BASE_REPO BASE_BRANCH PR_REPO PR_BRANCH"
    exit 1
fi
localRepo=$1
headRef=$2
baseRepo=$3
baseBranch=$4
prRepo=$5
prBranch=$6

readarray -t developmentBranches < <(git -C "$localRepo" branch --list --format "%(refname:short)" {master,staging{,-next}} 'release-*' 'staging-*' 'staging-next-*')

if ! elementIn "$baseBranch" "${developmentBranches[@]}"; then
    echo "PR does not go to any base branch among (${developmentBranches[*]}), no commit check necessary" >&2
    exit 0
fi

if [[ "$baseRepo" == "$prRepo" ]] && elementIn "$prBranch" "${developmentBranches[@]}"; then
    echo "This is a merge of $prBranch into $baseBranch, no commit check necessary" >&2
    exit 0
fi

for branch in "${developmentBranches[@]}"; do

    if [[ -z "$(git -C "$localRepo" rev-list -1 --since="1 year ago" "$branch")" ]]; then
        # Skip branches that haven't been active for a year
        continue
    fi
    echo "Checking for extra commits from branch $branch" >&2

    # The first ancestor of the PR head that already exists in the other branch
    mergeBase=$(git -C "$localRepo" merge-base "$headRef" "$branch")

    # The number of commits that are reachable from the PR head, not reachable from the PRs base branch
    # (up to here this would be the number of commits in the PR itself),
    # but that are _also_ in the development branch we're testing against.
    # So, in other words, the number of commits that the PR includes from other development branches
    count=$(git -C "$localRepo" rev-list --count "$mergeBase" ^"$baseBranch")

    if (( count != 0 )); then
        echo -en "\e[31m"
        echo "This PR's base branch is set to $baseBranch, but $count already-merged commits are included from the $branch branch."
        echo "To remedy this, first make sure you know the target branch for your changes: https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md#branch-conventions"
        echo "- If the changes should go to the $branch branch instead, change the base branch accordingly:"
        echo "  https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/changing-the-base-branch-of-a-pull-request"
        echo "- If the changes should really go to the $baseBranch branch, rebase your PR on top of the merge base with the $branch branch:"
        echo "  git rebase --onto $mergeBase && git push --force-with-lease"
        echo -en "\e[0m"
        exit 1
    fi
done

echo "All good, no extra commits from any development branch"
