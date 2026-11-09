# ehpc.io NixOS config

Hi there :smile:

This is my [NixOS](https://nixos.org/) config for the [ehpc.io](https://ehpc.io) VPS server.

It's based on [flakes](https://wiki.nixos.org/wiki/Flakes).

A few secrets are managed by [sops-nix](https://github.com/Mic92/sops-nix).

## Commands

Before any planned activation, record the current system generation, review
all pending user changes and resource headroom, and choose a maintenance
window: activation may restart services. This branch is **not activated**.
Verify that the reviewed local build source includes all intended live-checkout
changes and that its deployment manifest and image pin match the approved
release. Never overwrite unrelated staged work or build from an older branch
while claiming it includes newer user changes.
The apply service reads `/home/ehpc/ehpc.io-configs/k8s` at runtime; those
live manifests must match the reviewed build source and final image pin before
activation. The isolated auth worktree is not the live path. Take a fresh,
consistent SQLite backup immediately before the authenticated cutover.

Build on a development workstation or CI, never on the 4 GiB VPS. From the
reviewed configuration checkout, limit build concurrency, then copy the actual
resulting closure:

```sh
nix build --max-jobs 1 --cores 2 'path:'"$PWD"'#nixosConfigurations.ehpc-io-vps.config.system.build.toplevel' &&
system=$(readlink -f result) &&
nix copy --to ssh-ng://ehpc-io-vps "$system"
```

After an independently approved cutover and confirming the closure is present,
an authorized root operator may set the remote system profile and switch to
that exact copied store path. This invokes no build or evaluation on the VPS:

```sh
ssh -t ehpc-io-vps "sudo nix-env --profile /nix/var/nix/profiles/system --set '$system' && sudo '$system/bin/switch-to-configuration' switch"
```

If a local build fails with `error: public key is not valid`, build locally
using the official NixOS cache and key without disabling signature checks:

```sh
nix build --max-jobs 1 --cores 2 'path:'"$PWD"'#nixosConfigurations.ehpc-io-vps.config.system.build.toplevel' \
  --option substituters https://cache.nixos.org \
  --option trusted-public-keys cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
```

Run VM regressions and `nix flake check` on a development machine or CI too.
The corrected `nix-community` key in `nixos/main.nix` comes from the
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
`default/audio-openrouter`. Invite-only access additionally requires independent
`AUTH_OTP_SECRET` and `AUTH_INVITE_SECRET` values from `default/audio-auth`.
The existing SOPS-encrypted `secrets.yaml` is the source of truth; the prepared
configuration has not yet been activated or deployed.

Five encrypted top-level keys must exist: `modal-token-id`,
`modal-token-secret`, `openrouter-api-key`, `audio-auth-otp-secret`, and
`audio-auth-invite-secret`. The two auth secrets must be distinct stable
CSPRNG values of at least 32 bytes (for example, 64 hexadecimal characters).
An authorized root operator can edit them privately using
`sudo env SOPS_AGE_KEY_FILE=/etc/age/keys.txt sops /home/ehpc/ehpc.io-configs/secrets.yaml`.
Never print credentials, commit plaintext or dummy values, or use developer
credentials. Retain stable existing keys and back them up securely.

The prepared apply service refuses missing/unreadable templates, short or equal
auth keys, and unavailable `audio-mail` group before applying audio resources.
Its renderer resolves the host's actual group ID and adds it to supplemental
groups without changing fsGroup. The pod mounts `/run/audio-mail` as a read-only
directory, not a socket inode. The gateway-only ingress NetworkPolicy must be
enforced before trusting the observed gateway node subnet `10.42.0.0/24`.
An isolated equivalent policy test allowed the gateway, denied a nonmatching
pod and preserved kubelet readiness; it did not test the actual audio pod's
policy or socket mount. Recheck subnet, labels, permissions, additive policies,
gateway forwarding, kubelet probes and socket connectivity during the approved
cutover. Production activation still requires a verified image and root access.

The checked-in audio Deployment requests `128Mi`/`100m` and limits `1Gi`/`1`
CPU. Preserve the route-scoped `64m` client-settings policy when changing it.

## Outbound authentication mail

The NixOS mail configuration in `nixos/mail.nix` is active. On 2026-11-09,
Postfix, OpenDKIM, and `audio-mail.socket` were observed active. The application
adapter and invite-only access are implemented and tested locally, not deployed.

The sender is `no-reply@auth.ehpc.io`, the envelope sender is
`bounce@auth.ehpc.io`, the signing domain is `auth.ehpc.io`, and the outbound
EHLO name is `mail.ehpc.io`. Public SMTP listens on IPv4 port 25 and accepts
only local `bounce@auth.ehpc.io` and `postmaster@auth.ehpc.io`; it does not
provide an open relay. Inbound port 25 receives delayed failure notifications:
it is not required to send outbound mail, but closing it loses remote bounces
unless another receiver is configured. Do not add an `auth.ehpc.io` MX until
bounce intake is verified.

Trusted submission uses `/run/audio-mail/submit.sock` (`root:audio-mail`, mode
`0660`) through a private Postfix socket; there is no public submission port.
The prepared pod uses the directory mount and runtime group described above;
pod loopback is not host loopback. The authorized client must supply the exact
bare header
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
