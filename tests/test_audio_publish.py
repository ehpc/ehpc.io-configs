"""Release publisher trust, monotonicity and exact pin-update behavior."""
import copy
import importlib.util
import os
import subprocess
import tempfile
from unittest import mock
from pathlib import Path
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('audio_publish', ROOT / '.github/audio_publish.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

OLD = '1' * 40
NEW = '2' * 40
OLD_DIGEST = 'sha256:' + 'a' * 64
NEW_DIGEST = 'sha256:' + 'b' * 64


def run_record():
    return {'head_sha': NEW, 'workflow_id': MODULE.WORKFLOW_ID, 'event': 'push',
            'head_branch': 'main', 'status': 'completed', 'conclusion': 'success',
            'repository': {'id': MODULE.APP_REPOSITORY_ID},
            'head_repository': {'id': MODULE.APP_REPOSITORY_ID}}


def deployment():
    return ('apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  annotations:\n'
            f'    audio.ehpc.io/release-sha: "{OLD}"\n'
            f'    audio.ehpc.io/release-digest: {OLD_DIGEST}\n'
            'spec:\n  template:\n    spec:\n      containers:\n        - name: audio\n'
            f'          image: ghcr.io/ehpc/ehpc.io-audio@{OLD_DIGEST}\n'
            '          env:\n            - name: KEEP_UNCHANGED\n              value: safe\n')


class PublisherTest(unittest.TestCase):
    def test_only_completed_successful_main_push_for_exact_repository_and_sha(self):
        baseline = run_record()
        self.assertTrue(MODULE.trusted_run(baseline, NEW))
        for field, value in [('event', 'pull_request'), ('head_branch', 'feature'),
                             ('status', 'in_progress'), ('conclusion', 'failure'),
                             ('workflow_id', 9), ('head_sha', OLD)]:
            altered = copy.deepcopy(baseline)
            altered[field] = value
            self.assertFalse(MODULE.trusted_run(altered, NEW), field)
        for field in ('repository', 'head_repository'):
            altered = copy.deepcopy(baseline)
            altered[field]['id'] += 1
            self.assertFalse(MODULE.trusted_run(altered, NEW), field)

    def test_all_six_jobs_must_pass_on_exact_commit(self):
        jobs = [{'name': name, 'status': 'completed', 'conclusion': 'success',
                 'head_sha': NEW, 'run_id': 55, 'run_attempt': 1} for name in MODULE.REQUIRED_JOBS]
        self.assertTrue(MODULE.trusted_jobs(jobs, NEW, 55, 1))
        self.assertFalse(MODULE.trusted_jobs(jobs[:-1], NEW, 55, 1))
        for field, value in [('status', 'in_progress'), ('conclusion', 'skipped'),
                             ('conclusion', 'failure'), ('head_sha', OLD),
                             ('run_id', 54), ('run_attempt', 2)]:
            changed = copy.deepcopy(jobs)
            changed[0][field] = value
            self.assertFalse(MODULE.trusted_jobs(changed, NEW, 55, 1), field)

    def test_only_forward_descendant_or_idempotent_same_commit(self):
        self.assertTrue(MODULE.allowed_relation(OLD, NEW, 'ahead'))
        self.assertTrue(MODULE.allowed_relation(NEW, NEW, 'identical'))
        for relation in ('behind', 'diverged', 'identical'):
            self.assertFalse(MODULE.allowed_relation(OLD, NEW, relation))
        self.assertFalse(MODULE.allowed_relation(NEW, NEW, 'ahead'))

    def test_exact_pin_update_preserves_unrelated_content_and_is_idempotent(self):
        original = deployment()
        old, updated = MODULE.render_pin(original, NEW, NEW_DIGEST)
        self.assertEqual(old, OLD)
        self.assertEqual(updated, original.replace(OLD, NEW).replace(OLD_DIGEST, NEW_DIGEST))
        annotation = yaml.safe_load(updated)['metadata']['annotations']['audio.ehpc.io/release-sha']
        self.assertIsInstance(annotation, str)
        self.assertEqual(annotation, NEW)
        self.assertEqual(MODULE.render_pin(updated, NEW, NEW_DIGEST), (NEW, updated))
        with self.assertRaises(ValueError):
            MODULE.render_pin(updated, NEW, OLD_DIGEST)
        with self.assertRaises(ValueError):
            MODULE.render_pin(original.replace(OLD_DIGEST, NEW_DIGEST, 1), NEW, NEW_DIGEST)
        with self.assertRaises(ValueError):
            MODULE.render_pin(original + f'    audio.ehpc.io/release-sha: "{OLD}"\n', NEW, NEW_DIGEST)
        with self.assertRaises(ValueError):
            MODULE.render_pin(original, 'bad-sha', NEW_DIGEST)


    def test_comparison_rejects_persistence_changes_and_incomplete_evidence(self):
        good = {'status': 'ahead', 'total_commits': 1, 'base_commit': {'sha': OLD},
                'commits': [{'sha': NEW}],
                'files': [{'filename': 'frontend/app.tsx', 'status': 'modified'}]}
        self.assertTrue(MODULE.safe_comparison(good, OLD, NEW))
        for name in ('backend/playback.py', 'separator/cache_versions.py', 'separator/producer_manifest.py'):
            unrelated = copy.deepcopy(good)
            unrelated['files'] = [{'filename': name, 'status': 'modified'}]
            self.assertTrue(MODULE.safe_comparison(unrelated, OLD, NEW), name)
        bad = []
        for name in ('backend/db.py', 'backend/auth_store.py', 'backend/models.py',
                     'separator/options.py', 'backend/migrations/new.py'):
            changed = copy.deepcopy(good)
            changed['files'] = [{'filename': name, 'status': 'modified'}]
            bad.append(changed)
        renamed = copy.deepcopy(good)
        renamed['files'] = [{'filename': 'new.py', 'previous_filename': 'backend/db.py', 'status': 'renamed'}]
        bad.append(renamed)
        omitted = copy.deepcopy(good)
        del omitted['files']
        bad.append(omitted)
        truncated = copy.deepcopy(good)
        truncated['files'] = [{'filename': f'frontend/{i}.tsx', 'status': 'modified'} for i in range(300)]
        bad.append(truncated)
        incomplete = copy.deepcopy(good)
        incomplete['total_commits'] = 2
        bad.append(incomplete)
        wrong_head = copy.deepcopy(good)
        wrong_head['commits'] = [{'sha': OLD}]
        bad.append(wrong_head)
        wrong_base = copy.deepcopy(good)
        wrong_base['base_commit'] = {'sha': NEW}
        bad.append(wrong_base)
        bad_status = copy.deepcopy(good)
        bad_status['files'] = [{'filename': 'frontend/x.tsx', 'status': 'unknown'}]
        bad.append(bad_status)
        rename_missing = copy.deepcopy(good)
        rename_missing['files'] = [{'filename': 'frontend/x.tsx', 'status': 'renamed'}]
        bad.append(rename_missing)
        for item in bad:
            with self.assertRaises(ValueError):
                MODULE.safe_comparison(item, OLD, NEW)

    def test_real_git_publication_advances_only_validated_pin(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bare = root / 'origin.git'
            work = root / 'work'
            subprocess.run(['git', 'init', '--bare', str(bare)], check=True, capture_output=True)
            subprocess.run(['git', 'clone', str(bare), str(work)], check=True, capture_output=True)
            target = work / 'gitops/audio/deployment.yaml'
            target.parent.mkdir(parents=True)
            target.write_text(deployment())
            (work / 'unrelated.txt').write_text('retained')
            def git(*args):
                return subprocess.run(['git', '-C', str(work), *args], check=True,
                                      capture_output=True, text=True).stdout.strip()
            git('add', '--', 'gitops/audio/deployment.yaml', 'unrelated.txt')
            git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'initial')
            git('branch', '-M', 'main')
            git('push', '-u', 'origin', 'main')
            fake_run = {**run_record(), 'id': 55, 'run_number': 3, 'run_attempt': 1}
            jobs = [{'name': name, 'status': 'completed', 'conclusion': 'success',
                     'head_sha': NEW, 'run_id': 55, 'run_attempt': 1} for name in MODULE.REQUIRED_JOBS]
            def api(url, **_):
                if '/actions/workflows/' in url:
                    return {'workflow_runs': [fake_run]}
                if '/actions/runs/' in url:
                    self.assertIn('/actions/runs/55/attempts/1/jobs?', url)
                    return {'total_count': 6, 'jobs': jobs}
                if '/compare/' in url:
                    return {'status': 'ahead', 'total_commits': 1,
                            'base_commit': {'sha': OLD}, 'commits': [{'sha': NEW}],
                            'files': [{'filename': 'frontend/app.tsx', 'status': 'modified'}]}
                raise AssertionError(url)
            previous = Path.cwd()
            os.chdir(work)
            try:
                with mock.patch.dict(os.environ, {'AUDIO_PUBLISH_PAUSED': ''}), \
                     mock.patch.object(MODULE, 'main_sha', return_value=NEW), \
                     mock.patch.object(MODULE, 'get_json', side_effect=api), \
                     mock.patch.object(MODULE, 'registry_digest', return_value=NEW_DIGEST):
                    MODULE.main()
            finally:
                os.chdir(previous)
            self.assertEqual(git('show', 'origin/main:gitops/audio/deployment.yaml'),
                             deployment().replace(OLD, NEW).replace(OLD_DIGEST, NEW_DIGEST).strip())
            self.assertEqual((work / 'unrelated.txt').read_text(), 'retained')
            self.assertEqual(git('diff', '--name-only', 'HEAD^', 'HEAD'), 'gitops/audio/deployment.yaml')
            # The next scheduled run must not publish another commit or re-query
            # workflow jobs once the current pin matches the registry.
            published = git('rev-parse', 'HEAD')
            os.chdir(work)
            try:
                with mock.patch.dict(os.environ, {'AUDIO_PUBLISH_PAUSED': ''}), \
                     mock.patch.object(MODULE, 'main_sha', return_value=NEW), \
                     mock.patch.object(MODULE, 'registry_digest', return_value=NEW_DIGEST), \
                     mock.patch.object(MODULE, 'get_json', side_effect=AssertionError('unexpected CI query')):
                    MODULE.main()
            finally:
                os.chdir(previous)
            self.assertEqual(git('rev-parse', 'HEAD'), published)


    def test_publication_refuses_a_concurrent_remote_advance(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            bare, work, other = root / 'origin.git', root / 'work', root / 'other'
            def command(*args):
                return subprocess.run(args, check=True, capture_output=True, text=True).stdout.strip()
            def git(directory, *args):
                return command('git', '-C', str(directory), *args)
            command('git', 'init', '--bare', str(bare))
            command('git', 'clone', str(bare), str(work))
            target = work / 'gitops/audio/deployment.yaml'
            target.parent.mkdir(parents=True)
            target.write_text(deployment())
            git(work, 'add', '--', 'gitops/audio/deployment.yaml')
            git(work, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'initial')
            git(work, 'branch', '-M', 'main')
            git(work, 'push', '-u', 'origin', 'main')
            command('git', 'clone', '--branch', 'main', str(bare), str(other))
            fake_run = {**run_record(), 'id': 55, 'run_number': 3, 'run_attempt': 1}
            jobs = [{'name': name, 'status': 'completed', 'conclusion': 'success',
                     'head_sha': NEW, 'run_id': 55, 'run_attempt': 1} for name in MODULE.REQUIRED_JOBS]
            def api(url, **_):
                if '/actions/workflows/' in url:
                    return {'workflow_runs': [fake_run]}
                if '/actions/runs/55/attempts/1/jobs' in url:
                    return {'total_count': 6, 'jobs': jobs}
                if '/compare/' in url:
                    return {'status': 'ahead', 'total_commits': 1,
                            'base_commit': {'sha': OLD}, 'commits': [{'sha': NEW}],
                            'files': [{'filename': 'frontend/app.tsx', 'status': 'modified'}]}
                raise AssertionError(url)
            calls = 0
            def app_head():
                nonlocal calls
                calls += 1
                if calls == 3:
                    (other / 'concurrent.txt').write_text('not overwritten')
                    git(other, 'add', '--', 'concurrent.txt')
                    git(other, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                        'commit', '-m', 'concurrent change')
                    git(other, 'push', 'origin', 'HEAD:refs/heads/main')
                return NEW
            previous = Path.cwd()
            os.chdir(work)
            try:
                with mock.patch.dict(os.environ, {'AUDIO_PUBLISH_PAUSED': ''}), \
                     mock.patch.object(MODULE, 'main_sha', side_effect=app_head), \
                     mock.patch.object(MODULE, 'get_json', side_effect=api), \
                     mock.patch.object(MODULE, 'registry_digest', return_value=NEW_DIGEST):
                    with self.assertRaises(subprocess.CalledProcessError):
                        MODULE.main()
            finally:
                os.chdir(previous)
            self.assertEqual(git(other, 'show', 'origin/main:concurrent.txt'), 'not overwritten')
            self.assertEqual(git(other, 'show', 'origin/main:gitops/audio/deployment.yaml'), deployment().strip())



if __name__ == '__main__':
    unittest.main()
