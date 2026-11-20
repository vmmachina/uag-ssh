# v3.0.0 validation — 2026-11-20

Tested against a UAG 2609 development appliance running AlmaLinux 9.6 and
open-vm-tools 12.5.0, using PowerShell 7.7.0 and PowerCLI through vCenter.
The target VM was selected by its unique VM ID because its inventory name
was duplicated. No credentials or environment-specific addresses are included.

- Reproduced the previous main-file substitution failure using an isolated
  Include-only configuration and real OpenSSH on the appliance.
- Passed all 10 isolated guest-program tests in `test_guest.py` on the appliance,
  transferred and executed through vCenter guest operations.
- Ran the complete PowerShell script against the actual appliance configuration.
- Disabled root/password access, stopped and disabled `sshd`, and confirmed that
  TCP port 22 was unreachable. The new script re-enabled access through vCenter
  without SSH. A fresh root/password SSH login then succeeded.
- Repeated execution reported `Changed: 0`.
- Verified byte-identical main and STIG configuration files, and unchanged
  ownership, mode and SELinux context of `30-uag.conf`.
- Confirmed duplicate VM names are rejected before guest execution.
- Confirmed `-WhatIf` completes without guest credentials or guest execution.
- Confirmed an existing vCenter session is retained, while a session opened by
  the script using `-VCenterCredential` is disconnected afterwards.
- Passed PowerShell parsing, embedded Bash syntax validation and `git diff --check`.

The development appliance was left with SSH active and enabled and root/password
login working. Configuration backups remain on the appliance. Test configuration
and temporary test keys were removed. Legacy main-file handling and failure
rollback were tested in isolation; no older UAG appliance was available for a
full end-to-end test.
