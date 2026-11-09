import email.utils
import mailbox
import os
import re
import smtplib
import socket
import subprocess
import sys
import time

import dkim

SOCKET = '/run/audio-mail/submit.sock'
MAILBOX = '/var/spool/mail/mail-bounce'

class UnixSMTP(smtplib.SMTP):
    def _get_socket(self, host, port, timeout):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        sock.connect(SOCKET)
        return sock

def submit():
    client = UnixSMTP(timeout=20)
    code, _ = client.connect('localhost')
    assert code == 220, code
    assert client.ehlo()[0] == 250
    return client

if sys.argv[1:] == ['--submit']:
    # Authorized clients may relay externally, but this test never supplies DATA.
    c = submit()
    assert c.mail('bounce@auth.ehpc.io')[0] == 250
    assert c.rcpt('recipient@example.invalid')[0] == 250
    assert c.rset()[0] == 250
    c.quit()

    c = submit()
    assert c.mail('forged@example.invalid')[0] == 250
    assert c.rcpt('recipient@example.invalid')[0] >= 500
    c.quit()

    # Actual messages are submitted only to the local bounce mailbox.
    def attempt(from_line):
        c = submit()
        assert c.mail('bounce@auth.ehpc.io')[0] == 250
        assert c.rcpt('bounce@auth.ehpc.io')[0] == 250
        headers = ('Date: ' + email.utils.formatdate(localtime=False) + '\r\n'
                   'To: bounce@auth.ehpc.io\r\n'
                   'Subject: isolated mail test\r\n')
        if from_line is not None:
            headers += 'From: ' + from_line + '\r\n'
        result = c.data(headers + '\r\nlocal test body\r\n')
        c.quit()
        return result

    assert attempt('forged@example.invalid')[0] >= 500
    assert attempt('no-reply@auth.ehpc.io')[0] == 250
    sys.exit(0)

# Internet-facing daemon must not relay or accept arbitrary local users.
c = smtplib.SMTP('127.0.0.1', 25, timeout=20)
c.ehlo()
assert c.mail('outside@example.invalid')[0] == 250
assert c.rcpt('outside@example.invalid')[0] >= 500
assert c.rcpt('root@auth.ehpc.io')[0] >= 500
assert c.rcpt('other@auth.ehpc.io')[0] >= 500
assert c.rcpt('bounce@auth.ehpc.io')[0] == 250
assert c.rcpt('postmaster@auth.ehpc.io')[0] == 250
c.quit()

# Neither the published Unix socket nor the private Postfix socket is reachable
# by a user outside the dedicated group.
for path in (SOCKET, '/var/lib/postfix/queue/private/audio-submit'):
    probe = "import socket; s=socket.socket(socket.AF_UNIX); s.connect(%r)" % path
    p = subprocess.run(['runuser', '-u', 'nobody', '--', 'python3', '-c', probe], capture_output=True)
    assert p.returncode != 0, path
assert os.stat(SOCKET).st_mode & 0o777 == 0o660

# The protected postdrop/sendmail path must not bypass the Unix socket boundary.
sendmail = sys.argv[1]
assert os.path.isfile(sendmail) and os.access(sendmail, os.X_OK), sendmail
p = subprocess.run(['runuser', '-u', 'nobody', '--', sendmail, '-i', '-f', 'bounce@auth.ehpc.io', 'bounce@auth.ehpc.io'], input=b'From: no-reply@auth.ehpc.io\n\nnot authorized\n', capture_output=True)
assert p.returncode != 0, (p.returncode, p.stderr)

# Submit through the Unix socket as a real, non-root group member.
subprocess.run(['runuser', '-u', 'audio-mail-client', '--', sys.executable, __file__, '--submit'], check=True)

for _ in range(60):
    if os.path.exists(MAILBOX):
        messages = list(mailbox.mbox(MAILBOX))
        if messages:
            break
    time.sleep(1)
else:
    raise AssertionError('Local bounce mailbox did not receive message')

message = messages[-1].as_bytes().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
assert re.search(br'(?i)\bd=auth\.ehpc\.io\b', message)
assert re.search(br'(?i)\bs=vps2026\b', message)
record_file = open('/var/lib/opendkim/keys/vps2026.txt', encoding='ascii').read()
record = ''.join(re.findall(r'"([^"]*)"', record_file)).encode('ascii')
assert b'v=DKIM1' in record and b'p=' in record

def dns(name, **kwargs):
    assert name.rstrip(b'.') == b'vps2026._domainkey.auth.ehpc.io', name
    return record

assert dkim.verify(message, dnsfunc=dns), 'DKIM signature failed verification'
tampered = message.replace(b'local test body', b'tampered test body')
assert tampered != message and not dkim.verify(tampered, dnsfunc=dns)
print('Local SMTP, authorization, signing and tamper checks passed')
