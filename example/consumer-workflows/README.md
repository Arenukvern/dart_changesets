# Consumer workflow templates

Copy these into your repository's `.github/workflows/`:

- `release.yml` — push to main: assembles/updates the version PR and, on its
  merge, pushes one `<package>-v<version>` tag per release and dispatches the
  publish runs.
- `publish.yml` — push to `<package>-v*` tags plus manual dispatch (preflight
  = dispatch with `execute` unchecked): one pub.dev publish run per tag,
  each gated on its same-train dependency floors being visible on pub.dev.

Both wrap the engine: the composite action (release mode) and the reusable
publish workflow. See the engine README for setup, the required repo
setting, workflow permissions, and the "Show your release train" section for
README badge snippets that surface train health in your repository.
