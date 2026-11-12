{
  lib,
  writeText,
  runCommand,
  makeWrapper,
  python3,
  nix,
  git,
  gh,
  cacert,
  core,
  driver,
  sdkVersion,
  nixpkgsSrc,
  purifierSrc,
}:
let
  source = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../.
      ../../lib-overlays
      ../../native
    ];
  };
  realize = writeText "chef-purifier-realize.nix" ''
    { projectPath, lockPath ? "", target ? "environment" }:
    let
      pkgs = import (builtins.storePath "${nixpkgsSrc}") {};
      scope = import ${source}/pkgs/default.nix {
        inherit pkgs;
        nixpkgsSrc = builtins.storePath "${nixpkgsSrc}";
        purifierSrc = builtins.storePath "${purifierSrc}";
      };
      src = builtins.path {
        path = builtins.toPath projectPath;
        name = "chef-project";
        filter = path: type: !(builtins.elem (baseNameOf path) [ ".git" ".chef-purifier" ]);
      };
        lockFile = if lockPath == "" then src + "/chef-purifier.lock.json" else builtins.toPath lockPath;
    build = scope.buildChefProject { inherit src lockFile; };
    in if target == "environment" then build.packages.environment
       else if target == "project" then build.packages.project
       else if target == "release" then build.release
       else throw "Unknown Chef purifier build target"
  '';
in
runCommand "chef-purifier" { nativeBuildInputs = [ makeWrapper ]; } ''
  mkdir -p "$out/bin" "$out/lib/chef_purifier"
  cp ${../../chef_purifier}/*.py "$out/lib/chef_purifier/"
  ln -s ${core}/bin/cinc-client "$out/bin/cinc-client"
  for name in chef-purifier cinc-cli chef-cli; do
    makeWrapper ${python3}/bin/python3 "$out/bin/$name" \
      --add-flags "$out/lib/chef_purifier/launcher.py" \
      --set-default SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt \
      --set-default NIX_SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt \
      --set PYTHONPATH "$out/lib" \
      --set CHEF_PURIFIER_DRIVER ${driver}/bin/cinc-cli \
      --set CHEF_PURIFIER_CORE ${core} \
      --set CHEF_PURIFIER_SDK ${sdkVersion} \
      --set CHEF_PURIFIER_REALIZE ${realize} \
      --set CHEF_PURIFIER_COMMAND "$name" \
      --prefix PATH : ${
        lib.makeBinPath [
          nix
          git
          gh
          core
        ]
      }
  done
''
