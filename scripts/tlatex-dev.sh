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
#   scripts/tlatex-dev.sh setup               Init the ./tlaplus submodule at the pinned commit, install git hooks
#   scripts/tlatex-dev.sh status              Show branch/commit/dirty state of both repos and the dev jar
#   scripts/tlatex-dev.sh build               Compile + package dist/tla2tools.jar
#   scripts/tlatex-dev.sh test [glob]         Run tla2tex JUnit tests (default tla2tex/*)
#   scripts/tlatex-dev.sh install             Copy built jar into ./tools (+ ./out/tools)
#   scripts/tlatex-dev.sh dev                 build + install (fast inner loop)
#   scripts/tlatex-dev.sh typeset <File.tla>...  Typeset spec(s) with the built jar; fails on LaTeX errors
#   scripts/tlatex-dev.sh golden              Regenerate the JUnit golden .tex files (review the diff!)
#   scripts/tlatex-dev.sh regress [N]         Release jar vs built jar: .tex must be identical for tests/tlatex-regress.txt
#   scripts/tlatex-dev.sh check               build + test + typeset fixtures + regress (what CI runs; TLATEX_SKIP_REGRESS=1 skips regress)
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
    install_hooks
    log "Source ready at ${BUILD_DIR} (branch: $(git -C "${SUBMODULE_DIR}" branch --show-current))"
}

# Guard hooks (see .githooks/): block committing the dev jar, an unpushed
# submodule pointer, Eclipse metadata, or from a detached HEAD in the fork.
install_hooks() {
    git config core.hooksPath .githooks
    git -C "${SUBMODULE_DIR}" config core.hooksPath "${REPO_ROOT}/.githooks/${SUBMODULE_DIR}"
    log "Git hooks installed (core.hooksPath) in both repos"
    install_local_excludes
}

# The Java language server writes an encoding prefs file into every Eclipse
# project it imports. Upstream does not track it for the sibling projects, so
# hide it per-clone via .git/info/exclude (never pushed; the fork stays clean).
install_local_excludes() {
    local exclude; exclude="$(git -C "${SUBMODULE_DIR}" rev-parse --git-path info/exclude)"
    local marker="# tlatex-dev: generated by the Java language server"
    [[ -f "${exclude}" ]] || { mkdir -p "$(dirname "${exclude}")"; : > "${exclude}"; }
    if ! grep -qF "${marker}" "${exclude}"; then
        printf '%s\n%s\n' "${marker}" \
            "tlatools/org.lamport.tlatools.*/.settings/org.eclipse.core.resources.prefs" >> "${exclude}"
        log "Local git excludes for generated Eclipse prefs added to ${SUBMODULE_DIR}"
    fi
}

cmd_status() {
    require git
    local branch sha detached
    branch="$(git config -f .gitmodules "submodule.${SUBMODULE_DIR}.branch")"
    log "Extension repo: $(git branch --show-current) @ $(git rev-parse --short HEAD)"
    if git diff --quiet -- "tools/$(basename "${TARGET_JAR}")"; then
        log "  tools/tla2tools.jar: release jar (unmodified)"
    else
        warn "  tools/tla2tools.jar: MODIFIED (local dev build installed; 'tlatex:restore' before committing)"
    fi
    [[ -d "${BUILD_DIR}" ]] || { warn "  ${SUBMODULE_DIR}: not initialized (run setup)"; return 0; }
    sha="$(git -C "${SUBMODULE_DIR}" rev-parse --short HEAD)"
    detached=""; git -C "${SUBMODULE_DIR}" symbolic-ref -q HEAD >/dev/null || detached=" (DETACHED HEAD, run setup before committing)"
    log "${SUBMODULE_DIR}: $(git -C "${SUBMODULE_DIR}" branch --show-current) @ ${sha}${detached}"
    local pinned; pinned="$(git ls-files -s -- "${SUBMODULE_DIR}" | awk '{print substr($2,1,7)}')"
    [[ "${pinned}" == "${sha}" ]] && log "  pinned by extension repo: yes" || warn "  pinned by extension repo: no (pinned ${pinned}; 'git add ${SUBMODULE_DIR}' to bump)"
    if git -C "${SUBMODULE_DIR}" rev-parse -q --verify "refs/remotes/origin/${branch}" >/dev/null 2>&1; then
        git -C "${SUBMODULE_DIR}" merge-base --is-ancestor HEAD "refs/remotes/origin/${branch}" \
            && log "  pushed to origin/${branch}: yes" || warn "  pushed to origin/${branch}: NO (push the fork before bumping the pointer)"
    fi
    local dirty; dirty="$(git -C "${SUBMODULE_DIR}" status --porcelain | wc -l | tr -d ' ')"
    [[ "${dirty}" == "0" ]] && log "  working tree: clean" || warn "  working tree: ${dirty} changed file(s)"
    [[ -f "${BUILT_JAR}" ]] && log "  built jar: $(date -r "${BUILT_JAR}" '+%Y-%m-%d %H:%M') ${BUILT_JAR#${REPO_ROOT}/}" || log "  built jar: none (run build)"
}

