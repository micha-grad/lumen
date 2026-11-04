#!/usr/bin/env python3
"""Run a llama.cpp CLI and measure wall-clock time to first generated text.

Usage: ttft_wall.py <ready-regex> <out-prefix> -- <command...>

"ready" is the moment the CLI logs a line matching <ready-regex> on stderr (end of
model loading and warm-up). TTFT is measured from that line to the first
non-whitespace byte the CLI writes on stdout. Both clocks are this script's
monotonic clock, so log-timestamp offsets do not matter.
Writes <out-prefix>.out, <out-prefix>.err and prints "ttft_wall_ms=<value>".
"""
import os, re, selectors, subprocess, sys, time

ready_re = re.compile(sys.argv[1])
prefix = sys.argv[2]
cmd = sys.argv[sys.argv.index("--") + 1:]

proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
sel = selectors.DefaultSelector()
sel.register(proc.stdout, selectors.EVENT_READ, "out")
sel.register(proc.stderr, selectors.EVENT_READ, "err")
out_f, err_f = open(prefix + ".out", "wb"), open(prefix + ".err", "wb")
t_ready = t_first = None
err_buf = b""
open_streams = 2
while open_streams:
    for key, _ in sel.select():
        data = os.read(key.fileobj.fileno(), 65536)
        now = time.monotonic()
        if not data:
            sel.unregister(key.fileobj)
            open_streams -= 1
            continue
        if key.data == "out":
            out_f.write(data)
            if t_first is None and t_ready is not None and data.strip():
                t_first = now
        else:
            err_f.write(data)
            if t_ready is None:
                err_buf += data
                if ready_re.findall(err_buf.decode("utf-8", "replace")):
                    t_ready = now
rc = proc.wait()
out_f.close(); err_f.close()
if t_ready is None or t_first is None:
    sys.exit("error: ready line or first output not seen (rc=%d)" % rc)
print("ttft_wall_ms=%.1f" % ((t_first - t_ready) * 1000.0))
sys.exit(rc)
