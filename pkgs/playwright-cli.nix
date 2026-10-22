{ pkgs }:
pkgs.buildNpmPackage rec {
  pname = "playwright-cli";
  version = "0.1.6";

  src = pkgs.fetchFromGitHub {
    owner = "microsoft";
    repo = "playwright-cli";
    rev = "v${version}";
    hash = "sha256-TUzWI0uOsm5HP4RKlMwm4bcYdS0fUkO6ceH82o1zSmU=";
  };

  npmDepsHash = "sha256-mjfrV6ZX8PnjjeIXpKcQ6IadX6qqb8KG8tx/PPuVR8k=";

  nativeBuildInputs = [ pkgs.makeWrapper ];

  env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";

  npmInstallFlags = [ "--ignore-scripts" ];

  dontNpmBuild = true;

  postFixup = ''
    chromiumPath=$(find -L ${pkgs.playwright-driver.browsers} -maxdepth 1 -name "chromium-*" | head -1)
    chromeBin=$(find -L "$chromiumPath" -name "chrome" -type f -executable | head -1)
    wrapProgram $out/bin/playwright-cli \
      --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1 \
      --set PLAYWRIGHT_BROWSERS_PATH ${pkgs.playwright-driver.browsers} \
      --set PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS true \
      --set PLAYWRIGHT_HOST_PLATFORM_OVERRIDE ubuntu-24.04 \
      --set PLAYWRIGHT_MCP_EXECUTABLE_PATH "$chromeBin"
  '';
}
