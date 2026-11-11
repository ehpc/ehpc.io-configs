#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CLUSTER_NAME=audio-gitops
readonly EXPECTED_CONTEXT="kind-${CLUSTER_NAME}"
readonly AUDIO_RECONCILER=system:serviceaccount:flux-system:audio-reconciler
readonly GIT_URL=http://git-http.git-fixture.svc.cluster.local:8080/audio.git
readonly GIT_IMAGE=docker.io/library/node@sha256:63538dfe497cc29dfafdda25ada09b46db68a3f4cc205abf1f5d6bf0913f3384
readonly IMAGE_A=registry.k8s.io/pause@sha256:ee6521f290b2168b6e0935a181d4cff9be1ac3f505666ef0e3c98fae8199917a
readonly IMAGE_B=registry.k8s.io/pause@sha256:7031c1b283388d2c2e09b57badb803c05ebed362dc88d84b480cc47f72a21097
readonly TEST_GID=2147483647
readonly TEST_RELEASE_SHA=2222222222222222222222222222222222222222
readonly SMOKE_DEADLINE=$((SECONDS + 17 * 60))

fail() {
  printf 'flux integration: %s\n' "$*" >&2
  exit 1
}

remaining_timeout() {
  local requested="$1" remaining=$((SMOKE_DEADLINE - SECONDS))
  ((remaining > 0)) || fail 'smoke exceeded its 17-minute execution budget'
  ((requested < remaining)) && remaining="$requested"
  printf '%s' "$remaining"
}

bounded_deadline() {
  local deadline="$1"
  ((deadline > SMOKE_DEADLINE)) && deadline="$SMOKE_DEADLINE"
  printf '%s' "$deadline"
}

run_bounded() {
  local seconds="$1"
  shift
  seconds="$(remaining_timeout "$seconds")"
  timeout "${seconds}s" "$@"
}

for command in kubectl kind git python3 curl grep timeout; do
  command -v "$command" >/dev/null || fail "required command not found: $command"
done
[[ -n "${KUBECONFIG:-}" && -r "$KUBECONFIG" ]] || fail 'CI must provide a readable, explicit KUBECONFIG'
[[ "$(kubectl config current-context)" == "$EXPECTED_CONTEXT" ]] || fail "refusing non-test context (expected $EXPECTED_CONTEXT)"
api_server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
[[ "$api_server" =~ ^https://(127\.0\.0\.1|localhost):[0-9]+$ ]] || fail 'refusing a non-loopback Kubernetes API server'
kind get clusters | grep -Fqx "$CLUSTER_NAME" || fail "Kind cluster $CLUSTER_NAME is not present"
server_version="$(kubectl version -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["serverVersion"]["gitVersion"])')"
[[ "$server_version" == v1.34.* ]] || fail "expected a Kubernetes 1.34 server, got $server_version"

python3 -c 'import yaml' || fail 'PyYAML is required by the CI job'


WORK="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/audio-flux-integration.XXXXXX")"
chmod 700 "$WORK"
PORT_FORWARD_PID=''
cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n "$PORT_FORWARD_PID" ]]; then
    kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
    wait "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
  fi
  kubectl delete namespace git-fixture --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
  rm -rf -- "$WORK"
  exit "$status"
}
trap cleanup EXIT

REPO="$WORK/source"
mkdir -p "$REPO/gitops/audio"
python3 - "$ROOT/gitops/audio/deployment.yaml" "$REPO/gitops/audio/deployment.yaml" "$IMAGE_A" "$TEST_GID" "$TEST_RELEASE_SHA" <<'PY'
import copy
import sys
from pathlib import Path

import yaml
source, destination, image, gid, release_sha = sys.argv[1:]
deployment = yaml.safe_load(Path(source).read_text())
deployment["metadata"].pop("annotations", None)
deployment["metadata"]["annotations"] = {"audio.ehpc.io/release-sha": release_sha}
pod = deployment["spec"]["template"]["spec"]
pod.pop("volumes", None)
pod["securityContext"]["supplementalGroups"] = ["${AUDIO_MAIL_GID}"]
pod["terminationGracePeriodSeconds"] = 5
container = pod["containers"][0]
for key in ("env", "ports", "volumeMounts", "livenessProbe", "readinessProbe", "startupProbe", "lifecycle", "command", "args"):
    container.pop(key, None)
container["image"] = image
container["imagePullPolicy"] = "IfNotPresent"
Path(destination).write_text(yaml.safe_dump(deployment, sort_keys=False))
precreated = copy.deepcopy(deployment)
precreated["spec"]["replicas"] = 0
precreated["spec"]["template"]["spec"]["securityContext"]["supplementalGroups"] = [int(gid)]
Path(destination + ".precreated").write_text(yaml.safe_dump(precreated, sort_keys=False))
PY
cat >"$REPO/gitops/audio/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
YAML
git -C "$REPO" init --initial-branch=main >/dev/null
git -C "$REPO" -c user.name='Flux integration fixture' -c user.email='flux-fixture@localhost' add gitops/audio/deployment.yaml gitops/audio/kustomization.yaml
git -C "$REPO" -c user.name='Flux integration fixture' -c user.email='flux-fixture@localhost' commit -m 'Initial local Flux fixture' >/dev/null
INITIAL_COMMIT="$(git -C "$REPO" rev-parse HEAD)"

