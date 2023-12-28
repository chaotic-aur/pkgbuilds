#!/usr/bin/env bash

for dep in curl git jq shfmt; do
	command -v "$dep" &>/dev/null || echo "$dep is not installed!"
done

function update_pkgbuild() {
	git clone "${_SOURCES[$_COUNTER]}" "$_TMPDIR/source"

	cp -v "$_TMPDIR"/source/{*,.SRCINFO} "./${_PKGNAME[$_COUNTER]}"

	# Format the PKGBUILD
	shfmt -w "./${_PKGNAME[$_COUNTER]}/PKGBUILD"

	# Only push if there are changes
	if ! git diff --exit-code --quiet; then
		git add "${_PKGNAME[$_COUNTER]}"

		# Commit and push the changes back to trigger a new pipeline run
		git commit -m "chore(${_PKGNAME[$_COUNTER]}): $_CURRENT_VERSION -> $_LATEST_VERSION"

		git push "$REPO_URL" HEAD:main # Env provided via GitLab CI
		echo ""
	else
		echo "No changes detected, skipping!"
	fi
}

# This might be subsituted by parsing .CI_CONFIG in PKGBUILDs folders
# eg. via a CI_PKGBUILD_SOURCE variable
readarray -t _SOURCES < <(awk -F ' ' '{ print $1 }' ./SOURCES)
readarray -t _PKGNAME < <(awk -F ' ' '{ print $2 }' ./SOURCES)

_COUNTER=0
for package in "${_PKGNAME[@]}"; do
	echo "Checking ${_PKGNAME[$_COUNTER]}..."

	# Get the latest tag from via AUR RPC endpoint, using a placeholder for git packages
	if [[ ! "$package" == *"-git"* ]]; then
		_LATEST_VERSION=$(curl -s "https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=${_PKGNAME[$_COUNTER]}" | jq -r '.results.[0].Version')
	elif [[ -f "${_PKGNAME[$_COUNTER]}/.CI_CONFIG" ]] && grep -q "CI_IS_GIT_SOURCE=1" "${_PKGNAME[$_COUNTER]}/.CI_CONFIG"; then
		_LATEST_VERSION="git-src"
	else
		_LATEST_VERSION="git-src"
	fi

	# Extract current version from PKGBUILD
	_CURRENT_VERSION=$(echo "$(grep -oP '^pkgver=\K.*' "${_PKGNAME[$_COUNTER]}/PKGBUILD")"-"$(grep -oP '^pkgrel=\K.*' "${_PKGNAME[$_COUNTER]}/PKGBUILD")")

	if [[ "$_LATEST_VERSION" == "$_CURRENT_VERSION" ]]; then
		printf "%s is up to date.\n\n" "${_PKGNAME[$_COUNTER]}"
		((_COUNTER++))
		continue
	elif [[ "$_LATEST_VERSION" == "git-src" ]]; then
		# Up-to-date pkgver is maintained by us via fetch-gitsrc, so no need to do anything here
		printf "%s is managed by fetch-gitsrc, skipping.\n\n" "${_PKGNAME[$_COUNTER]}"
		((_COUNTER++))
		continue
	elif [[ "$_LATEST_VERSION" != "$_CURRENT_VERSION" ]]; then
		# Otherwise just push the version update to main
		_TMPDIR=$(mktemp -d)
		update_pkgbuild
	fi

	((_COUNTER++))

	# Try to avoid rate limiting
	sleep 1
done
