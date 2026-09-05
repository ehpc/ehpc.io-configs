{ lib, stdenv, fetchurl }:
stdenv.mkDerivation rec {
  pname = "helmfile";
  version = "1.7.4";

  src = fetchurl {
    url = "https://github.com/helmfile/helmfile/releases/download/v${version}/helmfile_${version}_linux_amd64.tar.gz";
    hash = "sha256-+W7woBXfBrKdfzi/DKCIIQGK4l65a/LHq9Ov+huE4RI=";
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 helmfile $out/bin/helmfile
    runHook postInstall
  '';

  meta = {
    description = "Declarative spec for deploying helm charts";
    homepage = "https://github.com/helmfile/helmfile";
    license = lib.licenses.mit;
    mainProgram = "helmfile";
    platforms = [ "x86_64-linux" ];
  };
}