commit_fixture_image() {
  local image="$1" message="$2" commit
  python3 - "$REPO/gitops/audio/deployment.yaml" "$image" <<'PY'
import sys
from pathlib import Path
import yaml
path, image = sys.argv[1:]
obj = yaml.safe_load(Path(path).read_text())
obj["spec"]["template"]["spec"]["containers"][0]["image"] = image
Path(path).write_text(yaml.safe_dump(obj, sort_keys=False))
PY
  git -C "$REPO" add gitops/audio/deployment.yaml
  git -C "$REPO" -c user.name='Flux integration fixture' -c user.email='flux-fixture@localhost' commit -m "$message" >/dev/null
  commit="$(git -C "$REPO" rev-parse HEAD)"
  run_bounded 60 git -C "$REPO" push http://127.0.0.1:38080/audio.git main >/dev/null
  printf '%s' "$commit"
}

commit_fixture_probe_state() {
  local state="$1" message="$2" commit
  python3 - "$REPO/gitops/audio/deployment.yaml" "$state" <<'PY'
import sys
from pathlib import Path
import yaml
path, state = sys.argv[1:]
obj = yaml.safe_load(Path(path).read_text())
container = obj["spec"]["template"]["spec"]["containers"][0]
if state == "unhealthy":
    obj["spec"]["progressDeadlineSeconds"] = 10
    container["readinessProbe"] = {
        "tcpSocket": {"port": 1},
        "periodSeconds": 2,
        "timeoutSeconds": 1,
        "failureThreshold": 1,
    }
elif state == "healthy":
    obj["spec"].pop("progressDeadlineSeconds", None)
    container.pop("readinessProbe", None)
else:
    raise SystemExit(f"unknown fixture probe state: {state}")
Path(path).write_text(yaml.safe_dump(obj, sort_keys=False))
PY
  git -C "$REPO" add gitops/audio/deployment.yaml
  git -C "$REPO" -c user.name='Flux integration fixture' -c user.email='flux-fixture@localhost' commit -m "$message" >/dev/null
  commit="$(git -C "$REPO" rev-parse HEAD)"
  run_bounded 60 git -C "$REPO" push http://127.0.0.1:38080/audio.git main >/dev/null
  printf '%s' "$commit"
}

commit_fixture_path() {
  local mode="$1" message="$2" commit
  case "$mode" in
    empty)
      cat >"$REPO/gitops/audio/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
YAML
      ;;
    audio)
      cat >"$REPO/gitops/audio/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
YAML
      ;;
    *) fail "unknown fixture path mode: $mode" ;;
  esac
  git -C "$REPO" add gitops/audio/kustomization.yaml
  git -C "$REPO" -c user.name='Flux integration fixture' -c user.email='flux-fixture@localhost' commit -m "$message" >/dev/null
  commit="$(git -C "$REPO" rev-parse HEAD)"
  run_bounded 60 git -C "$REPO" push http://127.0.0.1:38080/audio.git main >/dev/null
  printf '%s' "$commit"
}

kubectl create namespace git-fixture
kubectl -n git-fixture create configmap git-http-backend \
  --from-file=server.js="$ROOT/tests/flux-git-http-backend.js" \
  --dry-run=client -o yaml | kubectl apply -f -
cat <<YAML | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: git-http
  namespace: git-fixture
spec:
  replicas: 1
  selector:
    matchLabels:
      app: git-http
  template:
    metadata:
      labels:
        app: git-http
    spec:
      automountServiceAccountToken: false
      securityContext:
        fsGroup: 1000
        runAsGroup: 1000
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
      initContainers:
        - name: initialize-bare-repository
          image: $GIT_IMAGE
          imagePullPolicy: IfNotPresent
          command: [sh, -ec, "git init --bare /repos/audio.git && git --git-dir=/repos/audio.git config http.receivepack true"]
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
          volumeMounts:
            - name: repos
              mountPath: /repos
      containers:
        - name: git-http
          image: $GIT_IMAGE
          imagePullPolicy: IfNotPresent
          command: [node, /fixture/server.js]
          ports:
            - name: http
              containerPort: 8080
          readinessProbe:
            httpGet:
              path: /healthz
              port: http
            periodSeconds: 2
            timeoutSeconds: 1
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 256Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
            readOnlyRootFilesystem: true
            runAsGroup: 1000
            runAsNonRoot: true
            runAsUser: 1000
            seccompProfile:
              type: RuntimeDefault
          volumeMounts:
            - name: fixture-script
              mountPath: /fixture
              readOnly: true
            - name: repos
              mountPath: /repos
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: fixture-script
          configMap:
            name: git-http-backend
        - name: repos
          emptyDir: {}
        - name: tmp
          emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: git-http
  namespace: git-fixture
spec:
  selector:
    app: git-http
  ports:
    - name: http
      port: 8080
      targetPort: http
