"""Capture native Policyfile selection without replacing the native resolver."""

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlsplit


def run(command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)


def project_model(driver, project, temporary):
    output = temporary / "project.json"
    run(
        [driver],
        cwd=project,
        env=os.environ
        | {
            "CHEF_PURIFIER_MODE": "project",
            "CHEF_PURIFIER_PROJECT": str(project),
            "CHEF_PURIFIER_MODEL": str(output),
        },
    )
    return json.loads(output.read_text())


def capture(project, driver, sdk_version, lock_file=None):
    project = Path(project).resolve()
    lock_file = (
        Path(lock_file).resolve() if lock_file else project / "chef-purifier.lock.json"
    )
    with tempfile.TemporaryDirectory(prefix="chef-purifier-capture-") as name:
        temporary = Path(name)
        selection = project_model(driver, project, temporary)
        staged = temporary / "project"
        shutil.copytree(
            project, staged, ignore=shutil.ignore_patterns(".git", ".chef-purifier")
        )
        run(["git", "init", "-q", str(staged)])
        home = temporary / "home"
        home.mkdir()
        environment = os.environ | {"HOME": str(home)}
        environment.pop("CHEF_PURIFIER_MODE", None)
        environment.pop("CHEF_PURIFIER_CONTEXT", None)
        run([driver, "update"], cwd=staged, env=environment)
        native_path = staged / "Policyfile.lock.json"
        native = json.loads(native_path.read_text())
        remotes = {}
        entries = []
        archives = {}
        for cookbook, record in native["cookbook_locks"].items():
            options = record["source_options"]
            if "path" in options:
                if cookbook not in selection["localCookbooks"]:
                    raise ValueError(
                        "Native local cookbook was not declared in the project"
                    )
                continue
            if (
                set(options) - {"artifactserver", "version"}
                or "artifactserver" not in options
            ):
                raise ValueError(
                    "This native cookbook source requires an additional provider"
                )
            url = record["origin"]
            parsed = urlsplit(url)
            if (
                parsed.scheme != "https"
                or parsed.username
                or parsed.password
                or parsed.fragment
            ):
                raise ValueError("Cookbook downloads must use public HTTPS sources")
            key = record["cache_key"]
            if key in {".", ".."} or "/" in key or "\\" in key:
                raise ValueError("Unsafe native cookbook cache key")
            result = subprocess.check_output(
                ["nix", "store", "prefetch-file", "--json", url], text=True
            )
            downloaded = json.loads(result)
            archives[url] = downloaded["storePath"]
            entries.append(
                {
                    "path": key + ".tar.gz",
                    "url": url,
                    "hash": downloaded["hash"],
                    "mirrors": [],
                }
            )
            remotes[cookbook] = record
        manifest = {
            "schema": 1,
            "sdkVersion": sdk_version,
            "selection": selection,
            "remotes": remotes,
            "entries": entries,
        }
        archives_file = temporary / "archives.json"
        archives_file.write_text(json.dumps(archives))
        manifest_file = temporary / "manifest.json"
        manifest_file.write_text(json.dumps(manifest))
        replay_environment = environment | {
            "CHEF_PURIFIER_MODE": "replay",
            "CHEF_PURIFIER_ARCHIVES": str(archives_file),
            "CHEF_PURIFIER_STORE": str(temporary / "cookbooks"),
            "CHEF_PURIFIER_CACHE": str(temporary / "cache"),
        }
        run(
            [driver, "install", "Policyfile.lock.json"],
            cwd=staged,
            env=replay_environment,
        )
        run(
            [driver],
            cwd=staged,
            env=replay_environment
            | {
                "CHEF_PURIFIER_MODE": "validate",
                "CHEF_PURIFIER_MANIFEST": str(manifest_file),
                "CHEF_PURIFIER_DEPENDENCIES": str(temporary / "cookbooks"),
            },
        )
        # Publish only after native resolution and every fetch succeeds. Readers
        # compare native remote rows, so interruption between writes fails closed.
        for filename, content in [
            (project / "Policyfile.lock.json", native_path.read_text()),
            (lock_file, json.dumps(manifest, indent=2, sort_keys=True) + "\n"),
        ]:
            with tempfile.NamedTemporaryFile(
                mode="w", dir=filename.parent, prefix=".chef-purifier-", delete=False
            ) as output:
                output.write(content)
                output.flush()
                os.fsync(output.fileno())
            os.replace(output.name, filename)
        return manifest
