{ lib, config, pkgs, ... }:
with lib;

let
in {
  imports = [
    ../../modules/netboot.nix
  ];

  netboot.nixpkgs = builtins.path {path=../../channels/nixpkgs-stable;};
  netboot.ipxe.password = "letmein";
  netboot.ipxe.items = {
    labClient = {
      menu = "Lab Client";
      modules = [./lab-client.nix];
    };
  };
}