YAML
run_bounded 240 kubectl -n git-fixture rollout status deployment/git-http --timeout=240s
run_bounded 180 kubectl apply --server-side --field-manager=audio-flux-components -f "$ROOT/nixos/flux-components.yaml"
run_bounded 120 kubectl wait --for=condition=Established crd/gitrepositories.source.toolkit.fluxcd.io --timeout=120s
run_bounded 120 kubectl wait --for=condition=Established crd/kustomizations.kustomize.toolkit.fluxcd.io --timeout=120s
run_bounded 180 kubectl -n flux-system rollout status deployment/source-controller --timeout=180s
run_bounded 180 kubectl -n flux-system rollout status deployment/kustomize-controller --timeout=180s

kubectl -n git-fixture port-forward service/git-http 38080:8080 >"$WORK/port-forward.log" 2>&1 &
PORT_FORWARD_PID=$!
for _ in $(seq 1 30); do
  if curl -fsS --max-time 1 http://127.0.0.1:38080/healthz >/dev/null; then break; fi
  kill -0 "$PORT_FORWARD_PID" 2>/dev/null || { cat "$WORK/port-forward.log" >&2; fail 'Git fixture port-forward exited'; }
  sleep 1
done
curl -fsS --max-time 2 http://127.0.0.1:38080/healthz >/dev/null || fail 'Git fixture HTTP endpoint did not become ready'
git -C "$REPO" push http://127.0.0.1:38080/audio.git main >/dev/null

python3 - "$ROOT/nixos/audio-flux-bootstrap.yaml" "$WORK/bootstrap-local.yaml" "$GIT_URL" <<'PY'
import sys
from pathlib import Path
import yaml
source, destination, url = sys.argv[1:]
objects = list(yaml.safe_load_all(Path(source).read_text()))
for obj in objects:
    if obj and obj.get("kind") == "GitRepository":
        obj["spec"]["url"] = url
Path(destination).write_text(yaml.safe_dump_all(objects, sort_keys=False))
PY

cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: audio-auth
  namespace: default
stringData:
  fixture-only: harmless-test-value
---
apiVersion: v1
kind: Secret
metadata:
  name: audio-modal-token
  namespace: default
stringData:
  fixture-only: harmless-test-value
---
apiVersion: v1
kind: Secret
metadata:
  name: audio-openrouter
  namespace: default
stringData:
  fixture-only: harmless-test-value
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: audio-data
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ""
  resources:
    requests:
      storage: 1Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: unrelated
  namespace: default
spec:
  replicas: 0
  selector:
    matchLabels:
      app: flux-integration-unrelated
  template:
    metadata:
      labels:
        app: flux-integration-unrelated
    spec:
      containers:
        - name: unrelated
          image: $IMAGE_A
          imagePullPolicy: IfNotPresent
YAML
python3 - "$REPO/gitops/audio/deployment.yaml.precreated" "$WORK/invalid-gid.yaml" <<'PY'
import sys
from pathlib import Path
import yaml
obj = yaml.safe_load(Path(sys.argv[1]).read_text())
obj["metadata"]["name"] = "invalid-gid-boundary"
obj["spec"]["template"]["spec"]["securityContext"]["supplementalGroups"] = [2147483648]
Path(sys.argv[2]).write_text(yaml.safe_dump(obj, sort_keys=False))
PY
if kubectl create --dry-run=server -f "$WORK/invalid-gid.yaml" >"$WORK/invalid-gid.log" 2>&1; then
  fail 'Kubernetes accepted an out-of-range supplemental GID'
fi
grep -q 'supplementalGroups' "$WORK/invalid-gid.log" || { cat "$WORK/invalid-gid.log" >&2; fail 'GID boundary request failed for an unrelated reason'; }
kubectl create --dry-run=server -f "$REPO/gitops/audio/deployment.yaml.precreated" -o json >"$WORK/audio-deployment-dryrun.json"
python3 - "$WORK/audio-deployment-dryrun.json" <<'PY'
import json
import sys
obj = json.load(open(sys.argv[1], encoding="utf-8"))
status = obj.get("status")
assert isinstance(status, dict), obj
for field in ("observedGeneration", "replicas", "readyReplicas", "updatedReplicas", "availableReplicas", "unavailableReplicas"):
    assert field not in status, status
PY
if kubectl -n default get deployment audio >/dev/null 2>&1; then fail 'server-side dry-run persisted the audio Deployment'; fi
kubectl apply -f "$REPO/gitops/audio/deployment.yaml.precreated"

readonly SECRET_UID="$(kubectl -n default get secret audio-auth -o jsonpath='{.metadata.uid}')"
readonly PVC_UID="$(kubectl -n default get pvc audio-data -o jsonpath='{.metadata.uid}')"
readonly UNRELATED_UID="$(kubectl -n default get deployment unrelated -o jsonpath='{.metadata.uid}')"
readonly UNRELATED_IMAGE="$(kubectl -n default get deployment unrelated -o jsonpath='{.spec.template.spec.containers[0].image}')"
readonly UNRELATED_REPLICAS="$(kubectl -n default get deployment unrelated -o jsonpath='{.spec.replicas}')"
readonly INITIAL_AUDIO_UID="$(kubectl -n default get deployment audio -o jsonpath='{.metadata.uid}')"

