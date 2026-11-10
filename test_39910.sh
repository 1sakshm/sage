#!/usr/bin/env bash
# Verify the fix for sagemath/sage#39910 in a Codespace (runs from the repo root).
set -uo pipefail
cd "$(dirname "$0")"
LOG=~/test_39910.log


if [ ! -x ~/miniforge3/bin/conda ]; then
  echo "### Installing miniforge"
  curl -fsSL -o /tmp/mf.sh https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh
  bash /tmp/mf.sh -b -p ~/miniforge3
fi
source ~/miniforge3/etc/profile.d/conda.sh

if ! conda env list | grep -q '^sage '; then
  echo "### Creating sage env (sage + full GAP package set)"
  conda create -y -n sage -c conda-forge sage gap python=3.12 || { echo "### full gap not solvable, falling back"; conda create -y -n sage -c conda-forge sage python=3.12 || exit 1; }
fi
conda activate sage
sage --version

SITE=$(python -c "import sage, os; print(os.path.dirname(sage.__file__))")
MOD="$SITE/combinat/designs/incidence_structures.py"
cp -n "$MOD" "$MOD.orig"
cp "$MOD.orig" "$MOD"

echo "### Is the GAP design package available?"
sage -c 'print(gap.eval("TestPackageAvailability(\"design\")"))'

cat > /tmp/repro.sage <<'EOF'
BD = IncidenceStructure(7,[[0,1,2],[0,3,4],[0,5,6],[1,3,5],[1,4,6],[2,3,6],[2,4,5]])
gap.quit()
try:
    print("RESULT:", gap(BD))
except Exception as e:
    print("RESULT: FAILS ->", type(e).__name__, str(e)[:300])
EOF

echo "### BEFORE fix: plain repro"
sage /tmp/repro.sage

echo "### Applying patch from branch to installed module"
git diff 34cf369dd4f~1 34cf369dd4f -- src/sage/combinat/designs/incidence_structures.py > /tmp/fix.patch
patch "$MOD" < /tmp/fix.patch || { echo "PATCH FAILED"; exit 1; }

echo "### AFTER fix: plain repro"
sage /tmp/repro.sage

echo "### AFTER fix: doctests of the patched module (incl. optional design tests)"
sage -t --optional=sage,gap_package_design "$MOD"

echo "### BEFORE fix: doctests of the patched docstrings against the original code"
# Put the old code back but keep the new doctests: proves the new test catches the bug.
python - "$MOD" <<'EOF'
import sys, re
p = sys.argv[1]
s = open(p).read()
s = s.replace('        G.load_package("design")\n        return super()._gap_(G)',
              '        return super()._gap_(G)')
open(p, "w").write(s)
EOF
sage -t --optional=sage,gap_package_design "$MOD"

cp "$MOD.orig" "$MOD"
echo "### DONE"
