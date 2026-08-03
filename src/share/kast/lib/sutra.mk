# sutra.mk -- the family's shared RECIPE layer, vendored like code (see
# docs/BOOTSTRAP.md for the sibling code-vendoring mechanics). Include from
# a pill's own root Makefile:
#
#   PILL := coldspot
#   include src/share/coldspot/lib/sutra.mk
#
# PILL must be set before the include line. Everything else resolves
# relative to sutra.mk's OWN location -- $(lastword $(MAKEFILE_LIST)) at
# include-time is exactly that path, however the including Makefile spelled
# it -- never to sutra's own repo. That is the design constraint: get it
# wrong and five pills each debug their own copy of the same mistake, which
# is the exact failure mode this file exists to close.
#
# 441 lines of this recipe were maintained by hand across five pills before
# this existed; check-sutra alone ranged 30-57 lines for what was nominally
# one thing, and every divergence the family suffered was a recipe, never
# vendored CODE (which has never drifted once, because it has a hash
# anchor -- see docs/ARCHITECTURE.md). This is that same guard, extended to
# recipes: ship the recipe itself under the anchor, so a pill runs the
# current correct thing by construction instead of a snapshot someone
# copied by hand and never revisited.
#
# PILOT CORRECTIONS (Till, ramstein, msg 2739 via Alfred): the first
# published form was validated against sutra itself and a fake pill built
# from the same head that authored it -- both share the author's own
# assumptions and neither could surface a gap only a REAL, independently-
# built consumer would hit. Four gaps found by ramstein's real pilot
# adoption are fixed below; each is called out at its own site rather than
# only here, since "what changed" matters less than "why the first cut
# missed it."

_SUTRA_MK_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
_SUTRA_CANON := $(HOME)/code/REPOS/sutra

# --- check-sutra: integrity (hard gate) + freshness (LAG/DRIFT) -----------
#
# Integrity: the vendored file's sha256 against its own .version anchor --
# hand-edited or corrupted, always a hard fail, no nuance.
#
# Freshness: the .commit anchor compared against canonical sutra's history
# for THAT FILE SPECIFICALLY -- `git -C "$canon" log -1 --format=%H --
# "<name>"` -- never canonical's repo HEAD, which advances on every commit
# including ones that never touch the file at all. That was the 0.7.3 fix
# (decision 325b1969, correcting d51e090f's original HEAD-compare, which
# false-positived a LAG warning across the whole family the first time a
# docs-only commit landed). It reached one pill by hand-copying before this
# file existed; the other four still carry the stale form. Recorded at or
# after the file's own last commit -> fresh. A strict ancestor of it ->
# LAG, the copy has genuinely fallen behind, warn only. Not in canonical's
# history at all -> DRIFT, hard fail.
#
# PILOT FIX 1 (Till/ramstein): the first cut looped only sutra/sutra_update/
# sutra_xen -- the three .py modules living beside sutra.mk itself. But
# byebyte, phanspeed AND ramstein (three of four pills with a hand-written
# check-sutra today) also check pill.js, per BOOTSTRAP.md's own escape
# hatch ("extend the for mod in... line with pill.js") -- a hatch that
# never made it into this generalized form. Verbatim adoption would have
# silently DELETED an existing guard from three of five pills. pill.js
# lives in the extension dir, not the lib dir, and is .js not .py, so it
# cannot just join the same `for mod in ...` loop -- it needs its own path.
# SUTRA_EXT_DIR opts a pill in; empty (the default) skips it exactly like
# a pill with no extension should.
#
# PILOT FIX 5 (Werner, found mid-adoption in a real pill; confirmed by
# Alfred, msg 2768): the first cut of the branch below tested "$(SUTRA_EXT_DIR)"
# -- a Make-level expansion, substituted at parse time -- but then read the
# value back as "$${SUTRA_EXT_DIR%/}", a SHELL-level parameter expansion.
# SUTRA_EXT_DIR is a Makefile variable, never exported to the recipe's
# shell environment, so the shell's own $SUTRA_EXT_DIR was always empty:
# the `-n` test correctly saw a non-empty value and took the branch, then
# extdir resolved to nothing, the pill.js path became just "/pill.js", and
# _sutra_check_one's own not-vendored-here fallback reported a clean skip.
# check-sutra therefore exited 0 while covering nothing -- the exact defect
# PILOT FIX 1 above exists to close, reintroduced inside its own fix, and
# more dangerous than an ordinary failure because it reads as routine
# output rather than a red run. Fixed below by using $(SUTRA_EXT_DIR)
# (Make-level, via patsubst for the trailing-slash strip) consistently
# instead of mixing it with a shell-level read -- this removes the
# export/parse-order question entirely rather than requiring a pill to
# `export SUTRA_EXT_DIR` around the include, which was the workaround
# before this was understood.
SUTRA_EXT_DIR ?=

