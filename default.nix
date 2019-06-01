{ nixpkgsPath ? ./channels/nixpkgs-stable
, system ? builtins.currentSystem
, nixpkgs ? builtins.path { path = nixpkgsPath; }
, config
}:


with import nixpkgs { inherit system; };
with lib;

let
in (import "${nixpkgs}/nixos/lib/eval-config.nix" {
    inherit system;
    pkgs = (import nixpkgs {inherit system;});
    modules = [
      "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
       config
    ];
}).config.system.build.isoImage
