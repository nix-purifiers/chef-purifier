"""Native workflows, immutable cookbooks, root networking and fallback."""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("cli", type=Path)
parser.add_argument("core", type=Path)
options = parser.parse_args()
cli = options.cli.resolve()
core = options.core.resolve()
fixture = Path(__file__).resolve().parents[1] / "examples/minimal"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"root-network-ok")

    def log_message(self, *args):
        pass


with tempfile.TemporaryDirectory(
    prefix="chef-native-", dir=os.environ.get("TMPDIR")
) as directory:
    temporary = Path(directory)
    project = temporary / "project"
    shutil.copytree(fixture, project)
    subprocess.run(["git", "init", "-q", "-b", "main", str(project)], check=True)
    environment = os.environ | {"HOME": str(temporary / "home")}
    Path(environment["HOME"]).mkdir()

    def run(command, expected=0, **kwargs):
        result = subprocess.run(
            command,
            check=False,
            env=environment,
            capture_output=True,
            text=True,
            **kwargs,
        )
        assert result.returncode == expected, result.stdout + result.stderr
        return result

    run([str(cli / "bin/chef-purifier"), "--project", str(project), "prefetch"])
    policy = project / "Policyfile.rb"
    original_policy = policy.read_text()
    policy.write_text(original_policy + "\ndefault['purifier']['body'] = 43\n")
    run([str(cli / "bin/cinc-cli"), "update"], cwd=project)
    assert (
        json.loads((project / "Policyfile.lock.json").read_text())[
            "default_attributes"
        ]["purifier"]["body"]
        == 43
    )
    policy.write_text(original_policy)
    print("native policy attribute update with fixed cookbook versions: PASS")
    gc_record = temporary / "gc-roots"
    environment["CHEF_PURIFIER_GC_PROOF"] = str(gc_record)
    policy.write_text(
        original_policy
        + """
if ENV['CHEF_PURIFIER_MODE'] == 'frozen'
  roots = IO.popen(['nix-store', '--query', '--roots', ENV.fetch('CHEF_PURIFIER_DEPENDENCIES')], &:read)
  raise 'Active dependency root missing' unless roots.include?('dependencies')
  File.write(ENV.fetch('CHEF_PURIFIER_GC_PROOF'), roots)
end
"""
    )
    run(
        [
            str(cli / "bin/chef-purifier"),
            "exec",
            "--project",
            str(project),
            "--",
            "export",
            str(temporary / "gc-export"),
        ]
    )
    assert "dependencies" in gc_record.read_text()
    policy.write_text(original_policy)
    print("active native command dependency GC root: PASS")
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        recipe = project / "cookbooks/purifier-fixture/recipes/default.rb"
        original = recipe.read_text()
        for number in (42, 43, 42):
            network = f"\nrequire 'net/http'\nraise 'root networking blocked' unless Net::HTTP.get(URI('http://127.0.0.1:{server.server_port}/')) == 'root-network-ok'\n"
            recipe.write_text(
                original.replace("answer = 42", f"answer = {number}") + network
            )
            exported = temporary / f"export-{number}-{len(list(temporary.iterdir()))}"
            run(
                [
                    str(cli / "bin/chef-purifier"),
                    "--project",
                    str(project),
                    "exec",
                    "--",
                    "export",
                    str(exported),
                ]
            )
            answer = temporary / "answer"
            environment["PURIFIER_PROOF_OUTPUT"] = str(answer)
            run(
                [
                    str(core / "bin/cinc-client"),
                    "--local-mode",
                    "--minimal-ohai",
                    "--node-name",
                    "purifier-proof",
                    "--config",
                    str(exported / ".cinc/config.rb"),
                ],
                cwd=exported,
            )
            assert answer.read_text().strip() == f"answer={number}"
        print("native 42/43/42 and root HTTP: PASS")
    finally:
        server.shutdown()
        server.server_close()
    recipe.write_text(original)
    archive = Path(
        run(
            [str(cli / "bin/chef-purifier"), "bundle", "--project", str(project)]
        ).stdout.strip()
    )
    consumer = temporary / "consumer"
    consumer.mkdir()
    with tarfile.open(archive) as bundle:
        bundle.extractall(consumer, filter="data")
    exported = consumer / "policy"
    run(
        [
            str(core / "bin/cinc-client"),
            "--local-mode",
            "--minimal-ohai",
            "--node-name",
            "purifier-proof",
            "--config",
            str(exported / ".cinc/config.rb"),
        ],
        cwd=exported,
    )
    assert answer.read_text().strip() == "answer=42"
    publication = temporary / "publication.json"
    fake = temporary / "fake-gh"
    fake.write_text(
        "#!"
        + sys.executable
        + "\nimport sys,json\nfrom pathlib import Path\nPath("
        + repr(str(publication))
        + ").write_text(json.dumps(sys.argv[1:]))\n"
    )
    fake.chmod(0o755)
    environment["CHEF_PURIFIER_GH"] = str(fake)
    run(
        [
            str(cli / "bin/chef-purifier"),
            "publish",
            "--project",
            str(project),
            "--tag",
            "v-proof",
        ]
    )
    assert json.loads(publication.read_text()) == [
        "release",
        "upload",
        "v-proof",
        str(archive),
        "--clobber",
    ]
    external = temporary / "external.lock.json"
    external.write_bytes((project / "chef-purifier.lock.json").read_bytes())
    (project / "chef-purifier.lock.json").unlink()
    run(
        [
            str(cli / "bin/chef-purifier"),
            "prefetch",
            "--project",
            str(project),
            "--lock",
            str(external),
        ]
    )
    result = subprocess.run(
        [str(cli / "bin/cinc-cli"), "export", str(temporary / "external-export")],
        cwd=project,
        env=environment
        | {"CHEF_PURIFIER_PROJECT": str(project), "CHEF_PURIFIER_LOCK": str(external)},
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    (project / "chef-purifier.lock.json").write_bytes(external.read_bytes())
    print(
        "native exported-policy consumer, exact publication asset and external lock: PASS"
    )
    metadata = project / "cookbooks/purifier-fixture/metadata.rb"
    metadata.write_text(metadata.read_text() + "\ndepends 'unlocked-cookbook'\n")
    result = run(
        [str(cli / "bin/chef-purifier"), "--project", str(project), "prefetch"],
        expected=1,
    )
    assert "Policy dependencies changed" in result.stderr
    print("changed dependency declaration: PASS")
    empty = temporary / "empty"
    empty.mkdir()
    native = subprocess.run(
        [str(core / "bin/cinc-cli"), "--invalid-purifier-test"],
        check=False,
        cwd=empty,
        env=environment,
        capture_output=True,
    )
    wrapped = subprocess.run(
        [str(cli / "bin/cinc-cli"), "--invalid-purifier-test"],
        check=False,
        cwd=empty,
        env=environment,
        capture_output=True,
    )
    warning, stderr = wrapped.stderr.split(b"\n", 1)
    assert b"no chef-purifier lockfile" in warning
    assert (wrapped.returncode, wrapped.stdout, stderr) == (
        native.returncode,
        native.stdout,
        native.stderr,
    )
    print("no-lock native status/stdout/stderr: PASS")
