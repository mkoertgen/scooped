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

## Documentation

See [_docs/](_docs/index.md) for architecture decision records and additional documentation.
