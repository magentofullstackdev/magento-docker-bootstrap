# Contributing

Thanks for taking the time to look at this project. Contributions are welcome — bug reports, fixes, new Magento versions in the compatibility matrix, additional optional services, or documentation tweaks.

## Filing an issue

Before opening an issue, please check the existing ones first. When you do open one, the more of the following you can include, the easier it is to help:

- your host OS (`uname -srm`)
- Docker / Compose version (`docker version` and `docker compose version`)
- the contents of your `.env` (with passwords redacted)
- exact `make` command you ran and the full error output

## Submitting a pull request

1. Fork the repo and create a topic branch off `main`.
2. Keep changes focused — one logical change per PR is much easier to review than a sprawling refactor.
3. Test the change on at least one of Linux or macOS. If you can test both, even better — the OS-detection logic is the most accident-prone part of the codebase.
4. Update `CHANGELOG.md` under an `## [Unreleased]` heading at the top.
5. Open the PR with a description of what changed and why.

## Adding a new Magento / MageOS version

Edit the `MAGENTO_VERSIONS` (or `MAGEOS_VERSIONS`) associative array at the top of `dockerimages/bin/init.sh`. The format is:

```
[2.4.9]="php=8.3 8.4|recommended=8.3|mariadb=10.6 11.4|mysql=8.0 8.4|opensearch=2.19-1.4.0|composer=2"
```

Cross-check `php`, `mariadb`, `mysql` and `opensearch` against the Adobe system-requirements page for that exact patch release before submitting.

## Code style

- Bash scripts: `set -euo pipefail`, comments where intent isn't obvious, prefer arrays over space-separated strings.
- Makefile: each target gets a `## description` so it shows up in `make help`.
- YAML / Dockerfiles: 4-space indent, blank line between blocks.

That's it — keep it pragmatic.
