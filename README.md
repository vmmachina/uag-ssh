# VMware UAG SSH Enabler

A robust PowerShell script to enable **SSH** and **Root Login** on VMware Unified Access Gateways (UAG) using PowerCLI `Invoke-VMScript`.

Useful for lab environments, troubleshooting, or when the UAG console is not accessible via standard means.

## 🚀 Improvements in v2 (Latest Update)

The script has been refactored to be more reliable in modern terminals (VS Code, Windows Terminal) and headless environments.

* **No UI Dependencies:** Replaced `Get-Credential` pop-ups with secure console-based input (`Read-Host`). This fixes issues where the credential window would not appear or crash the script in VS Code.
* **Smart Authentication:** Automatically detects existing vCenter sessions to avoid repeated login prompts.
* **Pre-flight Checks:** Verifies that **VMware Tools** is running on the target UAG before attempting execution.
* **SSL Handling:** Automatically handles invalid/self-signed certificates (common in lab environments).
* **Clean Output:** Removed special characters/icons to ensure compatibility with all distinct shell encodings.

## 📋 Prerequisites

* **PowerCLI** installed (`Install-Module -Name VMware.PowerCLI`).
* **Network Access:**
    * HTTPS (443) to vCenter.
    * The vCenter must have access to the ESXi host where the UAG resides.
* **VMware Tools:** Must be running on the UAG appliance (required for `Invoke-VMScript`).

## 💻 Usage

Download the script and run it via PowerShell. You can pass arguments or let the script prompt you interactively.

### Option 1: Interactive Mode
Simply run the script. It will prompt for the vCenter IP, Credentials, and UAG Root Password securely in the console.

```powershell
.\Enable-UAG-SSHAccess.ps1
