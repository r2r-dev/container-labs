{ config, lib, pkgs, ... }:
with lib;

let
in
rec {
  imports = [
    ./k8s-lab/kubernetes/kubernetes.profile.nix
  ];

  services = {
    nixosManual.showManual = lib.mkForce false;
    dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      servers = ["192.168.100.1"]; #TODO: modularize
    };
    resolved.enable = false;
  };

  environment = {
    etc = {
      "resolv.conf".text = "nameserver 127.0.0.1\n";
    };
  };

  virtualisation.docker = {
    enable = true;
  };

  virtualisation.docker.enableOnBoot = true;
  virtualisation.docker.extraOptions = ''
    --insecure-registry=127.0.0.1 \
    --insecure-registry=10.1.0.1:5000 \
    --insecure-registry=master.lab:5000 \
  '';

  systemd.services.docker.after = lib.mkForce [ "flannel.service" ];
  networking.firewall.trustedInterfaces = [ "docker0" ];

  services.dockerRegistry = {
    enable = true;
    enableDelete = true;
    enableGarbageCollect = true;
  };

  systemd.services.docker-registry = {
    wantedBy = [ "multi-user.target" ];
    requires = lib.mkForce [
      "docker.service"
      "docker.socket"
      "flannel.service"
    ];
    after = lib.mkForce [
      "docker.service"
      "docker.socket"
      "flannel.service"
    ];
  };

  systemd.services.docker-load-images = {
    description = "Docker load images";
    wantedBy    = [ "multi-user.target" ];
    wants = lib.mkForce [
      "docker.service"
      "docker.socket"
      "flannel.service"
    ];


    after = lib.mkForce [
      "docker.service"
      "docker.socket"
      "flannel.service"
    ];


    script = ''
      ${pkgs.docker}/bin/docker load < ${builtins.path { path = ./k8s_lab/pause.tar;}}
      ${pkgs.docker}/bin/docker load < ${builtins.path { path = ./k8s_lab/kubernetes-dashboard-amd64.tar;}}
      ${pkgs.docker}/bin/docker load < ${builtins.path { path = ./k8s_lab/k8s-dns-sidecar-amd64.tar;}}
      ${pkgs.docker}/bin/docker load < ${builtins.path { path = ./k8s_lab/k8s-dns-kube-dns-amd64.tar;}}
      ${pkgs.docker}/bin/docker load < ${builtins.path { path = ./k8s_lab/k8s-dns-dnsmasq-nanny-amd64.tar;}}
      ${pkgs.docker}/bin/docker load < ${builtins.path { path = ./k8s_lab/hostpath-provisioner.tar;}}
      ${pkgs.docker}/bin/docker tag mazdermind/hostpath-provisioner:latest 10.1.0.1:5000/mazdermind/hostpath-provisioner:latest
      ${pkgs.docker}/bin/docker push 10.1.0.1:5000/mazdermind/hostpath-provisioner:latest
    '';

    serviceConfig = {
      Type = "oneshot";
    };
  };

   # enable ssh
   systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
   services.dbus.socketActivated = true;

   fonts = {
     fontconfig = {
       enable = lib.mkForce true;
       hinting.autohint = true;
       antialias = true;
     };

     enableFontDir = true;
     #enableCoreFonts = true;
     enableGhostscriptFonts = true;

     fonts = with pkgs; [
       fira
       fira-code
       fira-mono
       ibm-plex
       overpass
       terminus_font_ttf
       #nerdfonts
       source-code-pro
       font-awesome_5
       opensans-ttf
       roboto
       ubuntu_font_family
     ];
   };

   services.xserver = {
     synaptics.enable = true;
     enable = true;
     
     displayManager.slim.defaultUser = "student";
     desktopManager = {
       default = "xfce";
       xterm.enable = false;
       xfce.enable = true;
     };
   };        

   users.extraUsers.student = {
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
       "docker"
     ];
     createHome = true;
     home = "/home/student";
     uid = 1000;
     password = "student";
   };
   time.timeZone = "Europe/Warsaw";
   system.activationScripts = {
     dotfiles = stringAfter [ "users" ]
     ''
       cd /home/student
       mkdir .kube || true && cp ${./k8s_lab/kubernetes/dotfiles/kubernetes} .kube/config
       chown student:nogroup .kube -R
       chmod 755 .kube -R
     '';
   };

   services.openssh.enable = true;
   nix.useSandbox = true;
   users.mutableUsers = false;
    environment.systemPackages = with pkgs; [
      curl
      firefox
      git
      sudo
      kubectl
      vim
      docker
      docker_compose
      xfce.xfconf
      xfce.mousepad
      xfce.thunar
      xfce.xfce4icontheme
      xfce.xfce4settings
      xfce.xfce4-terminal
      rxvt_unicode-with-plugins
      termite
    ];
  }