ensure_source() {
    [[ -d "${BUILD_DIR}" ]] || cmd_setup
}

# Run Ant in the tlatools project. Never call the 'info' target: it depends on
# 'git-revision', a jgit build-number task that walks the whole commit history
# and fails on the shallow submodule clone ("MissingObjectException"). The only
# thing it provides is the git.* properties for the jar manifest, so supply
# those from plain git instead.
ant_tools() {
    local rev short branch
    rev="$(git -C "${SUBMODULE_DIR}" rev-parse HEAD)"
    short="$(git -C "${SUBMODULE_DIR}" rev-parse --short HEAD)"
    branch="$(git -C "${SUBMODULE_DIR}" branch --show-current)"
    ( cd "${BUILD_DIR}" && ant -f customBuild.xml \
        -Dgit.revision="${rev}" -Dgit.shortRevision="${short}" \
        -Dgit.branch="${branch:-detached}" -Dgit.tag="" "$@" )
}

cmd_build() {
    require ant
    require javac
    ensure_source
    log "Building tla2tools.jar (compile + compile-test + dist)"
    ant_tools compile compile-test dist
    [[ -f "${BUILT_JAR}" ]] || die "Build finished but ${BUILT_JAR} is missing."
    log "Built: ${BUILT_JAR}"
}

cmd_test() {
    require ant
    ensure_source
    local glob="${1:-tla2tex/*}"
    log "Running JUnit tests matching: ${glob}"
    # Ant's batchtest silently runs nothing when the glob matches no files;
    # an empty suite must not look like a green one.
    ls "${BUILD_DIR}"/test/${glob} >/dev/null 2>&1 \
        || die "No test files match test/${glob} (tests live in tlaplus/tlatools/org.lamport.tlatools/test/tla2tex/)."
    ant_tools compile compile-test test-set -Dtest.testcases="${glob}"
}