.PHONY: check-sutra
check-sutra:
	@[ -n "$(PILL)" ] || { echo "check-sutra: set PILL=<pill-name> before including sutra.mk"; exit 1; }
	@canon="$(_SUTRA_CANON)"; libdir="$(_SUTRA_MK_DIR)"; fail=0; \
	_sutra_check_one() { \
	    label="$$1"; py="$$2"; ver="$$3"; cmt="$$4"; canon_relpath="$$5"; \
	    [ -f "$$py" ] || { echo "check-sutra: $$py not vendored here, skipping $$label"; return 0; }; \
	    v=$$(cut -d' ' -f1 "$$ver"); \
	    sha=$$(awk '{print $$NF}' "$$ver"); \
	    actual=$$(sha256sum "$$py" | cut -d' ' -f1); \
	    if [ "$$sha" != "$$actual" ]; then \
	        echo "check-sutra FAIL: $$py doesn't match $$ver" \
	             "(hand-edited? re-vendor: bash $$canon/vendor.sh $$libdir --bootstrap=$(PILL))"; \
	        return 1; \
	    fi; \
	    echo "check-sutra: integrity ok ($$label $$v, sha256 $$sha)"; \
	    if [ -d "$$canon/.git" ]; then \
	        if [ ! -f "$$cmt" ]; then \
	            echo "check-sutra: freshness unknown for $$label (no $$cmt anchor, an older vendor)"; \
	        else \
	            recorded=$$(cat "$$cmt"); \
	            filehead=$$(git -C "$$canon" log -1 --format=%H -- "$$canon_relpath"); \
	            if git -C "$$canon" merge-base --is-ancestor "$$filehead" "$$recorded" 2>/dev/null; then \
	                echo "check-sutra: freshness ok ($$label vendored from $$recorded, at or after its own head $$filehead)"; \
	            elif git -C "$$canon" merge-base --is-ancestor "$$recorded" "$$filehead" 2>/dev/null; then \
	                echo "check-sutra: LAG ($$label vendored from $$recorded, canonical has since moved to $$filehead) -- warn, not a failure"; \
	            else \
	                echo "check-sutra FAIL: DRIFT ($$label's vendored commit $$recorded is not in canonical's history at $$canon) -- re-vendor"; \
	                return 1; \
	            fi; \
	        fi; \
	    fi; \
	    return 0; \
	}; \
	for mod in sutra sutra_update sutra_xen; do \
	    _sutra_check_one "$$mod" "$$libdir$$mod.py" "$$libdir$$mod.version" "$$libdir$$mod.commit" "$$mod.py" || fail=1; \
	done; \
	if [ -n "$(SUTRA_EXT_DIR)" ]; then \
	    extdir="$(patsubst %/,%,$(SUTRA_EXT_DIR))"; \
	    _sutra_check_one "pill.js" "$$extdir/pill.js" "$$extdir/pill.version" "$$extdir/pill.commit" "pill.js" || fail=1; \
	fi; \
	if [ ! -d "$$canon/.git" ]; then \
	    echo "check-sutra: canonical sutra checkout not present, freshness skipped"; \
	fi; \
	exit $$fail

