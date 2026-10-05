# Scoop Bucket Mko

[![Tests](https://github.com/mkoertgen/scooped/actions/workflows/ci.yml/badge.svg)](https://github.com/mkoertgen/scooped/actions/workflows/ci.yml) [![Excavator](https://github.com/mkoertgen/scooped/actions/workflows/excavator.yml/badge.svg)](https://github.com/mkoertgen/scooped/actions/workflows/excavator.yml)

Bucket for [Scoop](https://scoop.sh), the Windows command-line installer.

## How do I install these manifests?

After manifests have been committed and pushed, run the following:

```powershell
# Add the bucket
$ scoop bucket add mko https://github.com/mkoertgen/scooped
# Verify bucket has been added
$ scoop bucket known
# Install an app
$ scoop install mko/phone-home
# Update bucket(s) and manifests
$ scoop update
# Update all apps in bucket
$ scoop update mko *
```

## How do I contribute new manifests?

To make a new manifest contribution, please read the [Contributing
Guide](https://github.com/ScoopInstaller/.github/blob/main/.github/CONTRIBUTING.md)
and [App Manifests](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests)
wiki page.

## Automatic Manifest Updates

`checkver` detects upstream versions. `autoupdate` supplies URL and path templates;
Scoop obtains the new checksum from the publisher where configured, otherwise it
downloads the release asset and calculates the hash. This is not signature verification.

The Excavator workflow runs every four hours and can also be started manually.
It has permission to write updated manifests. Installed applications are updated
separately with `scoop update <app>`.

```powershell
# Check versions without modifying manifests
.\bin\checkver.ps1

# Update one manifest, including its download hash
.\bin\checkver.ps1 -App cyclonedx-cli -Update

# Update all manifests that have update metadata
.\bin\checkver.ps1 -Update
```

Upstream manifests use GitHub release checks, including special tag selection for
Kor's CLI (not its Helm chart) and Grafana Mimir. Neo4j-Migrations also updates its
versioned executable path. Existing pinned versions are not changed when adding
update metadata; review generated updates before installing a major upgrade.

Exceptions:

- `browser-contexts`, `git-ws`, `git-merge-bots`, and `phone-home` already use the
  app-specific tag release workflow, which updates versions, hashes, and archive paths.
- `dsbulk` remains manual until a stable version-discovery endpoint is established.
- `neobench` remains manual: its configured GitHub repository currently returns 404.
- `logcli` currently declares `2.9.3` but downloads `2.8.7`. The next reviewed update
  must align the version, URL, and checksum; this existing pin was left untouched.

## Documentation

See [\_docs/](_docs/index.md) for architecture decision records and additional documentation.
