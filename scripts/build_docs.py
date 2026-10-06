#!/usr/bin/env python3
"""Build the public-library DocC catalogs without changing Package.swift."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
MODULES = ("Roost", "RoostTest")


def run(arguments, **kwargs):
    print("+ " + shlex.join(str(argument) for argument in arguments), flush=True)
    return subprocess.run([str(argument) for argument in arguments], check=True, **kwargs)


def main():
    cache_base = Path.home() / "Library/Caches" if sys.platform == "darwin" else Path(
        os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")
    )
    checkout = hashlib.sha256(str(ROOT).encode()).hexdigest()[:16]
    cache = cache_base / "roost-documentation" / checkout
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-path", type=Path, default=cache / "build",
                        help="SwiftPM build directory (defaults outside the source checkout)")
    parser.add_argument("--output", type=Path, default=cache / "Roost.doccarchive",
                        help="combined documentation archive and static website directory")
    parser.add_argument("--hosting-base-path", default="/",
                        help="URL prefix when hosting under a subdirectory, such as /swift-roost/docs")
    args = parser.parse_args()
    scratch = args.scratch_path.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if output.suffix != ".doccarchive":
        parser.error("--output must end in .doccarchive")
    if output.exists() and not (output / "metadata.json").is_file():
        parser.error("--output exists but is not a DocC archive")
    docc = None if sys.platform == "darwin" else shutil.which("docc")
    if docc is None and shutil.which("xcrun"):
        docc = subprocess.check_output(["xcrun", "--find", "docc"], text=True).strip()
    docc = docc or shutil.which("docc")
    if not docc:
        parser.error("DocC is required; select an Xcode or Swift toolchain that includes docc")

    # Use SwiftPM's native builder: Swift Build on Xcode 27 also tries to extract
    # documentation for dependency C headers, including Linux-only headers.
    # Extract current declarations and documentation comments. A dedicated scratch
    # path also keeps signed SwiftPM resource bundles outside synced source folders.
    # SwiftPM 6.4 also requests the synthetic test-runner graph. Build that
    # module first; this compiles tests but does not execute them or open a DB.
    run(["swift", "build", "--package-path", ROOT, "--scratch-path", scratch,
         "--build-system", "native", "--build-tests"])
    result = run(["swift", "package", "--package-path", ROOT, "--scratch-path", scratch,
                  "--build-system", "native",
                  "dump-symbol-graph", "--minimum-access-level", "public",
                  "--skip-synthesized-members", "--emit-extension-block-symbols"], stdout=subprocess.PIPE, text=True)
    print(result.stdout, end="", flush=True)
    match = re.search(r"^Files written to (.+)$", result.stdout, re.MULTILINE)
    if not match:
        raise RuntimeError("SwiftPM did not report its symbol graph output directory")
    graphs = Path(match.group(1).strip())
    output.parent.mkdir(parents=True, exist_ok=True)

    # Each catalog receives only its own module's graphs. Keep conversion outputs
    # temporary so a failed link check cannot replace a previously built website.
    with tempfile.TemporaryDirectory(prefix="roost-docc-", dir=output.parent) as temporary:
        workspace = Path(temporary)
        archives = []
        for module in MODULES:
            module_graphs = workspace / module
            module_graphs.mkdir()
            graph = graphs / f"{module}.symbols.json"
            if not graph.is_file():
                raise RuntimeError(f"Missing symbol graph for {module}: {graph}")
            for source in [graph, *graphs.glob(f"{module}@*.symbols.json")]:
                shutil.copy2(source, module_graphs / source.name)
            archive = workspace / f"{module}.doccarchive"
            command = [docc, "convert", ROOT / "Sources" / module / f"{module}.docc",
                 "--additional-symbol-graph-dir", module_graphs,
                 "--output-path", archive,
                 "--fallback-bundle-identifier", f"dev.roost.{module}",
                 "--fallback-default-module-kind", "Library",
                 "--hosting-base-path", args.hosting_base_path,
                 "--warnings-as-errors", "--analyze",
                 "--enable-experimental-external-link-support"]
            for dependency in archives:
                command.extend(["--dependency", dependency])
            run(command)
            archives.append(archive)
        combined = workspace / "Combined.doccarchive"
        run([docc, "merge", *archives, "--output-path", combined,
             "--synthesized-landing-page-name", "Roost Libraries"])
        previous = workspace / "Previous.doccarchive"
        if output.exists():
            output.rename(previous)
        try:
            combined.rename(output)
        except OSError:
            if previous.exists():
                previous.rename(output)
            raise

    print(f"\nDocumentation: {output}")
    prefix = args.hosting_base_path.strip("/")
    if prefix:
        print(f"Mount this archive at /{prefix}/ on your static host.")
    else:
        serve = ["python3", "-m", "http.server", "8000", "--bind", "127.0.0.1", "--directory", str(output)]
        print("Serve locally: " + shlex.join(serve))
        print("Open: http://127.0.0.1:8000/documentation/")


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, RuntimeError, OSError) as error:
        print(f"Documentation build failed: {error}", file=sys.stderr)
        sys.exit(1)