# --- the row-count primitive ----------------------------------------------
# The exact measurement, not a find+skip-list: three of five pills each
# wrote their own skip-list independently and all three came out wrong
# differently. This is what git itself tracks -- build output and local
# scratch never enter it, by construction (REPO-STANDARD.md's "honest
# measurement"). A pill's own check-repo should reference this variable
# instead of re-deriving the command by hand.
SUTRA_ROOT_ROWS = $(shell git ls-files | cut -d/ -f1 | sort -u | wc -l)

.PHONY: check-sutra-rows
check-sutra-rows:
	@echo "root row count: $(SUTRA_ROOT_ROWS)"

# --- the checkout-run guard ------------------------------------------------
# Till's form (ramstein tests/smoke.sh:296; maat, kast tests/smoke.sh:168):
# a binary that silently imported a DIFFERENT sutra.py off sys.path would
# still exit 0 -- rc=0 alone proves nothing about WHICH copy got imported.
# Prove the path Python actually bound, not a prediction of what it should be.
#
# CORRECTION (msg 2673, Alfred, caught by reproduction): the first cut of
# this target computed the EXPECTED path in shell from the bootstrap
# preamble's own formula and checked that a file exists there. That is a
# LAYOUT check, not a RESOLUTION check -- it never asks Python what the
# binary actually imported. A binary that forgot the bootstrap preamble
# entirely, sitting beside a stale co-located sutra.py (the exact
# pre-migration shape the whole ruling exists to clean up), would still
# import successfully (Python's own sys.path includes the script's own
# directory) and the shell arithmetic would still find a real file at the
# computed path -- green on the precise regression this guard exists to
# catch. Fixed: load the binary as a module for real and read back
# <module>.<SUTRA_CHECK_MODULE>.__file__, the path Python actually
# resolved, never a second shell computation of what it SHOULD be.
#
# SUTRA_CHECK_BIN is the pill-specific part: which binary to run.
# SUTRA_CHECK_MODULE is the attribute name the import binds (almost always
# "sutra"; a binary that only imports sutra_update, e.g. an update-spine-
# only tool, sets this to "sutra_update").
#
# DEFECT 5 (maat/kast, msg 2787): SUTRA_CHECK_BIN used to default to
# src/bin/$(PILL). Measured across five pills: that binary does not import
# sutra for two of them -- kast's src/bin/kast is the bash CLI (only
# kast-update imports sutra); phanspeed's src/bin/phanspeed has the same
# shape. A default that's wrong 40% of the time is a trap, not a default,
# and the failure it produces is confusing rather than obviously "you
# configured this wrong": line 262 only proves the path EXISTS, so a real
# file with no sutra binding gets run through the guard and fails looking
# like a broken vendor or a missing preamble, when the actual problem is
# that the wrong binary was named. No default here now -- every pill names
# its own sutra-importing binary explicitly, because a wrong guess that's
# sometimes right is worse than no guess: "I didn't set it and it passed"
# would be indistinguishable from "I set it correctly".
#
# SAFETY CORRECTION (Till/ramstein pilot, escalated by Alfred as family-
# wide, not ramstein-specific): the first cut defaulted SUTRA_CHECK_ARGS to
# "--help", on the assumption that's a universally safe, recognized flag.
# It is not. Three of ramstein's four binaries hand-roll their own argument
# parsing rather than using argparse, so an unrecognized "--help" falls
# through to their DEFAULT VERB -- for ramstein/ramstein-healthcheck that
# means `make check` makes a REAL socket call to the LIVE daemon on every
# single run. Harmless there by ramstein's own security model, but a pill
# whose default verb has a non-idempotent side effect would have this guard
# silently perform that side effect forever, unnoticed, because nothing
# about "the guard failed to print help" looks like an incident. tjmax's
# ACTUAL pattern (phanspeed Makefile:38-42) never assumed a generic flag --
# it uses "--selftest"/"--check", pill-specific flags the binary's own
# author added and verified are safe. So: no default here anymore.
# SUTRA_CHECK_ARGS is empty unless a pill sets it to a flag ITS OWN author
# has verified is safe and idempotent. Left empty, the real-subprocess
# sanity call below is skipped entirely -- this guard then relies solely on
# the resolution check, which never calls main() (a non-"__main__" module
# name, below) and is therefore safe against ANY binary regardless of how
# it parses arguments, known-safe flag or not.
SUTRA_CHECK_BIN ?=
SUTRA_CHECK_ARGS ?=
SUTRA_CHECK_MODULE ?= sutra

