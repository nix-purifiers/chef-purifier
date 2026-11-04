{ pkgs, nixpkgsSrc }:
let
  p = pkgs;
  base = import (nixpkgsSrc + "/pkgs/by-name/ch/chef-cli/gemset.nix");
  pins = builtins.fromJSON (builtins.readFile ../native/sdk-source/cinc-pins.json);
  gemset =
    base
    // p.lib.mapAttrs (
      name: pin:
      (base.${name} or {
        dependencies = [ "chef" ];
        groups = [ "default" ];
        platforms = [ ];
      }
      )
      // {
        inherit (pin) version;
        source = {
          type = "gem";
          remotes = [ "https://rubygems.cinc.sh" ];
          inherit (pin) sha256;
        };
      }
    ) pins;
in
p.bundlerApp {
  pname = "chef-cli";
  gemdir = ../native/sdk-source;
  inherit gemset;
  exes = [
    "cinc-cli"
    "cinc-client"
    "chef-cli"
    "chef-client"
  ];
  gemConfig = p.defaultGemConfig // {
    ffi-libarchive = attrs: {
      postInstall = (attrs.postInstall or "") + ''
        substituteInPlace "$out/${p.ruby.gemPath}/gems/ffi-libarchive-${base.ffi-libarchive.version}/lib/ffi-libarchive/archive.rb" --replace-fail \
          'ffi_lib %w{libarchive.so.13 libarchive.13 libarchive-13 libarchive.so libarchive archive}' \
          'ffi_lib "${p.lib.getLib p.libarchive}/lib/libarchive${p.stdenv.hostPlatform.extensions.sharedLibrary}"'
      '';
    };
  };
}
