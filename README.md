# 🚀 Enable SSH Access on Omnissa UAG via vCenter (PowerCLI)

This PowerShell script enables **SSH access** (including root login) on an  
**Omnissa Unified Access Gateway (UAG)** VM by executing guest OS commands  
through **VMware vCenter** with **PowerCLI**.

---

## 📌 Features

✔ Connects securely to **vCenter**  
✔ Locates the specified **UAG VM**  
✔ Updates `/etc/ssh/sshd_config` → `PermitRootLogin yes`  
✔ Enables & starts the **SSH service** (`sshd` / `ssh`)  
✔ Provides clear success & warning messages  

---

## ⚙️ Requirements

- **PowerShell** (Windows, Linux, or macOS)  
- **VMware PowerCLI** module installed  
- Network access to **vCenter**  
- Sufficient **vCenter permissions** (VM inventory + guest operations)  
- UAG VM must run **VMware Tools / open-vm-tools**  
- **Root password** of the UAG  

---

## 📥 Parameters

| Parameter       | Description                                      | Required |
|-----------------|--------------------------------------------------|----------|
| `-vCenter`      | vCenter hostname or IP                           | ✅       |
| `-vmName`       | Display name of the UAG VM in vCenter            | ✅       |
| `-guestPassword`| Root password of the UAG guest OS (or prompt)    | ❌       |

> The script always uses **`root`** as the guest username.

---

## ▶️ Usage

### Prompt for missing values
```powershell
.\Enable-UAG-SSH.ps1
