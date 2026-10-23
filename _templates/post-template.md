---
# ─── Post settings ──────────────────────────────────────────────
# Rename this file to: YYYY-MM-DD-short-slug.md  (e.g. 2026-10-23-htb-cozyhosting.md)
# and drop it in _posts/ when it's ready to publish.
title: "Platform: Box / Challenge Name"
date: 2026-10-23 12:00:00 -0400
categories: [CTF, HackTheBox]        # max 2 levels: [Main, Sub]
tags: [linux, web, privesc]          # lowercase, as many as you like
description: >-
  One or two sentences summarizing the post. Shows in search results and link previews.
image:
  path: banner.png                   # optional header image, from assets/img/posts/<slug>/
  alt: "Short description of the banner"
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
| **OS** | Linux |
| **Key techniques** | Technique 1, Technique 2 |

Brief summary of the box/project and what made it interesting.

> This post covers a retired box. Spoilers ahead.
{: .prompt-info }

## Recon

### Port scan

```bash
nmap -sC -sV -oA nmap/initial 10.10.10.10
```

```text
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 8.9p1
80/tcp open  http    nginx 1.18.0
```

Notes on what stood out.

### Web enumeration

![Landing page](landing.png){: w="800" }
_Caption text goes here_

## Initial Access

Explain the vulnerability and how you found it.

```python
# exploit.py
import requests

r = requests.get("http://target/")
print(r.status_code)
```
{: file="exploit.py" }

> Highlight something useful the reader should remember.
{: .prompt-tip }

## Privilege Escalation

```console
$ sudo -l
User avery may run the following commands on target:
    (root) NOPASSWD: /usr/bin/example
```

> Anything risky or easy to get wrong.
{: .prompt-warning }

## Root / Flags

```console
# cat /root/root.txt
[redacted]
```

## Lessons Learned

- Takeaway 1
- Takeaway 2

## Remediation

How a defender would fix or detect this:

- Fix 1
- Detection idea 1

## References

- [Resource name](https://example.com)
