#!/usr/bin/env python3
"""Find WCS/LUA/PROM signals in VCD header. Keywords searched in full signal path."""
from collections import defaultdict

import os
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.vcd")

KEYWORDS = ["lua", "prom", "wcstb", "csbits", "wca_", "blcs",
            "debug_lcs", "ecsl", "ewca", "wcs_n", "maclk",
            "regdata", "ww_3_0", "debug_csa", "s_lua", "s_wca"]

SCOPE_TAG   = "$scope"
UPSCOPE_TAG = "$upscope"
VAR_TAG     = "$var"
END_TAG     = "$enddefinitions"

scope = []
results = []
with open(VCD, "r", buffering=8*1024*1024) as f:
    for line in f:
        s = line.strip()
        if s.startswith(SCOPE_TAG):
            p = s.split()
            if len(p) >= 3:
                scope.append(p[2])
        elif s.startswith(UPSCOPE_TAG):
            if scope:
                scope.pop()
        elif s.startswith(VAR_TAG):
            p = s.split()
            if len(p) >= 5:
                full = ".".join(scope + [p[4]])
                fl = full.lower()
                if any(kw in fl for kw in KEYWORDS):
                    results.append((full, p[3], p[2]))
        elif s.startswith(END_TAG):
            break

print(f"Total matching signals: {len(results)}")
for full, sid, bits in sorted(results):
    print(f"  {sid:8s}  {bits:3s}bit  {full}")
