# ehpc.io NixOS config

Hi there :smile:

This is my [NixOS](https://nixos.org/) config for the [ehpc.io](https://ehpc.io) VPS server.

It's based on [flakes](https://wiki.nixos.org/wiki/Flakes).

A few secrets are managed by [sops-nix](https://github.com/Mic92/sops-nix).

## Commands

Before a planned rebuild, record the current generation, review all pending
changes and resource headroom, and choose a maintenance window: activation may
restart services. The checkout path includes untracked files; a Git flake ignores
new untracked files. Commit intended modules, tests, and documentation to the
repository when authorized, but never commit runtime keys or other secrets.
Limit build concurrency:

```sh
readlink /nix/var/nix/profiles/system
sudo nixos-rebuild switch --max-jobs 1 --cores 2 --flake path:/home/ehpc/ehpc.io-configs#ehpc-io-vps
```

Run VM regressions and `nix flake check` on a development machine or CI, not
on the 4 GiB production VPS.

If an older generation fails with `error: public key is not valid`, rebuild once
with the official NixOS cache and key explicitly selected. This bypasses the
malformed key in the active configuration without disabling signature checks:

```sh
sudo nixos-rebuild switch --max-jobs 1 --cores 2 --flake path:/home/ehpc/ehpc.io-configs#ehpc-io-vps \
  --option substituters https://cache.nixos.org \
  --option trusted-public-keys cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
```

After activation, use the normal rebuild command again. The corrected
`nix-community` key in `nixos/main.nix` comes from the
[Cachix API](https://cachix.org/api/v1/cache/nix-community).

## GitHub SSH key caching

`nixos/ssh.nix` starts a user SSH agent and configures GitHub connections to use
`~/.ssh/github` with `AddKeysToAgent yes`. After applying the configuration,
start a fresh login session so the shell inherits `SSH_AUTH_SOCK`.

The first GitHub SSH connection prompts for the key's passphrase and caches the
unlocked key in the agent; subsequent connections using that agent do not prompt.
A new agent session requires unlocking again. Start coding agents from that same
shell so they can use the cached key.

## Audio credentials

The audio server obtains `MODAL_TOKEN_ID` and `MODAL_TOKEN_SECRET` from
`default/audio-modal-token`, and `OPENROUTER_API_KEY` from
`default/audio-openrouter`. The source of truth is the existing SOPS-encrypted
`secrets.yaml`: sops-nix renders both Kubernetes Secrets, and
`apply-k8s-manifests` applies them before the audio Deployment.

For initial provisioning, all three encrypted top-level keys must exist:
`modal-token-id`, `modal-token-secret`, and `openrouter-api-key`. The current
deployment is already running; edit `secrets.yaml` privately with `sops` and the
existing recipients when rotation is needed. Never print or paste credentials, commit
plaintext or dummy values, or substitute developer credentials. Existing values
are managed separately from this configuration.

sops-nix installs secrets before service startup. The manifest apply service
waits for secret installation when applicable and refuses to apply manifests if
either rendered audio Secret is unreadable. Do not apply the Deployment alone
before both Secrets are ready. Rotation takes effect in running containers only
after an explicitly approved Deployment restart. The CPU web deployment still
uses Modal credentials for GPU workloads; manage other Modal-side secrets according
to the workloads that use them.

The checked-in audio Deployment requests `128Mi`/`100m` and limits `1Gi`/`1`
CPU. Preserve the route-scoped `64m` client-settings policy when changing it.

## Outbound authentication mail

The NixOS mail configuration in `nixos/mail.nix` is active. On 2026-11-09,
Postfix, OpenDKIM, and `audio-mail.socket` were observed active. This is mail
infrastructure only: the
audio application has no SMTP Unix-socket adapter, mount, or group access yet;
invitation and email-OTP authentication are not implemented.

The sender is `no-reply@auth.ehpc.io`, the envelope sender is
`bounce@auth.ehpc.io`, the signing domain is `auth.ehpc.io`, and the outbound
EHLO name is `mail.ehpc.io`. Public SMTP listens on IPv4 port 25 and accepts
only local `bounce@auth.ehpc.io` and `postmaster@auth.ehpc.io`; it does not
provide an open relay. Inbound port 25 receives delayed failure notifications:
it is not required to send outbound mail, but closing it loses remote bounces
unless another receiver is configured. Do not add an `auth.ehpc.io` MX until
bounce intake is verified.

Trusted submission uses `/run/audio-mail/submit.sock` (`root:audio-mail`, mode
`0660`) through a private Postfix socket; no public submission port or trusted
pod CIDR is configured. A future pod must be explicitly granted the required
mount and group, and use an SMTP-over-Unix-socket adapter: pod loopback is not
host loopback. The authorized client must supply the exact bare header
`From: no-reply@auth.ehpc.io`; a wrong present From is rejected, but a missing
From can be accepted unsigned by the pinned OpenDKIM. Test the client contract.
Outbound delivery requires STARTTLS; this does not establish recipient identity
with DANE or guarantee delivery.

The existing `auth.ehpc.io` SPF and DMARC records, `mail.ehpc.io` IPv4 A/PTR,
and `vps2026._domainkey.auth.ehpc.io` DKIM TXT have been verified. The published
RSA-2048 public key has DER SHA-256
`ac9d293a4669c8337a11492929ce7d9d4fc14c23170cbf4949eb7362e6bc5011`.
Preserve the existing Google-hosted root `ehpc.io` MX, SPF, DKIM, and DMARC.
The private signing key is generated at runtime under `/var/lib/opendkim/keys`,
outside the Nix store; never print it, share it in chat, or commit it. Keep
encrypted, access-controlled backups of the DKIM key and SOPS age identity
outside the Nix store and repository. Coordinate key rotation with the
selector's DNS TXT update. The
public record can be displayed with `sudo cat /var/lib/opendkim/keys/vps2026.txt`.

One approved test (queue `1B8081805E3`) reached the user's Gmail inbox on
2026-11-09. The user reported Gmail SPF, DKIM, and DMARC passes, with TLS 1.3
`TLS_AES_256_GCM_SHA384` on the receiving hop. This is evidence for that test,
not a guarantee for other providers or future delivery. No further messages
should be sent without approval.

For routine, non-sending checks, inspect service state and metadata only:

```sh
systemctl is-active postfix.service opendkim.service audio-mail.socket
sudo stat -c '%U:%G %a %n' /run/audio-mail/submit.sock
sudo stat -c '%U:%G %a %n' /var/lib/opendkim/keys/vps2026.private
sudo stat -c '%U:%G %a %s %n' /var/spool/mail/mail-bounce
```

The bounded bounce mailbox is created on first delivery; its absence before
then is not necessarily a failure. An isolated local NixOS VM regression passed
for the mail module, including socket access and DKIM signing. Run
`nix build "path:$PWD#checks.x86_64-linux.mail"` only on a development machine or CI,
never on the production VPS. It is not a production delivery test.

Before any future system change, record the current generation as above. For a
rollback, select the appropriate recorded prior generation and activate it; the
pre-mail generation 242 is historical, not a universal rollback target:

```sh
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
printf 'Recorded previous generation to restore: '; read -r generation
sudo nix-env --profile /nix/var/nix/profiles/system --switch-generation "$generation" &&
  sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

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
