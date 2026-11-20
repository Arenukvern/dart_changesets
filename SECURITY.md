# Security Policy

## Reporting

Report vulnerabilities privately — please do not open a public issue.

- **Preferred**: [GitHub Security Advisory](https://github.com/Arenukvern/dart_changesets/security/advisories/new)
  ("Report a vulnerability") on this repository.
- **Alternative**: contact [@Arenukvern](https://github.com/Arenukvern)
  through their profile.

Please include:

- The workflow YAML and the exact action ref (`Arenukvern/dart_changesets@…`).
- Run logs with tokens and secrets redacted.
- Expected versus actual behavior, and your repo's `changesets.yaml`.

## Scope

What the action and engine do inside your CI:

- Create/update the `chore: version packages` pull request, push
  `<package>-v<version>` tags, and dispatch the publish workflow you
  configure — using the `GITHUB_TOKEN` (or PAT) you grant the workflow.
- Publish to pub.dev only via GitHub OIDC (`id-token: write`) for packages
  where you enabled automated publishing; no registry tokens are stored,
  logged, or transmitted anywhere else.

Out of scope: vulnerabilities in your consumer workflow wiring, in
`actions/checkout`/`dart-lang/setup-dart`, or in pub.dev itself — report
those to their maintainers.

## Supported versions

Only the latest major tag (`v1`) receives security fixes.
