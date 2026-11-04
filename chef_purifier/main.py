import argparse
import json
import os
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

from .capture import capture, project_model


def main():
    driver = os.environ["CHEF_PURIFIER_DRIVER"]
    sdk = os.environ["CHEF_PURIFIER_SDK"]
    project = Path(os.environ.get("CHEF_PURIFIER_PROJECT", os.getcwd())).resolve()
    name = Path(sys.argv[0]).name
    target = "environment"
    publish_tag = None
    if name in {"chef-cli", "cinc-cli"}:
        arguments = sys.argv[1:]
        lockfile = project / "chef-purifier.lock.json"
        if not lockfile.exists():
            print(
                "warning: no chef-purifier lockfile; using ordinary impure cookbook resolution",
                file=sys.stderr,
            )
            os.execv(
                str(Path(os.environ["CHEF_PURIFIER_CORE"]) / "bin/cinc-cli"),
                ["cinc-cli", *arguments],
            )
    else:
        parser = argparse.ArgumentParser(prog="chef-purifier")
        parser.add_argument("--project", type=Path, default=project)
        commands = parser.add_subparsers(dest="command", required=True)
        lock = commands.add_parser("lock")
        lock.add_argument("--update", action="store_true")
        commands.add_parser("prefetch")
        commands.add_parser("build")
        commands.add_parser("bundle")
        publish = commands.add_parser("publish")
        publish.add_argument("--tag", required=True)
        execute = commands.add_parser("exec")
        execute.add_argument("arguments", nargs=argparse.REMAINDER)
        parser.add_argument("--lock", type=Path)
        for command in commands.choices.values():
            command.add_argument("--project", type=Path, default=argparse.SUPPRESS)
            command.add_argument("--lock", type=Path, default=argparse.SUPPRESS)
        options = parser.parse_args()
        project = options.project.resolve()
        lockfile = (
            options.lock.resolve()
            if options.lock
            else project / "chef-purifier.lock.json"
        )
        if options.command == "lock" and options.update:
            capture(project, driver, sdk, lockfile)
            return
        target = (
            "release"
            if options.command in {"bundle", "publish"}
            else "project"
            if options.command == "build"
            else "environment"
        )
        publish_tag = options.tag if options.command == "publish" else None
        arguments = options.arguments if options.command == "exec" else None
        if arguments and arguments[0] == "--":
            arguments = arguments[1:]
        if not lockfile.exists():
            raise ValueError("No cookbook lock; run chef-purifier lock --update")
    lock = json.loads(lockfile.read_text())
    if lock.get("schema") != 1 or lock.get("sdkVersion") != sdk:
        raise ValueError(
            "Unsupported lock or changed SDK; run chef-purifier lock --update"
        )
    with tempfile.TemporaryDirectory(prefix="chef-purifier-") as directory:
        temporary = Path(directory)
        selection = project_model(driver, project, temporary)
        if selection != lock["selection"]:
            raise ValueError(
                "Policy dependencies changed; run chef-purifier lock --update"
            )
        native = json.loads((project / "Policyfile.lock.json").read_text())
        remotes = {
            key: value
            for key, value in native["cookbook_locks"].items()
            if "path" not in value["source_options"]
        }
        if remotes != lock["remotes"]:
            raise ValueError(
                "Native cookbook pins changed; run chef-purifier lock --update"
            )
        result = subprocess.check_output(
            [
                "nix",
                "build",
                "--impure",
                "--out-link",
                str(temporary / "dependencies"),
                "--json",
                "--file",
                os.environ["CHEF_PURIFIER_REALIZE"],
                "--argstr",
                "projectPath",
                str(project),
                "--argstr",
                "lockPath",
                str(lockfile),
                "--argstr",
                "target",
                target,
            ],
            text=True,
        )
        dependencies = json.loads(result)[0]["outputs"]["out"]
        if target == "release":
            dependencies = str(Path(dependencies) / "policy.tar.gz")
        if publish_tag:
            subprocess.run(
                [
                    os.environ.get("CHEF_PURIFIER_GH", "gh"),
                    "release",
                    "upload",
                    publish_tag,
                    dependencies,
                    "--clobber",
                ],
                check=True,
            )
        if arguments is None:
            print(dependencies)
            return
        # Temporary state stays alive until the child exits, including on errors.
        context = temporary / "context.json"
        context.write_text(
            json.dumps(
                {"project": str(project), "selection": selection, "remotes": remotes}
            )
        )
        environment = os.environ | {
            "CHEF_PURIFIER_MODE": "frozen",
            "CHEF_PURIFIER_CONTEXT": str(context),
            "CHEF_PURIFIER_DEPENDENCIES": dependencies,
            "CHEF_PURIFIER_STORE": str(temporary / "cookbooks"),
            "CHEF_PURIFIER_CACHE": str(temporary / "cache"),
        }
        result = subprocess.run(
            [driver, *arguments],
            check=False,
            env=environment,
            cwd=None if name in {"chef-cli", "cinc-cli"} else project,
        )
        if result.returncode < 0:
            signal.signal(-result.returncode, signal.SIG_DFL)
            os.kill(os.getpid(), -result.returncode)
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"chef-purifier: {error}", file=sys.stderr)
        raise SystemExit(1)
