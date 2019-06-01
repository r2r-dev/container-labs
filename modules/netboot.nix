{ lib, config, pkgs, ... }:

with lib;

let
  cfg = config.netboot;
  server = cfg.network.lan.hostName;

  nixosBuild = {modules ? []}:
    (import "${cfg.nixpkgs}/nixos/lib/eval-config.nix" {
      system = builtins.currentSystem;
      pkgs = (import cfg.nixpkgs {system=builtins.currentSystem;});
      modules = [
        "${cfg.nixpkgs}/nixos/modules/installer/netboot/netboot-minimal.nix"
      ] ++ modules;
    }).config.system.build;

  nixosNetboot = {modules ? []}:
    let
      build = nixosBuild { inherit modules; };
    in {
      toplevel = build.toplevel;
      dir = pkgs.symlinkJoin {
        name = "nixos_netboot";
        paths = with build; [ netbootRamdisk kernel netbootIpxeScript ];
      };
    };

  inMenu = name: netbootitem: netbootitem // { menu = name; };
  evaluated_items = mapAttrs (name: value: inMenu value.menu (nixosNetboot {modules=value.modules;})) cfg.ipxe.items;

  ipxe_item_nixos = name: item: ''
    :${name}
    imgfree
    imgfetch http://${server}/${name}/bzImage init=${builtins.unsafeDiscardStringContext item.toplevel}/init loglevel=7
    imgfetch http://${server}/${name}/initrd
    imgselect bzImage
    boot
  '';

  concatNl = concatStringsSep "\n";
  items_nixos = concatNl (mapAttrsToList ipxe_item_nixos evaluated_items);

  items_symlinks = items: subfolder: concatNl (mapAttrsToList (name: x: ''
      mkdir -p $out/${subfolder}/${name}
      for i in ${x.dir}/*; do
        ln -s $i $out/${subfolder}/${name}/$( basename $i)
      done
    '') items);

  menu_items = concatNl (mapAttrsToList (name: x: "item ${name} ${x.menu}" )
    (filterAttrs (const (hasAttr "menu")) evaluated_items));

  ipxe_script = pkgs.writeText "script.ipxe" ''
    #!ipxe
    echo ${cfg.ipxe.banner} stage 2
    console --x 1024 --y 768 --picture http://${server}/bg.png --keep
    cpair 0

    :net
    goto menu

    :menu
    :restart
    menu Chose Boot Option
    ${menu_items}
    item loop Start iPXE shell
    item off Shutdown
    item reset Reboot
    choose --default nixos_netboot --timeout 5000 res || goto restart
    goto ''${res}

    :off
    poweroff
    goto off
    :reset
    reboot
    goto reset

    :loop
    login || goto cancelled

    iseq ''${password} ${cfg.ipxe.password} && goto is_correct ||
    echo password wrong
    sleep 5
    goto loop

    :cancelled
    echo you gave up, goodbye
    sleep 5
    poweroff
    goto cancelled

    :is_correct
    shell

    ${items_nixos}
  '';

  ipxe = pkgs.lib.overrideDerivation pkgs.ipxe (x: {
    script = pkgs.writeText "embed.ipxe" ''
      #!ipxe
      echo ${cfg.ipxe.banner} stage 1
      dhcp
      imgfetch http://${server}/script.ipxe
      chain script.ipxe
      echo temporary debug shell
      shell
    '';
    nativeBuildInputs = x.nativeBuildInputs ++ [ pkgs.openssl ];
    makeFlags = x.makeFlags ++ [
      ''EMBED=''${script}''
    ];

    enabledOptions = x.enabledOptions ++ [
      "POWEROFF_CMD"
      "CONSOLE_CMD"
      "IMAGE_PNG"
    ];
    configurePhase = ''
      runHook preConfigure
      for opt in $enabledOptions; do echo "#define $opt" >> src/config/general.h; done
      echo "#define CONSOLE_FRAMEBUFFER" >> src/config/console.h
      runHook postConfigure
    '';
  });

  pxeLinuxDefault = pkgs.writeText "default" ''
    DEFAULT ipxe
    LABEL ipxe
    KERNEL ipxe.lkrn
    '';

  nginx_root = pkgs.runCommand "nginxroot" { buildInputs = [ pkgs.openssl ]; } ''
    mkdir -pv $out
    ln -sv ${ipxe_script} $out/script.ipxe
    ln -sv ${pkgs.nixos-artwork.wallpapers.simple-dark-gray}/share/artwork/gnome/nix-wallpaper-simple-dark-gray.png $out/bg.png
    ${items_symlinks evaluated_items ""}
  '';

  tftp_root = pkgs.runCommand "tftproot" {} ''
    mkdir -pv $out
    mkdir $out/pxelinux.cfg

    ln -s ${pxeLinuxDefault} $out/pxelinux.cfg/default

    ln -s ${pkgs.syslinux}/share/syslinux/pxelinux.0 $out/pxelinux.0
    ln -s ${pkgs.syslinux}/share/syslinux/ldlinux.c32 $out/ldlinux.c32

    ln -s ${ipxe}/ipxe.lkrn $out/ipxe.lkrn

    #cp -vi ${ipxe}/undionly.kpxe $out/undionly.kpxe
  '';


in
{
  options = {
    netboot = rec {
      nixpkgs = mkOption {
        type = types.path;
        description = "path to nixpkgs";
        default = pkgs.path;
      };

      network.lan.interface = mkOption {
        type = types.str;
        description = "the netboot client facing IF";
        default = "eth0";
      };

      network.lan.networkAddress = mkOption {
        type = types.str;
        description = "netboot client facing network address";
        default = "192.168.100.0";
      };

      network.lan.networkMask = mkOption {
        type = types.str;
        description = "netboot client facing network mask";
        default = "255.255.255.0";
      };

      network.lan.startAddress = mkOption {
        type = types.str;
        description = "first address in network";
        default = "192.168.100.10";
      };

      network.lan.endAddress = mkOption {
        type = types.str;
        description = "last address in network";
        default = "192.168.100.254";
      };

      network.lan.broadcastAddress = mkOption {
        type = types.str;
        description = "broadcast address in network";
        default = "192.168.100.255";
      };

      network.lan.hostAddress = mkOption {
        type = types.str;
        description = "netboot host address";
        default = "192.168.100.1";
      };

      network.lan.hostName = mkOption {
        type = types.str;
        description = "netboot host name";
        default = "netboot.local";
      };

      ipxe.banner = mkOption {
        type = types.str;
        description = "Message to display on ipxe script load";
        default = "ipxe loading";
      };

      ipxe.password = mkOption {
        type = types.str;
        description = "IPXE menu password";
      };

      ipxe.items = mkOption {
        type = types.attrsOf types.unspecified;
        default = {};
      };

      ipxe.mapping = mkOption {
        type = types.attrsOf types.unspecified;
        default = {};
      };
    };
  };

  config = {
    users = {
      extraUsers.root.password = "root";
      users.root.initialPassword = "root";
    };

    networking = {
      firewall = {
        allowedTCPPorts = [ 80 22 ];
        allowedUDPPorts = [ 67 68 69 53 ];
      };

      usePredictableInterfaceNames = false; #TODO: optional
      interfaces = {
        "${cfg.network.lan.interface}".ipv4.addresses = [
          {
            address = "${cfg.network.lan.hostAddress}";
            prefixLength = 24;
          }
        ];
      };
    };

    services.dhcpd4 = {
      enable = true;
      interfaces = [ cfg.network.lan.interface ];
      extraConfig = ''
        option arch code 93 = unsigned integer 16;
        subnet ${cfg.network.lan.networkAddress} netmask ${cfg.network.lan.networkMask} {
          option subnet-mask ${cfg.network.lan.networkMask};
          option broadcast-address ${cfg.network.lan.broadcastAddress};
          option routers ${cfg.network.lan.hostAddress};
          option domain-name-servers ${cfg.network.lan.hostAddress};
          range ${cfg.network.lan.startAddress} ${cfg.network.lan.endAddress} ;
          next-server ${cfg.network.lan.hostName};
          filename "pxelinux.0";
        }
      '';
    };
    systemd.services.dhcpd4.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];

    services.dnsmasq = {
      enable = true;
      resolveLocalQueries = true;
      servers = [];
      extraConfig = ''
        address=/${cfg.network.lan.hostName}/${cfg.network.lan.hostAddress}
      '';
    };
    systemd.services.dnsmasq.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];

    services.tftpd = {
        enable = true;
        path = tftp_root;
    };
    systemd.services.tftpd.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];

    services.nginx = {
      enable = true;
      virtualHosts = {
        "${server}" = {
          root = nginx_root;
          locations = {
            "/" = {
              extraConfig = "autoindex on;";
            };
          };
        };
      };
    };
  };
}
