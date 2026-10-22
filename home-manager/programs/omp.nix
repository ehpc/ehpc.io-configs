{
  lib,
  pkgs,
  pkgsTools,
  ...
}:
let
  settings = {
    modelRoles = {
      default = "openai-codex/gpt-6.1-sol";
      slow = "openai-codex/gpt-6-astra:auto";
      advisor = "openai-codex/gpt-6-luna:auto";
      image = "openai-codex/gpt-image-2";
      smol = "openai-codex/gpt-6-luna:auto";
      tiny = "openai-codex/gpt-6-luna:auto";
      commit = "openai-codex/gpt-6-luna:auto";
      plan = "openai-codex/gpt-6-astra:auto";
    };
    symbolPreset = "nerd";
    composer.shape = "band";
    theme.dark = "titanium";
    setupVersion = 2;
    defaultThinkingLevel = "auto";
  };
  configFile = (pkgs.formats.yaml { }).generate "omp-config.yml" settings;
in
{
  home.packages = [ pkgsTools.omp ];

  # omp rewrites this file when preferences change. Keep it writable, but
  # restore the declared settings on every Home Manager activation.
  home.activation.ompSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.omp/agent"
    run install -m600 ${configFile} "$HOME/.omp/agent/config.yml"
  '';
}
