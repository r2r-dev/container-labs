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
    # os'es to show up in a boot menu
    labClient = {
      menu = "Lab Client";
      modules = [./lab-client.nix];
    };
  };
}
