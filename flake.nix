{
  description = "Dekin Infrastructure Development Shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [
            "terraform"
          ];
      };
    in {
      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.ansible
          pkgs.terraform
        ];
      };
    });
}
