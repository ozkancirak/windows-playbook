# Security Policy

## Reporting a Vulnerability

This project aims to balance security, performance and usability. Security reports are welcome, including ones that argue a particular balance was struck wrongly.

Because this playbook sits on top of Windows and is applied by a separate tool, a security issue found while running it may belong to one of three projects. Please use the section below to work out where yours goes.

## Scope

**Windows itself.** If the behaviour also occurs on a stock Windows install of the same build, it is Microsoft's to fix rather than this project's. Report it to [Microsoft](https://www.microsoft.com/en-us/msrc/faqs-report-an-issue).

**AME Wizard.** If the issue is in how a playbook is applied, reverted or packaged, report it through [ameliorated.io](https://ameliorated.io).

**This playbook.** If a change introduced here causes the exposure, open an issue on this repository.

## What to include

- The affected file, registry value, service or script
- Your Windows build number
- Which playbook options you selected during installation
- Steps to reproduce
- The security impact — what an attacker gains

Behaviour varies significantly depending on the options chosen at install time, so the third item matters more than it might appear.

Please do not put passwords, tokens or personal data in a public issue. If a report would require sharing a working exploit before a fix exists, use GitHub's private vulnerability reporting on this repository instead of opening a public issue.

## Out of scope

- Reduced protection resulting from the Defender, CPU mitigation or Core Isolation options being set to their less protective choice during installation
- Stock Windows behaviour that this playbook does not modify
- Feature requests and configuration preferences, which belong in a normal issue rather than a security report

## Response

This is an independently maintained project, worked on by one person. Response times are not guaranteed.
