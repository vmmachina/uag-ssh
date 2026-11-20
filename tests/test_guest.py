"""Linux integration tests: real OpenSSH parsing, isolated files, fake systemd.

Run: sudo python3 -m unittest discover -s tests -v
Requires bash, openssh-server, ssh-keygen and an existing privilege-separation
runtime directory (e.g. /run/sshd on Ubuntu). Never changes host SSH configuration.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'Enable-UAG-SSHAccess.ps1'
PROGRAM = re.search(r"\$guestScript = @'\n(.*?)\n'@", SOURCE.read_text(), re.S).group(1)
SSHD = shutil.which('sshd') or '/usr/sbin/sshd'


class GuestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='uag-ssh-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'etc/ssh'
        self.dropins = self.config / 'sshd_config.d'
        self.dropins.mkdir(parents=True)
        self.main = self.config / 'sshd_config'
        self.uag = self.dropins / '30-uag.conf'
        self.stig = self.dropins / '40-stig.conf'
        self.backups = self.root / 'backups'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.state = self.root / 'state'
        self.state.write_text('enabled active')
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(self.root / 'key')], check=True)
        self.main.write_text(f'HostKey {self.root}/key\nInclude {self.dropins}/*.conf\n')
        self.uag.write_text('# UAG configuration\nPermitRootLogin no\nPasswordAuthentication no\nPubkeyAuthentication no\n')
        self.stig.write_text('PermitRootLogin no\nPasswordAuthentication no\nUsePAM yes\n')
        self.write_executable('sshd', f'''#!/bin/bash
if [ "$1" = -t ] && [ -f '{self.root}/reject-valid-config' ] && grep -q '^PermitRootLogin yes' '{self.uag}'; then
    echo 'simulated syntax validation failure' >&2; exit 1
fi
exec '{SSHD}' -f '{self.main}' "$@"
''')
        self.write_executable('systemctl', f'''#!/bin/bash
set -e
read -r enabled active < '{self.state}' || true
printf '%s\\n' "$*" >> '{self.root}/calls'
case "$1" in
show)
    if [ -f '{self.root}/custom-config' ]; then echo '/usr/sbin/sshd -D -f /custom/config'; else echo '/usr/sbin/sshd -D'; fi ;;
is-enabled)
    if [ "$2" != --quiet ]; then echo "$enabled"; fi
    [ "$enabled" = enabled ] ;;
is-active)
    if [ "$2" != --quiet ]; then echo "$active"; fi
    [ "$active" = active ] ;;
enable) enabled=enabled ;;
disable) enabled=disabled ;;
start|reload-or-restart) active=active ;;
stop) active=inactive ;;
reload) [ ! -f '{self.root}/fail-reload' ] ;;
*) exit 1 ;;
esac
printf '%s %s' "$enabled" "$active" > '{self.state}'
''')
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'])
        self.program = PROGRAM.replace('/etc/ssh', str(self.config)).replace('/var/backups/uag-ssh', str(self.backups))

    def write_executable(self, name, text):
        path = self.bin / name
        path.write_text(text)
        path.chmod(0o700)

    def run_program(self, success=True):
        result = subprocess.run(['bash', '-c', self.program], env=self.env, text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('UAG_SSH_SUCCESS:', result.stdout)
            self.assertIn('permitrootlogin yes', self.effective())
            self.assertIn('passwordauthentication yes', self.effective())
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertNotIn('UAG_SSH_SUCCESS:', result.stdout)
        return result

    def effective(self):
        return subprocess.check_output([SSHD, '-T', '-f', str(self.main)], text=True)

    def test_old_substitution_misses_dropin_new_program_fixes_it(self):
        before = self.uag.read_bytes()
        main_before, stig_before = self.main.read_bytes(), self.stig.read_bytes()
        subprocess.run(['sed', '-i', r's/^#\?PermitRootLogin.*/PermitRootLogin yes/', str(self.main)], check=True)
        self.assertIn('permitrootlogin no', self.effective())
        self.assertEqual(self.uag.read_bytes(), before)
        self.uag.chmod(0o600)
        result = self.run_program()
        self.assertIn('30-uag.conf', result.stdout)
        self.assertEqual(self.main.read_bytes(), main_before)
        self.assertEqual(self.stig.read_bytes(), stig_before)
        self.assertEqual(self.uag.stat().st_mode & 0o777, 0o600)
        self.assertEqual(next(self.backups.glob('*/config.before')).read_bytes(), before)

    def test_repeated_run_is_idempotent(self):
        self.run_program()
        before = self.uag.read_bytes()
        backups = list(self.backups.glob('*/config.before'))
        self.assertIn('Changed: 0', self.run_program().stdout)
        self.assertEqual(self.uag.read_bytes(), before)
        self.assertEqual(list(self.backups.glob('*/config.before')), backups)

    def test_legacy_main_file_missing_directives(self):
        self.uag.unlink()
        self.stig.unlink()
        self.main.write_text(f'HostKey {self.root}/key\n#PermitRootLogin prohibit-password\n')
        self.assertIn(f'Configuration: {self.main}', self.run_program().stdout)

    def test_earlier_include_rolls_back(self):
        (self.dropins / '10-earlier.conf').write_text('PermitRootLogin no\n')
        before = self.uag.read_bytes()
        self.run_program(success=False)
        self.assertEqual(self.uag.read_bytes(), before)
        self.assertEqual(self.state.read_text(), 'enabled active')

    def test_syntax_failure_rolls_back(self):
        (self.root / 'reject-valid-config').touch()
        before = self.uag.read_bytes()
        self.run_program(success=False)
        self.assertEqual(self.uag.read_bytes(), before)

    def test_service_failure_rolls_back(self):
        (self.root / 'fail-reload').touch()
        self.state.write_text('disabled active')
        before = self.uag.read_bytes()
        self.run_program(success=False)
        self.assertEqual(self.uag.read_bytes(), before)
        self.assertEqual(self.state.read_text(), 'disabled active')

    def test_stopped_disabled_service_is_started(self):
        self.state.write_text('disabled inactive')
        self.run_program()
        self.assertEqual(self.state.read_text(), 'enabled active')

    def test_custom_config_is_rejected_without_mutation(self):
        (self.root / 'custom-config').touch()
        before = self.uag.read_bytes()
        self.run_program(success=False)
        self.assertEqual(self.uag.read_bytes(), before)
        self.assertFalse(self.backups.exists())

    def test_required_second_factor_is_not_silently_removed(self):
        self.uag.write_text('PermitRootLogin no\nPasswordAuthentication yes\nPubkeyAuthentication yes\nAuthenticationMethods publickey,password\n')
        before = self.uag.read_bytes()
        self.run_program(success=False)
        self.assertEqual(self.uag.read_bytes(), before)

    def test_match_blocks_are_preserved(self):
        block = 'Match User nobody\n    PasswordAuthentication no\n'
        self.uag.write_text(self.uag.read_text() + block)
        self.run_program()
        self.assertTrue(self.uag.read_text().endswith(block))


if __name__ == '__main__':
    unittest.main(verbosity=2)