# A `define`/`endef` block, not a heredoc inlined into the recipe: GNU Make
# requires every physical recipe line to either start with a TAB or be a
# backslash-continuation of one, and a quoted heredoc's body is neither --
# measured, not assumed (the heredoc form hit "missing separator" the first
# time this was tried). `define` is Make's own mechanism for a multi-line
# value; `export` turns it into a real environment variable a subshell can
# read back with `$$VARNAME`, sidestepping Make's own recipe-line rules
# entirely for the payload. Piped to python3 via `printf '%s\n'`, not
# `echo`: dash's `echo` builtin (the family's `/bin/sh`) interprets `\n`/
# `\t` as real escapes in its argument, silently corrupting any embedded
# script that contains one as a Python string literal -- this script has
# none today so `echo` never broke it, but check-packages below does and
# hit exactly that corruption the first time it ran. `printf`'s `%s` never
# interprets its argument's content, only the format string, which is
# ours and escape-free.
define _SUTRA_CHECK_VENDORED_PATH_PY
import importlib.util
import os
import sys
from importlib.machinery import SourceFileLoader

bin_path, mod_attr, expected = sys.argv[1], sys.argv[2], sys.argv[3]
expected = os.path.realpath(expected)

# Two mistakes measured and corrected here, in order:
#
# 1. SourceFileLoader/exec_module does not add the loaded file's own
#    directory to sys.path, and neither does runpy.run_path on its own --
#    but a real `python3 <bin>` invocation always does, and that is
#    precisely the mechanism a stale sibling import exploits. Replicated
#    deliberately below rather than inherited for free.
# 2. runpy.run_path was tried next and gets (1) right with a manual
#    sys.path insert, but loses everything on an exception -- no partial
#    result. A binary whose import-time code raises something unrelated
#    AFTER a successful `import sutra` would then read as "never bound a
#    name", indistinguishable from actually missing the import.
#    exec_module instead updates the module object's namespace
#    incrementally as each top-level statement runs, so whatever was bound
#    BEFORE a later exception survives it -- inspect that, and report the
#    exception too, rather than silently discarding it.
bin_dir = os.path.dirname(os.path.abspath(bin_path))
sys.path.insert(0, bin_dir)
caught = None
try:
    loader = SourceFileLoader("_sutra_check_vendored_path_probe", bin_path)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    m = importlib.util.module_from_spec(spec)
    try:
        loader.exec_module(m)
    except BaseException as exc:
        caught = exc
finally:
    sys.path.remove(bin_dir)

actual_mod = getattr(m, mod_attr, None)
if actual_mod is None or not hasattr(actual_mod, "__file__"):
    detail = f" ({caught!r} raised while loading it)" if caught is not None else ""
    print(f"check-vendored-path FAIL: {bin_path!r} never bound a name {mod_attr!r} with a "
          f"__file__{detail} (missing the bootstrap preamble and the import entirely, or a "
          f"different attribute name -- set SUTRA_CHECK_MODULE=)")
    sys.exit(1)