kubectl apply -f "$WORK/bootstrap-local.yaml"
kubectl -n flux-system create configmap audio-runtime --from-literal="AUDIO_MAIL_GID=$TEST_GID" \
  --dry-run=client -o yaml | kubectl apply --server-side --field-manager=audio-runtime -f -
run_bounded 180 kubectl -n flux-system wait --for=condition=Ready gitrepository/audio-config --timeout=180s

cat >"$WORK/freeze.yaml" <<YAML
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: audio-config
  namespace: flux-system
spec:
  ref:
    commit: $INITIAL_COMMIT
YAML
kubectl apply --server-side --field-manager=audio-operator-freeze -f "$WORK/freeze.yaml"
kubectl apply -f "$WORK/bootstrap-local.yaml"
[[ "$(kubectl -n flux-system get gitrepository audio-config -o jsonpath='{.spec.ref.commit}')" == "$INITIAL_COMMIT" ]] || fail 'Nix client-side reapply removed the operator Git commit freeze'

request_gitrepository_reconcile() {
  local token
  token="$(date -u +%s%N)"
  kubectl -n flux-system annotate gitrepository audio-config \
    reconcile.fluxcd.io/requestedAt="$token" --overwrite >/dev/null
  printf '%s' "$token"
}
request_kustomization_reconcile() {
  local token
  token="$(date -u +%s%N)"
  kubectl -n flux-system annotate kustomization audio \
    reconcile.fluxcd.io/requestedAt="$token" --overwrite >/dev/null
  printf '%s' "$token"
}
wait_for_gitrepository_revision() {
  local expected="$1" deadline revision ready observed generation handled token
  token="$(request_gitrepository_reconcile)"
  generation="$(kubectl -n flux-system get gitrepository audio-config -o jsonpath='{.metadata.generation}')"
  deadline="$(bounded_deadline "$((SECONDS + 180))")"
  while (( SECONDS < deadline )); do
    revision="$(kubectl -n flux-system get gitrepository audio-config -o jsonpath='{.status.artifact.revision}' 2>/dev/null || true)"
    ready="$(kubectl -n flux-system get gitrepository audio-config -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    observed="$(kubectl -n flux-system get gitrepository audio-config -o jsonpath='{.status.observedGeneration}' 2>/dev/null || true)"
    handled="$(kubectl -n flux-system get gitrepository audio-config -o jsonpath='{.status.lastHandledReconcileAt}' 2>/dev/null || true)"
    if [[ "$ready" == True && "$observed" == "$generation" && "$handled" == "$token" && "$revision" == *"$expected"* ]]; then return 0; fi
    sleep 2
  done
  kubectl -n flux-system get gitrepository audio-config -o yaml >&2
  fail "GitRepository did not publish expected commit $expected for generation $generation and request $token"
}
wait_for_kustomization_revision() {
  local expected="$1" deadline revision ready observed generation handled token
  token="$(request_kustomization_reconcile)"
  generation="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.metadata.generation}')"
  deadline="$(bounded_deadline "$((SECONDS + 180))")"
  while (( SECONDS < deadline )); do
    revision="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.lastAppliedRevision}' 2>/dev/null || true)"
    ready="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    observed="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.observedGeneration}' 2>/dev/null || true)"
    handled="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.lastHandledReconcileAt}' 2>/dev/null || true)"
    if [[ "$ready" == True && "$observed" == "$generation" && "$handled" == "$token" && "$revision" == *"$expected"* ]]; then return 0; fi
    sleep 2
  done
  kubectl -n flux-system get kustomization audio -o yaml >&2
  kubectl -n default get pods -l app=audio -o wide >&2 || true
  kubectl -n default describe deployment audio >&2 || true
  kubectl -n default describe pods -l app=audio >&2 || true
  kubectl -n flux-system logs deployment/kustomize-controller --tail=100 >&2 || true
  fail "Kustomization did not handle request $token for generation $generation at Git revision $expected"
}
wait_for_strict_substitution_failure() {
  local deadline ready message observed generation handled token
  token="$(request_kustomization_reconcile)"
  generation="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.metadata.generation}')"
  deadline="$(bounded_deadline "$((SECONDS + 180))")"
  while (( SECONDS < deadline )); do
    ready="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    message="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || true)"
    observed="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.observedGeneration}' 2>/dev/null || true)"
    handled="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.lastHandledReconcileAt}' 2>/dev/null || true)"
    if [[ "$ready" == False && "$observed" == "$generation" && "$handled" == "$token" && "$message" == *AUDIO_MAIL_GID* ]]; then return 0; fi
    sleep 2
  done
  kubectl -n flux-system get kustomization audio -o yaml >&2
  fail "missing AUDIO_MAIL_GID did not produce a current failure for request $token"
}
wait_for_kustomization_create_denial() {
  local deadline ready message observed generation handled lower_message token
  token="$(request_kustomization_reconcile)"
  generation="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.metadata.generation}')"
  deadline="$(bounded_deadline "$((SECONDS + 180))")"
  while (( SECONDS < deadline )); do
    ready="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    message="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null || true)"
    observed="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.observedGeneration}' 2>/dev/null || true)"
    handled="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.lastHandledReconcileAt}' 2>/dev/null || true)"
    lower_message="${message,,}"
    if [[ "$ready" == False && "$observed" == "$generation" && "$handled" == "$token" && "$lower_message" == *forbidden* ]]; then return 0; fi
    if [[ "$ready" == True ]] && kubectl -n default get deployment audio >/dev/null 2>&1; then fail 'Flux recreated audio despite the reconciler ServiceAccount lacking create'; fi
    sleep 2
  done
  kubectl -n flux-system get kustomization audio -o yaml >&2
  fail "removing the audio Deployment did not produce a current Forbidden result for request $token"
}

