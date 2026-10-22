{
  pkgs,
  ...
}:
let
  username = "ehpc";
  homeDirectory = "/home/${username}";

  format = pkgs.formats.toml { };

  # Codex rewrites ~/.codex/config.toml at runtime (project trust, /model,
  # /theme), so it cannot be a read-only home-manager symlink. /etc/codex is the
  # system config layer: it is loaded *below* the user layer, so these act as
  # defaults and anything Codex writes for the user still wins.
  settings = {
    # `on-request` lets the model decide when to escalate, matching the
    # Claude Code "auto" default mode.
    approval_policy = "on-request";
    sandbox_mode = "workspace-write";
    sandbox_workspace_write = {
      # The workspace itself is always writable; this mirrors the extra
      # "~/.cache/" entry from the Claude Code sandbox allowWrite list.
      writable_roots = [ "${homeDirectory}/.cache" ];
      network_access = false;
    };
    web_search = "live";
    tui = {
      theme = "catppuccin-mocha";
      status_line = [
        "current-dir"
        "git-branch"
        "model-with-reasoning"
        "context-used"
      ];
      status_line_use_colors = true;
    };
  };
in
{
  environment.etc."codex/config.toml".source = format.generate "codex-config.toml" settings;
}