actual = os.path.realpath(actual_mod.__file__)
if actual != expected:
    print(f"check-vendored-path FAIL: {bin_path} resolved {mod_attr} to {actual}, expected "
          f"{expected} -- it imported a DIFFERENT copy (stale sibling? missing bootstrap "
          f"preamble?)")
    sys.exit(1)

print(f"check-vendored-path: ok -- {bin_path} resolved {mod_attr} to {actual}")
endef
export _SUTRA_CHECK_VENDORED_PATH_PY

.PHONY: check-vendored-path
check-vendored-path:
	@[ -n "$(PILL)" ] || { echo "check-vendored-path: set PILL=<pill-name> before including sutra.mk"; exit 1; }
	@[ -n "$(SUTRA_CHECK_BIN)" ] || { echo "check-vendored-path: set SUTRA_CHECK_BIN=<path-to-your-sutra-importing-binary> -- no default, src/bin/<pill> does not import sutra for every pill (e.g. kast/phanspeed's main CLI)"; exit 1; }
	@[ -e "$(SUTRA_CHECK_BIN)" ] || { echo "check-vendored-path: no $(SUTRA_CHECK_BIN) -- SUTRA_CHECK_BIN points at a file that doesn't exist"; exit 1; }
	@if [ -n "$(SUTRA_CHECK_ARGS)" ]; then \
	    out=$$(python3 "$(SUTRA_CHECK_BIN)" $(SUTRA_CHECK_ARGS) 2>&1); rc=$$?; \
	    if [ $$rc -ne 0 ] && echo "$$out" | grep -qE 'ModuleNotFoundError|ImportError'; then \
	        echo "check-vendored-path FAIL: $(SUTRA_CHECK_BIN) could not import $(SUTRA_CHECK_MODULE) from the checkout:"; \
	        echo "$$out"; exit 1; \
	    fi; \
	fi; \
	expected="$$(cd "$(_SUTRA_MK_DIR)" && pwd)/$(SUTRA_CHECK_MODULE).py"; \
	printf '%s\n' "$$_SUTRA_CHECK_VENDORED_PATH_PY" | python3 - "$(SUTRA_CHECK_BIN)" "$(SUTRA_CHECK_MODULE)" "$$expected"

# --- check-vendored-path-all: the same guard, across every binary ---------
# PILOT FIX 2 (Till/ramstein): check-vendored-path validates exactly one
# SUTRA_CHECK_BIN per invocation. Any pill with more than one sutra-
# importing binary -- ramstein has four -- needs a loop, and left to each
# pill that becomes another hand-written supplement (Till wrote
# check-vendored-path-all with four $(MAKE) calls; that duplication across
# five pills is exactly what this file exists to prevent). Takes a list
# instead: SUTRA_CHECK_BINS, space-separated, each entry either a bare path
# (checked against SUTRA_CHECK_MODULE) or "path:module" (checked against
# that module specifically -- e.g. an update binary that binds
# sutra_update, not sutra). Empty by default; a pill with exactly one
# sutra-importing binary has no reason to set it and should just call
# check-vendored-path directly.
SUTRA_CHECK_BINS ?=

.PHONY: check-vendored-path-all
check-vendored-path-all:
	@[ -n "$(SUTRA_CHECK_BINS)" ] || { \
	    echo "check-vendored-path-all: SUTRA_CHECK_BINS is empty -- set it to a space-separated" \
	         "list of bin or bin:module entries, or call check-vendored-path directly for a" \
	         "single binary"; exit 1; }
	@fail=0; \
	for entry in $(SUTRA_CHECK_BINS); do \
	    bin="$${entry%%:*}"; \
	    if [ "$$entry" = "$$bin" ]; then mod="$(SUTRA_CHECK_MODULE)"; else mod="$${entry#*:}"; fi; \
	    $(MAKE) --no-print-directory check-vendored-path PILL=$(PILL) \
	        SUTRA_CHECK_BIN="$$bin" SUTRA_CHECK_MODULE="$$mod" SUTRA_CHECK_ARGS="$(SUTRA_CHECK_ARGS)" \
	        || fail=1; \
	done; \
	exit $$fail

