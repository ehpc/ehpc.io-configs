"""Run Flux's actual substitution against the canonical audio manifest."""
import copy
import os
from pathlib import Path
import subprocess
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
FLUX = os.environ.get('FLUX_BIN', 'flux')


class SubstitutionTest(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / 'gitops/audio/deployment.yaml').read_text()
        self.template = yaml.safe_load(self.source)

    def substitute(self, gid):
        env = os.environ.copy()
        env.pop('AUDIO_MAIL_GID', None)
        if gid is not None:
            env['AUDIO_MAIL_GID'] = gid
        return subprocess.run([FLUX, 'envsubst', '--strict'], input=self.source,
                              capture_output=True, text=True, env=env, timeout=10)

    def test_real_substitution_preserves_deployment_and_uses_integer_gid(self):
        for gid in ('1', '777', '4294967294'):
            result = self.substitute(gid)
            self.assertEqual(result.returncode, 0, result.stderr)
            rendered = yaml.safe_load(result.stdout)
            expected = copy.deepcopy(self.template)
            security = expected['spec']['template']['spec']['securityContext']
            self.assertEqual(security['fsGroup'], 1000)
            security['supplementalGroups'] = [int(gid)]
            self.assertEqual(rendered, expected)
            self.assertIs(type(rendered['spec']['template']['spec']['securityContext']['supplementalGroups'][0]), int)

    def test_missing_gid_fails_closed(self):
        self.assertNotEqual(self.substitute(None).returncode, 0)


if __name__ == '__main__':
    unittest.main()
