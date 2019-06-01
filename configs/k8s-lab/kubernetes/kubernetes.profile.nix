{ config, lib, pkgs, ... }:
with lib;

let
in
rec {
  # Kubernetes configuration
  # Insecure, for local development only, totally unsuitable for production
  services.flannel.iface = "127.0.0.1";
  services.flannel.subnetMin = "10.1.0.0";
  services.flannel.subnetMax = "10.1.0.0";

  services.kubernetes = {
    roles = ["master" "node"];

    addons = {
      dashboard = {
        enable = true;
        rbac = {
          enable = true;
          clusterAdmin = true;
        };
      };
      dns = {
        enable = true;
        clusterDomain = "cluster.local";
      };
    };

    path = [ pkgs.zfs ];
    featureGates = ["AllAlpha"];
    flannel.enable = true;
    clusterCidr = "10.1.0.0/16"; ## used by flannel too

    # Without explicitly defined keys things will break after reboot,
    # as by default keys will be generated in /var/run/kubernetes.
    # Note, for simplicity and laziness sake, a single keypair is used
    # for CA, server and client keys - which is totally insecure.
    caFile = "${./k8s.crt}";

    kubeconfig = {
      keyFile = "${./k8s.key}";
      certFile = "${./k8s.crt}";
    };

    apiserver = {
      bindAddress = "0.0.0.0";
      advertiseAddress = "10.1.0.1";
      authorizationMode = [ "AlwaysAllow" "RBAC"];
      tlsCertFile = "${./k8s.crt}";
      tlsKeyFile = "${./k8s.key}";
      kubeletClientCaFile = "${./k8s.crt}";
      kubeletClientCertFile = "${./k8s.crt}";
      kubeletClientKeyFile = "${./k8s.key}";
      serviceAccountKeyFile = "${./k8s.key}";
      extraOpts = "--insecure-bind-address=0.0.0.0";
      basicAuthFile = pkgs.writeText "users" ''
        kubernetes,admin,0,"cluster-admin"
      '';
      serviceClusterIpRange = "172.30.0.0/16";
    };
    proxy = {
      kubeconfig = {
        certFile = "${./k8s.crt}";
        keyFile = "${./k8s.key}";
     };
    };
    scheduler = {
      kubeconfig = {
        certFile = "${./k8s.crt}";
        keyFile = "${./k8s.key}";
     };
    };
    controllerManager = {
      rootCaFile = "${./k8s.crt}";
      serviceAccountKeyFile = "${./k8s.key}";
      kubeconfig = {
        certFile = "${./k8s.crt}";
        keyFile = "${./k8s.key}";
     };
    };

    kubelet = {
      unschedulable = false;
      hostname = "node.127.0.0.1.nip.io";
      tlsKeyFile = "${./k8s.key}";
      tlsCertFile = "${./k8s.crt}";
      extraOpts = "--fail-swap-on=false --eviction-hard=memory.available<128Mi,nodefs.available<512Mi,imagefs.available<512Mi,nodefs.inodesFree<5%";
      kubeconfig = {
        certFile = "${./k8s.crt}";
        keyFile = "${./k8s.key}";
     };
    };
  };

  # virtualisation.docker.extraOptions = "--dns=${config.services.kubernetes.addons.dns.clusterIp}";
  # services.dnsmasq.enable = true;
  # services.dnsmasq.resolveLocalQueries = false;
  services.dnsmasq.servers = [
    "/cluster.local/${config.services.kubernetes.addons.dns.clusterIp}#53"
  ];

  networking.firewall.allowedUDPPorts = [ 8472 ];
  networking.firewall.trustedInterfaces = [ "flannel.1" ];

  networking.firewall.extraCommands = ''
    ip46tables -A nixos-fw -i cbr0 -j ACCEPT
    ip46tables -A nixos-fw -i docker0 -j ACCEPT
    ip46tables -A nixos-fw -i flannel.1 -j ACCEPT
    ip46tables -A nixos-fw -i zt0 -j ACCEPT
  '';

  services.kubernetes.addonManager.addons.provisioner-cr = {
    kind = "ClusterRole";
    apiVersion = "rbac.authorization.k8s.io/v1beta1";
    metadata = {
      labels = {
        "addonmanager.kubernetes.io/mode" = "Reconcile";
      };
      name = "hostpath-provisioner";
    };
    rules = [
      {
        apiGroups = [""];
        resources = ["persistentvolumes"];
        verbs = ["get" "list" "watch" "create" "delete"];
      }
      {
        apiGroups = [""];
        resources = ["persistentvolumeclaims"];
        verbs = ["get" "list" "watch" "update"];
      }
      {
        apiGroups = ["storage.k8s.io"];
        resources = ["storageclasses"];
        verbs = ["get" "list" "watch"];
      }
      {
        apiGroups = [""];
        resources = ["events"];
        verbs = ["list" "watch" "create" "update" "patch"];
      }
    ];
  };
  services.kubernetes.addonManager.addons.provisioner-crb = {
    kind = "ClusterRoleBinding";
    apiVersion = "rbac.authorization.k8s.io/v1beta1";
    metadata = {
      labels = {
        "addonmanager.kubernetes.io/mode" = "Reconcile";
      };
      name="hostpath-provisioner";
    };
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = "hostpath-provisioner";
    };
    subjects = [
      {
        kind = "ServiceAccount";
        name = "default";
        namespace = "kube-system";
      }
    ];
  };
  services.kubernetes.addonManager.addons.provisioner-dep = {
    apiVersion="extensions/v1beta1";
    kind="Deployment";
    metadata = {
      name="hostpath-provisioner";
      labels = {
        k8s-app = "hostpath-provisioner";
        "addonmanager.kubernetes.io/mode" = "Reconcile";
      };
      namespace = "kube-system";
    };
    spec = {
      replicas = 1;
      revisionHistoryLimit = 0;

      selector = {
        matchLabels = {
          k8s-app = "hostpath-provisioner";
        };
      };

      template = {
        metadata = {
          labels = {
            k8s-app = "hostpath-provisioner";
          };
        };

        spec = {
          containers = [
            {
              name = "hostpath-provisioner";
              image = "10.1.0.1:5000/mazdermind/hostpath-provisioner:latest";
              env = [
                {
                  name = "NODE_NAME";
                  valueFrom = {
                    fieldRef = {
                        fieldPath="spec.nodeName";
                      };
                    };
                }
                {
                  name="PV_DIR";
                  value="/var/kubernetes";
                }
              ];
              volumeMounts = [
                {
                  name="pv-volume";
                  mountPath="/var/kubernetes";
                }
              ];
            }
          ];

          volumes = [
            {
              name="pv-volume";
              hostPath = {
                path="/var/kubernetes";
              };
            }
          ];
        };
      };
    };
  };
  services.kubernetes.addonManager.addons.provisioner-sc = {
    kind = "StorageClass";
    apiVersion = "storage.k8s.io/v1";
    metadata = {
      name = "hostpath";
      annotations = {
        "storageclass.kubernetes.io/is-default-class" = "true";
      };
      labels = {
        "addonmanager.kubernetes.io/mode" = "Reconcile";
      };
    };
    provisioner = "hostpath";
  };
  services.kubernetes.addonManager.addons.admin-crb = {
    apiVersion="rbac.authorization.k8s.io/v1";
    kind = "ClusterRoleBinding";
    metadata = {
      labels = {
        "addonmanager.kubernetes.io/mode" = "Reconcile";
      };
      name = "cluster-admin-binding";
    };
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = "cluster-admin";
    };
    subjects = [
        {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "User";
          name = "admin";
        }
      ];
  };

  services.kubernetes.addonManager.addons.kubedns-cm.data.upstreamNameservers = ''
    ["10.1.0.1"]
  '';
}
