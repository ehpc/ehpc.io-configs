"""Validate audio authentication keys before applying cluster resources."""
import hmac
import sys
from pathlib import Path


def validate_secrets(otp: Path, invite: Path) -> None:
    a, b = otp.read_bytes().strip(), invite.read_bytes().strip()
    if len(a) < 32 or len(b) < 32 or hmac.compare_digest(a, b):
        raise ValueError('Audio auth keys must be distinct and at least 32 bytes')


if __name__ == '__main__':
    if len(sys.argv) != 4 or sys.argv[1] != '--check-secrets':
        raise SystemExit('usage: audio-render.py --check-secrets OTP INVITE')
    try:
        validate_secrets(Path(sys.argv[2]), Path(sys.argv[3]))
    except (ValueError, OSError) as error:
        raise SystemExit(str(error)) from error
