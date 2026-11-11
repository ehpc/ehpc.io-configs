# ehpc.io NixOS config

Hi there :smile:

This is my [NixOS](https://nixos.org/) config for the [ehpc.io](https://ehpc.io) VPS server.

It's based on [flakes](https://wiki.nixos.org/wiki/Flakes).

A few secrets are managed by [sops-nix](https://github.com/Mic92/sops-nix).

System packages in `nixos/system-packages.nix` include the OpenSSL CLI for
certificate inspection and TLS diagnostics.

## Commands

Before any planned activation, record the current system generation, review
all pending user changes and resource headroom, and choose a maintenance
window: activation may restart services. The checked-in image is the desired
pin, not proof of the currently running image. Verify that the reviewed local
build source includes all intended live-checkout changes and that
`gitops/audio/deployment.yaml` has the approved release image and annotations.
Never overwrite unrelated staged work.
The 2026-11-10 audio release `86c3f47` passed its complete CI workflow; the
checked-in digest is the desired pin and is not itself proof of activation.
The apply service reads common manifests from
`/home/ehpc/ehpc.io-configs/k8s` at runtime and owns the audio NetworkPolicy,
secrets, Service, PVC and Flux bootstrap. Flux alone reconciles the Deployment
from `gitops/audio/deployment.yaml`; Nix never reapplies that Deployment.
Ensure the live common manifests and built source match the reviewed release
before activation. After draining, take fresh consistent SQLite online backups
of `/data/jobs.db` and, if present, `/data/cache-catalog.sqlite` before each
cutover. Preserve all non-database files separately; do not treat a live WAL
archive as the canonical database backup or invent missing catalog metadata.

Save the original live Deployment specification and immutable image pin as
well as the database backup. A pre-auth Nix generation's apply unit does not
restore the Deployment after its legacy manifest was moved, and `kubectl
apply` without prune retains existing Secrets and NetworkPolicies. Recovery
requires a separately reviewed Kubernetes rollback or forward fix; do not
assume a Nix generation switch reverses the application. If an old anonymous
image is ever restored, keep public access closed. Never restore an old
database over newly accepted work. After Flux ownership begins, the Deployment
comes from Git, not a Nix closure. A pre-Flux generation may contain its own
Deployment writer and can conflict with Flux or revert the image. Suspend Flux
and the publisher, safely drain, and independently review that generation
before any host rollback; never treat a Nix rollback as an application rollback.
Follow the reviewed GitOps rollback procedure below.

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

After switching, explicitly start the new `apply-k8s-manifests.service` once
the SOPS templates are ready; an inactive oneshot is not guaranteed to rerun
on switch. Verify the unit result, Secret metadata, pod image and readiness.

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

## Audio GitOps and first ownership transfer

Nix installs digest-pinned Flux 2.9.6 source and kustomize controllers and owns
their bootstrap resources. Flux reads this public repository on `main`, and the
`flux-system/audio` Kustomization applies only `gitops/audio/deployment.yaml`
using the narrowly scoped `audio-reconciler` account. Pruning is disabled;
Secrets, PVCs, Service and NetworkPolicy remain Nix-owned. The controller
cannot create or delete the audio Deployment. Flux checks the Deployment
rollout using its own generation and replica status via a native CEL health
expression: the default health reader also lists ReplicaSets and Pods, which
this account is deliberately not allowed to read. Deadline or replica failures
fail the health check. Missing fields within a returned `status` object wait for
the Deployment controller; if the API omits the entire root `status` binding,
Flux reports a CEL evaluation error and does not mark the rollout Ready. A later
valid status can be retried by normal reconciliation. If the Deployment is
accidentally deleted, an authorized
operator must restore the reviewed Deployment with its actual mail GID before
reconciliation can resume; Flux will not recreate it.

The first Nix activation creates the Kustomization **suspended** if absent.
Nix does not own or reset its `suspend` field on later applies. Do not resume it
against the old application: first verify a full-CI-tested image containing
`python -m backend.drain` and `/ready`, take fresh consistent SQLite and file
backups, pause admissions, and drain existing jobs, searches and inference using
the reviewed operator procedure. Save the live Deployment, Service and PVC
identities. The current legacy workload has no reliable Flux preStop drain.

Before resuming, pin the GitRepository to the exact reviewed config commit so a
concurrent publisher cannot change the candidate during the handoff. With the
matching RKE2 client and an explicitly reviewed commit, for example:

```sh
k=/var/lib/rancher/rke2/bin/kubectl
reviewed_config_commit=$(git -C /home/ehpc/ehpc.io-configs rev-parse HEAD)
"$k" -n flux-system patch gitrepository audio-config --type=merge \
  -p "{\"spec\":{\"ref\":{\"branch\":\"main\",\"commit\":\"$reviewed_config_commit\"}}}"
```

Confirm the source's observed generation is current and its artifact revision
contains that exact commit, and verify the intended image/annotations and runtime
GID. Only then resume `kustomization/audio`, verify its Ready condition, the new
pod image and data preservation, and wait for both EndpointSlice and the served
NGINX upstream before restoring admission. After the rollout is healthy, remove
`spec.ref.commit` without replacing the GitRepository spec so `branch: main`
resumes, then verify the observed source revision and Kustomization:

```sh
"$k" -n flux-system patch gitrepository audio-config --type=merge \
  -p '{"spec":{"ref":{"commit":null}}}'
```

Never restore an old database over newly accepted work. The new app's preStop drain is best-effort:
the 300-second Kubernetes termination grace allows up to five minutes for drain
and cannot guarantee completion of an unbounded external call. Recreate can
make the application unavailable during that drain and replacement; this is not
a zero-downtime rollout. Durable accepted call IDs resume after restart and
uncertain dispatches fail closed rather than spawning duplicates. If bootstrap
fails after resume, keep admission closed and follow a reviewed recovery; do not
automatically activate an old Nix writer while Flux remains active.

The `Publish verified audio pin` workflow runs every five minutes or by manual
dispatch. It changes only the SHA/digest annotations and immutable image after
current app `main` has a successful trusted six-job release run, validates the
registry digest, and refuses non-descendant updates. Automatic publication also
fails closed for persistence/migration-sensitive source changes or an incomplete
GitHub comparison. This path-based conservative gate can require manual review
even for a change that does not actually migrate data. Review the changes and
take a fresh backup before manually committing their verified image pin; later
compatible releases can advance automatically. Playback-only and cache producer
version changes do not by themselves trigger this review. GitHub schedules may
be delayed or dropped, and schedules in
public repositories can be disabled after
60 days of inactivity; use manual dispatch or re-enable the workflow if needed.
For a deliberate rollback, first set the repository Actions variable
`AUDIO_PUBLISH_PAUSED` to `true` and suspend `kustomization/audio`, then perform
an independently reviewed Git rollback and safe admission/drain procedure.
Resume only when ready: a running publisher will otherwise re-advance the pin.
The config workflow's own `GITHUB_TOKEN` writes only this repository; no
cross-repository Git credential is needed. A token-generated push does not
start another workflow, so the publisher validates its own pin update.

## Audio credentials

The audio server obtains `MODAL_TOKEN_ID` and `MODAL_TOKEN_SECRET` from
`default/audio-modal-token`, and `OPENROUTER_API_KEY` from
`default/audio-openrouter`. Invite-only access additionally requires independent
`AUTH_OTP_SECRET` and `AUTH_INVITE_SECRET` values from `default/audio-auth`.
The existing SOPS-encrypted `secrets.yaml` is the source of truth; retain the
installed keys across upgrades so existing accounts and sessions continue to work.

Five encrypted top-level keys must exist: `modal-token-id`,
`modal-token-secret`, `openrouter-api-key`, `audio-auth-otp-secret`, and
`audio-auth-invite-secret`. The two auth secrets must be distinct stable
CSPRNG values of at least 32 bytes (for example, 64 hexadecimal characters).
An authorized root operator can edit them privately using
`sudo env SOPS_AGE_KEY_FILE=/etc/age/keys.txt sops /home/ehpc/ehpc.io-configs/secrets.yaml`.
Never print credentials, commit plaintext or dummy values, or use developer
credentials. Retain stable existing keys and back them up securely.

The apply service refuses missing/unreadable templates, short or equal
auth keys, and unavailable `audio-mail` group before applying audio resources.
The apply service requires and starts after `audio-mail.socket`, so a failed
mail socket prevents the auth workload from being applied. Upon activation the
RKE2 kubeconfig is configured as `0640` rather than world-readable; `ehpc`
retains operator access through its membership in the `kube` group.
The apply service resolves the host's actual group ID into the Nix-owned
`flux-system/audio-runtime` ConfigMap; Flux substitutes it as an integer in
supplemental groups without changing fsGroup. The pod mounts `/run/audio-mail` as a read-only
directory, not a socket inode. The gateway-only ingress NetworkPolicy must be
enforced before trusting the observed gateway node subnet `10.42.0.0/24`.
The 2026-11-09 cutover checked gateway access, nonmatching-pod denial and a
new-pod socket connection. Recheck subnet, labels, permissions, additive
policies, gateway traffic, kubelet probes and socket connectivity for each
cutover. EndpointSlice readiness alone does not prove NGINX has reconciled:
verify the served closed state before draining, and the expected upstream and
served ready state before public checks. Activation requires a verified image
and root access.

On 2026-11-10, release `4480431` was activated, but its helper stopped after
the temporary policy probe's deletion was not observed within its cleanup
window. The probe was later absent; ingress was rechecked and the owned Service
barrier was removed with UID/resource-version guards before public checks.
For future boundary checks, prefer a bounded one-shot probe, normal deletion
with a UID precondition, and observed deletion; retain both the probe and
cleanup errors. Do not rerun a completed switch or restore an old database
over accepted work to recover a paused admission barrier.

The checked-in audio Deployment requests `128Mi`/`100m` and limits `1Gi`/`1`
CPU. Preserve the route-scoped `64m` client-settings policy when changing it.

## Outbound authentication mail

The NixOS mail configuration in `nixos/mail.nix` is active. On 2026-11-09,
Postfix, OpenDKIM, and `audio-mail.socket` were observed active. Invite-only
access and the application adapter were deployed with release `4480431`; its
public guest API returned 401 after activation. The desired image pin and Flux
configuration above do not by themselves establish a later deployment.

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

Before any future system change, record the current generation. List available
generations with `sudo nix-env --profile /nix/var/nix/profiles/system
--list-generations`; the pre-mail generation 242 is historical, not a universal
rollback target. Before selecting one, suspend the publisher and Flux, safely
drain, and independently review its application ownership and the recovery plan
as described above. Never automatically restore an old database over newer work.

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
