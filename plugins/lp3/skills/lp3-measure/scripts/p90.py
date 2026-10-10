#!/usr/bin/env python3
"""Nearest-rank percentiles for timing samples.

    p90.py [--key NAME] [--drop N] [FILE ...]      # reads stdin when no FILE is given

Input lines are bare numbers, or log lines carrying key=value pairs (logcat lines work as they are).
With --key, only NAME=<number> values count. Without it, bare numbers form one series and each key
found in key=value pairs forms its own.

--drop N drops the first N samples of each series (warm-up frames, a first cold open).

Prints one line per series: name, n, P50, P90, P99, max. Percentiles are nearest-rank: the value at
1-based rank ceil(p * n) in sorted order, so every reported number is a real sample.
Exit 0 = printed. 1 = no samples. 64 = usage.
"""
import argparse
import math
import re
import sys

PAIR = re.compile(r"([A-Za-z_][A-Za-z0-9_.]*)=(-?[0-9]+(?:\.[0-9]+)?)\b")
NUMBER = re.compile(r"^\s*(-?[0-9]+(?:\.[0-9]+)?)\s*$")


def nearest_rank(sorted_values, p):
    # round() first, so a product a hair above a whole number in floating point doesn't move up a rank.
    rank = max(1, math.ceil(round(p * len(sorted_values), 9)))
    return sorted_values[rank - 1]


def collect(lines, key):
    series = {}
    for line in lines:
        bare = NUMBER.match(line)
        if bare and key is None:
            series.setdefault("value", []).append(float(bare.group(1)))
            continue
        for name, value in PAIR.findall(line):
            if key is None or name == key:
                series.setdefault(name, []).append(float(value))
    return series


def fmt(x):
    return str(int(x)) if x == int(x) else f"{x:.3f}".rstrip("0")


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--key")
    parser.add_argument("--drop", type=int, default=0)
    parser.add_argument("files", nargs="*")
    try:
        args = parser.parse_args(argv)
    except SystemExit as e:
        return 0 if e.code == 0 else 64
    if args.drop < 0:
        print("--drop must be 0 or more", file=sys.stderr)
        return 64

    lines = []
    if args.files:
        for path in args.files:
            with open(path, encoding="utf-8", errors="replace") as f:
                lines.extend(f)
    else:
        lines = sys.stdin.readlines()

    series = collect(lines, args.key)
    printed = False
    for name in sorted(series):
        values = sorted(series[name][args.drop:])
        if not values:
            continue
        cols = [nearest_rank(values, p) for p in (0.5, 0.9, 0.99)] + [values[-1]]
        print(f"{name} n={len(values)} " + " ".join(
            f"{label}={fmt(v)}" for label, v in zip(("p50", "p90", "p99", "max"), cols)))
        printed = True
    if not printed:
        print("no samples", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