# --- check-packages: Depends/Suggests generated from packages.txt, never
# hand-maintained -- ruling 2cd900ce (operator, 2026-08-03): the hard
# Depends floor is a short fixed list (python3/systemd/openssh-client plus
# documented domain exemptions), EVERYTHING else is Suggests -- never
# Recommends, because apt installs Recommends by default and a headless
# `apt install <pill>` must never pull GNOME Shell -- and build-time deps
# appear in neither tier. packages.txt becomes the generated source of
# control so the two can never drift again (dispatch msg 3356 via Alfred).
#
# Measured before building (msg 3364, confirmed msg 3365): packages.txt
# across the family already carries a "# --- hard (...) ---" / "# ---
# optional (...) ---" header-comment convention in three of five pills.
# Adopted here as the machine marker rather than inventing new syntax, so
# those three need zero reformatting. A line is read as a real dependency
# only inside an open hard/optional section, and only the text before its
# OWN trailing `# comment` -- everything else in the file, including a
# pill's build-time-only deps, is prose this parser never looks at. That
# is what keeps build-time deps out of control WITHOUT a special case for
# them: the thing you must not emit is simply unreachable, not merely
# forbidden -- same shape as SUTRA_EXT_DIR's opt-in above, a parser that
# sees nothing until a file is shaped for it.
#
# SUTRA_PACKAGES_TXT is the pill's own packages.txt. No default for
# SUTRA_PACKAGES_VERIFY_AGAINST -- same doctrine as SUTRA_CHECK_BIN above:
# a pill's real Depends line lives in a static packaging/debian/control
# for some pills (coldspot, phanspeed) and inside an inline Makefile
# heredoc for others (byebyte, ramstein, kast); no single guess is right
# for both shapes, and a wrong guess that's sometimes right is worse than
# refusing to guess.
#
# CONSTRAINT ON ADOPTING INLINE COMMENTS (found by Maat/kast, verified by
# Alfred, msg 3399): this format assumes packages.txt is read only by a
# human and by this parser. That is false for kast -- install.sh:245 feeds
# packages.txt's surviving lines straight to `apt-get install`, filtered
# only by `grep -Ev '^\s*(#|$)'` (drops whole-comment and blank lines, but
# does NOT strip a trailing inline `# comment` off an otherwise-real line).
# A bare-name-only file like kast's works today; a pill CANNOT SAFELY
# ADOPT this file's inline-comment style if anything else machine-parses
# the same file without first stripping trailing comments. Checked family-
# wide: byebyte/ramstein/coldspot/phanspeed/gestalt have no second
# consumer; kast alone does. RULE: before a pill's packages.txt gains
# inline comments, confirm nothing besides this parser reads the file
# directly, or fix that consumer to strip trailing `#...` first (one
# `sed 's/#.*//'` ahead of its own filter costs nothing). Same shape as
# the echo/printf bug above: a convention that is safe only because nobody
# has exercised the unsafe case yet, and says nothing about it on its own.
SUTRA_PACKAGES_TXT ?= packaging/packages.txt
SUTRA_PACKAGES_VERIFY_AGAINST ?=

# A `define`/`endef` + `export` block, not a heredoc inlined into the
# recipe -- same reason as _SUTRA_CHECK_VENDORED_PATH_PY above (GNU Make's
# recipe-line rules do not tolerate a quoted heredoc body).
define _SUTRA_CHECK_PACKAGES_PY
import re
import sys

HEADER_RE = re.compile(r'^#\s*-{2,}\s*(hard|optional|build)\b', re.IGNORECASE)


def parse(path):
    tiers = {"hard": [], "optional": [], "build": []}
    current = None
    with open(path) as f:
        for raw in f:
            line = raw.rstrip("\n")
            m = HEADER_RE.match(line)
            if m:
                current = m.group(1).lower()
                continue
            if current not in ("hard", "optional"):
                continue
            entry = line.split("#", 1)[0].strip()
            if entry:
                tiers[current].append(entry)
    return tiers


