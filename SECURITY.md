# Security Policy

SciPlot is currently a beta source preview. Please report suspected vulnerabilities privately instead of opening a public issue.

## Supported Versions

Only the current `main` branch is supported during the beta period.

## Reporting a Vulnerability

If you find a security issue:

1. Email the maintainer or repository owner privately, or use GitHub private vulnerability reporting if it is enabled for the repository.
2. Include a minimal reproduction, affected files or endpoints, and the impact you believe is possible.
3. Do not include private research data, credentials, or unpublished datasets in the report.

## Scope

Useful reports include:

- unsafe file handling in import, project open/save, export, or Finder reveal flows
- code execution issues in Code Console, custom function fitting, or expression evaluation
- path traversal or archive extraction issues in `.sciplot` project files
- dependency vulnerabilities with a concrete exploit path in this project

Out of scope during beta:

- social engineering
- denial-of-service reports without a practical mitigation
- issues requiring access to a user's local machine beyond normal app permissions
