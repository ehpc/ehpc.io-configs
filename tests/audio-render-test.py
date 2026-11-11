"""Exercise authentication-key preflight."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('audio_render', ROOT / 'nixos/audio-render.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RenderTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

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
