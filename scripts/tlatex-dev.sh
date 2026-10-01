#!/usr/bin/env bash
#
# tlatex-dev.sh — reproducible TLATeX (tla2tex) development workflow.
#
# TLATeX is the Java typesetter (tla2tex.TLA) that lives in the tlaplus/tlaplus
# repo and ships inside tla2tools.jar. This extension only shells out to that
# jar. This script checks out the Java source, builds a fresh tla2tools.jar,
# runs the tla2tex JUnit tests, and swaps the jar into this extension so you can
# exercise "Export module to LaTeX/PDF" end to end.
#
# The Java source is the ./tlaplus git submodule (our fork of tlaplus/tlaplus,
# branch tlatex-overhaul; see .gitmodules). The extension repo pins the exact
# submodule commit, so every teammate builds from the same source.
#
# Usage:
#   scripts/tlatex-dev.sh doctor              Check prerequisites (JDK, Ant, git)
#   scripts/tlatex-dev.sh setup               Init the ./tlaplus submodule at the pinned commit
#   scripts/tlatex-dev.sh build               Compile + package dist/tla2tools.jar
#   scripts/tlatex-dev.sh test [glob]         Run tla2tex JUnit tests (default tla2tex/*)
#   scripts/tlatex-dev.sh install             Copy built jar into ./tools (+ ./out/tools)
#   scripts/tlatex-dev.sh dev                 build + install (fast inner loop)
#   scripts/tlatex-dev.sh typeset <File.tla>  Typeset a spec with the built jar
#   scripts/tlatex-dev.sh restore             Restore the release jar (git checkout)
#
set -euo pipefail

# --- locate repo root and the tlaplus submodule ------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

SUBMODULE_DIR="tlaplus"
# The Ant project lives in a fixed sub-path of the tlaplus repo.
TOOLS_SUBDIR="tlatools/org.lamport.tlatools"
BUILD_DIR="${REPO_ROOT}/${SUBMODULE_DIR}/${TOOLS_SUBDIR}"
BUILT_JAR="${BUILD_DIR}/dist/tla2tools.jar"
TARGET_JAR="${REPO_ROOT}/tools/tla2tools.jar"

log()  { printf '\033[1;34m[tlatex]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[tlatex]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[tlatex]\033[0m %s\n' "$*" >&2; exit 1; }

require() {
    command -v "$1" >/dev/null 2>&1 || die "Required tool '$1' not found on PATH. Run: scripts/tlatex-dev.sh doctor"
}

# --- commands ---------------------------------------------------------------
cmd_doctor() {
    local ok=0
    log "Checking prerequisites..."
    if command -v git  >/dev/null 2>&1; then log "  git:  $(git --version)"; else warn "  git:  MISSING"; ok=1; fi
    if command -v ant  >/dev/null 2>&1; then log "  ant:  $(ant -version)";   else warn "  ant:  MISSING (apt-get install ant)"; ok=1; fi
    if command -v javac >/dev/null 2>&1; then
        log "  javac: $(javac -version 2>&1)"
    else
        warn "  javac: MISSING — a JDK (>=11) is required to build. A JRE alone is not enough."; ok=1
    fi
    command -v pdflatex >/dev/null 2>&1 && log "  pdflatex: present (needed for PDF export)" \
        || warn "  pdflatex: MISSING (only needed for 'typeset' / PDF export)"
    log "  source repo: $(git config -f .gitmodules "submodule.${SUBMODULE_DIR}.url")"
    log "  source:      $(git submodule status "${SUBMODULE_DIR}")"
    [[ ${ok} -eq 0 ]] && log "All required prerequisites present." || die "Missing prerequisites (see above)."
}

