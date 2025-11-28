{ stdenv, fetchurl }:
stdenv.mkDerivation {
  pname = "longhornctl";
  version = "1.10.1";

  src = fetchurl {
    url = "https://github.com/longhorn/cli/releases/download/v1.10.1/longhornctl-linux-amd64";
    sha256 = "sha256:955c7085b29594a1310ffc9f2ad35bc566a45ab664ccb042667d2129dbf6a3cd";
  };

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/longhornctl
    chmod +x $out/bin/longhornctl
  '';
}
