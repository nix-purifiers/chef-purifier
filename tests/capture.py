"""Fresh native resolution/replay and failed-capture lock preservation."""

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("cli", type=Path)
options = parser.parse_args()
cli = options.cli.resolve() / "bin/chef-purifier"
fixture = Path(__file__).resolve().parents[1] / "examples/minimal"
with tempfile.TemporaryDirectory(
    prefix="chef-capture-", dir=os.environ.get("TMPDIR")
) as name:
    project = Path(name) / "project"
    shutil.copytree(fixture, project)
    subprocess.run(
        [str(cli), "lock", "--update", "--project", str(project)], check=True
    )
    files = [project / "Policyfile.lock.json", project / "chef-purifier.lock.json"]
    before = [path.read_bytes() for path in files]
    metadata = project / "cookbooks/purifier-fixture/metadata.rb"
    metadata.write_text(metadata.read_text() + "\ngem 'purifier-unsupported-gem'\n")
    result = subprocess.run(
        [str(cli), "lock", "--update", "--project", str(project)],
        check=False,
        capture_output=True,
        text=True,
    )
    assert (
        result.returncode != 0
        and "Cookbook gem dependencies require an additional provider" in result.stderr
    ), result.stdout + result.stderr
    assert [path.read_bytes() for path in files] == before
    print("fresh native capture/replay and failed-capture lock preservation: PASS")
