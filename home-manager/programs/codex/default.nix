{
  pkgs,
  pkgsTools,
  ...
}:
{ config, lib, ... }:
let
  homeDirectory = config.home.homeDirectory;

  # Mirrors the Bash allow/deny lists of the Claude Code config. Codex matches
  # on the argv prefix, so [ "git" "log" ] covers `git log --oneline` etc.
  allowPrefixes = [
    [
      "git"
      "status"
    ]
    [
      "git"
      "log"
    ]
    [
      "git"
      "diff"
    ]
    [
      "git"
      "show"
    ]
    [
      "git"
      "branch"
    ]
    [
      "git"
      "commit"
    ]
    [ "ls" ]
    [ "cat" ]
    [ "echo" ]
    [ "which" ]
    [ "pwd" ]
    [ "env" ]
    [ "printenv" ]
    [ "find" ]
    [ "wc" ]
    [ "head" ]
    [ "tail" ]
    [ "sort" ]
    [ "uniq" ]
    [ "grep" ]
    [ "tree" ]
    [ "file" ]
    [ "rg" ]
    [ "fd" ]
    [ "jq" ]
  ];

  forbidPrefixes = [
    [ "sudo" ]
    [ "rm" ]
    [
      "git"
      "push"
    ]
    [
      "git"
      "reset"
    ]
    [
      "git"
      "rebase"
    ]
  ];

  mkRule =
    decision: pattern:
    ''prefix_rule(pattern=[${
      lib.concatMapStringsSep ", " (part: ''"${part}"'') pattern
    }], decision="${decision}")'';

  rulesFile = pkgs.writeText "codex-nix.rules" ''
    # Managed by home-manager. Do not edit; edit programs/codex/default.nix.
    ${lib.concatMapStringsSep "\n" (mkRule "allow") allowPrefixes}

    ${lib.concatMapStringsSep "\n" (mkRule "forbidden") forbidPrefixes}
  '';
in
{
  # Symlink the skill directory itself rather than its contents: Codex does not
  # follow a symlinked SKILL.md, only a symlinked skill directory.
  home.file.".codex/skills/playwright-cli".source =
    pkgsTools.playwright-cli.src + "/skills/playwright-cli";

  # Codex skips symlinked *.rules files (it stats directory entries without
  # following symlinks) and home.file would install one, so copy a real file
  # instead. The rules directory stays writable so Codex can keep managing its
  # own default.rules when approvals are accepted interactively.
  home.activation.codexRules = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "${homeDirectory}/.codex/rules"
    run install -m 644 ${rulesFile} "${homeDirectory}/.codex/rules/nix.rules"
  '';

  programs.codex = {
    enable = true;
    package = pkgsTools.codex;
    # Settings deliberately live in /etc/codex/config.toml (modules/codex.nix),
    # not here: Codex rewrites ~/.codex/config.toml at runtime to persist
    # project trust, model and theme, which fails against a store symlink.
    settings = { };
  };
}
