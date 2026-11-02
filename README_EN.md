# android-proot-rootfs

English · [简体中文](README.md)

Linux rootfs images for [proot](https://proot-me.github.io/) on Android.

No root, no kernel patches — unpack and use. Every image ships a package manager, `ca-certificates` and a usable set of command-line tools, so you can carry on with `apt install` or `pip install` right away.

## Why this exists

Most rootfs tarballs you find for Android share the same three problems:

- **They are built for containers, not proot.** Missing `bash`, missing CA certificates, and `/etc/resolv.conf` is a symlink to `127.0.0.53`. There is no systemd-resolved inside proot, so DNS dies and `apt` / `git` / `pip` cannot reach anything.
- **Unreliable mirrors.** Downloads get cut off halfway, and the install fails with `unexpected end of stream` or a cryptic tar parsing error.
- **You do not know what is inside.** You find out after installing that there is no editor, no curl, no certificates.

Contents, sizes and checksums here are deterministic, and the builds are reproducible.

## Where it runs

- The workspace feature in [RikkaHub Work](https://github.com/ziwa0213-crypto/rikkahub_work) — paste a download URL below when installing a rootfs
- Termux `proot-distro`
- Any custom proot launcher you have written yourself

## Packages

Eleven distributions × up to two architectures × three tiers.

| Distribution | Version | Package manager | Architectures | Notes |
|---|---|---|---|---|
| Debian | 12 `bookworm` | apt | arm64 / amd64 | supported until 2028-06 |
| Debian | 13 `trixie` | apt | arm64 / amd64 | current stable |
| Ubuntu | 24.04 LTS `noble` | apt | arm64 / amd64 | what RikkaHub downloads by default |
| Ubuntu | 26.04 LTS `resolute` | apt | arm64 / amd64 | |
| Alpine | 3.24 | apk | arm64 / amd64 | smallest; musl + busybox, not glibc |
| Void Linux | rolling (glibc) | xbps | arm64 / amd64 | runit, no systemd; glibc only — musl has poor wheel coverage |
| openSUSE | Tumbleweed | zypper | arm64 / amd64 | rolling; usr-merged `/etc` (`nsswitch.conf` lives in `/usr/etc`) |
| AlmaLinux | 9 | dnf | arm64 / amd64 | RHEL 9 rebuild |
| OpenCloudOS | 9.6 Minimal | dnf | arm64 / amd64 | Tencent-backed CentOS replacement |
| Kali NetHunter | current (minimal) | apt | arm64 / amd64 | the same rootfs Termux uses; minimal, not full |
| Arch Linux | ARM rolling | pacman | **arm64 only** | the x86 build ships as `.tar.zst`, which the app cannot extract |

| Tier | Contents |
|---|---|
| `min` | Package manager + `ca-certificates` + `tzdata`. Debian/Ubuntu ship `bash`; **Alpine's `min` only has busybox `ash`, no bash**; Arch's `min` is the official image as-is (it already carries coreutils / file / less / procps) |
| `base` | adds curl / wget / git / less / vim / jq / tree / htop / unzip / zip / xz / procps / psmisc / iproute2 / net-tools / ssh client / gnupg / bash-completion |
| `dev` | adds gcc / make / python3 / pip / venv / cmake / sqlite3 / common `-dev` headers (`build-essential` on Debian-likes, `base-devel` on Arch/Void, split into `gcc gcc-c++ make` on RHEL-likes) |

`min ⊂ base ⊂ dev` — each tier includes the previous one. Package names are maintained per distribution, not one list forced onto all of them.

### Size reference (arm64)

| Distribution | Source / output | Note |
|---|---|---|
| Alpine 3.24 `min` | **4.1 MB** | measured output |
| openSUSE Tumbleweed `base` | source **38.9 MB** | grows after the `base` packages are installed |
| OpenCloudOS 9.6 `base` | source **35.4 MB** | same |
| Void Linux `base` | source **43.7 MB** | same |
| Ubuntu 24.04 `base` | **58 MB** | measured output |
| Debian 12 `base` | **70 MB** | measured output |
| Debian 13 `base` | **76 MB** | measured output |
| AlmaLinux 9 `base` | source **98.9 MB** | same |
| Kali NetHunter `base` | source **120 MB** | same |
| Arch Linux `base` | source **791 MB** | the biggest one |

`dev` typically adds another 60–150 MB. The full list lives in [`docs/包清单.md`](docs/包清单.md) (Chinese).

## Where the images come from

| Source | Used for | Notes |
|---|---|---|
| `mmdebstrap` against the official archive | Debian, Ubuntu | bootstrapped from scratch; contents and size are fully controlled by the script |
| Official Alpine minirootfs | Alpine | 3–4 MB official root filesystem, then `apk add` |
| [images.linuxcontainers.org](https://images.linuxcontainers.org/) | AlmaLinux, openSUSE | the official LXC / Incus image server; built daily, ships `SHA256SUMS` |
| Distribution-provided rootfs tarballs | Arch Linux ARM, Kali NetHunter, Void | official artifacts, verified on download |
| Official container image (`docker save` format) | OpenCloudOS | the inner `layer.tar` is the root filesystem |

> AlmaLinux / openSUSE come from the LXC image server, which is often limited to tens of KB/s from mainland China. Switch to the Tsinghua mirror (same files, identical paths):
> ```bash
> sudo ./build.sh almalinux-9 arm64 base --lxc-mirror https://mirrors.tuna.tsinghua.edu.cn/lxc-images/images
> ```
> The mirror lags upstream by a day or two, so the newest date directories may still be empty — the script falls back to the first date that actually has `rootfs.tar.xz`.

The last three are not bootstrapped here — an official artifact is taken and then adapted for proot uniformly: rewrite `/etc/resolv.conf` as a regular file, fill in `/etc/hosts` and `/etc/hostname`, set the locale, install the tier's extra tools, clear caches and trim docs. That saves build time and removes the "what I installed is not what upstream shipped" doubt.

## Download

File naming: `<distro>-<version>-<arch>-<tier>.tar.gz`

Each distribution gets its own release, tagged `<distro>-<version>`. Rebuilds replace the files in place, so these URLs stay valid:

```
https://github.com/ziwa0213-crypto/android-proot-rootfs/releases/download/debian-12/debian-12-arm64-base.tar.gz
https://github.com/ziwa0213-crypto/android-proot-rootfs/releases/download/ubuntu-24.04/ubuntu-24.04-arm64-base.tar.gz
https://github.com/ziwa0213-crypto/android-proot-rootfs/releases/download/alpine-3.24/alpine-3.24-arm64-min.tar.gz
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
sudo ./build.sh almalinux-9 arm64 base
sudo ./build.sh void amd64 dev
```

→ **Everything** (11 distributions × 2 architectures × 3 tiers = 66 packages, heavy):

```bash
sudo ./build.sh all
```

→ **Only the six added in 2026-11**:

```bash
sudo ./build.sh new-all
```

→ A single tier:

```bash
ONLY_TIERS=base sudo ./build.sh new-all
```

A source archive is reused across `min` / `base` / `dev`, cached under `.work/cache/`, so it is downloaded once.

Full instructions, mirror addresses, timing estimates and troubleshooting live in [docs/构建.md](docs/构建.md) (Chinese).

## Known limitations

- **Alpine uses musl, not glibc.** Many prebuilt binaries (Python manylinux wheels, some closed-source tools) will not install there. It is a good "small, fast, good enough" option; for real development use Debian or Ubuntu. For the same reason Void is offered in its glibc variant only.
- **Arch is arm64 only.** Arch Linux ARM is a separate project and publishes aarch64 only; upstream's x86 build is `archlinux-bootstrap-x86_64.tar.zst`, and `.zst` is not supported by the app.
- **Kali NetHunter's rootfs is made for Termux.** It may carry a pre-created `kali` user and Termux-specific conventions. This repo only rewrites the network and locale configuration and leaves the rest alone.
- **Package installs are slower on RHEL-likes and openSUSE.** `dnf` and `zypper` metadata runs to tens of MB, and proot makes it worse; a slow first `install` is expected.
- **Images contain no `/proc`, `/sys` or `/dev` entries.** proot bind-mounts those from the host.
- **`.tar.gz`, not `.tar.xz`.** Extraction on the app side is pure Java; xz is 5–10× slower on a phone (source archives that ship as xz are repacked with gzip during the build).

## License

Build scripts: [MIT](LICENSE).

Software inside each rootfs image keeps its own license (the Debian / Ubuntu / Alpine / openSUSE / AlmaLinux / OpenCloudOS / Void / Arch Linux ARM / Kali copyright systems).
`/usr/share/doc/*/copyright` is preserved, and sources are available from the respective distribution archives.
This project is not affiliated with any of those distributions.
