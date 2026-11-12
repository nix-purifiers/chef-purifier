{ lib }:
{
  src,
  lockFile ? src + "/chef-purifier.lock.json",
}:
let
  raw = if builtins.pathExists lockFile then builtins.fromJSON (builtins.readFile lockFile) else { };
  data = if builtins.isAttrs raw then raw else { };
  entries = data.entries or [ ];
  remotes = data.remotes or { };
  safe =
    value:
    builtins.isString value
    && builtins.match "[A-Za-z0-9_.+-]+" value != null
    && !(builtins.elem value [
      "."
      ".."
    ]);
  shape =
    (data.schema or null) == 1
    && builtins.isString (data.sdkVersion or null)
    && builtins.isAttrs (data.selection or null)
    && builtins.isAttrs remotes
    && builtins.isList entries
    && builtins.all (
      entry:
      builtins.isAttrs entry
      && safe (entry.path or null)
      && builtins.isString (entry.url or null)
      && lib.hasPrefix "https://" entry.url
      && builtins.isString (entry.hash or null)
      && builtins.match "sha256-[A-Za-z0-9+/]{43}=" entry.hash != null
      && (entry.mirrors or null) == [ ]
    ) entries
    && builtins.all (
      record:
      builtins.isAttrs record
      && safe (record.cache_key or null)
      && builtins.isString (record.origin or null)
      && builtins.isString (record.identifier or null)
      && builtins.any (
        entry: entry.path == record.cache_key + ".tar.gz" && entry.url == record.origin
      ) entries
    ) (builtins.attrValues remotes);
  valid =
    shape
    && builtins.length entries == builtins.length (builtins.attrNames remotes)
    && builtins.length (lib.unique (map (entry: entry.path) entries)) == builtins.length entries;
in
{
  purifier = "chef";
  inherit data entries;
  problems = lib.optional (
    !valid
  ) "Chef cookbook lock is missing or malformed; run chef-purifier lock --update";
  outputs = {
    packages = [
      "default"
      "environment"
      "project"
    ];
    tests = [ "default" ];
    release = [ "default" ];
  };
}
