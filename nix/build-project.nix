{
  lib,
  runCommand,
  git,
  gnutar,
  gzip,
  core,
  driver,
  readLock,
  environment,
}:
{
  src,
  lockFile ? src + "/chef-purifier.lock.json",
  fetchers ? { },
  doCheck ? false,
  checkCommand ? "",
}:
let
  lock = readLock { inherit src lockFile; };
  dependencies = environment { inherit src lock fetchers; };
  project =
    runCommand "chef-exported-policy"
      {
        nativeBuildInputs = [
          git
          core
        ];
      }
      ''
        export HOME="$TMPDIR/home" CHEF_PURIFIER_MODE=frozen
        export CHEF_PURIFIER_DEPENDENCIES=${dependencies}
        export CHEF_PURIFIER_STORE="$TMPDIR/cookbooks" CHEF_PURIFIER_CACHE="$TMPDIR/cache"
        mkdir -p "$HOME"
        cp -r ${src} source
        chmod -R u+w source
        cd source
        git init -q -b main
        ${driver}/bin/cinc-cli export "$out"
        ${lib.optionalString doCheck ''
          cp -r "$out" "$TMPDIR/check-policy"
          chmod -R u+w "$TMPDIR/check-policy"
          cd "$TMPDIR/check-policy"
          ${checkCommand}
        ''}
      '';
  release =
    runCommand "chef-policy.tar.gz"
      {
        nativeBuildInputs = [
          gnutar
          gzip
        ];
      }
      ''
        mkdir -p "$out" policy
        cp -r ${project}/. policy/
        tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
          -cf - policy | gzip -n > "$out/policy.tar.gz"
      '';
in
{
  packages = {
    inherit project;
    default = project;
    environment = dependencies;
  };
  tests = project;
  fetches = lock.entries;
  inherit release;
}
