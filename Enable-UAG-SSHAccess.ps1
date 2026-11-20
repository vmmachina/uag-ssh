<#
.SYNOPSIS
Enables root/password SSH access on an Omnissa UAG through VMware Tools.
.DESCRIPTION
Version 3.0.0. Supports UAG 2609 AlmaLinux drop-ins and older main-file
configurations. Saves changed configuration and rolls back on error.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$vCenter,
    [string]$vmName,
    # Retained for existing callers. Prefer GuestCredential or the secure prompt.
    [string]$guestPassword,
    [string]$VMId,
    [PSCredential]$GuestCredential,
    [PSCredential]$VCenterCredential,
    [switch]$IgnoreInvalidCertificate
)

$ErrorActionPreference = 'Stop'
Import-Module VMware.VimAutomation.Core -ErrorAction Stop
if ($IgnoreInvalidCertificate) {
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null
}
if (-not $vCenter) { $vCenter = Read-Host 'Enter vCenter hostname/IP' }
if (-not $vmName -and -not $VMId) { $vmName = Read-Host 'Enter UAG VM name (exact name)' }
if (-not $vCenter -or (-not $vmName -and -not $VMId)) { throw 'vCenter and VM name or VMId are required.' }
if ($vmName -and $VMId) { throw 'Specify vmName or VMId, not both.' }
$currentSession = @(@($global:DefaultVIServers) + @($global:DefaultVIServer)) |
    Where-Object { $_ -and $_.IsConnected -and $_.Name -eq $vCenter } |
    Select-Object -First 1
$openedSession = $false
try {
    if (-not $currentSession) {
        if (-not $VCenterCredential) {
            $vcUser = Read-Host 'Enter vCenter username (default: administrator@vsphere.local)'
            if (-not $vcUser) { $vcUser = 'administrator@vsphere.local' }
            $VCenterCredential = [PSCredential]::new($vcUser, (Read-Host 'Enter vCenter password' -AsSecureString))
        }
        $currentSession = Connect-VIServer -Server $vCenter -Credential $VCenterCredential -ErrorAction Stop
        $openedSession = $true
    }
    $matches = if ($VMId) {
        @(Get-VM -Server $currentSession -Id $VMId -ErrorAction Stop)
    } else {
        @(Get-VM -Server $currentSession -Name $vmName -ErrorAction Stop |
            Where-Object { $_.Name -eq $vmName })
    }
    $matches = @($matches)
    if ($matches.Count -ne 1) { throw "Expected exactly one VM on '$vCenter'; found $($matches.Count). Use VMId when VM names are duplicated." }
    $uagVM = $matches[0]
    $vmName = $uagVM.Name
    if ($uagVM.PowerState -ne 'PoweredOn') { throw "VM '$vmName' must be powered on." }
    if ($uagVM.ExtensionData.Guest.ToolsRunningStatus -ne 'guestToolsRunning') {
        throw "VMware Tools is not running on '$vmName'. Invoke-VMScript cannot continue."
    }
    if (-not $PSCmdlet.ShouldProcess("$vCenter / $vmName / $($uagVM.Id)", 'Enable root/password SSH access')) { return }
    if ($GuestCredential -and $guestPassword) { throw 'Specify GuestCredential or guestPassword, not both.' }
    if (-not $GuestCredential) {
        $securePassword = if ($guestPassword) {
            ConvertTo-SecureString $guestPassword -AsPlainText -Force
        } else {
            Read-Host 'Enter UAG root password' -AsSecureString
        }
        $GuestCredential = [PSCredential]::new('root', $securePassword)
        $guestPassword = $null
    }
    if ($GuestCredential.UserName -ne 'root') { throw 'The guest credential must be for root.' }

    # Self-contained so the downloadable PS1 is sufficient.
    $guestScript = @'
set -euo pipefail
export LC_ALL=C
[ "$(id -u)" = 0 ] || { echo 'ERROR: root is required.' >&2; exit 1; }
sshd_bin=$(command -v sshd || true)
[ -n "$sshd_bin" ] || { echo 'ERROR: sshd was not found in PATH.' >&2; exit 1; }
main_config=/etc/ssh/sshd_config
target=$main_config
if [ -f /etc/ssh/sshd_config.d/30-uag.conf ]; then
    target=/etc/ssh/sshd_config.d/30-uag.conf
fi
[ -f "$target" ] || { echo "ERROR: SSH configuration not found: $target" >&2; exit 1; }
service_command=$(systemctl show sshd.service -p ExecStart --value)
if [[ "$service_command" =~ (^|[[:space:]])-f ]]; then
    echo 'ERROR: sshd.service uses a custom -f configuration; refusing to edit the default configuration.' >&2
    exit 1
fi
"$sshd_bin" -t
was_enabled=$(systemctl is-enabled sshd.service 2>/dev/null || true)
was_active=$(systemctl is-active sshd.service 2>/dev/null || true)
case "$was_enabled" in
    enabled|disabled) ;;
    *) echo "ERROR: unsupported sshd service state: $was_enabled" >&2; exit 1 ;;
