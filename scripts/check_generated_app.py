#!/usr/bin/env python3
"""Exercise the generated app against an owned PostgreSQL database.

python3 scripts/check_generated_app.py --ecosystem ..
Omit --ecosystem to check published ESW/Nexus/Spectro dependencies.
Use --published-framework after a release to also resolve Roost from its tag.
Set ROOST_ESW_PATH to use only local ESW while checking released Spectro/Nexus.
Requires Swift 6.3+, PostgreSQL client tools on PATH, and a local Postgres server.
DB_HOST/DB_PORT/DB_USER/DB_PASSWORD configure the local test server. DB_NAME is
never reused: this script creates and drops a uniquely named database.
"""
import argparse
import getpass
import http.cookiejar
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]


def run(args, *, cwd=ROOT, env=None, log=None, succeeds=True):
    result = subprocess.run([str(a) for a in args], cwd=cwd, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if log:
        Path(log).write_text(result.stdout)
    if (result.returncode == 0) != succeeds:
        raise RuntimeError(f"Command failed: {args}\n{result.stdout[-14000:]}")
    return result.stdout


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Browser:
    def __init__(self, base):
        self.base = base
        self.cookies = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cookies), NoRedirect())

    def request(self, path, *, method="GET", form=None, value=None, headers=None, status=200):
        headers = dict(headers or {})
        data = None
        if form is not None:
            data = urllib.parse.urlencode(form).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
            method = "POST" if method == "GET" else method
        if value is not None:
            data = json.dumps(value).encode()
            headers["Content-Type"] = "application/json"
        try:
            response = self.opener.open(urllib.request.Request(self.base + path, data=data, headers=headers, method=method), timeout=90)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            body = response.read().decode()
            assert response.status == status, f"{method} {path}: expected {status}, got {response.status}\n{body[:3000]}"
            return body, response.headers

    def csrf(self, path):
        body, _ = self.request(path)
        match = re.search(r'name="_csrf_token" value="([^"]+)"', body)
        assert match, f"Missing CSRF field at {path}"
        return match[1]

    def register(self, email):
        token = self.csrf("/auth/register")
        self.request("/auth/register", form={"email": email, "password": "swift-roost-password", "_csrf_token": token}, status=303)


