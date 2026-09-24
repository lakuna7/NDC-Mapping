"""
NDC Intelligence System - Windows Launcher
===========================================

Replaces the bash wrappers for Windows environments where bash is unavailable.
Extracts embedded Python from the .sh files and runs it with the correct
environment variables set.

Usage (from PowerShell, inside the commands/ folder):

    python run.py source_matrix 0006-0277
    python run.py geo_matrix 0006-0277
    python run.py shortages 0006-0277
    python run.py derived_kpis 0006-0277
    python run.py lookup 0006-0277
    python run.py lookup 0006

Or with explicit flags:

    python run.py source_matrix --input 0006-0277 --api-key YOUR_KEY
    python run.py derived_kpis --matrix-dir C:\\path\\to\\source_matrix --geo-dir C:\\path\\to\\geo_matrix
"""

import os
import re
import sys
import tempfile
import subprocess
from pathlib import Path


SCRIPT_MAP = {
    "source_matrix": "ndc_source_matrix.sh",
    "geo_matrix": "ndc_geo_matrix.sh",
    "shortages": "ndc_shortages.sh",
    "derived_kpis": "ndc_derived_kpis.sh",
    "lookup": "ndc_lookup.sh",
}

ALIASES = {
    "matrix": "source_matrix",
    "sm": "source_matrix",
    "geo": "geo_matrix",
    "gm": "geo_matrix",
    "short": "shortages",
    "sh": "shortages",
    "kpi": "derived_kpis",
    "kpis": "derived_kpis",
    "dk": "derived_kpis",
    "lu": "lookup",
    "look": "lookup",
}


def extract_python(sh_path):
    """Extract embedded Python from a bash heredoc script."""
    with open(sh_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    inside = False
    python_lines = []
    for line in lines:
        if not inside:
            if line.strip().startswith("exec python3") and "ENDOFPYTHON" in line:
                inside = True
                continue
        else:
            if line.strip() == "ENDOFPYTHON":
                break
            python_lines.append(line)

    if not python_lines:
        sys.exit("ERROR: Could not extract Python from " + str(sh_path))

    return "".join(python_lines)


def find_commands_dir():
    """Find the commands/ directory relative to this script."""
    this_dir = Path(__file__).resolve().parent
    if this_dir.name == "commands":
        return this_dir
    commands = this_dir / "commands"
    if commands.is_dir():
        return commands
    return this_dir


def resolve_project_root(commands_dir):
    """Resolve PROJECT_ROOT from the commands directory."""
    if commands_dir.name == "commands":
        return commands_dir.parent
    return commands_dir


def print_usage():
    print("")
    print("NDC Intelligence System - Windows Launcher")
    print("=" * 50)
    print("")
    print("Usage:")
    print("  python run.py <command> <input>")
    print("")
    print("Commands:")
    print("  source_matrix (or: matrix, sm)    Multi-source NDC-11 matrix")
    print("  geo_matrix    (or: geo, gm)       State-level geographic analysis")
    print("  shortages     (or: short, sh)     FDA drug shortage flags")
    print("  derived_kpis  (or: kpi, kpis, dk) Derived analytics")
    print("  lookup        (or: look, lu)       Family hierarchy browser")
    print("")
    print("Examples:")
    print("  python run.py lookup 0006              # browse all Merck products")
    print("  python run.py lookup 0006-0277         # see JANUVIA packages")
    print("  python run.py sm 0006-0277             # full source matrix")
    print("  python run.py geo 0006-0277            # state-level tables")
    print("  python run.py short 0006-0277          # shortage check")
    print("  python run.py kpi 0006-0277            # derived KPIs")
    print("")
    print("Options:")
    print("  --api-key KEY     openFDA API key (optional, higher rate limits)")
    print("  --workers N       parallel fetch threads (default: 8)")
    print("  --matrix-dir DIR  for derived_kpis: path to source_matrix output")
    print("  --geo-dir DIR     for derived_kpis: path to geo_matrix output")
    print("")


def main():
    args = sys.argv[1:]

    if not args or args[0] in ("-h", "--help", "help"):
        print_usage()
        return

    # Parse command
    cmd = args[0].lower().replace("-", "_")
    cmd = ALIASES.get(cmd, cmd)
    if cmd not in SCRIPT_MAP:
        print("ERROR: Unknown command '" + args[0] + "'")
        print_usage()
        sys.exit(1)

    # Parse remaining args
    ndc_input = ""
    api_key = ""
    max_workers = "8"
    cache_ttl = "24"
    include_wac = "1"
    matrix_dir = ""
    geo_dir = ""

    i = 1
    while i < len(args):
        a = args[i]
        if a == "--api-key" and i + 1 < len(args):
            api_key = args[i + 1]
            i += 2
        elif a == "--workers" and i + 1 < len(args):
            max_workers = args[i + 1]
            i += 2
        elif a == "--cache-ttl" and i + 1 < len(args):
            cache_ttl = args[i + 1]
            i += 2
        elif a == "--no-wac":
            include_wac = "0"
            i += 1
        elif a == "--matrix-dir" and i + 1 < len(args):
            matrix_dir = args[i + 1]
            i += 2
        elif a == "--geo-dir" and i + 1 < len(args):
            geo_dir = args[i + 1]
            i += 2
        elif not a.startswith("-"):
            ndc_input = a
            i += 1
        else:
            print("WARNING: Unknown flag '" + a + "', skipping")
            i += 1

    # Find paths
    commands_dir = find_commands_dir()
    project_root = resolve_project_root(commands_dir)
    sh_path = commands_dir / SCRIPT_MAP[cmd]

    if not sh_path.exists():
        sys.exit("ERROR: Script not found: " + str(sh_path))

    # Set up environment
    env = os.environ.copy()
    env["PROJECT_ROOT"] = str(project_root)
    env["BASH_SOURCE_DIR"] = str(commands_dir)
    env["OPENFDA_API_KEY"] = api_key
    env["MAX_WORKERS"] = max_workers
    env["CACHE_TTL_HOURS"] = cache_ttl
    env["INCLUDE_WAC"] = include_wac

    if cmd == "derived_kpis":
        if not ndc_input and not matrix_dir:
            print("ERROR: derived_kpis requires INPUT or --matrix-dir + --geo-dir")
            sys.exit(1)
        if ndc_input and not matrix_dir:
            input_safe = re.sub(r"[^A-Za-z0-9._-]", "_", ndc_input)
            matrix_dir = str(project_root / "exports" / "tables" / ("source_matrix_" + input_safe))
            geo_dir = str(project_root / "exports" / "tables" / ("geo_matrix_" + input_safe))
        env["MATRIX_DIR"] = matrix_dir
        env["GEO_DIR"] = geo_dir
        env["INPUT"] = ndc_input or "derived"
    else:
        if not ndc_input:
            print("ERROR: No NDC input provided.")
            print("  Example: python run.py " + cmd + " 0006-0277")
            sys.exit(1)
        env["INPUT"] = ndc_input

    # Extract and run Python
    python_code = extract_python(sh_path)

    # Write to temp file and execute
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".py", encoding="utf-8", delete=False
    ) as tmp:
        tmp.write(python_code)
        tmp_path = tmp.name

    try:
        python_exe = sys.executable or "python"
        result = subprocess.run(
            [python_exe, tmp_path],
            env=env,
            cwd=str(commands_dir),
        )
        sys.exit(result.returncode)
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


if __name__ == "__main__":
    main()