wait_for_kustomization_health_failure() {
  local expected="$1" token generation deadline attempted ready observed handled
  token="$(request_kustomization_reconcile)"
  generation="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.metadata.generation}')"
  deadline="$(bounded_deadline "$((SECONDS + 120))")"
  while (( SECONDS < deadline )); do
    attempted="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.lastAttemptedRevision}' 2>/dev/null || true)"
    ready="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    observed="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.observedGeneration}' 2>/dev/null || true)"
    handled="$(kubectl -n flux-system get kustomization audio -o jsonpath='{.status.lastHandledReconcileAt}' 2>/dev/null || true)"
    if [[ "$observed" == "$generation" && "$handled" == "$token" && "$attempted" == *"$expected"* && "$ready" == True ]]; then
      fail "Kustomization reported Ready for unhealthy Git revision $expected"
    fi
    if [[ "$observed" == "$generation" && "$handled" == "$token" && "$attempted" == *"$expected"* && "$ready" == False ]]; then return 0; fi
    sleep 1
  done
  kubectl -n flux-system get kustomization audio -o yaml >&2
  kubectl -n default get deployment audio -o yaml >&2 || true
  fail "Kustomization did not report a current health failure for Git revision $expected"
}
assert_audio_image() {
  local expected="$1" actual release_sha
  actual="$(kubectl -n default get deployment audio -o jsonpath='{.spec.template.spec.containers[0].image}')"
  [[ "$actual" == "$expected" ]] || fail "expected audio image $expected, found $actual"
  release_sha="$(kubectl -n default get deployment audio -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["metadata"]["annotations"]["audio.ehpc.io/release-sha"])')"
  [[ "$release_sha" == "$TEST_RELEASE_SHA" ]] || fail "expected decimal release SHA string $TEST_RELEASE_SHA, found $release_sha"
}
assert_audio_gid() {
  python3 - "$TEST_GID" <<'PY'
import json
import subprocess
import sys
obj = json.loads(subprocess.check_output([
    "kubectl", "-n", "default", "get", "deployment", "audio", "-o", "json"
], text=True))
groups = obj["spec"]["template"]["spec"]["securityContext"]["supplementalGroups"]
expected = int(sys.argv[1])
assert len(groups) == 1 and type(groups[0]) is int and groups[0] == expected, groups
PY
}

assert_audio_progress_deadline_exceeded() {
  python3 - <<'PY'
import json
import subprocess
obj = json.loads(subprocess.check_output([
    "kubectl", "-n", "default", "get", "deployment", "audio", "-o", "json"
], text=True))
spec = obj["spec"]
assert spec["progressDeadlineSeconds"] == 10, spec
assert spec["template"]["spec"]["containers"][0]["readinessProbe"]["tcpSocket"]["port"] == 1, spec
status = obj.get("status", {})
assert status.get("observedGeneration") == obj["metadata"]["generation"], status
conditions = status.get("conditions", [])
assert any(
    condition.get("type") == "Progressing"
    and condition.get("status") == "False"
    and condition.get("reason") == "ProgressDeadlineExceeded"
    for condition in conditions
), conditions
PY
}

