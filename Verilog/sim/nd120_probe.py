#!/usr/bin/env python3
r"""
nd120_probe.py - pexpect-style driver for the ND-120 generic sim PROBE.

Mirrors the ergonomics of nd100x's tools/nd100x_expect.py, but instead of
driving a terminal it drives the nd120_probe.cpp ENGINE over a machine-parseable
line protocol on stdin/stdout. The engine is built (WSL only) via:

    make probe USE_LATCHES=0     # -> obj_dir_probe/VND120_TOP

Then from Python (stdlib only):

    from nd120_probe import Probe
    with Probe(bpun="INSTRUCTION-B.BPUN") as p:      # FF mode default
        p.watch_group("MMU"); p.watch_group("STORE")
        p.set(pre=64, post=64); p.open("mmu_177777.csv")
        p.rule("shadow", 'MMU.s_wmap_n==0', ["log"])
        p.run(200000)
        ev = p.runto('CSA_12_0 == o6000', maxticks=1_000_000)
        print(p.examine(0o177777))                    # backdoor verify

Protocol (engine replies, all unbuffered):
    OK ...      command succeeded
    ERR ...     command failed
    VAL ...     a value reply (get / examine / console)
    EVENT ...   a rule fired (id=, trig=, tick=, ...)
    LOG ...     a rule log line (rule=, tick=, sig=val ...)

The engine also mirrors emulated-terminal (UART) output to its STDERR, so the
console stream never corrupts the stdout protocol. wait_console() reads stderr.

WSL note: on Windows the engine binary lives under the WSL filesystem and must be
launched through `wsl.exe -e bash -lc`. Pass wsl=True (default on Windows) so the
driver wraps the command. On Linux it is spawned directly.
"""

import os
import re
import sys
import time
import threading
import subprocess


class ProbeError(Exception):
    """Raised when the engine replies ERR or a command times out."""


class Event:
    """A parsed EVENT line: fields captured as a dict (all strings)."""
    def __init__(self, raw, fields):
        self.raw = raw
        self.fields = fields

    def __repr__(self):
        return "Event(%r)" % self.fields

    def __getitem__(self, k):
        return self.fields.get(k)


# Default engine path (relative to this file: sim/obj_dir_probe/VND120_TOP).
_HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ENGINE = os.path.join(_HERE, "obj_dir_probe", "VND120_TOP")

def _to_wsl_path(p):
    r"""A Windows path (X:\a\b) as WSL sees it (/mnt/<drive>/a/b); any other path is returned as is."""
    if re.match(r"^[A-Za-z]:", p):
        return "/mnt/%s%s" % (p[0].lower(), p[2:].replace("\\", "/"))
    return p


# The sim/ directory as seen from INSIDE WSL (so we can cd there and use relative
# BPUN paths). Overridable via ND120_SIM_WSLDIR. The default is this file's own
# folder, translated to its WSL form, so no machine path is written here.
DEFAULT_WSLDIR = os.environ.get(
    "ND120_SIM_WSLDIR", _to_wsl_path(_HERE))


def _line_fields(line):
    """Parse `key=value` tokens out of a protocol line into a dict.

    The leading verb (OK/ERR/VAL/EVENT/LOG) is stored under '_verb'; bare tokens
    that are not key=value are appended to a list under '_args'.
    """
    parts = line.split()
    out = {"_verb": parts[0] if parts else "", "_args": []}
    for tok in parts[1:]:
        if "=" in tok:
            k, v = tok.split("=", 1)
            out[k] = v
        else:
            out["_args"].append(tok)
    return out


