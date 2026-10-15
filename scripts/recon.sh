#!/usr/bin/env bash
#
# recon.sh — track selected folders of this workspace in a second git repo,
# ReconTEXTualization (https://github.com/chris-ortiz-sndk/ReconTEXTualization).
#
# The files stay where they are. A second git dir (.git/recon.git, invisible to
# this repo) uses the workspace root as its work tree, with the same paths:
#
#   tlaplus/tlatools/org.lamport.tlatools/src/tla2tex/   (inside the submodule)
#   tests/fixtures/tlatex/
#   docs/
#
# Sparse checkout limits the second repo to those folders: files it has outside
# them (e.g. its own README.md) are never written into the workspace, and an
# exclude whitelist hides the rest of the workspace from `status`.
#
# Usage:
#   scripts/recon.sh init            Create/refresh .git/recon.git, fetch, start tracking (idempotent)
#   scripts/recon.sh <git args>...   Run git against the second repo, e.g. status, diff, add, commit, push, pull, log
#   scripts/recon.sh                 Same as `status`
#
# After init, `git recon <args>` works too (local alias in this repo's .git/config).
# Override the remote/branch with RECON_REMOTE / RECON_BRANCH.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RECON_REMOTE="${RECON_REMOTE:-https://github.com/chris-ortiz-sndk/ReconTEXTualization.git}"
RECON_BRANCH="${RECON_BRANCH:-main}"
TRACKED_DIRS=(
    "tlaplus/tlatools/org.lamport.tlatools/src/tla2tex"
    "tests/fixtures/tlatex"
    "docs"
)

GIT_DIR_RECON="$(git -C "${REPO_ROOT}" rev-parse --path-format=absolute --git-common-dir)/recon.git"

log()  { printf '\033[1;34m[recon]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[recon]\033[0m %s\n' "$*" >&2; exit 1; }

rgit() { git --git-dir="${GIT_DIR_RECON}" --work-tree="${REPO_ROOT}" "$@"; }

# Whitelist for info/exclude: ignore everything at each level except the path
# leading to a tracked folder. Later patterns win, so deeper re-includes follow.
exclude_patterns() {
    echo '/*'
    local dir prefix part
    for dir in "${TRACKED_DIRS[@]}"; do
        prefix=""
        IFS='/' read -r -a parts <<< "${dir}"
        for part in "${parts[@]}"; do
            [[ -n "${prefix}" ]] && echo "${prefix}/*"
            prefix="${prefix}/${part}"
            echo "!${prefix}/"
        done
    done
}

cmd_init() {
    if [[ ! -d "${GIT_DIR_RECON}" ]]; then
        log "Creating ${GIT_DIR_RECON}"
        git init -q --bare --initial-branch="${RECON_BRANCH}" "${GIT_DIR_RECON}"
    fi
    rgit config core.bare false
    rgit config core.worktree "${REPO_ROOT}"
    if rgit remote get-url origin >/dev/null 2>&1; then
        rgit remote set-url origin "${RECON_REMOTE}"
    else
        rgit remote add origin "${RECON_REMOTE}"
    fi

    # Non-cone sparse checkout keeps the second repo's other files (README.md)
    # out of the work tree; expectFilesOutsideOfPatterns stops git from
    # un-skipping them because this workspace has its own files at those paths.
    rgit config core.sparseCheckout true
    rgit config core.sparseCheckoutCone false
    rgit config sparse.expectFilesOutsideOfPatterns true
    mkdir -p "${GIT_DIR_RECON}/info"
    printf '/%s/\n' "${TRACKED_DIRS[@]}" > "${GIT_DIR_RECON}/info/sparse-checkout"
    exclude_patterns | awk '!seen[$0]++' > "${GIT_DIR_RECON}/info/exclude"

    log "Fetching ${RECON_REMOTE}"
    rgit fetch -q origin \
        || die "Fetch failed. Check access to ${RECON_REMOTE} and your git credentials (gh auth setup-git)."

    if ! rgit rev-parse -q --verify HEAD >/dev/null; then
        rgit symbolic-ref HEAD "refs/heads/${RECON_BRANCH}"
        if rgit rev-parse -q --verify "refs/remotes/origin/${RECON_BRANCH}" >/dev/null; then
            # Index only: the work tree is this workspace and must not be touched.
            rgit reset -q "origin/${RECON_BRANCH}"
            rgit branch -q --set-upstream-to="origin/${RECON_BRANCH}"
        fi
    fi

    # A plain `git add` will not descend into the tlaplus submodule (it looks
    # like a nested repo). Seeding the index once lets later add/status work.
    local dir n
    for dir in "${TRACKED_DIRS[@]}"; do
        [[ -d "${REPO_ROOT}/${dir}" ]] || die "Missing ${dir}. Run npm run tlatex:setup first."
        if [[ -n "$(rgit ls-files -- "${dir}" | head -n 1)" ]]; then
            continue
        fi
        n="$(git -C "${REPO_ROOT}/${dir}" ls-files -co --exclude-standard | wc -l)"
        git -C "${REPO_ROOT}/${dir}" ls-files -z -co --exclude-standard \
            | while IFS= read -r -d '' f; do printf '%s\0' "${dir}/${f}"; done \
            | rgit update-index --add -z --stdin
        log "Staged ${n} file(s) under ${dir}/"
    done

    git -C "${REPO_ROOT}" config alias.recon "!bash \"${SCRIPT_DIR}/recon.sh\""
    log "Ready. Use 'git recon <git args>' or 'npm run recon -- <git args>'."
    rgit status --short --branch
}

guard() {
    case "${1:-}" in
        clean)
            die "'clean' is blocked: everything outside the tracked folders counts as ignored here, so it would delete workspace files." ;;
        sparse-checkout)
            [[ "${2:-}" == "list" ]] \
                || die "Changing sparse checkout is blocked: it would write ReconTEXTualization's other files over this workspace. Edit TRACKED_DIRS in scripts/recon.sh and re-run init." ;;
    esac
}

main() {
    if [[ "${1:-}" == "init" ]]; then
        cmd_init
        return
    fi
    if [[ "${1:-}" == "help" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'
        return
    fi
    [[ -d "${GIT_DIR_RECON}" ]] || die "Not initialized. Run: npm run recon -- init"
    [[ $# -gt 0 ]] || set -- status
    guard "$@"
    # .gitignore negations (e.g. tlaplus/.gitignore's `!tlatools/**/lib/`)
    # override info/exclude, so scope pathspec-less status/add to the folders.
    if [[ "$1" == "status" || "$1" == "add" ]]; then
        local arg has_path=0
        for arg in "${@:2}"; do
            [[ "${arg}" == "--" || "${arg}" != -* ]] && has_path=1
        done
        if [[ ${has_path} -eq 0 ]]; then
            local dir
            for dir in "${TRACKED_DIRS[@]}"; do set -- "$@" ":(top)${dir}"; done
        fi
    fi
    # Keep pathspecs relative to where the user ran `git recon`.
    cd "${REPO_ROOT}/${GIT_PREFIX:-}"
    rgit "$@"
}

main "$@"
