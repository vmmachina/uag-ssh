# Changelog

## 3.0.0

- Support the AlmaLinux `30-uag.conf` layout used by UAG 2609, while retaining
  support for older main-file configurations.
- Enable root and password authentication explicitly; verify OpenSSH syntax and
  effective settings before activating the service.
- Add protected configuration backups, rollback on failure and idempotent runs.
- Replace manual plaintext password conversion with `PSCredential`; keep the
  legacy `guestPassword` parameter for existing callers.
- Abort on VMware Tools, guest execution and service failures; scope inventory
  operations to one vCenter and require a unique exact VM name or explicit VMId.
- Add `-WhatIf`, credential parameters and explicit `-IgnoreInvalidCertificate`.
- Breaking default: certificate validation is no longer disabled automatically.
- Add isolated integration tests using real OpenSSH.