# Rewrite the golden .tex files used by test/tla2tex/GoldenLaTeXTest.java.
# Only do this for an intended output change, and review the resulting diff in
# tlaplus/ before committing it.
cmd_golden() {
    TLA2TEX_UPDATE_GOLDEN=1 cmd_test "tla2tex/GoldenLaTeXTest*"
    log "Golden files updated under ${TOOLS_SUBDIR}/test-model/tla2tex/. Changed:"
    git -C "${SUBMODULE_DIR}" status --short -- "${TOOLS_SUBDIR}/test-model/tla2tex" | sed 's/^/    /'
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
    [[ $# -ge 1 ]] || die "Usage: scripts/tlatex-dev.sh typeset <File.tla>..."
    require java
    local jar="${TARGET_JAR}"
    [[ -f "${jar}" ]] || jar="${BUILT_JAR}"
    [[ -f "${jar}" ]] || die "No tla2tools.jar available. Run: scripts/tlatex-dev.sh dev"
    local spec
    for spec in "$@"; do
        [[ -f "${spec}" ]] || die "Spec not found: ${spec}"
        [[ "${spec}" == *.tla ]] || die "Expected a .tla file: ${spec}"
        log "Typesetting ${spec} with ${jar#${REPO_ROOT}/}"
        typeset_one "${jar}" "$(dirname "${spec}")" "$(basename "${spec}")" \
            || die "Typesetting failed for ${spec}"
        check_latex_output "${spec%.tla}"
    done
    log "Output written next to the spec(s) (.tex/.pdf/.log)."
}

# Run tla2tex.TLA on one spec inside its directory, with the same flags the
# extension's 'Export module to PDF' uses (see buildTexOptions in src/tla2tools.ts).
typeset_one() {
    local jar="$1" dir="$2" file="$3"
    ( cd "${dir}" && java -cp "${jar}" tla2tex.TLA -latexCommand pdflatex -nops -shade -grayLevel 0.85 "${file}" )
}

# tla2tex runs LaTeX in \batchmode and treats only a negative exit code as a
# failure, so a LaTeX error leaves tla2tex's exit code at 0. The .log is the
# only evidence; an error line there starts with '!'.
check_latex_output() {
    local root="$1" errors overfull
    [[ -f "${root}.log" ]] || die "LaTeX log ${root}.log not found; LaTeX did not run."
    errors="$(grep -c '^!' "${root}.log" || true)"
    if [[ "${errors}" != "0" ]]; then
        grep -n -A2 '^!' "${root}.log" | head -30 >&2
        die "LaTeX reported ${errors} error(s) while typesetting ${root}.tex (see ${root}.log)."
    fi
    overfull="$(grep -c '^Overfull' "${root}.log" || true)"
    [[ "${overfull}" == "0" ]] || warn "${overfull} overfull box(es) in ${root}.log"
    [[ -f "${root}.pdf" ]] || die "Expected ${root}.pdf was not produced."
}

# Regression guard: typeset the specs listed in tests/tlatex-regress.txt with
# the committed release jar and with the freshly built jar, and require the
# generated .tex files to be byte-identical. Phase 1 features are opt-in, so a
# spec that uses none of them must typeset exactly as before.
REGRESS_LIST="${REPO_ROOT}/tests/tlatex-regress.txt"
cmd_regress() {
    require java
    require pdflatex
    require git
    [[ -f "${BUILT_JAR}" ]] || die "No built jar found. Run: scripts/tlatex-dev.sh build"
    [[ -f "${REGRESS_LIST}" ]] || die "Missing ${REGRESS_LIST}"
    local limit="${1:-0}"
    local work; work="$(mktemp -d "${TMPDIR:-/tmp}/tlatex-regress.XXXXXX")"
    local baseline="${work}/baseline.jar"
    git -C "${REPO_ROOT}" show HEAD:tools/tla2tools.jar > "${baseline}" 2>/dev/null \
        || die "Could not extract the committed release jar (git show HEAD:tools/tla2tools.jar)."
    local model="${BUILD_DIR}/test-model"
    local -a specs
    mapfile -t specs < <(grep -v '^[[:space:]]*#' "${REGRESS_LIST}" | grep -v '^[[:space:]]*$')
    if [[ "${limit}" -gt 0 && "${limit}" -lt "${#specs[@]}" ]]; then
        specs=( "${specs[@]:0:${limit}}" )
    fi
    log "Regression: ${#specs[@]} spec(s), committed release jar vs ${BUILT_JAR#${REPO_ROOT}/}"
    local failed=0 name root
    for name in "${specs[@]}"; do
        root="${name%.tla}"
        if [[ ! -f "${model}/${name}" ]]; then
            warn "  missing: ${model}/${name}"; failed=$((failed + 1)); continue
        fi
        mkdir -p "${work}/base/${root}" "${work}/new/${root}"
        cp "${model}/${name}" "${work}/base/${root}/"
        cp "${model}/${name}" "${work}/new/${root}/"
        if ! typeset_one "${baseline}" "${work}/base/${root}" "${name}" > "${work}/base/${root}/tla2tex.out" 2>&1; then
            warn "  release jar failed on ${name} (see ${work}/base/${root}/tla2tex.out)"; failed=$((failed + 1)); continue
        fi
        if ! typeset_one "${BUILT_JAR}" "${work}/new/${root}" "${name}" > "${work}/new/${root}/tla2tex.out" 2>&1; then
            warn "  built jar failed on ${name} (see ${work}/new/${root}/tla2tex.out)"; failed=$((failed + 1)); continue
        fi
        if ! cmp -s "${work}/base/${root}/${root}.tex" "${work}/new/${root}/${root}.tex"; then
            warn "  DIFF: ${name}"
            diff -u "${work}/base/${root}/${root}.tex" "${work}/new/${root}/${root}.tex" | head -40 >&2 || true
            failed=$((failed + 1))
        fi
    done
    if [[ "${failed}" -eq 0 ]]; then
        rm -rf "${work}"
        log "regress passed: ${#specs[@]} spec(s) produce identical .tex with both jars."
    else
        die "regress: ${failed} of ${#specs[@]} spec(s) differ or failed. Outputs kept in ${work}"
    fi
}

# One-shot verification used by CI (.github/workflows/tlatex.yml) and before
# pushing: fresh build, tla2tex unit tests, and every fixture must typeset.
cmd_check() {
    require pdflatex
    cmd_build
    cmd_test
    local fixtures=( "${REPO_ROOT}"/tests/fixtures/tlatex/*.tla )
    [[ -f "${fixtures[0]}" ]] || die "No fixtures found under tests/fixtures/tlatex/"
    TARGET_JAR="${BUILT_JAR}" cmd_typeset "${fixtures[@]}"
    if [[ -n "${TLATEX_SKIP_REGRESS:-}" ]]; then
        warn "TLATEX_SKIP_REGRESS set; skipping the release-vs-built regression."
    else
        cmd_regress
    fi
    log "check passed: build, tests, ${#fixtures[@]} fixture(s) typeset, regression."
}

cmd_restore() {
    require git
    log "Restoring release tools/tla2tools.jar from git"
    git -C "${REPO_ROOT}" checkout -- tools/tla2tools.jar
    log "Restored."
}

usage() {
    # Print the header comment block (everything before 'set -euo pipefail').
    sed -n '2,/^set -euo pipefail/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

main() {
    local cmd="${1:-dev}"
    shift || true
    case "${cmd}" in
        doctor)  cmd_doctor "$@" ;;
        setup)   cmd_setup "$@" ;;
        status)  cmd_status "$@" ;;
        build)   cmd_build "$@" ;;
        test)    cmd_test "$@" ;;
        install) cmd_install "$@" ;;
        dev)     cmd_dev "$@" ;;
        typeset) cmd_typeset "$@" ;;
        golden)  cmd_golden "$@" ;;
        regress) cmd_regress "$@" ;;
        check)   cmd_check "$@" ;;
        restore) cmd_restore "$@" ;;
        -h|--help|help) usage ;;
        *) die "Unknown command '${cmd}'. Run: scripts/tlatex-dev.sh --help" ;;
    esac
}

main "$@"
