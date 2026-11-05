#!/bin/sh
# platform: host-agnostic
#   usage: workflow-invariants-test.sh     reads .github/workflows/release.yml and INGREDIENTS.md, never runs them
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
W="$ROOT/.github/workflows/release.yml"
fail() { echo "FAIL $1"; exit 1; }
[ -f "$W" ] || fail "no .github/workflows/release.yml"
job() { awk -v j="$1" '$0 == "  " j ":" { p = 1; next } p && /^  [a-z]/ { p = 0 } p' "$W"; }
jobs() { awk '/^jobs:/ { p = 1; next } p && /^  [a-z][a-z0-9_-]*:$/ { sub(/^  /, ""); sub(/:$/, ""); print }' "$W"; }
needs() { job "$1" | sed -n 's/^    needs: *//p' | tr -d '[]' | tr ',' '\n' | tr -d ' '; }
has_job() { jobs | grep -qx "$1"; }

! grep -q 'pull_request_target' "$W" || fail "pull_request_target would hand a fork PR this repo's secrets"
awk '/^permissions:/{p=1; next} p && /^[^ ]/{p=0} p' "$W" | grep -qx '  contents: read' \
  || fail "top-level permissions must be contents: read; only publish writes (the build jobs run third-party build code)"
job publish | grep -q 'contents: write' || fail "publish must declare its own contents: write"
nco="$(grep -c 'uses: actions/checkout@' "$W")"
npc="$(grep -c 'persist-credentials: false' "$W")"
[ "$nco" = "$npc" ] || fail "every checkout needs persist-credentials: false ($nco checkouts, $npc without persisted credentials)"

for j in ver build-cross build-native collect modern-smoke on-mavericks scan publish retry required; do
  has_job "$j" || fail "release.yml has no $j job"
done

for n in on-mavericks modern-smoke scan; do
  needs publish | grep -qx "$n" || fail "publish must need $n: nothing ships that the 10.9 guest, the Apple Silicon smoke and the key scan have not passed"
done

for j in $(jobs); do
  job "$j" | grep -q 'sign_and_appcast.sh' || continue
  scanner="$(for s in $(jobs); do if job "$s" | grep -q 'uses: Mavergreen/shipyard/.github/workflows/scan-for-key.yml@'; then echo "$s"; fi; done)"
  [ -n "$scanner" ] || fail "$j signs, so a job must call scan-for-key.yml before publish"
  needs "$scanner" | grep -qx "$j" || fail "$scanner must need $j, the job that signs"
  job "$scanner" | grep -q 'if: always()' || fail "$scanner must run under always(): a run that fails after signing left logs written while the key was in use"
done

for j in $(jobs); do
  job "$j" | grep -Eq 'version\.sh|release-mode\.sh|resolve-version\.sh|release-notes\.sh|build/build-|build/package-|build/versions\.sh' || continue
  job "$j" | grep -q 'uses: actions/checkout@' || fail "$j resolves a version but checks nothing out"
  job "$j" | grep -q 'fetch-depth: 0' || fail "$j resolves a version, so its checkout needs fetch-depth: 0 (N comes from the tags)"
done

RC="$ROOT/.github/workflows/reconcile.yml"
[ -f "$RC" ] || fail "no .github/workflows/reconcile.yml"
grep -Eq '^ +dispatch-field: reconcile=true$' "$RC" \
  || fail "reconcile.yml must dispatch with dispatch-field: reconcile=true: the default, local_release=true, always cuts N+1, so a nightly dispatch after a release had landed would cut a duplicate"
awk '/^  workflow_dispatch:/{p=1} p' "$W" | grep -Eq '^      reconcile:$' \
  || fail "release.yml's workflow_dispatch must take a reconcile input, which reconcile.yml sets"