assert_audio_generation_advanced_and_observed() {
  python3 - "$1" <<'PY'
import json
import subprocess
import sys
obj = json.loads(subprocess.check_output([
    "kubectl", "-n", "default", "get", "deployment", "audio", "-o", "json"
], text=True))
previous = int(sys.argv[1])
generation = obj["metadata"]["generation"]
status = obj.get("status", {})
assert generation > previous, (previous, generation)
assert status.get("observedGeneration") == generation, status
assert status.get("readyReplicas", 0) >= 1, status
PY
}
assert_subject_can_i() {
  local expected="$1" subject="$2" verb="$3" resource="$4" namespace="${5:-}" actual
  local -a args=("$verb" "$resource" "--as=$subject")
  [[ -z "$namespace" ]] || args+=(-n "$namespace")
  actual="$(kubectl auth can-i "${args[@]}" 2>"$WORK/can-i.stderr" || true)"
  [[ ! -s "$WORK/can-i.stderr" ]] || cat "$WORK/can-i.stderr" >&2
  [[ "$actual" == "$expected" ]] || fail "$subject can-i $verb $resource expected '$expected', got '$actual'"
}
assert_can_i() {
  assert_subject_can_i "$1" "$AUDIO_RECONCILER" "$2" "$3" "${4:-}"
}
assert_protected_resources_unchanged() {
  [[ "$(kubectl -n default get secret audio-auth -o jsonpath='{.metadata.uid}')" == "$SECRET_UID" ]] || fail 'protected audio-auth Secret changed or disappeared'
  [[ "$(kubectl -n default get pvc audio-data -o jsonpath='{.metadata.uid}')" == "$PVC_UID" ]] || fail 'protected audio-data PVC changed or disappeared'
  [[ "$(kubectl -n default get deployment unrelated -o jsonpath='{.metadata.uid}')" == "$UNRELATED_UID" ]] || fail 'unrelated Deployment changed or disappeared'
  [[ "$(kubectl -n default get deployment unrelated -o jsonpath='{.spec.template.spec.containers[0].image}')" == "$UNRELATED_IMAGE" ]] || fail 'unrelated Deployment image changed'
  [[ "$(kubectl -n default get deployment unrelated -o jsonpath='{.spec.replicas}')" == "$UNRELATED_REPLICAS" ]] || fail 'unrelated Deployment replica count changed'
}
assert_flux_inventory_is_scoped() {
  python3 - <<'PY'
import json
import subprocess
obj = json.loads(subprocess.check_output([
    "kubectl", "-n", "flux-system", "get", "kustomization", "audio", "-o", "json"
], text=True))
entries = obj.get("status", {}).get("inventory", {}).get("entries", [])
ids = {entry["id"] for entry in entries}
assert ids == {"default_audio_apps_Deployment"}, ids
PY
}

wait_for_gitrepository_revision "$INITIAL_COMMIT"
TRANSITION_COMMIT="$(commit_fixture_image "$IMAGE_B" 'Advance branch while Flux is commit-pinned')"
wait_for_gitrepository_revision "$INITIAL_COMMIT"
[[ "$(kubectl -n flux-system get gitrepository audio-config -o jsonpath='{.status.artifact.revision}')" == *"$INITIAL_COMMIT"* ]] || fail 'commit-pinned GitRepository artifact advanced with the branch'
assert_audio_image "$IMAGE_A"

python3 - "$ROOT/nixos/audio-flux-kustomization.yaml" "$WORK/kustomization-suspended.yaml" <<'PY'
import sys
from pathlib import Path
import yaml
source, destination = sys.argv[1:]
obj = yaml.safe_load(Path(source).read_text())
obj["spec"]["suspend"] = True
Path(destination).write_text(yaml.safe_dump(obj, sort_keys=False))
PY
kubectl apply --server-side --field-manager=audio-nix -f "$WORK/kustomization-suspended.yaml"
cat >"$WORK/suspend-only.yaml" <<'YAML'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: audio
  namespace: flux-system
spec:
  suspend: true
YAML
kubectl apply --server-side --field-manager=audio-bootstrap -f "$WORK/suspend-only.yaml"
kubectl apply --server-side --field-manager=audio-nix -f "$ROOT/nixos/audio-flux-kustomization.yaml"
[[ "$(kubectl -n flux-system get kustomization audio -o jsonpath='{.spec.suspend}')" == true ]] || fail 'first-boot Kustomization was not suspended'

assert_can_i yes get deployments.apps/audio default
assert_can_i yes patch deployments.apps/audio default
assert_can_i yes update deployments.apps/audio default
assert_can_i no create deployments.apps/audio default
assert_can_i no delete deployments.apps/audio default
assert_can_i no patch deployments.apps/unrelated default
assert_can_i no get secrets/audio-auth default
assert_can_i no get persistentvolumeclaims/audio-data default
assert_can_i no get deployments.apps/audio kube-system
assert_can_i no create namespaces
assert_subject_can_i no system:serviceaccount:flux-system:source-controller get nodes
assert_subject_can_i no system:serviceaccount:flux-system:source-controller get secrets/audio-auth default
assert_subject_can_i no system:serviceaccount:flux-system:source-controller create namespaces
assert_subject_can_i no system:serviceaccount:flux-system:kustomize-controller get nodes
assert_subject_can_i no system:serviceaccount:flux-system:kustomize-controller get secrets/audio-auth default
assert_subject_can_i no system:serviceaccount:flux-system:kustomize-controller create namespaces

cat >"$WORK/resume.yaml" <<'YAML'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: audio
  namespace: flux-system
spec:
  suspend: false
