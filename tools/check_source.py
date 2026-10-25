"""Verify reviewed Phoenix rules and Cadence calculations without changing either tree."""
import argparse
from pathlib import Path

from generate_modifiers import REF
from source_parity import GitSource, check


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', type=Path, default=Path(__file__).resolve().parents[2] / 'Phoenix')
    parser.add_argument('--ref', default=REF, help='revision to compare with the reviewed rules')
    args = parser.parse_args()
    source = GitSource(args.server, args.ref)
    counts = check(source)
    print('Source parity passed at %s: %d TP, %d recovery, %d delay and %d re-engage cases.'
          % (source.ref, counts['tp'], counts['recovery'], counts['delay'], counts['reengage']))
    print('The delay profile uses 0.93; this checks source and offline calculations, not deployed settings or gameplay.')


if __name__ == '__main__':
    main()
