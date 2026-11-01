# android-proot-rootfs

English · [简体中文](README.md)

Linux rootfs images for [proot](https://proot-me.github.io/) on Android.

No root, no kernel patches — unpack and use. Every image ships `apt` / `apk`, `ca-certificates` and a usable set of command-line tools, so you can carry on with `apt install` or `pip install` right away.

## Why this exists

Most rootfs tarballs you find for Android share the same three problems:

- **They are built for containers, not proot.** Missing `bash`, missing CA certificates, and `/etc/resolv.conf` is a symlink to `127.0.0.53`. There is no systemd-resolved inside proot, so DNS dies and `apt` / `git` / `pip` cannot reach anything.
- **Unreliable mirrors.** Downloads get cut off halfway, and the install fails with `unexpected end of stream` or a cryptic tar parsing error.
- **You do not know what is inside.** You find out after installing that there is no editor, no curl, no certificates.

These images are bootstrapped straight from the official distribution archives. Contents, sizes and checksums are deterministic, and the builds are reproducible.

## Where it runs

- The workspace feature in [RikkaHub Work](https://github.com/ziwa0213-crypto/rikkahub_work) — paste a download URL below when installing a rootfs
- Termux `proot-distro`
- Any custom proot launcher you have written yourself

## Packages

Five distributions × two architectures × three tiers.

| Distribution | Version | Notes |
|---|---|---|
| Debian | 12 `bookworm` | supported until 2028-06 |
| Debian | 13 `trixie` | current stable |
| Ubuntu | 24.04 LTS `noble` | what RikkaHub downloads by default |
| Ubuntu | 26.04 LTS `resolute` | |
| Alpine | 3.22 | smallest; musl + busybox, not glibc |

| Tier | Size (arm64, approx.) | Contents |
|---|---|---|
| `min` | 15–25 MB | bash + apt/apk + ca-certificates + tzdata. Enough to install packages, nothing else |
| `base` | 45–75 MB | adds curl / wget / git / less / vim-tiny / jq / unzip / zip / xz / procps / openssh-client / gnupg / htop / tree / bash-completion |
| `dev` | 180–260 MB | adds build-essential / gcc / make / python3 / pip / venv / cmake / sqlite3 / common `-dev` headers |

`min ⊂ base ⊂ dev` — each tier includes the previous one. Actual sizes are listed in [`docs/包清单.md`](docs/包清单.md) after every release.

## Download

File naming: `<distro>-<version>-<arch>-<tier>.tar.gz`

Each distribution gets its own release, tagged `<distro>-<version>`. Rebuilds replace the files in place, so these URLs stay valid:

```
https://github.com/ziwa0213-crypto/android-proot-rootfs/releases/download/debian-12/debian-12-arm64-base.tar.gz
https://github.com/ziwa0213-crypto/android-proot-rootfs/releases/download/ubuntu-24.04/ubuntu-24.04-arm64-base.tar.gz
https://github.com/ziwa0213-crypto/android-proot-rootfs/releases/download/alpine-3.22/alpine-3.22-arm64-min.tar.gz
```

> Phones are almost always `arm64`. Use `amd64` for emulators, Windows Subsystem for Android, or desktop containers.

Every archive has a matching `.sha256`. Verify before installing:

```bash
sha256sum -c debian-12-arm64-base.tar.gz.sha256
```

## Building it yourself

You need a Linux machine with root (Ubuntu or Debian, x86_64 or arm64):

```bash
sudo ./build.sh debian-12 arm64 base
```

Full instructions, mirror addresses, timing estimates and troubleshooting live in [docs/构建.md](docs/构建.md) (Chinese).

## Known limitations

- **Alpine uses musl, not glibc.** Many prebuilt binaries (Python manylinux wheels, some closed-source tools) will not install there. It is a good "small, fast, good enough" option; for real development use Debian or Ubuntu.
- **Images contain no `/proc`, `/sys` or `/dev` entries.** proot bind-mounts those from the host.
- **`.tar.gz`, not `.tar.xz`.** Extraction on the app side is pure Java; xz is 5–10× slower on a phone.

## License

Build scripts: [MIT](LICENSE).

Software inside each rootfs image keeps its own license (the Debian / Ubuntu / Alpine copyright systems).
`/usr/share/doc/*/copyright` is preserved, and sources are available from the respective distribution archives.
This project is not affiliated with any of those distributions.