YAML
kubectl apply --server-side --force-conflicts --field-manager=audio-operator-resume -f "$WORK/resume.yaml"
kubectl apply --server-side --field-manager=audio-nix -f "$ROOT/nixos/audio-flux-kustomization.yaml"
[[ "$(kubectl -n flux-system get kustomization audio -o jsonpath='{.spec.suspend}')" == false ]] || fail 'Nix SSA reapply re-suspended the operator-resumed Kustomization'
python3 - "$ROOT/nixos/audio-flux-kustomization.yaml" "$WORK/kustomization-interval-change.yaml" <<'PY'
import sys
from pathlib import Path
import yaml
source, destination = sys.argv[1:]
obj = yaml.safe_load(Path(source).read_text())
obj["spec"]["interval"] = "2m"
Path(destination).write_text(yaml.safe_dump(obj, sort_keys=False))
PY
kubectl apply --server-side --field-manager=audio-nix -f "$WORK/kustomization-interval-change.yaml"
[[ "$(kubectl -n flux-system get kustomization audio -o jsonpath='{.spec.interval}')" == 2m ]] || fail 'Nix could not update its own Kustomization interval field'
[[ "$(kubectl -n flux-system get kustomization audio -o jsonpath='{.spec.suspend}')" == false ]] || fail 'non-suspend Nix update re-suspended the Kustomization'
kubectl apply --server-side --field-manager=audio-nix -f "$ROOT/nixos/audio-flux-kustomization.yaml"
[[ "$(kubectl -n flux-system get kustomization audio -o jsonpath='{.spec.suspend}')" == false ]] || fail 'canonical Nix Kustomization reapply re-suspended the operator gate'
wait_for_kustomization_revision "$INITIAL_COMMIT"
run_bounded 180 kubectl -n default rollout status deployment/audio --timeout=180s
[[ "$(kubectl -n default get deployment audio -o jsonpath='{.spec.replicas}')" == 1 ]] || fail 'Flux did not adopt the pre-created audio Deployment'
assert_audio_image "$IMAGE_A"
assert_audio_gid
[[ "$(kubectl -n default get deployment audio -o jsonpath='{.metadata.uid}')" == "$INITIAL_AUDIO_UID" ]] || fail 'Flux replaced instead of adopting the pre-created Deployment'
assert_flux_inventory_is_scoped
run_bounded 60 kubectl -n default delete deployment audio --wait=true --timeout=60s
wait_for_kustomization_create_denial
if kubectl -n default get deployment audio >/dev/null 2>&1; then fail 'Flux created audio despite the reconciler ServiceAccount lacking create'; fi
kubectl apply -f "$REPO/gitops/audio/deployment.yaml.precreated"
RECOVERED_AUDIO_UID="$(kubectl -n default get deployment audio -o jsonpath='{.metadata.uid}')"
[[ "$RECOVERED_AUDIO_UID" != "$INITIAL_AUDIO_UID" ]] || fail 'operator restore did not create a new audio Deployment UID'
wait_for_kustomization_revision "$INITIAL_COMMIT"
run_bounded 120 kubectl -n default rollout status deployment/audio --timeout=120s
[[ "$(kubectl -n default get deployment audio -o jsonpath='{.spec.replicas}')" == 1 ]] || fail 'Flux did not restore the operator-created Deployment'
[[ "$(kubectl -n default get deployment audio -o jsonpath='{.metadata.uid}')" == "$RECOVERED_AUDIO_UID" ]] || fail 'Flux replaced the operator-restored Deployment'
assert_audio_image "$IMAGE_A"
assert_audio_gid
assert_flux_inventory_is_scoped

cat >"$WORK/unfreeze.yaml" <<'YAML'
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: audio-config
  namespace: flux-system
spec:
  ref:
    branch: main
YAML
kubectl apply --server-side --field-manager=audio-operator-freeze -f "$WORK/unfreeze.yaml"
[[ -z "$(kubectl -n flux-system get gitrepository audio-config -o jsonpath='{.spec.ref.commit}')" ]] || fail 'operator unfreeze left the Git commit pin in place'
wait_for_gitrepository_revision "$TRANSITION_COMMIT"
wait_for_kustomization_revision "$TRANSITION_COMMIT"
run_bounded 120 kubectl -n default rollout status deployment/audio --timeout=120s
assert_audio_image "$IMAGE_B"
assert_audio_gid
[[ "$(kubectl -n default get deployment audio -o jsonpath='{.metadata.uid}')" == "$RECOVERED_AUDIO_UID" ]] || fail 'image transition replaced the audio Deployment'

ROLLBACK_COMMIT="$(commit_fixture_image "$IMAGE_A" 'Rollback to first pinned test image')"
wait_for_gitrepository_revision "$ROLLBACK_COMMIT"
wait_for_kustomization_revision "$ROLLBACK_COMMIT"
run_bounded 120 kubectl -n default rollout status deployment/audio --timeout=120s
assert_audio_image "$IMAGE_A"
assert_audio_gid
[[ "$(kubectl -n default get deployment audio -o jsonpath='{.metadata.uid}')" == "$RECOVERED_AUDIO_UID" ]] || fail 'image rollback replaced the audio Deployment'

UNHEALTHY_COMMIT="$(commit_fixture_probe_state unhealthy 'Make pause Deployment readiness fail briefly')"
wait_for_gitrepository_revision "$UNHEALTHY_COMMIT"
wait_for_kustomization_health_failure "$UNHEALTHY_COMMIT"
assert_audio_progress_deadline_exceeded
UNHEALTHY_DEPLOYMENT_GENERATION="$(kubectl -n default get deployment audio -o jsonpath='{.metadata.generation}')"
[[ "$(kubectl -n default get deployment audio -o jsonpath='{.metadata.uid}')" == "$RECOVERED_AUDIO_UID" ]] || fail 'unhealthy rollout replaced the audio Deployment'
assert_audio_image "$IMAGE_A"
assert_audio_gid

