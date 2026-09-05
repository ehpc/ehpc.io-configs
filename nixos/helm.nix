{ pkgs, ... }:
let
  my-kubernetes-helm =
    with pkgs;
    wrapHelm kubernetes-helm {
      plugins = with pkgs.kubernetes-helmPlugins; [
        helm-secrets
        helm-diff
        helm-s3
        helm-git
      ];
    };

  my-helmfile = pkgs.symlinkJoin {
    name = "helmfile-${pkgs.helmfile.version}";
    paths = [ pkgs.helmfile ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/helmfile \
        --set HELM_PLUGINS ${my-kubernetes-helm.pluginsDir}
    '';
  };
in

{
  environment.systemPackages = [
    my-kubernetes-helm
    my-helmfile
  ];
}
