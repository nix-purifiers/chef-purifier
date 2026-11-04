{
  description = "Locked, Nix-resolved Chef and Cinc cookbook dependencies";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.purifier = {
    url = "github:nix-purifiers/purifier";
    flake = false;
  };
  outputs =
    {
      self,
      nixpkgs,
      purifier,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = nixpkgs.lib.genAttrs systems;
      overlay = final: prev: {
        chef-purifier = import ./nix/scope.nix {
          pkgs = final;
          nixpkgsSrc = nixpkgs;
          purifierSrc = purifier;
        };
      };
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ overlay ];
        };
    in
    {
      overlays.default = overlay;
      packages = forAll (
        system:
        let
          p = pkgsFor system;
        in
        {
          default = p.chef-purifier.cli;
          core = p.chef-purifier.core;
        }
      );
      apps = forAll (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/chef-purifier";
        };
      });
      lib.chef-purifier.readLock = import ./nix/read-lock.nix { lib = nixpkgs.lib; };
      checks = forAll (
        system:
        let
          p = pkgsFor system;
          build = p.chef-purifier.buildChefProject {
            src = ./examples/minimal;
            doCheck = true;
            checkCommand = ''
              export PURIFIER_PROOF_OUTPUT="$TMPDIR/answer"
              cinc-client --local-mode --node-name purifier-proof --config .cinc/config.rb
              test "$(cat "$PURIFIER_PROOF_OUTPUT")" = answer=42
            '';
          };
        in
        {
          inherit (build.packages) environment project;
          release = build.release;
          cli = self.packages.${system}.default;
        }
      );
      formatter = forAll (system: (pkgsFor system).nixfmt-tree);
    };
}
