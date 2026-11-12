{
  lib,
  runCommand,
  fetchurl,
  fetchgit,
  writeText,
  python3,
  git,
  purifier,
  driver,
  sdkVersion,
}:
{
  src,
  lock,
  fetchers ? { },
}:
let
  source = lib.cleanSourceWith {
    inherit src;
    filter =
      path: type:
      !(builtins.elem (baseNameOf path) [
        ".git"
        ".chef-purifier"
        "__pycache__"
        "result"
      ]);
  };
  checked = purifier.checkLock lock;
  archives = purifier.tree (
    {
      name = "chef-cookbook-archives";
      inherit
        runCommand
        fetchurl
        fetchgit
        writeText
        python3
        ;
      inherit (checked) entries;
    }
    // fetchers
  );
  replay = writeText "chef-cookbook-archives.json" (
    builtins.toJSON (
      builtins.listToAttrs (
        map (entry: {
          name = entry.url;
          value = "${archives}/${entry.path}";
        }) checked.entries
      )
    )
  );
  manifest = writeText "chef-cookbook-manifest.json" (builtins.toJSON lock.data);
  nativeLock = builtins.fromJSON (builtins.readFile (src + "/Policyfile.lock.json"));
  nativeRemotes = lib.filterAttrs (
    _: record: !(record.source_options ? path)
  ) nativeLock.cookbook_locks;
  expected = lock.data.remotes;
  cacheKeys = map (record: record.cache_key) (builtins.attrValues expected);
in
assert lib.assertMsg (
  lock.data.sdkVersion == sdkVersion
) "Cinc SDK changed; run chef-purifier lock --update";
assert lib.assertMsg (
  nativeRemotes == expected
) "Native Policyfile cookbook pins changed; run chef-purifier lock --update";
runCommand "chef-native-cookbooks" { nativeBuildInputs = [ git ]; } ''
  export HOME="$TMPDIR/home" CHEF_PURIFIER_MODE=replay
  export CHEF_PURIFIER_ARCHIVES=${replay}
  export CHEF_PURIFIER_CACHE="$TMPDIR/cache" CHEF_PURIFIER_STORE="$out"
  mkdir -p "$HOME" "$out"
  cp -r ${source} source
  chmod -R u+w source
  cd source
  CHEF_PURIFIER_MODE=verify-project CHEF_PURIFIER_PROJECT="$PWD" CHEF_PURIFIER_MANIFEST=${manifest} ${driver}/bin/cinc-cli
  ${driver}/bin/cinc-cli install Policyfile.lock.json
  CHEF_PURIFIER_MODE=validate CHEF_PURIFIER_MANIFEST=${manifest} CHEF_PURIFIER_DEPENDENCIES="$out" ${driver}/bin/cinc-cli
  ${lib.concatMapStringsSep "\n" (key: "test -d \"$out/\"${lib.escapeShellArg key}") cacheKeys}
''