def find_field(name, text):
    # Not anchored to line-start: a static control file has "Depends:" as
    # the whole line, but a pill's inline Makefile heredoc has it embedded
    # mid-line inside a quoted echo, trailing "; \ -- quote, semicolon,
    # continuation backslash, each possibly separated by whitespace, not
    # one contiguous run. Strip one artifact char at a time, from the
    # right, until none remain -- a single regex class-match only eats a
    # CONTIGUOUS run and stops at the first space, which silently left a
    # trailing '"; \' on the Makefile shape the first time this was run
    # (measured, not assumed -- caught before landing, not after).
    m = re.search(name + r':\s*([^\n]*)', text)
    if not m:
        return None
    val = m.group(1).strip()
    while val and val[-1] in '\\;"\'':
        val = val[:-1].rstrip()
    return val


def entry_set(s):
    # Depends:/Suggests: is an unordered comma list to dpkg (no family
    # package here uses "|" alternatives, which WOULD be order-sensitive) --
    # compare as a set, not a string, or a control file that lists the same
    # packages in a different order than packages.txt reads as drift when
    # it is not. Measured: phanspeed's real control and packages.txt
    # disagreed only on order the first time this ran, not content.
    return {p.strip() for p in s.split(",") if p.strip()}


path = sys.argv[1]
mode = sys.argv[2]
tiers = parse(path)
depends = ", ".join(tiers["hard"])
suggests = ", ".join(tiers["optional"])

if mode == "--depends":
    print(depends)
elif mode == "--suggests":
    print(suggests)
elif mode == "--verify":
    target = sys.argv[3]
    with open(target) as f:
        text = f.read()
    fail = False
    recommends = find_field("Recommends", text)
    if recommends is not None:
        print(f"check-packages FAIL: {target} has a Recommends: line "
              f"({recommends!r}) -- family doctrine is Suggests only "
              f"(2cd900ce): apt installs Recommends by default")
        fail = True
    actual_depends = find_field("Depends", text)
    if entry_set(actual_depends or "") != entry_set(depends):
        print("check-packages FAIL: Depends mismatch")
        print(f"  {target}: {actual_depends!r}")
        print(f"  {path}:   {depends!r}")
        fail = True
    else:
        print(f"check-packages: Depends ok ({depends or '(empty)'})")
    actual_suggests = find_field("Suggests", text)
    if entry_set(actual_suggests or "") != entry_set(suggests):
        print("check-packages FAIL: Suggests mismatch")
        print(f"  {target}: {actual_suggests!r}")
        print(f"  {path}:   {suggests!r}")
        fail = True
    else:
        print(f"check-packages: Suggests ok ({suggests or '(none declared)'})")
    sys.exit(1 if fail else 0)
else:
    print(f"check-packages: unknown mode {mode!r} -- use --depends, "
          f"--suggests, or --verify <file>", file=sys.stderr)
    sys.exit(1)
endef
export _SUTRA_CHECK_PACKAGES_PY

.PHONY: check-packages
check-packages:
	@[ -f "$(SUTRA_PACKAGES_TXT)" ] || { echo "check-packages: no $(SUTRA_PACKAGES_TXT) -- set SUTRA_PACKAGES_TXT=<path>"; exit 1; }
	@[ -n "$(SUTRA_PACKAGES_VERIFY_AGAINST)" ] || { echo "check-packages: set SUTRA_PACKAGES_VERIFY_AGAINST=<path-to-your-control-file-or-Makefile> -- no default, see sutra.mk's own comment above this target"; exit 1; }
	@printf '%s\n' "$$_SUTRA_CHECK_PACKAGES_PY" | python3 - "$(SUTRA_PACKAGES_TXT)" --verify "$(SUTRA_PACKAGES_VERIFY_AGAINST)"
