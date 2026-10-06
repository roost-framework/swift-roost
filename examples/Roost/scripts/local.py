#!/usr/bin/env python3
"""Run the example locally or test it in a database owned by this invocation."""
import getpass
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

APP = Path(__file__).resolve().parents[1]
FRAMEWORK = APP.parents[1]


def run(args, env, *, cwd=APP, capture=False, input=None):
    return subprocess.run(
        [str(arg) for arg in args], cwd=cwd, env=env, text=True,
        check=True, input=input, stdout=subprocess.PIPE if capture else None,
    ).stdout


def main(mode):
    for tool in ("swift", "psql", "createdb", "dropdb"):
        if not shutil.which(tool):
            raise RuntimeError(f"Install {tool} and put it on PATH before running Roost.")

    env = dict(os.environ)
    ecosystem = env.get("ROOST_ECOSYSTEM_PATH")
    env.setdefault("DB_HOST", "localhost")
    env.setdefault("DB_PORT", "5432")
    env.setdefault("DB_USER", getpass.getuser())
    env.setdefault("DB_PASSWORD", "")
    if env["DB_HOST"] not in ("localhost", "127.0.0.1", "::1"):
        raise RuntimeError("These example helpers use a local PostgreSQL server; set DB_HOST=localhost.")
    if ecosystem:
        for name in ("Nexus", "Spectro", "esw"):
            if not (Path(ecosystem) / name / "Package.swift").exists():
                raise RuntimeError(f"Missing {name} checkout. Set ROOST_ECOSYSTEM_PATH to the parent of the companion repositories.")
    if "ROOST_ESW_PATH" in env and not (Path(env["ROOST_ESW_PATH"]) / "Package.swift").exists():
        raise RuntimeError("Missing ESW checkout. Set ROOST_ESW_PATH to its directory.")
    env.update(PGHOST=env["DB_HOST"], PGPORT=env["DB_PORT"], PGUSER=env["DB_USER"], PGPASSWORD=env["DB_PASSWORD"])
    env["ROOST_ENV"] = "test" if mode == "test" else "dev"
    env["DB_NAME"] = "roost_check_" + uuid.uuid4().hex[:16] if mode == "test" else env.get("DB_NAME", "roost_dev")
    env["ROOST_DEMO"] = "0" if mode == "test" else env.get("ROOST_DEMO", "1")
    env["ROOST_HOST"] = "127.0.0.1"
    env.setdefault("ROOST_PORT", "4000")

    # psql quotes this variable as a SQL literal; names are never interpolated into SQL.
    exists = run(["psql", "-XAt", "-d", "postgres", "-v", "roost_db=" + env["DB_NAME"]], env,
                 capture=True, input="SELECT 1 FROM pg_database WHERE datname = :'roost_db';\n").strip()
    if mode == "test" and exists:
        raise RuntimeError("The generated test database already exists; refusing to reuse it.")
    created = False
    try:
        if not exists:
            run(["createdb", env["DB_NAME"]], env)
            created = True
        run(["swift", "build", "--product", "RoostExample"], env)
        binary_dir = run(["swift", "build", "--show-bin-path"], env, capture=True).strip().splitlines()[-1]
        run([Path(binary_dir) / "RoostExample", "migrate", "up"], env)
        if mode == "test":
            run(["swift", "test"], env)
            print("Roost tests passed; the owned test database will now be removed.", flush=True)
        else:
            run(["swift", "build", "--product", "roost"], env, cwd=FRAMEWORK)
            cli_dir = run(["swift", "build", "--show-bin-path"], env, cwd=FRAMEWORK, capture=True).strip().splitlines()[-1]
            print(f"\nRoost → http://127.0.0.1:{env['ROOST_PORT']}", flush=True)
            if env["ROOST_DEMO"] == "1":
                print("Demo login: reader@roost.test / Read-with-Roost-2026", flush=True)
            print("Swift and ESW changes rebuild automatically. Ctrl-C stops the server.\n", flush=True)
            os.chdir(APP)
            os.execve(str(Path(cli_dir) / "roost"), ["roost", "server", "--port", env["ROOST_PORT"]], env)
    finally:
        if mode == "test" and created:
            run(["dropdb", env["DB_NAME"]], env)


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Roost: {error}", file=sys.stderr)
        sys.exit(1)
