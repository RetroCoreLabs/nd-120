import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave
VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")
SUBS = ['epans', 'EPANS', 'pres', 's_pres', 'idb_15_0_chip', 'debug_csa', 'f_15_0', 'pancal']
scope = []
found = []
with open_wave(VCD) as f:
    for line in f:
        s = line.strip()
        if s.startswith(''):
            p = s.split()
            if len(p) >= 3: scope.append(p[2])
        elif s.startswith(''):
            if scope: scope.pop()
        elif s.startswith(''):
            p = s.split()
            if len(p) >= 5:
                full = '.'.join(scope + [p[4]])
                for sub in SUBS:
                    if sub.lower() in full.lower():
                        found.append(full)
                        break
        elif s.startswith(''):
            break
for f in sorted(found): print(f)