HEALTHY_COMMIT="$(commit_fixture_probe_state healthy 'Restore healthy pause Deployment readiness')"
wait_for_gitrepository_revision "$HEALTHY_COMMIT"
wait_for_kustomization_revision "$HEALTHY_COMMIT"
run_bounded 120 kubectl -n default rollout status deployment/audio --timeout=120s
assert_audio_generation_advanced_and_observed "$UNHEALTHY_DEPLOYMENT_GENERATION"
[[ -z "$(kubectl -n default get deployment audio -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}')" ]] || fail 'healthy fixture retained the failing readiness probe'
[[ "$(kubectl -n default get deployment audio -o jsonpath='{.metadata.uid}')" == "$RECOVERED_AUDIO_UID" ]] || fail 'healthy recovery replaced the audio Deployment'
assert_audio_image "$IMAGE_A"
assert_audio_gid

before_uid="$(kubectl -n default get deployment audio -o jsonpath='{.metadata.uid}')"
before_generation="$(kubectl -n default get deployment audio -o jsonpath='{.metadata.generation}')"
before_image="$(kubectl -n default get deployment audio -o jsonpath='{.spec.template.spec.containers[0].image}')"
before_groups="$(kubectl -n default get deployment audio -o jsonpath='{.spec.template.spec.securityContext.supplementalGroups[0]}')"
[[ "$before_groups" == "$TEST_GID" && "$before_groups" != 0 ]] || fail 'precondition failed: applied supplemental GID is not the expected nonzero value'
cat >"$WORK/audio-runtime-empty.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: audio-runtime
  namespace: flux-system
data: {}
YAML
kubectl apply --server-side --field-manager=audio-runtime -f "$WORK/audio-runtime-empty.yaml"
[[ -z "$(kubectl -n flux-system get configmap audio-runtime -o jsonpath='{.data.AUDIO_MAIL_GID}')" ]] || fail 'AUDIO_MAIL_GID was not removed from the existing ConfigMap'
wait_for_strict_substitution_failure
[[ "$(kubectl -n default get deployment audio -o jsonpath='{.metadata.uid}')" == "$before_uid" ]] || fail 'missing GID recreated the audio Deployment'
[[ "$(kubectl -n default get deployment audio -o jsonpath='{.metadata.generation}')" == "$before_generation" ]] || fail 'missing GID changed the audio Deployment spec'
[[ "$(kubectl -n default get deployment audio -o jsonpath='{.spec.template.spec.containers[0].image}')" == "$before_image" ]] || fail 'missing GID changed the audio image'
[[ "$(kubectl -n default get deployment audio -o jsonpath='{.spec.template.spec.securityContext.supplementalGroups[0]}')" == "$before_groups" ]] || fail 'missing GID changed supplementalGroups (including to group zero)'
assert_audio_gid
assert_protected_resources_unchanged

cat >"$WORK/audio-runtime-restored.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: audio-runtime
  namespace: flux-system
data:
  AUDIO_MAIL_GID: "$TEST_GID"
YAML
kubectl apply --server-side --field-manager=audio-runtime -f "$WORK/audio-runtime-restored.yaml"
wait_for_kustomization_revision "$HEALTHY_COMMIT"
run_bounded 120 kubectl -n default rollout status deployment/audio --timeout=120s
assert_audio_image "$IMAGE_A"
assert_audio_gid
assert_protected_resources_unchanged
assert_flux_inventory_is_scoped

AUDIO_UID_BEFORE_PRUNE="$(kubectl -n default get deployment audio -o jsonpath='{.metadata.uid}')"
EMPTY_PATH_COMMIT="$(commit_fixture_path empty 'Use a valid empty Kustomize path to exercise prune=false')"
wait_for_gitrepository_revision "$EMPTY_PATH_COMMIT"
wait_for_kustomization_revision "$EMPTY_PATH_COMMIT"
[[ "$(kubectl -n default get deployment audio -o jsonpath='{.metadata.uid}')" == "$AUDIO_UID_BEFORE_PRUNE" ]] || fail 'empty Kustomize path pruned or replaced the audio Deployment'
assert_audio_image "$IMAGE_A"
assert_audio_gid
assert_protected_resources_unchanged

RESTORED_PATH_COMMIT="$(commit_fixture_path audio 'Restore the audio resource after prune=false check')"
wait_for_gitrepository_revision "$RESTORED_PATH_COMMIT"
wait_for_kustomization_revision "$RESTORED_PATH_COMMIT"
run_bounded 120 kubectl -n default rollout status deployment/audio --timeout=120s
[[ "$(kubectl -n default get deployment audio -o jsonpath='{.metadata.uid}')" == "$AUDIO_UID_BEFORE_PRUNE" ]] || fail 'restoring the fixture path replaced the audio Deployment'
assert_audio_image "$IMAGE_A"
assert_audio_gid
assert_protected_resources_unchanged
assert_flux_inventory_is_scoped
printf 'Flux integration passed: RBAC boundaries, SSA bootstrap handoff, pinned-source freeze, denied-create recovery, prune=false behavior, image transition/rollback, Deployment progress-deadline health failure/recovery, strict typed GID substitution, and protected resources.\n'