class Probe:
    """A running nd120_probe engine you drive with load/watch/rule/run/get/..."""

    def __init__(self, bpun=None, engine=None, latches=False, wsl=None,
                 wsldir=None, extra_args=None, echo_console=True, timeout=60):
        """
        bpun         - BPUN to load at startup (path relative to the sim dir, or absolute).
        engine       - path to the built VND120_TOP (default: sim/obj_dir_probe/VND120_TOP).
        latches      - kept for API symmetry; the binary's latch/FF mode is a BUILD choice.
        wsl          - wrap the launch in `wsl.exe -e bash -lc` (default: True on Windows).
        wsldir       - directory to cd into inside WSL (default: DEFAULT_WSLDIR).
        echo_console - mirror the engine's emulated-terminal (stderr) to our stderr.
        """
        self.engine = engine or DEFAULT_ENGINE
        self.bpun = bpun
        self.wsl = (os.name == "nt") if wsl is None else wsl
        self.wsldir = wsldir or DEFAULT_WSLDIR
        self.extra_args = extra_args or []
        self.echo_console = echo_console
        self.timeout = timeout

        self._proc = None
        self._lock = threading.Lock()
        self._lines = []            # parsed protocol lines (dicts) from stdout
        self._events = []           # EVENT/LOG lines, in order
        self._console = bytearray() # raw stderr (emulated terminal)
        self._readers = []
        self._closed = False

    # -- lifecycle ---------------------------------------------------------
    def _build_cmd(self):
        if self.wsl:
            # Launch the ELF under WSL. cd into the sim dir so relative BPUN paths work.
            eng = self.engine
            # Translate a Windows path to a /mnt path if needed.
            eng = _to_wsl_path(eng)
            inner = "cd %s && exec %s %s" % (self.wsldir, eng, " ".join(self.extra_args))
            return ["wsl.exe", "-e", "bash", "-lc", inner]
        return [self.engine] + self.extra_args

    def start(self):
        self._proc = subprocess.Popen(
            self._build_cmd(), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, bufsize=0)
        self._readers = [
            threading.Thread(target=self._pump_stdout, daemon=True),
            threading.Thread(target=self._pump_stderr, daemon=True),
        ]
        for t in self._readers:
            t.start()
        # Engine prints "OK probe ready ..." on startup.
        self.expect_ok(timeout=self.timeout, what="startup")
        if self.bpun:
            self.load(self.bpun)
        return self

    def _pump_stdout(self):
        for raw in iter(self._proc.stdout.readline, b""):
            line = raw.decode("latin-1", "replace").rstrip("\r\n")
            if not line:
                continue
            fields = _line_fields(line)
            with self._lock:
                self._lines.append((line, fields))
                if fields["_verb"] in ("EVENT", "LOG"):
                    self._events.append((line, fields))

    def _pump_stderr(self):
        for chunk in iter(lambda: self._proc.stderr.read(256), b""):
            with self._lock:
                self._console.extend(chunk)
            if self.echo_console:
                sys.stderr.buffer.write(chunk)
                sys.stderr.buffer.flush()

    def __enter__(self):
        return self.start()

    def __exit__(self, *exc):
        self.close()

    def close(self):
        if self._closed:
            return
        self._closed = True
        try:
            if self._proc and self._proc.poll() is None:
                self._send("quit")
                self._proc.wait(timeout=5)
        except Exception:
            try:
                self._proc.terminate()
            except Exception:
                pass

    # -- low-level protocol I/O -------------------------------------------
    def _send(self, cmd):
        if self._proc is None or self._proc.stdin is None:
            raise ProbeError("engine not running")
        self._proc.stdin.write((cmd + "\n").encode("latin-1", "replace"))
        self._proc.stdin.flush()

    def _next_reply(self, timeout, want=("OK", "ERR", "VAL"), what=""):
        """Wait for the next terminal reply line (OK/ERR/VAL) after issuing a command.

        Returns the parsed fields dict. Raises ProbeError on ERR or timeout.
        EVENT/LOG lines are collected separately and skipped here.
        """
        deadline = time.time() + timeout
        idx = 0
        with self._lock:
            idx = len(self._lines)
        while True:
            with self._lock:
                lines = self._lines[idx:]
            for (line, f) in lines:
                idx += 1
                if f["_verb"] in want:
                    if f["_verb"] == "ERR":
                        raise ProbeError("%s: %s" % (what or "command", line))
                    return f
            if self._proc.poll() is not None:
                raise ProbeError("engine exited (%s)" % what)
            if time.time() > deadline:
                raise ProbeError("timeout waiting for %s reply (%s)" % (want, what))
            time.sleep(0.005)

    def cmd(self, text, timeout=None, want=("OK", "ERR", "VAL")):
        """Send a raw protocol command and return the parsed reply fields."""
        self._send(text)
        return self._next_reply(timeout or self.timeout, want=want, what=text)

    def expect_ok(self, timeout=None, what=""):
        return self._next_reply(timeout or self.timeout, want=("OK", "ERR"), what=what)

    # -- high-level API ----------------------------------------------------
    def load(self, path):
        return self.cmd("load %s" % path)

    def deposit(self, addr, val):
        return self.cmd("deposit %o %o" % (int(addr), int(val)))

    def examine(self, addr):
        f = self.cmd("examine %o" % int(addr), want=("VAL", "ERR"))
        # VAL <addr> <val>  (both octal)
        return int(f["_args"][1], 8) if len(f["_args"]) >= 2 else None

    def get(self, signal):
        """One-shot signal read. Returns an int (octal on the wire) or None if unresolved."""
        f = self.cmd("get %s" % signal, want=("VAL", "ERR"))
        return int(f["_args"][1], 8) if len(f["_args"]) >= 2 else None

    def rtc(self, cycles_20ms=None, cycles_5ms=None):
        """Retune the simulation RTC period at runtime (decimal sysclk cycles).

        The boot is RTC-paced - OPCOM services one input/output character per RTC
        tick - so a slow period compiled in makes the boot itself just as slow.
        Boot at the fast default, then call this once at the TPE> prompt to give
        rate-sensitive software a realistic clock. Omitting cycles_5ms keeps the
        4:1 ratio; calling with no arguments just reports the current values.
        """
        if cycles_20ms is None:
            return self.cmd("rtc")
        if cycles_5ms is None:
            return self.cmd("rtc %d" % cycles_20ms)
        return self.cmd("rtc %d %d" % (cycles_20ms, cycles_5ms))

    def watch(self, signal):
        return self.cmd("watch add %s" % signal)

    def watch_group(self, group):
        return self.cmd("watch group %s" % group)

    def watch_clear(self):
        return self.cmd("watch clear")

    def set(self, pre=None, post=None):
        if pre is not None:
            self.cmd("set pre %d" % int(pre))
        if post is not None:
            self.cmd("set post %d" % int(post))

    def open(self, csv_path):
        """Select the compact CSV sink (alias of `capture csv`)."""
        return self.cmd("open %s" % csv_path)

    def capture(self, csv=None, fst=None, off=False):
        if off:
            return self.cmd("capture off")
        if csv:
            self.cmd("capture csv %s" % csv)
        if fst:
            self.cmd("capture fst %s" % fst)

    def rule(self, name, expr, actions, level=False):
        """Add a reactive rule: WHEN <expr> DO <actions>.

        actions is a list; each item is either "act" or "act:arg" (arg may be a
        quoted string for log:/mark:). E.g. rule("w","MMU.s_wmap_n==0",["log","fst_on"]).
        """
        act_spec = ",".join(actions)
        lv = " level" if level else ""
        return self.cmd('rule add %s%s when "%s" do %s' % (name, lv, expr, act_spec))

    def rule_clear(self, name="all"):
        return self.cmd("rule clear %s" % name)

    def run(self, ticks):
        """Step `ticks` full sysclk cycles. EVENT/LOG lines land in .events."""
        f = self.cmd("run %d" % int(ticks), timeout=max(self.timeout, ticks / 5000 + 30))
        return f

    def runto(self, expr, maxticks=1_000_000):
        """Run until `expr` fires (one-shot rule with event+stop). Returns the
        firing Event, or None if maxticks was exhausted first."""
        before = len(self._events)
        f = self.cmd('runto "%s" %d' % (expr, int(maxticks)),
                     timeout=max(self.timeout, maxticks / 5000 + 30))
        hit = f.get("hit") == "1"
        if not hit:
            return None
        # Return the EVENT emitted by the temp __runto__ rule.
        with self._lock:
            for (line, ff) in self._events[before:]:
                if ff["_verb"] == "EVENT" and ff.get("trig") == "__runto__":
                    return Event(line, ff)
        return Event(f.get("_verb", ""), f)

    def reset(self):
        return self.cmd("reset")

    def send(self, text):
        """Queue chars to the emulated UART TX (use \\r for CR)."""
        return self.cmd("send %s" % text)

    # -- event / console helpers ------------------------------------------
    def events(self, since=0):
        with self._lock:
            return [Event(l, f) for (l, f) in self._events[since:]]

    def expect_event(self, trig=None, timeout=30):
        """Block until an EVENT whose trig= matches appears; returns the Event."""
        deadline = time.time() + timeout
        idx = 0
        with self._lock:
            idx = len(self._events)
        while True:
            with self._lock:
                pend = self._events[idx:]
            for (line, f) in pend:
                idx += 1
                if f["_verb"] == "EVENT" and (trig is None or f.get("trig") == trig):
                    return Event(line, f)
            if self._proc.poll() is not None:
                raise ProbeError("engine exited waiting for event %r" % trig)
            if time.time() > deadline:
                raise ProbeError("timeout waiting for event %r" % trig)
            time.sleep(0.01)

    def console_text(self):
        with self._lock:
            return bytes(self._console).decode("latin-1", "replace")

    def wait_console(self, pattern, timeout=30):
        """Wait for `pattern` (regex) to appear in emulated-terminal output."""
        rx = re.compile(pattern.encode() if isinstance(pattern, str) else pattern)
        deadline = time.time() + timeout
        while True:
            with self._lock:
                window = bytes(self._console)
            m = rx.search(window)
            if m:
                return m.group(0).decode("latin-1", "replace")
            if self._proc.poll() is not None:
                raise ProbeError("engine exited waiting for console %r" % pattern)
            if time.time() > deadline:
                raise ProbeError("timeout waiting for console %r" % pattern)
            time.sleep(0.02)


if __name__ == "__main__":
    # Tiny smoke self-test when run directly: spawn, load, run, read CSA.
    with Probe(bpun="INSTRUCTION-B.BPUN") as p:
        print("signals:", p.cmd("signals")["_args"][:6], "...")
        p.run(2000)
        print("CSA_12_0 =", oct(p.get("CSA_12_0")))
        print("examine 0 =", oct(p.examine(0)))
