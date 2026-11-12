{
  pkgs,
  nixpkgsSrc,
  purifierSrc,
}:
pkgs.lib.makeScope pkgs.newScope (scope: {
  core = scope.callPackage ./build-chef-project/core.nix { inherit nixpkgsSrc; };
  purifier = import (purifierSrc + "/nix/lib") { inherit (pkgs) lib; };
  driver = pkgs.runCommand "chef-purifier-native-driver" { } ''
    mkdir -p "$out/bin"
    substitute ${scope.core}/bin/cinc-cli "$out/bin/cinc-cli" --replace-fail \
      'load Gem.bin_path("chef-cli", "cinc-cli")' \
      'require "${../native}/entry.rb";load Gem.bin_path("chef-cli", "cinc-cli")'
    chmod +x "$out/bin/cinc-cli"
  '';
  cli = scope.callPackage ./cli/default.nix { inherit nixpkgsSrc purifierSrc; };
  readLock = import ../lib-overlays/default/read-lock.nix { inherit (pkgs) lib; };
  buildChefProject = scope.callPackage ./build-chef-project/default.nix { };
  environment = scope.callPackage ./build-chef-project/environment.nix { };
  sdkVersion = builtins.hashString "sha256" (
    builtins.toJSON {
      nixpkgs = toString nixpkgsSrc;
      core = builtins.hashFile "sha256" ./build-chef-project/core.nix;
      gemfile = builtins.hashFile "sha256" ../native/sdk-source/Gemfile;
      gemLock = builtins.hashFile "sha256" ../native/sdk-source/Gemfile.lock;
      sources = builtins.hashFile "sha256" ../native/sdk-source/cinc-pins.json;
      project = builtins.hashFile "sha256" ../native/project-model.rb;
      runtime = builtins.hashFile "sha256" ../native/runtime.rb;
      entry = builtins.hashFile "sha256" ../native/entry.rb;
      validation = builtins.hashFile "sha256" ../native/validate.rb;
      replay = builtins.hashFile "sha256" ../native/replay.rb;
    }
  );
})