v="$(job ver)"
printf '%s\n' "$v" | grep -q 'RECONCILE: \${{ inputs.reconcile }}' || fail "ver must read the reconcile input"
printf '%s\n' "$v" | grep -q 'GH_TOKEN: \${{ github.token }}' || fail "ver must give release-needed.sh a GH_TOKEN to read the releases"
gate="$(printf '%s\n' "$v" | awk '/if \[ "\$rel" = yes \] && \[ "\$RECONCILE" = true \]; then/{p=1} p{print} p && /^ *fi$/{exit}')"
printf '%s\n' "$gate" | grep -q 'release-state.sh' && printf '%s\n' "$gate" | grep -q 'release-needed.sh" --digest "$digest"' \
  && printf '%s\n' "$gate" | grep -q 'PUBLISH) : ;;' && printf '%s\n' "$gate" | grep -q 'rel=no' \
  || fail "ver must publish a reconcile=true run only when release-needed.sh still says PUBLISH for this tree's release-state.sh digest; otherwise a reconcile dispatch after a release landed cuts a duplicate"
out_at="$(printf '%s\n' "$v" | grep -n 'echo "release=\$rel"' | head -n 1 | cut -d: -f1)"
gate_at="$(printf '%s\n' "$v" | grep -n 'release-needed.sh" --digest' | head -n 1 | cut -d: -f1)"
[ -n "$out_at" ] && [ -n "$gate_at" ] && [ "$gate_at" -lt "$out_at" ] || fail "ver must apply the reconcile gate before it writes the release output"
printf '%s\n' "$v" | grep -q 'effective_local_release=true' || fail "a reconcile=true run must resolve the version as a local_release (N+1) would"

needs build-native | grep -qx build-cross || fail "build-native must need build-cross: it builds with build-cross's host zig"
bc="$(job build-cross)"
clear_at="$(printf '%s\n' "$bc" | grep -n 'rm -rf "\$OUT"' | head -n 1 | cut -d: -f1)"
build_at="$(printf '%s\n' "$bc" | grep -n 'tests/compat-matrix.sh .*"\$OUT"' | head -n 1 | cut -d: -f1)"
[ -n "$build_at" ] || fail "build-cross must build the compat matrix into \$OUT with tests/compat-matrix.sh ZIG OUTDIR"
[ -n "$clear_at" ] && [ "$clear_at" -lt "$build_at" ] || fail "build-cross must clear \$OUT before the matrix build, so no stale binary reaches the 10.9 guest"

ms="$(job modern-smoke)"
printf '%s\n' "$ms" | grep -Eq '^    runs-on: macos-' || fail "modern-smoke must run on a macos-* runner: the zig-cross slice is arm64"
printf '%s\n' "$ms" | grep -q 'installer -pkg "dist/zig-cross-' || fail "modern-smoke must install the run's own zig-cross pkg"
printf '%s\n' "$ms" | grep -q 'tests/smoke-cross.sh' || fail "modern-smoke must run tests/smoke-cross.sh"

vm="$(job on-mavericks)"
printf '%s\n' "$vm" | grep -q 'uses: Mavergreen/mavericks-vm@v1' || fail "on-mavericks must run in Mavergreen/mavericks-vm@v1"
printf '%s\n' "$vm" | grep -q 'packages: write' || fail "on-mavericks needs packages: write to cache the mavericks-vm image"
printf '%s\n' "$vm" | grep -q 'components/longboat/version' || fail "on-mavericks must install the pinned Longboat"
printf '%s\n' "$vm" | grep -q 'longboat sdk install 10.9' || fail "on-mavericks must install sdk109, which the zig pkg requires"
printf '%s\n' "$vm" | grep -q 'installer -pkg "dist/zig-\$' || fail "on-mavericks must install the run's own zig pkg"
printf '%s\n' "$vm" | grep -q 'tests/smoke-native.sh "\$' || fail "on-mavericks must run tests/smoke-native.sh with the version it installed"
printf '%s\n' "$vm" | grep -q 'alarm' || fail "on-mavericks must run each compat-matrix binary under a timeout (10.9 has no timeout(1)): a deadlocked sync must not hang the job"
printf '%s\n' "$vm" | grep -q 'rm -rf compat-matrix' || fail "on-mavericks must unpack the matrix into a fresh directory"
printf '%s\n' "$vm" | grep -q 'printf .*ZIG_FULL_VERSION.* > VERSION' \
  || fail "on-mavericks must write VERSION before the guest: with none, build/versions.sh asks version.sh, which asks git, and the 10.9 guest has none"
