#!/usr/bin/env bash

function prepare-env() {
    # Get all commit messages between "scheduled" tag and HEAD to get all relevant
    # ones between 2 pipeline runs. This is required because the webhook execution
    # for pulling commits to GitLab CI doesn't seem to be running instantly, resulting
    # in only one pipeline run for multiple commits
    mapfile -t _CURRENT_COMMIT_MSG < <(git log --pretty=format:"commit=%h message=%s" scheduled..HEAD)

    # Determine which commits to parse how
    for commit in "${_CURRENT_COMMIT_MSG[@]}"; do
        if [[ "$commit" == *"[deploy"*"]"* ]]; then
            _DEPLOY_VIA_COMMIT_MSG+=("$commit")
        else
            _DEPLOY_VIA_GIT_DIFF+=("$commit")
        fi
    done

    # Build a list of valid packages
    mapfile -t _PACKAGES < <(find . -mindepth 1 -type d -prune | sed -e '/.\./d' -e 's/.\///g')
}

function parse-commit() {
    for commit in "${_DEPLOY_VIA_COMMIT_MSG[@]}"; do
        if [[ "$commit" == *"[deploy all]"* ]]; then
            for package in "${_PACKAGES[@]}"; do
                _PKG+=("chaotic-aur:$package")
            done
            echo "Requested a full routine run."
        elif [[ "$commit" == *"[deploy"*"]"* ]]; then
            for package in "${_PACKAGES[@]}"; do
                if [[ "$CI_COMMIT_MESSAGE" == *"[deploy $package]"* ]]; then
                    _PKG=("chaotic-aur:$package")
                    echo "Requested package build for $package."
                    return 0
                fi
            done
            echo "No package to build found in commit message. Exiting." && exit 1
        else
            echo "No package to build found in commit message. Exiting." && exit 1
        fi
    done
}

parse-gitdiff() {
    for commit in "${_DEPLOY_VIA_GIT_DIFF[@]}"; do
        # Extract commit ID
        local _CURRENT_COMMIT
        _CURRENT_COMMIT=$(echo "$commit" | grep -oP '^commit=\K[0-9a-f]{7}')

        # Compare differences between our current commit and the commit before it to get
        # a list of changes
        local _CURRENT_DIFF
        _CURRENT_DIFF=$(git --no-pager diff --name-only "$_CURRENT_COMMIT"~1.."$_CURRENT_COMMIT")

        # Check whether relevant folders got changed
        for package in "${_PACKAGES[@]}"; do
            if [[ "$_CURRENT_DIFF" =~ "$package"/ ]]; then
                _PKG+=("chaotic-aur:$package")
                echo "Detected changes in $package, scheduling build..."
            fi
        done
    done
}

schedule-package() {
    if [[ "${#_PKG[@]}" == 0 ]]; then
        echo "No relevant package changes to build found, exiting gracefully." && exit 0
    fi

    # To only schedule each package once, strip all duplicates
    mapfile -t _FINAL_PKG < <(for pkg in "${_PKG[@]}"; do echo "$pkg"; done | sort -u)

    # Schedule either a full run or a single package using chaotic-manager
    # the entry_point script also establishes a connection to our Redis server
    /entry_point.sh schedule --commit "${CI_COMMIT_SHA}:${CI_PIPELINE_ID}" --repo "$BUILD_REPO" "${_FINAL_PKG[@]}"
}

update-tag() {
    git tag -m "All PKGBUILD changes up to this tag have been scheduled." -f scheduled
    git push --tags -f "$REPO_URL" HEAD:main
}

prepare-env
parse-commit
parse-gitdiff
schedule-package
update-tag
