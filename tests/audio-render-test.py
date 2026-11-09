"""Exercise runtime group rendering and authentication-key preflight."""
import copy
import importlib.util
import tempfile
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('audio_render', ROOT / 'nixos/audio-render.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RenderTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.original = yaml.safe_load((ROOT / 'k8s/120-audio/deployment.yaml').read_text())
        self.source = self.root / 'deployment.yaml'
        self.out = self.root / 'rendered.yaml'

    def create(self, value):
        self.source.write_text(yaml.safe_dump(value))

    def test_real_deployment_adds_runtime_gid_without_changing_other_values(self):
        original = copy.deepcopy(self.original)
        security = original['spec']['template']['spec']['securityContext']
        security['supplementalGroups'] = [321, 888]
        self.create(original)
        MODULE.render(self.source, self.out, '777')
        result = yaml.safe_load(self.out.read_text())
        result_security = result['spec']['template']['spec']['securityContext']
        self.assertEqual(result_security['supplementalGroups'], [321, 777, 888])
        del result_security['supplementalGroups']
        del security['supplementalGroups']
        self.assertEqual(result, original)
        self.assertNotIn('777', self.source.read_text())

    def test_bad_gid_and_unsafe_security_fail_closed_without_output(self):
        for gid in ('', '0', '-1', '12x', '4294967296'):
            self.create(self.original)
            with self.assertRaises(ValueError):
                MODULE.render(self.source, self.out, gid)
            self.assertFalse(self.out.exists())
        altered = copy.deepcopy(self.original)
        altered['spec']['template']['spec']['securityContext']['fsGroup'] = 5
        self.create(altered)
        with self.assertRaises(ValueError):
            MODULE.render(self.source, self.out, '777')
        self.assertFalse(self.out.exists())

    def test_secret_preflight_rejects_missing_short_and_equal_values(self):
        otp, invite = self.root / 'otp', self.root / 'invite'
        otp.write_bytes(b'a' * 32)
        with self.assertRaises(OSError):
            MODULE.validate_secrets(otp, invite)
        invite.write_bytes(b'b' * 31)
        with self.assertRaises(ValueError):
            MODULE.validate_secrets(otp, invite)
        invite.write_bytes(b'a' * 32)
        with self.assertRaises(ValueError):
            MODULE.validate_secrets(otp, invite)
        invite.write_bytes(b'b' * 32)
        MODULE.validate_secrets(otp, invite)


if __name__ == '__main__':
    unittest.main()
