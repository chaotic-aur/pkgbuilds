#!/usr/bin/env bash

for dep in curl git jq shfmt; do
	command -v "$dep" &>/dev/null || echo "$dep is not installed!"
done

function update_pkgbuild() {
	git clone "${_SOURCES[$_COUNTER]}" "$_TMPDIR/source"

	cp -v "$_TMPDIR"/source/* "$_CURRDIR"

	# Format the PKGBUILD
	shfmt -w "$_CURRDIR/PKGBUILD"

	# Only push if there are changes
	if ! git diff --exit-code --quiet; then
		git add .
		# Commit and push the changes to our new branch
		git commit -m "chore(${_PKGNAME[$_COUNTER]}): ${pkgver}-${pkgrel} -> ${_LATEST}"

		git push "$REPO_URL" HEAD:main # Env provided via GitLab CI
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
		_LATEST=$(curl -s "https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=${_PKGNAME[$_COUNTER]}" | jq '.results.[0].Version')
	elif grep -q "CI_IS_GIT_SOURCE=1" "${_PKGNAME[$_COUNTER]}/.CI_CONFIG"; then
		_LATEST="git-src"
	else
		_LATEST="git-src"
	fi

	cd "${_PKGNAME[$_COUNTER]}" || mkdir "${_PKGNAME[$_COUNTER]}" && cd "${_PKGNAME[$_COUNTER]}"

	# To-do: parse version without sourcing PKGBUILD
	# shellcheck source=/dev/null 
	source PKGBUILD || echo "Failed to source PKGBUILD for ${_PKGNAME[$_COUNTER]}!"

	if [[ "$_LATEST" == "$pkgver"-"$pkgrel" ]]; then
		echo "${_PKGNAME[$_COUNTER]} is up to date"
		continue
	elif [[ "$_LATEST" == "git-src" ]]; then
		# If no review is required and the package is a git package, do nothing
		# we generally just want to update the PKGBUILD in case its something like deps,
		# functions or makedep changing. Up-to-date pkgver is maintained by us.
		return 0
	elif [[ "$pkgver"-"$pkgrel" != "$_LATEST" ]]; then
		# Otherwise just push the version update to main
		_TMPDIR=$(mktemp -d)
		_CURRDIR=$(pwd)

		update_pkgbuild
	fi

	cd .. || echo "Failed to change back to the previous directory!"
	((_COUNTER++))

	# Try to avoid rate limiting
	sleep 1
done
