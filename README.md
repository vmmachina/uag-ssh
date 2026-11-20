# Omnissa UAG SSH Enabler

Enable **root/password SSH access** on an Omnissa Unified Access Gateway VM
through vCenter and VMware Tools. SSH does not need to be available beforehand.

## v3.0.0 — UAG 2609 / AlmaLinux support

UAG 2609 uses AlmaLinux 9.6. Its `/etc/ssh/sshd_config` can contain only an
`Include` directive. Root and authentication settings are in
`/etc/ssh/sshd_config.d/30-uag.conf`, ahead of `40-stig.conf`. The old substitution
in the main file succeeded without changing anything in this layout.

The script now:

- Updates `30-uag.conf` when present, otherwise the main `sshd_config` for older
  appliance layouts. Leaves the other drop-ins, cryptographic settings and
  SSH public-key settings intact.
- Sets both `PermitRootLogin yes` and `PasswordAuthentication yes` globally;
  preserves existing `Match` blocks. Conflicting earlier includes or additional
  authentication requirements produce an error instead of a success message.
- Checks syntax with `sshd -t` and effective global settings with `sshd -T`.
- Backs up changed files under `/var/backups/uag-ssh/<UTC timestamp>-<PID>/`,
  preserves the original file's ownership, permissions and SELinux label, and
  restores configuration/service state if activation fails. Rollback errors
  are reported. Repeated successful runs do not create redundant backups or
  reload an unchanged running service.
- Enables and starts `sshd`, or reloads an already running service when needed.
- Requires a unique exact VM name, a powered-on VM, and running VMware Tools;
  all VM operations are scoped to the selected vCenter.
- Supports `-VMId` instead of `-vmName` when inventory names are duplicated.
- Accepts `PSCredential` directly, supports `-WhatIf`, and closes only the
  vCenter connection opened by this invocation.

**Upgrade note:** invalid vCenter certificates are no longer ignored by default.
Use `-IgnoreInvalidCertificate` explicitly for a trusted lab with a self-signed
certificate; the setting applies to the current PowerCLI session.

## Requirements

- PowerShell 7.4 or later recommended, with PowerCLI:
  `Install-Module -Name VCF.PowerCLI -Scope CurrentUser`.
- A vCenter account with guest operation privileges, and the appliance's root
  credential. VMware Tools must be running.
- Network access from the PowerCLI machine to vCenter and the ESXi host. The
  guest execution path does not depend on SSH or guest TCP port 22.
- OpenSSH and the standard `sshd.service` on the appliance. A service with a
  custom `-f` configuration is rejected rather than editing the wrong file.

## Usage

Download `Enable-UAG-SSHAccess.ps1` from the release. The file is self-contained.
Run interactively:

```powershell
.\Enable-UAG-SSHAccess.ps1
```

Or specify the vCenter and the exact inventory VM name:

```powershell
.\Enable-UAG-SSHAccess.ps1 -vCenter vcenter.example.com -vmName UAG01
```

For a self-signed lab vCenter:

```powershell
.\Enable-UAG-SSHAccess.ps1 -vCenter vcenter.example.com -vmName UAG01 -IgnoreInvalidCertificate
```

When names are duplicated, select the intended VM's PowerCLI ID explicitly:

```powershell
.\Enable-UAG-SSHAccess.ps1 -vCenter vcenter.example.com -VMId VirtualMachine-vm-123
```

Use either `-vmName` or `-VMId`, not both.

For automation, use credentials obtained from your credential store or secure
prompts. Do not put passwords in script files or command history:

```powershell
$vcCredential = Get-Credential -Message 'vCenter credential'
$uagCredential = Get-Credential -UserName root -Message 'UAG root credential'
.\Enable-UAG-SSHAccess.ps1 -vCenter vcenter.example.com -vmName UAG01 `
    -VCenterCredential $vcCredential -GuestCredential $uagCredential
```

The original `-guestPassword` string parameter remains available for existing
callers; prefer `-GuestCredential` or the secure interactive prompt.

`-WhatIf` connects to vCenter and checks VM/Tools state, but does not run a guest
program or change the appliance. Existing vCenter sessions remain connected.

## Verification and scope

Success means the guest program exited successfully, the effective **global**
root/password settings are enabled, and `sshd` is active and enabled at boot.
It does not prove remote connectivity or override client-specific `Match`
restrictions, account expiration/locking, PAM policies, firewall rules, interface
bindings or nondefault ports. Test a new SSH login from your management network.
No firewall, user password, SSH key, or UAG deployment property is changed.

Restrict SSH to your management network/administrator addresses. UAG may regenerate
its configuration during appliance reconfiguration; this script does not change
the deployment's `sshEnabled`/authentication properties. For new deployments,
prefer the documented UAG deployment settings.

- [UAG 2609 operating system](https://docs.omnissa.com/UnifiedAccessGatewayDeployandConfigure-V2609/Deployingandconfiguring/)
- [UAG SSH deployment parameters](https://docs.omnissa.com/UnifiedAccessGatewayDeployandConfigure-V2609/PowerShelldeploymentparameters)
- [OpenSSH configuration precedence](https://man.openbsd.org/sshd_config)
- [Invoke-VMScript requirements](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/commands/invoke-vmscript)

## Tests

`tests/test_guest.py` exercises the embedded Bash program against **real OpenSSH**
with temporary configuration/keys and a simulated systemd service. It covers the
old Include-only failure, AlmaLinux and legacy layouts, idempotence, preserved
Match blocks, permissions/backups, conflicting settings, custom configurations,
starting a disabled service, and rollback after syntax/service failures.

On a disposable Linux test runner with OpenSSH server installed:

```bash
sudo mkdir -p /run/sshd  # Ubuntu privilege-separation runtime directory, if needed
sudo python3 -m unittest discover -s tests -v
```

The tests never edit the host's SSH configuration or control its real service.
