"""Advance the audio pin only to the current main commit with a complete green CI."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.parse
import urllib.request

APP_REPOSITORY = 'ehpc/ehpc.io-audio'
APP_REPOSITORY_ID = 1319330182
WORKFLOW_ID = 335525943
DEPLOYMENT = Path('gitops/audio/deployment.yaml')
REQUIRED_JOBS = {
    'Lint & test backend',
    'Build & test frontend',
    'Compare pinned Chromium visual baselines',
    'Deploy & test isolated Modal app',
    'Promote tested Modal app to production',
    'Build & push image to GHCR',
}
SHA = re.compile(r'^[0-9a-f]{40}$')
DIGEST = re.compile(r'^sha256:[0-9a-f]{64}$')
PERSISTENCE_PATHS = {
    'backend/db.py', 'backend/auth_store.py', 'backend/cache_catalog.py', 'backend/models.py',
    'backend/config.py', 'backend/session.py', 'backend/inference.py',
    'backend/modal_client.py', 'backend/queue.py', 'backend/song_search_worker.py',
    'backend/source_cache.py', 'backend/pitch_reference.py',
    'separator/options.py', 'separator/lyrics.py', 'separator/lyrics_reference.py',
    'separator/pitch.py', 'separator/processing.py', 'separator/inference_transport.py',
}
PERSISTENCE_PREFIXES = ('backend/migrations/', 'separator/migrations/', 'migrations/')
SHA_LINE = re.compile(r'(?m)^(    audio\.ehpc\.io/release-sha: )"([0-9a-f]{40})"$')
DIGEST_LINE = re.compile(r'(?m)^(    audio\.ehpc\.io/release-digest: )(sha256:[0-9a-f]{64})$')
IMAGE_LINE = re.compile(r'(?m)^(          image: ghcr\.io/ehpc/ehpc\.io-audio@)(sha256:[0-9a-f]{64})$')


def trusted_run(run, candidate):
    return (
        bool(SHA.fullmatch(candidate))
        and run.get('head_sha') == candidate
        and run.get('workflow_id') == WORKFLOW_ID
        and run.get('event') == 'push'
        and run.get('head_branch') == 'main'
        and run.get('status') == 'completed'
        and run.get('conclusion') == 'success'
        and run.get('repository', {}).get('id') == APP_REPOSITORY_ID
        and run.get('head_repository', {}).get('id') == APP_REPOSITORY_ID
    )


def trusted_jobs(jobs, candidate, run_id, attempt):
    return (
        len(jobs) == len(REQUIRED_JOBS)
        and {job.get('name') for job in jobs} == REQUIRED_JOBS
        and all(job.get('status') == 'completed' and job.get('conclusion') == 'success'
                and job.get('head_sha') == candidate and job.get('run_id') == run_id
                and job.get('run_attempt') == attempt for job in jobs)
    )


def read_pin(text):
    matched = [list(pattern.finditer(text)) for pattern in (SHA_LINE, DIGEST_LINE, IMAGE_LINE)]
    if any(len(group) != 1 for group in matched):
        raise ValueError('Expected exactly one release SHA, digest and image pin')
    old_sha, old_digest, image_digest = (group[0].group(2) for group in matched)
    if old_digest != image_digest:
        raise ValueError('Existing image and release digest disagree')
    return old_sha, old_digest


def render_pin(text, candidate, digest):
    if not SHA.fullmatch(candidate) or not DIGEST.fullmatch(digest):
        raise ValueError('Invalid immutable release identity')
    old_sha, old_digest = read_pin(text)
    if old_sha == candidate:
        if old_digest != digest:
            raise ValueError('Existing SHA points at a different immutable digest')
        return old_sha, text
    changed = SHA_LINE.sub(lambda m: m.group(1) + json.dumps(candidate), text)
    changed = DIGEST_LINE.sub(lambda m: m.group(1) + digest, changed)
    changed = IMAGE_LINE.sub(lambda m: m.group(1) + digest, changed)
    return old_sha, changed


def allowed_relation(old, candidate, status):
    if old == candidate:
        return status == 'identical'
    return status == 'ahead'


def safe_comparison(comparison, previous, candidate):
    if not allowed_relation(previous, candidate, comparison.get('status')):
        raise ValueError('Refusing a non-descendant or rollback pin')
    total = comparison.get('total_commits')
    commits = comparison.get('commits')
    files = comparison.get('files')
    if (type(total) is not int or not 0 < total <= 250 or not isinstance(commits, list)
            or len(commits) != total or not commits or commits[-1].get('sha') != candidate
            or not isinstance(files, list) or len(files) >= 300
            or comparison.get('base_commit', {}).get('sha') != previous):
        raise ValueError('Comparison is missing, truncated or does not identify both commits')
    for file in files:
        if not isinstance(file, dict) or not isinstance(file.get('filename'), str):
            raise ValueError('Comparison contains an unknown file entry')
        if file.get('status') not in ('added', 'modified', 'removed', 'renamed', 'copied', 'changed', 'unchanged'):
            raise ValueError('Comparison contains an unknown file status')
        if file['status'] in ('renamed', 'copied') and not isinstance(file.get('previous_filename'), str):
            raise ValueError('Comparison omits the previous filename')
        for name in (file['filename'], file.get('previous_filename', '')):
            if name in PERSISTENCE_PATHS or name.startswith(PERSISTENCE_PREFIXES):
                raise ValueError(f'Persistence-sensitive change requires manual review and backup: {name}')
    return True


def get_json(url, *, headers=None):
    request = urllib.request.Request(url, headers={'User-Agent': 'audio-pin-publisher', **(headers or {})})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def main_sha():
    value = get_json(f'https://api.github.com/repos/{APP_REPOSITORY}/commits/main')['sha']
    if not SHA.fullmatch(value):
        raise ValueError('Invalid app main commit')
    return value


def registry_digest(candidate):
    query = urllib.parse.urlencode({'service': 'ghcr.io', 'scope': f'repository:{APP_REPOSITORY}:pull'})
    token = get_json('https://ghcr.io/token?' + query)['token']
    request = urllib.request.Request(
        f'https://ghcr.io/v2/{APP_REPOSITORY}/manifests/{candidate}',
        headers={'Authorization': 'Bearer ' + token,
                 'Accept': 'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read()
        header = response.headers.get('Docker-Content-Digest')
    digest = 'sha256:' + hashlib.sha256(body).hexdigest()
    if header != digest:
        raise ValueError('Registry manifest digest mismatch')
    return digest


def git(*args):
    return subprocess.run(['git', *args], check=True, capture_output=True, text=True, timeout=60).stdout.strip()


def main():
    paused = os.environ.get('AUDIO_PUBLISH_PAUSED', '').strip().lower()
    if paused not in ('', 'false', 'true'):
        raise ValueError('AUDIO_PUBLISH_PAUSED must be true or false')
    if paused == 'true':
        print('Audio pin publisher is paused for operator control.')
        return
    if git('status', '--porcelain', '--untracked-files=all'):
        raise ValueError('Config checkout must be clean')
    candidate = main_sha()
    text = DEPLOYMENT.read_text()
    previous, _ = read_pin(text)
    if previous == candidate:
        # No update to authorize; check immutable registry consistency without
        # consuming several GitHub API requests on every five-minute schedule.
        render_pin(text, candidate, registry_digest(candidate))
        print('Current audio pin already matches the registry release.')
        return
    url = f'https://api.github.com/repos/{APP_REPOSITORY}/actions/workflows/{WORKFLOW_ID}/runs?'
    query = urllib.parse.urlencode({'head_sha': candidate, 'branch': 'main', 'event': 'push', 'per_page': 100})
    runs = get_json(url + query)['workflow_runs']
    eligible = [r for r in runs if r.get('head_sha') == candidate and r.get('workflow_id') == WORKFLOW_ID
                and r.get('event') == 'push' and r.get('head_branch') == 'main'
                and r.get('repository', {}).get('id') == APP_REPOSITORY_ID
                and r.get('head_repository', {}).get('id') == APP_REPOSITORY_ID]
    if not eligible:
        print('Current app main has no trusted push workflow yet; no pin change.')
        return
    run = max(eligible, key=lambda item: (item['run_number'], item.get('run_attempt', 1)))
    if not trusted_run(run, candidate):
        raise ValueError('Latest current-main CI has not completed successfully')
    attempt = run.get('run_attempt')
    if type(attempt) is not int or attempt < 1:
        raise ValueError('Current CI attempt is missing or invalid')
    result = get_json(f'https://api.github.com/repos/{APP_REPOSITORY}/actions/runs/{run["id"]}/attempts/{attempt}/jobs?per_page=100')
    if result.get('total_count') != len(REQUIRED_JOBS) or not trusted_jobs(result['jobs'], candidate, run['id'], attempt):
        raise ValueError('Required release jobs are missing, skipped or failed')
    digest = registry_digest(candidate)
    previous, changed = render_pin(text, candidate, digest)
    comparison = get_json(f'https://api.github.com/repos/{APP_REPOSITORY}/compare/{previous}...{candidate}')
    safe_comparison(comparison, previous, candidate)
    if main_sha() != candidate:
        raise ValueError('App main advanced while validating; no pin change')
    if changed == text:
        print('Current audio pin already matches the validated release.')
        return
    DEPLOYMENT.write_text(changed)
    if git('diff', '--name-only') != str(DEPLOYMENT):
        raise ValueError('Unexpected files changed')
    git('diff', '--check', '--', str(DEPLOYMENT))
    git('add', '--', str(DEPLOYMENT))
    git('-c', 'user.name=github-actions[bot]', '-c', 'user.email=41898282+github-actions[bot]@users.noreply.github.com',
        'commit', '-m', f'Pin verified audio release {candidate[:7]}', '--', str(DEPLOYMENT))
    if main_sha() != candidate:
        raise ValueError('App main advanced before push; local commit was not published')
    git('push', 'origin', 'HEAD:refs/heads/main')
    print(f'Published validated audio release {candidate} ({digest}) from CI run {run["id"]}.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'Audio release publication refused: {type(error).__name__}: {error}', file=sys.stderr)
        raise SystemExit(1) from None
