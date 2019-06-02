{ config, lib, pkgs, ... }:
with lib;

let
in
rec {
  services = {
    nixosManual.showManual = lib.mkForce false;

    dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      servers = ["192.168.100.1"]; #TODO: modularize
    };

    openssh.enable = true;
    dbus.socketActivated = true;
    resolved.enable = false;
    xserver = {
      synaptics.enable = true;
      enable = true;
      
      # TODO: add autologin
      displayManager.slim.defaultUser = "student";

      desktopManager = {
        default = "xfce";
        xterm.enable = false;
        xfce =  {
          enable = true;
          noDesktop = true;
        };
      };
    };        
  };

  environment = {
    etc = {
      "resolv.conf".text = "nameserver 127.0.0.1\n";
    };
  };

  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

  fonts = {
    fontconfig = {
      enable = lib.mkForce true;
      hinting.autohint = true;
      antialias = true;
    };

    enableFontDir = true;
    enableGhostscriptFonts = true;

    fonts = with pkgs; [
      fira
      fira-code
      fira-mono
      ibm-plex
      overpass
      terminus_font_ttf
      source-code-pro
      font-awesome_5
      opensans-ttf
      roboto
      ubuntu_font_family
    ];
  };

  users = {
    mutableUsers = false;
    extraUsers.student = {
      name = "student";
      group = "users";
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "disk"
        "audio"
        "video"
        "networkmanager"
        "systemd-journal"
      ];
      createHome = true;
      home = "/home/student";
      uid = 1000;
      password = "student";
    };
  };

  time.timeZone = "Europe/Warsaw";

  nix.useSandbox = true;

  environment.systemPackages = with pkgs; [
    curl
    firefox
    git
    sudo
    vim
    xfce.xfconf
    xfce.mousepad
    xfce.thunar
    xfce.xfce4icontheme
    xfce.xfce4settings
    xfce.xfce4-terminal
    xfce.xfce4-panel
    xfce.xfce4-notifyd
  ];
}