printf '%s\n' "$vm" | grep -q 'components/ca-certs/version' || fail "on-mavericks must fetch the pinned ca-certs pkg"
printf '%s\n' "$vm" | grep -q 'mavericks-clang-22-native-\$' || fail "on-mavericks must fetch the pinned clang-22 native pkg, which smoke-native's uselib_clang22 links with"
printf '%s\n' "$vm" | grep -q 'installer -pkg "deps/mavericks-clang-22-native-' || fail "on-mavericks must install clang22 in the guest"
printf '%s\n' "$vm" | grep -q 'SMOKE_NO_SKIP=1' || fail "on-mavericks must run smoke-native with SMOKE_NO_SKIP=1: a case that skips in the guest tested nothing"
absent_at="$(printf '%s\n' "$vm" | grep -n 'ZIG_SMOKE_CA_CERTS=absent .*tests/smoke-native.sh' | head -n 1 | cut -d: -f1)"
cacerts_at="$(printf '%s\n' "$vm" | grep -n 'installer -pkg "deps/ca-certs-' | head -n 1 | cut -d: -f1)"
present_at="$(printf '%s\n' "$vm" | grep -n 'ZIG_SMOKE_CA_CERTS=present .*tests/smoke-native.sh .*fetch_project' | head -n 1 | cut -d: -f1)"
matrix_at="$(printf '%s\n' "$vm" | grep -n 'tar -xf compat-matrix.tar' | head -n 1 | cut -d: -f1)"
[ -n "$absent_at" ] && [ -n "$cacerts_at" ] && [ -n "$present_at" ] && [ -n "$matrix_at" ] \
  && [ "$absent_at" -lt "$cacerts_at" ] && [ "$cacerts_at" -lt "$present_at" ] && [ "$cacerts_at" -lt "$matrix_at" ] \
  || fail "on-mavericks must smoke HTTPS without ca-certs, install ca-certs, smoke fetch_project with it, and only then run the matrix (its http program needs ca-certs on 10.9)"
printf '%s\n' "$vm" | grep -q 'run-repo-tests.sh' || fail "on-mavericks must run the repo's tests in the guest"

r="$(job required)"
printf '%s\n' "$r" | grep -qx '    name: required (release)' || fail "the gate job must be named 'required (release)'"
printf '%s\n' "$r" | grep -qx '    if: always()' || fail "the gate job must run under always()"
printf '%s\n' "$r" | grep -q 'uses: Mavergreen/shipyard/.github/actions/required-gate@v1' || fail "the gate job must use shipyard's required-gate action"
for j in $(jobs); do
  [ "$j" = required ] && continue
  needs required | grep -qx "$j" || fail "required must need every other job; it misses $j"
done
job retry | grep -q 'uses: Mavergreen/shipyard/.github/workflows/retry-release.yml@v1' || fail "retry must call retry-release.yml"
needs retry | grep -qx publish || fail "retry must need publish"

for j in $(jobs); do
  job "$j" | grep -Eq '^    runs-on: macos-' || continue
  grep -q "^- macos-runner:release.yml:$j: " "$ROOT/INGREDIENTS.md" \
    || fail "$j runs on macOS, so INGREDIENTS.md must declare '- macos-runner:release.yml:$j: <reason, exit>'"
done
grep -q '^- arm64:usr/local/mavergreen/zig-cross/\*: ' "$ROOT/INGREDIENTS.md" \
  || fail "INGREDIENTS.md must declare zig-cross's arm64 slice, which modern-smoke runs"
echo "OK workflow-invariants-test"