esac
candidate=$(mktemp)
backup_dir=''
changed=0
service_touched=0
rollback() {
    status=$?
    trap - EXIT
    if [ "$status" -ne 0 ]; then
        echo 'ERROR: SSH activation failed.' >&2
        if [ "$changed" = 1 ]; then
            if cat "$backup_dir/config.before" > "$target"; then
                echo "Restored configuration: $target" >&2
            else
                echo "ERROR: restore failed; backup: $backup_dir/config.before" >&2
            fi
        fi
        if [ "$service_touched" = 1 ]; then
            if [ "$was_enabled" = disabled ]; then systemctl disable sshd.service >&2 || true; fi
            if [ "$was_active" = active ]; then
                systemctl reload-or-restart sshd.service >&2 || true
            else
                systemctl stop sshd.service >&2 || true
            fi
        fi
    fi
    rm -f "$candidate"
    exit "$status"
}
trap rollback EXIT

# Override global values only; retain all other settings and Match blocks.
awk '
    BEGIN { print "PermitRootLogin yes"; print "PasswordAuthentication yes"; in_match=0 }
    tolower($1) == "match" { in_match=1 }
    !in_match && (tolower($1) == "permitrootlogin" || tolower($1) == "passwordauthentication") { next }
    { print }
' "$target" > "$candidate"
if ! cmp -s "$candidate" "$target"; then
    backup_dir=/var/backups/uag-ssh/$(date -u +%Y%m%dT%H%M%SZ)-$$
    (umask 077; mkdir -p "$backup_dir"; cp -p "$target" "$backup_dir/config.before")
    changed=1
    # Keep the existing inode, ownership, permissions and SELinux label.
    cat "$candidate" > "$target"
fi
"$sshd_bin" -t
effective=$("$sshd_bin" -T)
for setting in 'permitrootlogin yes' 'passwordauthentication yes'; do
    if ! grep -qx "$setting" <<< "$effective"; then
        echo "ERROR: effective SSH configuration does not contain '$setting'; check earlier includes/Match rules." >&2
        exit 1
    fi
done
auth_methods=$(awk '$1 == "authenticationmethods" { $1=""; sub(/^ /, ""); print }' <<< "$effective")
case " $auth_methods " in
    *' any '*|*' password '*) ;;
    *) echo "ERROR: AuthenticationMethods prevents password-only login: $auth_methods" >&2; exit 1 ;;
esac
service_touched=1
systemctl enable sshd.service
if [ "$was_active" != active ]; then
    systemctl start sshd.service
elif [ "$changed" = 1 ]; then
    systemctl reload sshd.service
fi
systemctl is-active --quiet sshd.service
systemctl is-enabled --quiet sshd.service
echo "Configuration: $target"
echo "Changed: $changed"
if [ -n "$backup_dir" ]; then echo "Backup: $backup_dir/config.before"; fi
grep -E '^(permitrootlogin|passwordauthentication|authenticationmethods|port|listenaddress) ' <<< "$effective"
echo 'UAG_SSH_SUCCESS: sshd is active/enabled; global root/password settings verified.'
'@

    $result = Invoke-VMScript -VM $uagVM -Server $currentSession -ScriptText $guestScript `
        -GuestCredential $GuestCredential -ScriptType Bash -ToolsWaitSecs 30 -ErrorAction Stop
    if ($result.ScriptOutput) { Write-Host $result.ScriptOutput.TrimEnd() }
    if ($result.ExitCode -ne 0 -or $result.ScriptOutput -notmatch '(?m)^UAG_SSH_SUCCESS:') {
        throw "SSH activation failed on '$vmName' (guest exit code: $($result.ExitCode))."
    }
    Write-Host "SSH enabled on '$vmName'. Verify connectivity from the intended management network." -ForegroundColor Green
} finally {
    if ($openedSession -and $currentSession) {
        Disconnect-VIServer -Server $currentSession -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
}
