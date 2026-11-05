#!/bin/sh
# platform: host-agnostic -- CI-only: needs python3 (exits 77 where there is none)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "no python3 -- skipping"; exit 77; }
python3 -I - "$ROOT/.github/renovate.json" "$ROOT" <<'PY' || { echo "FAIL: renovate.json"; exit 1; }
import json, re, sys
c = json.load(open(sys.argv[1]))
root = sys.argv[2]
assert c["extends"] == ["github>Mavergreen/shipyard"], "extends"
mgrs = c["customManagers"]
def matching(path):
    return [m for m in mgrs if any(re.search(p.strip("/"), path) for p in m["managerFilePatterns"])]
for pin in ["UPSTREAM_VERSION", "components/clang/version", "components/longboat/version", "components/ca-certs/version"]:
    assert len(matching(pin)) == 1, "%s must be matched by exactly one manager" % pin
u = matching("UPSTREAM_VERSION")[0]
assert u["datasourceTemplate"] == "gitea-tags" and u["depNameTemplate"] == "ziglang/zig", "zig manager"
assert u["registryUrlTemplate"] == "https://codeberg.org", "codeberg registry"
assert "extractVersionTemplate" not in u, "zig tags are bare"
k = matching("components/clang/version")[0]
assert k["depNameTemplate"] == "Mavergreen/clang-22" and k["datasourceTemplate"] == "github-releases", "clang manager"
assert k["versioningTemplate"].startswith("regex:") and "mavericks" in k["versioningTemplate"], "clang -mavericks.N versioning"
l = matching("components/longboat/version")[0]
assert l["depNameTemplate"] == "Mavergreen/longboat", "longboat manager"
a = matching("components/ca-certs/version")[0]
assert a["depNameTemplate"] == "Mavergreen/ca-certs" and a["datasourceTemplate"] == "github-releases", "ca-certs manager"
assert a["versioningTemplate"].startswith("regex:") and "mavericks" in a["versioningTemplate"], "ca-certs -mavericks.N versioning"
assert not any("automerge" in r for r in c.get("packageRules", [])), "no packageRule may set automerge: the shipyard preset decides"
PY
echo "PASS: renovate"