cmd_setup() {
    require git
    log "Initializing ${SUBMODULE_DIR} submodule at the pinned commit"
    git submodule sync -- "${SUBMODULE_DIR}"
    git submodule update --init --depth 1 -- "${SUBMODULE_DIR}"
    local branch
    branch="$(git config -f .gitmodules "submodule.${SUBMODULE_DIR}.branch")"
    # The shallow clone only knows its default branch; also track the working
    # branch and upstream master so commits/pushes/syncs work from inside it.
    git -C "${SUBMODULE_DIR}" config --replace-all remote.origin.fetch \
        "+refs/heads/${branch}:refs/remotes/origin/${branch}" "refs/heads/${branch}:"
    git -C "${SUBMODULE_DIR}" remote get-url upstream >/dev/null 2>&1 \
        || git -C "${SUBMODULE_DIR}" remote add -t master upstream https://github.com/tlaplus/tlaplus.git
    git -C "${SUBMODULE_DIR}" fetch -q --depth 1 origin "${branch}" \
        || warn "Could not fetch origin/${branch}; continuing at the pinned commit."
    if [[ -z "$(git -C "${SUBMODULE_DIR}" symbolic-ref -q HEAD)" ]]; then
        # Fresh init leaves a detached HEAD; put it on the working branch.
        git -C "${SUBMODULE_DIR}" checkout -q -B "${branch}"
        git -C "${SUBMODULE_DIR}" branch -q --set-upstream-to="origin/${branch}" 2>/dev/null || true
    fi
    [[ -d "${BUILD_DIR}" ]] || die "Expected ${TOOLS_SUBDIR} not found in the ${SUBMODULE_DIR} submodule."
    log "Source ready at ${BUILD_DIR} (branch: $(git -C "${SUBMODULE_DIR}" branch --show-current))"
}

ensure_source() {
    [[ -d "${BUILD_DIR}" ]] || cmd_setup
}

cmd_build() {
    require ant
    require javac
    ensure_source
    log "Building tla2tools.jar (compile + compile-test + dist)"
    ( cd "${BUILD_DIR}" && ant -f customBuild.xml info compile compile-test dist )
    [[ -f "${BUILT_JAR}" ]] || die "Build finished but ${BUILT_JAR} is missing."
    log "Built: ${BUILT_JAR}"
}

cmd_test() {
    require ant
    ensure_source
    local glob="${1:-tla2tex/*}"
    log "Running JUnit tests matching: ${glob}"
    if ! ls "${BUILD_DIR}/test/${glob}" >/dev/null 2>&1; then
        warn "No test files match test/${glob} yet."
        warn "TLATeX has no upstream JUnit tests — add them under test/tla2tex/ in your fork,"
        warn "then re-run. This target is wired and ready for them."
    fi
    ( cd "${BUILD_DIR}" && ant -f customBuild.xml compile compile-test test-set -Dtest.testcases="${glob}" )
}

cmd_install() {
    [[ -f "${BUILT_JAR}" ]] || die "No built jar found. Run: scripts/tlatex-dev.sh build"
    log "Installing built jar -> tools/tla2tools.jar"
    cp -f "${BUILT_JAR}" "${TARGET_JAR}"
    # Keep the test/runtime copy in sync when it exists (created by 'npm run pretest').
    if [[ -d "${REPO_ROOT}/out/tools" ]]; then
        cp -f "${BUILT_JAR}" "${REPO_ROOT}/out/tools/tla2tools.jar"
        log "Also refreshed out/tools/tla2tools.jar"
    fi
    log "Done. Reload the Extension Development Host to pick up the new jar."
}

cmd_dev() {
    cmd_build
    cmd_install
}

cmd_typeset() {
    local spec="${1:-}"
    [[ -n "${spec}" ]] || die "Usage: scripts/tlatex-dev.sh typeset <File.tla>"
    [[ -f "${spec}" ]] || die "Spec not found: ${spec}"
    require java
    local jar="${TARGET_JAR}"
    [[ -f "${jar}" ]] || jar="${BUILT_JAR}"
    [[ -f "${jar}" ]] || die "No tla2tools.jar available. Run: scripts/tlatex-dev.sh dev"
    log "Typesetting ${spec} with ${jar}"
    # Mirrors the extension's default 'Export to PDF' invocation (see src/tla2tools.ts).
    ( cd "$(dirname "${spec}")" \
        && java -cp "${jar}" tla2tex.TLA -latexCommand pdflatex -nops -shade -grayLevel 0.85 "$(basename "${spec}")" )
    log "Output written next to ${spec} (.dvi/.pdf/.tex)."
}

cmd_restore() {
    require git
    log "Restoring release tools/tla2tools.jar from git"
    git -C "${REPO_ROOT}" checkout -- tools/tla2tools.jar
    log "Restored."
}

usage() {
    sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
    local cmd="${1:-dev}"
    shift || true
    case "${cmd}" in
        doctor)  cmd_doctor "$@" ;;
        setup)   cmd_setup "$@" ;;
        build)   cmd_build "$@" ;;
        test)    cmd_test "$@" ;;
        install) cmd_install "$@" ;;
        dev)     cmd_dev "$@" ;;
        typeset) cmd_typeset "$@" ;;
        restore) cmd_restore "$@" ;;
        -h|--help|help) usage ;;
        *) die "Unknown command '${cmd}'. Run: scripts/tlatex-dev.sh --help" ;;
    esac
}

main "$@"
