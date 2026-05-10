{ pkgs, ... }:
{
  home.file.".claude/statusline-command.sh" = {
    source = ./statusline-command.sh;
    executable = true;
  };

  programs.claude-code = {
    enable = true;
    package = pkgs.claude-code;
    settings = {
      env = {
        CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
        ENABLE_LSP_TOOL = "1";
      };
      preferences = {
        tmuxSplitPanes = true;
      };
      includeCoAuthoredBy = false;
      permissions = {
        additionalDirectories = [ ];
        allow = [
          "Skill"
          "Read"
          "Grep"
          "Glob"
          "LS"
          "WebFetch"
          "WebSearch"
          "Bash(git status)"
          "Bash(git log *)"
          "Bash(git diff *)"
          "Bash(git show *)"
          "Bash(git branch *)"
          "Bash(ls *)"
          "Bash(cat *)"
          "Bash(echo *)"
          "Bash(which *)"
          "Bash(pwd)"
          "Bash(printenv *)"
          "Bash(find *)"
          "Bash(wc *)"
          "Bash(head *)"
          "Bash(tail *)"
          "Bash(sort *)"
          "Bash(uniq *)"
          "Bash(grep *)"
          "Bash(tree *)"
          "Bash(file *)"
          "Bash(rg *)"
          "Bash(fd *)"
          "Bash(jq *)"
        ];
        ask = [ ];
        defaultMode = "default";
        # Short, focused deny list. Anything else prompts (defaultMode = "default").
        # The sandbox + filesystem perms + sops are the real walls; this list just
        # blocks footguns you might rubber-stamp in a hurry.
        deny = [
          "Bash(sudo *)"
          "Bash(rm -rf *)"
          "Bash(git push *)"
          "Bash(nixos-rebuild *)"
          "Bash(kubectl delete *)"
          "Bash(helm uninstall *)"
        ];
      };
      statusLine = {
        command = "bash /home/ehpc/.claude/statusline-command.sh";
        type = "command";
      };
      theme = "dark";
      sandbox = {
        enabled = true;
        failIfUnavailable = true;
        filesystem = {
          allowWrite = [
            "./"
            "~/.cache/"
          ];
          denyWrite = [
            "~/.ssh"
            "~/.gnupg"
            "/etc"
            "/var/lib/rancher"
            "/etc/rancher"
          ];
        };
      };
    };
  };
}
