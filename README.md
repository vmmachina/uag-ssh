Enable SSH Access on Omnissa UAG via vCenter (PowerCLI)

This PowerShell script enables SSH access (and permits root login) on an Omnissa Unified Access Gateway (UAG) virtual machine by executing commands inside the guest OS through VMware vCenter using PowerCLI.

What the script does

Connects to the specified vCenter.

Locates the UAG VM by name.

Runs guest-OS commands via Invoke-VMScript to:

Set PermitRootLogin yes in /etc/ssh/sshd_config.

Enable the SSH service (sshd or ssh).

Start the SSH service (sshd or ssh).

Confirms success with a final status message.

The script modifies the UAG’s SSH configuration to allow root login and ensures the SSH service is enabled and running.

Requirements

PowerShell (Windows, Linux, or macOS).

VMware PowerCLI module installed.

Network access to the vCenter server.

Sufficient permissions in vCenter (connect & read VM inventory) and guest operations permissions to run scripts inside the VM.

The UAG VM must have VMware Tools / open-vm-tools running (required for Invoke-VMScript).

The UAG root password.

Parameters

-vCenter <string>
vCenter hostname or IP.

-vmName <string>
Display name of the UAG VM in vCenter.

-guestPassword <string>
Root password of the UAG guest OS. If omitted, you’ll be securely prompted.

The script always uses root as the guest username.

Usage
# If you want to be prompted for missing values:
.\Enable-UAG-SSH.ps1

# Or pass everything explicitly:
.\Enable-UAG-SSH.ps1 -vCenter vcsa.example.local -vmName UAG-01 -guestPassword 'YourRootPassword'


You may be prompted to authenticate to vCenter depending on your current PowerCLI session.

How it works (under the hood)

The script sends these commands to the guest:

sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl enable sshd || systemctl enable ssh
systemctl start sshd || systemctl start ssh


The sed line makes the change idempotent (it updates an existing line whether commented or not).

The systemctl lines handle Photon OS naming (sshd) and a fallback to ssh.

Security considerations

Enabling root SSH increases attack surface. Only enable temporarily for break-glass or advanced troubleshooting.

Restrict access at the network level (firewall, security groups) while SSH is enabled.

Revert the change after you’re done (see below).

Consider using key-based auth and PermitRootLogin prohibit-password if you must keep SSH open.

Reverting the change (disable SSH/root login)

Run via console or another guest execution to restore a safer configuration:

# Disable root SSH login
sed -i 's/^PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
# Optionally stop and disable the service
systemctl stop sshd || systemctl stop ssh
systemctl disable sshd || systemctl disable ssh
# Reload the service if you only changed the config
systemctl reload sshd || systemctl reload ssh

Troubleshooting

Invoke-VMScript fails / times out
Ensure VMware Tools is running inside the UAG. Verify guest operations permissions.

VM not found
Confirm the exact VM display name in vCenter matches -vmName.

Authentication errors
Verify the root password and that the account is not locked or expired.

Service name not found
The script already tries both sshd and ssh. If your image uses a nonstandard unit name, adjust the commands accordingly.

Notes

The script is idempotent: running it multiple times won’t break SSH.

Tested behavior assumes UAG’s underlying OS is Photon OS (typical for Omnissa UAG).

Use in accordance with your organization’s security policies and Omnissa guidance.
