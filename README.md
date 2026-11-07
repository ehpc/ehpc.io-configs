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

## Audio credentials

The audio server obtains `MODAL_TOKEN_ID` and `MODAL_TOKEN_SECRET` from
`default/audio-modal-token`, and `OPENROUTER_API_KEY` from
`default/audio-openrouter`. The source of truth is the existing SOPS-encrypted
`secrets.yaml`: sops-nix renders both Kubernetes Secrets, and
`apply-k8s-manifests` applies them before the audio Deployment.

**Activation prerequisite:** use `sops secrets.yaml` privately, with the
repository's existing recipients, to supply all three encrypted top-level keys:

- `modal-token-id` and `modal-token-secret`: dedicated production Modal credentials,
  mapped to `audio-modal-token` keys `token-id` and `token-secret`.
- `openrouter-api-key`: the application's OpenRouter key, mapped to
  `audio-openrouter` key `OPENROUTER_API_KEY`.

Never paste keys in chat or commit plaintext, dummy values, or a developer's
credentials. Credential values are managed separately; this wiring does not
supply them. Do not rebuild NixOS or apply the updated Deployment until all three
real entries exist and production activation is explicitly approved. sops-nix
validates the declared keys; a rebuild without them cannot provision the Secrets.

After that prerequisite and approval, use the normal NixOS rebuild above.
By default sops-nix installs secrets during NixOS activation, before services
start. If systemd secret installation is enabled, the root apply service requires
and waits for `sops-install-secrets.service` instead. The service refuses to apply
any manifests if either rendered audio Secret is unreadable, then creates both
Secrets before applying `120-audio`; the Deployment requires all three keys.
Never apply the Deployment by itself before both Secrets are ready. Key rotation
updates the Secrets on the next approved rebuild/apply; running containers keep
their old environment until an explicitly approved Deployment restart.

This credential wiring does not activate anything or move SongFinder to the VPS;
the application migration is separate. Keep the current Modal-side OpenRouter
secret/key active until that CPU cutover is complete. Keep the Modal token
credentials afterward for GPU workloads.

When merging this review patch into an existing server checkout, retain unrelated
local changes, including the audio Deployment's `1Gi`/`500m` limits and the
route-scoped `64m` client-settings policy. This patch only adds environment references
to the Deployment; it does not authorize a resource change or a rollout.

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