def check_http(base):
    alice, bob = Browser(base), Browser(base)
    alice.request("/css/app.css")
    alice.request("/todos", status=303)
    token = alice.csrf("/auth/register")
    invalid, _ = alice.request("/auth/register", form={"email": "invalid", "password": "short", "_csrf_token": token}, status=422)
    assert 'value="invalid"' in invalid and "valid email" in invalid
    alice.register("alice@example.test")
    token = alice.csrf("/todos/new")
    alice.request("/api/todos", method="POST", value={"title": "Bypass", "done": False}, status=403)
    invalid, _ = alice.request("/todos", form={"title": "", "done": "true", "_csrf_token": token}, status=422)
    assert "role=\"alert\"" in invalid and "checked" in invalid
    _, headers = alice.request("/todos", form={"title": "Walk <Swift> & +", "_csrf_token": token}, status=303)
    location = headers["Location"]
    todo_id = location.rsplit("/", 1)[1]
    shown, _ = alice.request(location)
    assert "Walk &lt;Swift&gt; &amp; +" in shown and "Todo created" in shown
    again, _ = alice.request(location)
    assert "Todo created" not in again, "Flash must be consumed once"
    rows = json.loads(alice.request("/api/todos")[0])
    assert len(rows) == 1 and rows[0]["done"] is False
    changed = json.loads(alice.request("/api/todos/" + todo_id, method="PUT",
        value={"title": "Updated", "done": True}, headers={"X-CSRF-Token": token}, status=200)[0])
    assert changed["id"].lower() == todo_id.lower() and changed["done"] is True
    assert len(json.loads(alice.request("/api/todos")[0])) == 1, "Update inserted an extra row"
    token = alice.csrf(location + "/edit")
    alice.request(location, form={"_method": "PUT", "title": "Edited", "_csrf_token": token}, status=303)
    row = json.loads(alice.request("/api/todos/" + todo_id)[0])
    assert row["title"] == "Edited" and row["done"] is False
    # Second resource proves namespaced index/new/edit/show templates coexist.
    note_token = alice.csrf("/notes/new")
    _, note_headers = alice.request("/notes", form={"body": "Second resource", "_csrf_token": note_token}, status=303)
    alice.request(note_headers["Location"])
    bob.register("bob@example.test")
    bob_token = bob.csrf("/todos/new")
    assert json.loads(bob.request("/api/todos")[0]) == []
    bob.request(location, status=404)
    bob.request(location + "/edit", status=404)
    bob.request("/api/todos/" + todo_id, status=404)
    bob.request("/api/todos/" + todo_id, method="PUT", value={"title": "Stolen", "done": True}, headers={"X-CSRF-Token": bob_token}, status=404)
    bob.request("/api/todos/" + todo_id, method="DELETE", headers={"X-CSRF-Token": bob_token}, status=404)
    bob.request(location, form={"_method": "PUT", "title": "Stolen", "_csrf_token": bob_token}, status=404)
    bob.request(location, form={"_method": "DELETE", "_csrf_token": bob_token}, status=404)
    assert json.loads(alice.request("/api/todos/" + todo_id)[0])["title"] == "Edited"
    _, bob_headers = bob.request("/todos", form={"title": "Bob's Todo", "userId": row["user_id"], "user_id": row["user_id"], "_csrf_token": bob_token}, status=303)
    assert len(json.loads(bob.request("/api/todos")[0])) == 1
    assert len(json.loads(alice.request("/api/todos")[0])) == 1
    bob.request(bob_headers["Location"], form={"_method": "DELETE", "_csrf_token": bob_token}, status=303)
    assert json.loads(bob.request("/api/todos")[0]) == []
    alice.request("/auth/logout", form={"_method": "DELETE", "_csrf_token": token}, status=303)
    alice.request("/todos", status=303)
    # Revoked token must not authenticate again; a fresh login still works.
    token = alice.csrf("/auth/login")
    alice.request("/auth/login", form={"email": "alice@example.test", "password": "wrong", "_csrf_token": token}, status=422)
    alice.request("/auth/login", form={"email": "alice@example.test", "password": "swift-roost-password", "_csrf_token": token}, status=303)
    alice.request(location)
    print("HTTP: auth, CSRF, flash, forms, JSON, updates, two-user isolation and second resource passed.", flush=True)


