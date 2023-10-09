# Phone-Home

Quickly manage apps & services that are phoning home (start, stop, ...)

## Motivation

In consulting you might need to switch working context on the same workstation.
Not all contexts allow using cloud-based virtual ones like [GitHub Codespaces](https://docs.github.com/en/codespaces/overview), [Azure Dev Box](https://learn.microsoft.com/en-us/azure/dev-box/), [GitPod](https://www.gitpod.io/), ...

## Features

To reduce friction in manually launching & stopping apps, activating/deactivating services I came up with a little PowerShell script `phone-home.ps1` automating a good part of this.
It acts as power switch for a configurable set of workloads (services & applications). Privilege escalation is handled transparently using [gsudo](https://github.com/gerardog/gsudo).

Install using sccop

```shell
$ scoop bucket add mko https://github.com/mkoertgen/scooped
$ scoop install mko/phone-home
```

And here is what you can do with `phone-home` (usually aliased as `ph`)

<script async id="asciicast-612778" src="https://asciinema.org/a/612778.js"></script>
