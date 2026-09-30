#!/usr/bin/env python3
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fst import open_wave

VCD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "waveform.fst")

WANT = {
    "csa":    "s_debug_csa",
    "lc":     "s_lc_3_0",
    "zf":     "s_zf",
    "alu_f":  "s_f_15_0",
    "idb2":   "POW.s_idb2",
    "conn_n": "POW.s_conn_n",
}

def find_ids(vcd_path, want):
    scope = []
    found = {}
    with open_wave(vcd_path) as f:
        for line in f:
            s = line.strip()
            if s.startswith('$scope'):
                p = s.split()
                if len(p) >= 3: scope.append(p[2])
            elif s.startswith('$upscope'):
                if scope: scope.pop()
            elif s.startswith('$var'):
                p = s.split()
                if len(p) >= 5:
                    full = '.'.join(scope + [p[4]])
                    for key, substr in want.items():
                        if key not in found and substr in full:
                            found[key] = (p[3], int(p[2]), full)
            elif s.startswith('$enddefinitions'):
                break
    return found

ids = find_ids(VCD, WANT)
print('Signals found:')
for k, (sid, bits, full) in sorted(ids.items()):
    print('  %-10s  id=%r  %3dbit  %s' % (k, sid, bits, full))
missing = set(WANT) - set(ids)
if missing:
    print('MISSING:', missing)

id_map = {v[0]: k for k, v in ids.items()}

def tick(t): return t // 10 + 1

events = []
cur_t = 0
in_data = False

with open_wave(VCD) as f:
    for line in f:
        if not in_data:
            if '$enddefinitions' in line:
                in_data = True
            continue
        line = line.rstrip()
        if not line: continue
        if line[0] == '#':
            cur_t = int(line[1:])
            continue
        if line[0] in 'bBrR':
            parts = line.split(None, 1)
            if len(parts) == 2:
                sid = parts[1].strip()
                if sid in id_map:
                    k = id_map[sid]
                    try: v = int(parts[0][1:], 2); events.append((cur_t, k, v))
                    except ValueError: pass
        elif line[0] in '01xXzZ':
            sid = line[1:]
            if sid in id_map:
                k = id_map[sid]
                try: v = int(line[0]); events.append((cur_t, k, v))
                except ValueError: pass

print('Total events: %d' % len(events))

state = {k: 0 for k in WANT}
MOPC_ADDR = 0o002337
PANVC = 0o000050
found_mopc = False
recording = False
seq = []

for t, k, v in events:
    state[k] = v
    if k == 'csa':
        if v == MOPC_ADDR and not found_mopc:
            found_mopc = True
            recording = True
            seq = []
            print('\nFirst o002337 at tick %d' % tick(t))
        if recording:
            snap = dict(state)
            snap['tick'] = tick(t)
            snap['csa_v'] = v
            seq.append(snap)
            if len(seq) > 1000: break

if not found_mopc:
    print('MOPC never reached!')
    sys.exit(0)

print('\nCSA sequence (first 150 steps):')
print('  %8s  %8s  %3s  %8s  %4s  %4s  %6s' % ('tick','CSA','LC','ALU_F','ZF','IDB2','conn_n'))
for snap in seq[:150]:
    csa=snap['csa_v']; lc=snap.get('lc',0); f=snap.get('alu_f',0)
    zf=snap.get('zf',0); idb2=snap.get('idb2',0); cn=snap.get('conn_n',1); t=snap['tick']
    note = ''
    if csa==PANVC: note = '  <<< PANVC LC=%d' % lc
    elif csa==0: note = '  <<< RESTART'
    elif csa==0o002203: note = '  <<< STOP'
    elif csa==0o002333: note = '  <<< MS20'
    elif csa==0o002336: note = '  <<< MOPC'
    elif csa==0o002335: note = '  <<< MIPANS'
    elif csa==0o002001: note = '  <<< EXEC_START'
    print('  %8d  o%06o  %3d  o%06o  %4d  %4d  %6d%s' % (t,csa,lc,f,zf,idb2,cn,note))