def prepare(cli, workspace):
    app = workspace / "TodoWorkshop"
    run([cli, "new", "TodoWorkshop"], cwd=workspace, log=workspace / "generate.log")
    run([cli, "gen", "auth"], cwd=app)
    run([cli, "gen", "resource", "Todo", "title:string", "done:bool", "--both", "--scope", "user_id"], cwd=app)
    run([cli, "gen", "resource", "Note", "body:text"], cwd=app)
    model = app / "Sources/TodoWorkshop/Models/Todo.swift"
    before = model.read_bytes()
    result = run([cli, "gen", "resource", "Todo", "title:string"], cwd=app, succeeds=False)
    assert "Refusing to overwrite" in result and model.read_bytes() == before
    (app / "Tests/TodoWorkshopTests/DatabaseWorkflowTests.swift").write_text((ROOT / "scripts/fixtures/DatabaseWorkflowTests.swift").read_text())
    return app


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ecosystem", type=Path)
    parser.add_argument("--published-framework", action="store_true",
                        help="Use published Roost matching the CLI version, with all local dependency overrides removed")
    parser.add_argument("--work-dir", type=Path)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--release", action="store_true", help="Also build and exercise the optimized release executable")
    parser.add_argument("--reuse", action="store_true", help="Resume a previously prepared, owned fixture while debugging")
    options = parser.parse_args()
    if options.published_framework and (options.ecosystem or options.reuse):
        parser.error("--published-framework requires a fresh fixture without --ecosystem or --reuse")
    if options.ecosystem:
        os.environ["ROOST_ECOSYSTEM_PATH"] = str(options.ecosystem.resolve())
    if options.published_framework:
        for key in ("ROOST_FRAMEWORK_PATH", "ROOST_ESW_PATH", "ROOST_ECOSYSTEM_PATH"):
            os.environ.pop(key, None)
    else:
        os.environ["ROOST_FRAMEWORK_PATH"] = str(ROOT)
    workspace = (options.work_dir or Path(tempfile.mkdtemp(prefix="roost-acceptance-"))).resolve()
    workspace.mkdir(parents=True, exist_ok=True)
    print(f"Acceptance workspace: {workspace}", flush=True)
    run(["swift", "build", "--product", "roost"], log=workspace / "cli-build.log")
    binary_dir = Path(run(["swift", "build", "--show-bin-path"]).strip().splitlines()[-1])
    cli = binary_dir / "roost"
    app = workspace / "TodoWorkshop" if options.reuse else prepare(cli, workspace)
    if options.prepare_only:
        return
    run(["swift", "build"], cwd=app, log=workspace / "app-build.log")
    if options.published_framework:
        version = run([cli, "--version"]).strip()
        pins = json.loads((app / "Package.resolved").read_text())["pins"]
        framework = next(pin for pin in pins if pin["identity"] == "swift-roost")
        assert framework["state"]["version"] == version, f"Expected Roost {version}, resolved {framework}"
        print(f"Published Roost {version} resolved at {framework['state']['revision']}.", flush=True)
    print("Generated SwiftPM app compiled.", flush=True)
    env = dict(os.environ)
    env.update(DB_HOST=env.get("DB_HOST", "localhost"), DB_PORT=env.get("DB_PORT", "5432"),
               DB_USER=env.get("DB_USER", getpass.getuser()), DB_PASSWORD=env.get("DB_PASSWORD", ""),
               DB_NAME="roost_acceptance_" + uuid.uuid4().hex[:16])
    pg_env = dict(env, PGHOST=env["DB_HOST"], PGPORT=env["DB_PORT"], PGUSER=env["DB_USER"], PGPASSWORD=env["DB_PASSWORD"])
    assert env["DB_HOST"] in ("localhost", "127.0.0.1", "::1"), "Acceptance databases must be local"
    run(["createdb", env["DB_NAME"]], env=pg_env)
    server = None
    try:
        run([cli, "migrate"], cwd=app, env=env, log=workspace / "migrations.log")
        run([cli, "migrate", "status"], cwd=app, env=env, log=workspace / "migration-status.log")
        run(["swift", "test"], cwd=app, env=env, log=workspace / "app-tests.log")
        print("Generated tests and transaction rollback passed.", flush=True)
        configuration = "release" if options.release else "debug"
        if options.release:
            run(["swift", "build", "-c", "release", "--product", "TodoWorkshop"], cwd=app, env=env, log=workspace / "release-build.log")
        executable = Path(run(["swift", "build", "-c", configuration, "--show-bin-path"], cwd=app).strip().splitlines()[-1]) / "TodoWorkshop"
        runtime = app
        if options.release:
            # Exercise the same payload and working directory as the Dockerfile.
            # This catches accidental dependence on sources or the build tree.
            runtime = Path(tempfile.mkdtemp(prefix="release-", dir=workspace))
            shutil.copy2(executable, runtime / "app")
            shutil.copytree(app / "Public", runtime / "Public", dirs_exist_ok=True)
            shutil.copytree(app / "Sources/Migrations", runtime / "Sources/Migrations", dirs_exist_ok=True)
            executable = runtime / "app"
            env["ROOST_ENV"] = "prod"
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        env.update(ROOST_HOST="127.0.0.1", ROOST_PORT=str(port))
        with (workspace / "server.log").open("w") as output:
            server = subprocess.Popen([str(executable)], cwd=runtime, env=env, stdout=output, stderr=subprocess.STDOUT)
            for _ in range(100):
                try:
                    urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=1).close()
                    break
                except (OSError, urllib.error.URLError):
                    if server.poll() is not None:
                        raise RuntimeError((workspace / "server.log").read_text())
                    time.sleep(0.1)
            check_http(f"http://127.0.0.1:{port}")
        run([executable, "migrate", "down"], cwd=runtime, env=env, log=workspace / "rollback.log")
        run([executable, "migrate", "up"], cwd=runtime, env=env, log=workspace / "remigrate.log")
        print("Compiled app migration rollback and reapply passed.", flush=True)
    finally:
        if server is not None:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
        run(["dropdb", "--force", env["DB_NAME"]], env=pg_env)
    print("Acceptance passed; owned database removed. Logs remain in the workspace.", flush=True)


if __name__ == "__main__":
    main()
