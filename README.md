# ehpc.io NixOS config

Hi there :smile:

This is my [NixOS](https://nixos.org/) config for the [ehpc.io](https://ehpc.io) VPS server.

It's based on [flakes](https://wiki.nixos.org/wiki/Flakes).

A few secrets are managed by [sops-nix](https://github.com/Mic92/sops-nix).

## Commands

Rebuild from config `sudo nixos-rebuild switch --flake .#ehpc-io-vps`

If an older generation fails with `error: public key is not valid`, rebuild once
with the official NixOS cache and key explicitly selected. This bypasses the
malformed key in the active configuration without disabling signature checks:

```sh
sudo nixos-rebuild switch --flake .#ehpc-io-vps \
  --option substituters https://cache.nixos.org \
  --option trusted-public-keys cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
```

After activation, use the normal rebuild command again. The corrected
`nix-community` key in `nixos/main.nix` comes from the
[Cachix API](https://cachix.org/api/v1/cache/nix-community).

## Coding agents

Home Manager installs `herdr`, `omp`, and `codex` for `ehpc`, using the same
agent-package nixpkgs revision as the desktop configuration. The separate
`nixpkgs-tools` input leaves the server's existing package set unchanged.

`home-manager/programs/omp.nix` restores the desktop's model roles, theme, and
composer preferences to a writable `~/.omp/agent/config.yml` on activation.
Interactive preference changes are overwritten on the next rebuild.

`nixos/codex.nix` supplies defaults through `/etc/codex/config.toml`, leaving
Codex free to manage its user config. Home Manager installs the matching
approval rules as a regular `~/.codex/rules/nix.rules` file and links the
Playwright CLI skill. The accompanying `playwright-cli` package uses the
desktop's pinned version and Nix-managed browsers.

Credentials and sessions are not copied; authenticate each agent on the server.
Herdr is installed as a CLI; no wherdr web service or network endpoint is enabled.
