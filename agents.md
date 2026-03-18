# scooped

> Personal Scoop bucket for Windows CLI tools — app manifests + source definitions.

## Stack

- **Manifests**: JSON files in `bucket/` (Scoop format)
- **Sources**: `_apps/` per-app — Dockerfiles, configs, scripts
- **Versioning**: GitVersion (Mainline mode)
- **Changelog**: conventional-changelog via npm

## Terminal Environment

**Windows PowerShell 5.1**

- Use semicolons `;` not `&&`
- Path separator: backslash `\`

## Commands

```powershell
# Add this bucket
scoop bucket add mko https://github.com/mkoertgen/scooped

# Install an app from bucket
scoop install mko/<appname>

# Changelog
npm run changelog
```

## Structure

| Path          | Purpose                                                                               |
| ------------- | ------------------------------------------------------------------------------------- |
| `bucket/`     | Scoop manifests (JSON) — one per app                                                  |
| `_apps/`      | App source definitions (`phone-home`, `git-ws`, `git-merge-bots`, `browser-contexts`) |
| `scripts/`    | Build/release helper scripts                                                          |
| `_docs/adrs/` | Architecture Decision Records                                                         |

## Working Rules

- Manifest files in `bucket/` follow [Scoop manifest schema](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests)
- App sources live under `_apps/<appname>/` — keep self-contained
- Use Conventional Commits for changelog generation
- This is a **public** repo — no credentials, internal URLs, or sensitive config
