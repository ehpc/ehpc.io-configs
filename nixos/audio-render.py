"""Render an audio deployment with the host's runtime mail-socket group."""
import hmac
import sys
from pathlib import Path

import yaml

def validate_secrets(otp: Path, invite: Path) -> None:
    a, b = otp.read_bytes().strip(), invite.read_bytes().strip()
    if len(a) < 32 or len(b) < 32 or hmac.compare_digest(a, b):
        raise ValueError('Audio auth keys must be distinct and at least 32 bytes')


def render(source: Path, destination: Path, gid_text: str) -> None:
    if not gid_text.isascii() or not gid_text.isdecimal() or not 0 < int(gid_text) <= 4294967295:
        raise ValueError('Invalid audio-mail group ID')
    deployment = yaml.safe_load(source.read_text())
    if not isinstance(deployment, dict) or deployment.get('kind') != 'Deployment' or deployment.get('metadata', {}).get('name') != 'audio':
        raise ValueError('Expected the audio Deployment')
    security = deployment['spec']['template']['spec']['securityContext']
    if security.get('fsGroup') != 1000:
        raise ValueError('Unexpected audio PVC fsGroup')
    groups = security.get('supplementalGroups', [])
    if not isinstance(groups, list) or any(type(group) is not int or group < 0 for group in groups):
        raise ValueError('Invalid existing supplemental groups')
    security['supplementalGroups'] = sorted(set([*groups, int(gid_text)]))
    destination.write_text(yaml.safe_dump(deployment, sort_keys=False))


if __name__ == '__main__':
    if len(sys.argv) != 4:
        raise SystemExit('usage: audio-render.py DEPLOYMENT OUTPUT MAIL_GID | --check-secrets OTP INVITE')
    try:
        if sys.argv[1] == '--check-secrets':
            validate_secrets(Path(sys.argv[2]), Path(sys.argv[3]))
        else:
            render(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])
    except (ValueError, KeyError, TypeError, OSError, yaml.YAMLError) as error:
        raise SystemExit(str(error)) from error
