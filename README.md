# Chaotic-AUR

WIP / subject to change!

## Overview

We use a combination of GitLab CI and [Chaotic Manager](https://gitlab.com/garuda-linux/tools/chaotic-manager) to manage this repository.

### GitLab CI

Since the main instance of the Chaotic-AUR resides on Garuda Linux infrastructure, it also inherits the GitLab side repository needed to make use of GitLab CI.
A webhook notifies GitLab of new commits happening on the GitHub side, causing new commits to be fetched.
This triggers GitLab CI runs. Additionally, there is a pipeline schedule which checks for PKGBUILD updates every 30 minutes.

Important links:

- [Pipeline runs](https://gitlab.com/garuda-linux/chaotic-aur/-/pipelines)
  - Invididual stages and jobs are listed here
  - Scheduled builds appear as individual jobs of the "external" stage, linking to live-updating log output of the builds
- [Invididual jobs](https://gitlab.com/garuda-linux/chaotic-aur/-/jobs)

#### Jobs

These generally execute scripts found in the `.ci` folder.

- Check PKGBUILD:
  - Checks PKGBUILD for superficial issues via `namcap` and `aura`
- Check rebuild:
  - Checks whether packages known to be causing rebuilds have been updated
  - Updates pkgrel for affected packages and pushes changes back to this repo
  - This triggers another pipeline run which schedules the corresponding builds
- Fetch Git sources:
  - Updates PKGBUILDs versions, which are derived from git commits and pushes changes back to this repo
  - This also triggers another pipeline run
- Lint:
  - Lints scripts, configs and PKGBUILDs via a set of linters
- Manage AUR:
  - Checks .CI_CONFIG in each PKGBUILDs folder for whether a package is meant to be managed on the AUR side
  - Clones the AUR repo and updates files with current versions of this repo
  - Pushes changes back
- Schedule package:
  - Checks for a list of commits between HEAD and "scheduled" tag
  - Checks whether a "[deploy]" string exists in the commit message or PKGBUILD directories changed
  - In either case a list of packages to be scheduled for a build gets created
  - Schedules all changed packages for a build via Chaotic Manager

### Chaotic Manager

This tool is distributed as Docker containers and consists of a pair of manager and builder instances.

- Manager: `registry.gitlab.com/garuda-linux/tools/chaotic-manager/manager`
- Builder: `registry.gitlab.com/garuda-linux/tools/chaotic-manager/builder`
  - This one contains the actual logic behind package builds (seen [here](https://gitlab.com/garuda-linux/tools/chaotic-manager/-/tree/main/builder-container?ref_type=heads)) known from infra 3.0 like `interfere.sh`, `database.sh` etc.
  - Picks packages to build from the Redis instance managed by the manager instance

The manager is used by GitLab CI in the `schedule-package` job, scheduling packages by adding it to the build queue.
The builder can be used by any machine capable of running the container. It will pick available jobs from our central Redis instance.

## Development setup

This repository features a NixOS flake, which may be used to set up the needed things like pre-commit hooks and checks, as well as needed utilities, automatically via [direnv](https://direnv.net/).
Needed are `nix` (the package manager) and [direnv](https://direnv.net/), after that, the environment may be entered by running `direnv allow`.
