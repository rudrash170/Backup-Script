"""
backup.py - Create a compressed archive of a directory, supporting incremental backups.
"""

import argparse
import subprocess
import sys
import os
from pathlib import Path

def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description="Create a compressed archive of directories (incremental supported)")
    parser.add_argument('--source', required=True, action='append', help='Directory to back up (can repeat)')
    parser.add_argument('--output', required=True, help='Output tar.gz file')
    parser.add_argument('--snapshot', required=False, help='Snapshot file for incremental backup')
    parser.add_argument('--exclude', nargs='*', default=[], help='Patterns to exclude from backup')
    return parser.parse_args()

def main():
    """Create a compressed archive of the source directories."""
    args = parse_args()

    # If only one source, keep compatibility
    # Flatten list because action='append'
    sources = [os.path.abspath(s) for group in args.source for s in group.split()]  # allow accidental space separated
    if not sources:
        sys.stderr.write("No sources provided\n")
        sys.exit(1)

    # If all sources share a common ancestor, use -C optimization; else tar absolute paths
    parents = {str(Path(s).parent) for s in sources}
    use_chdir = len(parents) == 1
    parent_dir = parents.pop() if use_chdir else None
    base_names = [os.path.basename(s) for s in sources]

    cmd = ['tar']
    if args.snapshot:
        cmd.append(f'--listed-incremental={args.snapshot}')
    cmd.append('-czf')
    cmd.append(args.output)
    # place excludes early
    for pattern in args.exclude:
        cmd.append(f'--exclude={pattern}')
    if use_chdir:
        cmd.extend(['-C', parent_dir])
        cmd.extend(base_names)
    else:
        # fallback to absolute paths
        cmd.extend(sources)

    try:
        result = subprocess.run(cmd, stderr=subprocess.PIPE)
    except Exception as exc:
        sys.stderr.write(f"Failed executing tar: {exc}\n")
        sys.exit(1)
    if result.returncode != 0:
        sys.stderr.write(result.stderr.decode())
        sys.exit(1)

if __name__ == "__main__":
    main()
