# CorePulse: install files and releases

CorePulse is a self-hosted network monitor: devices, services, traffic, logs and more, on one small server
of your own. This repository holds what installs and upgrades use; the releases themselves are under
[Releases](https://github.com/fetcher-llc/corepulse-install/releases).

## Install

On a Linux server (x86-64 or ARM64) with Docker Engine and the compose plugin, ports 80 and 443 free:

```bash
curl -fsSL https://raw.githubusercontent.com/fetcher-llc/corepulse-install/main/install.sh | bash
```

Read [install.sh](install.sh) first if you like: it downloads the newest release, checks it against its
published SHA-256, unpacks it into `/opt/corepulse` and runs `./corepulsectl install`. Each release
includes the full guides (`docs/INSTALL.md`, `docs/UPGRADE.md`, `docs/SECURITY.md`).

## In this repository

- `install.sh`: the installer above.
- `releases.txt`: one line per release (`version|date|channel|bundle URL|bundle SHA-256|notes URL`), read by
  the installer, by `./corepulsectl upgrade` and by CorePulse's update notices.
- `notes/`: each release's notes.

Each release has the bundle (`corepulse-VERSION.tar.gz`), an offline bundle with every image for servers
without internet access (`corepulse-VERSION-offline-amd64.tar`), and a `.sha256` file for each. The images
(`ghcr.io/fetcher-llc/corepulse`, `corepulse-radius`) are signed; `./corepulsectl` checks the signatures.

## Security problems

Please report them privately: Security → Report a vulnerability, in this repository.

## License

CorePulse is © Fetcher LLC, licensed under the Functional Source License 1.1 (ALv2 future license);
the license ships with each release.
