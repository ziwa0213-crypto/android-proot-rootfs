# android-proot-rootfs

[English](README_EN.md) · 简体中文

给 Android 上跑的 [proot](https://proot-me.github.io/) 环境用的 Linux rootfs 镜像。

不需要 root、不需要刷内核，解压即用。每个包都自带包管理器、`ca-certificates` 和一套常用命令行工具，装完就能继续 `apt install` / `pip install`。

## 为什么自己做

Android 上现成的 rootfs 包通常有三个毛病：

- **是给容器用的**：缺 `bash`、缺证书、`/etc/resolv.conf` 是指向 `127.0.0.53` 的软链 —— 在 proot 里没有 systemd-resolved，DNS 直接全挂，`apt` / `git` / `pip` 全部连不上网。
- **下载源不稳定**：下到一半断掉，安装时报 `unexpected end of stream` 或者一串看不懂的 tar 解析错误。
- **不知道里面装了什么**：装完才发现没有编辑器、没有 curl、没有证书。

这个仓库的包，内容、体积、校验和都是确定的，构建过程可复现。

## 用在哪

- [RikkaHub Work](https://github.com/ziwa0213-crypto/rikkahub_work) 的「工作区」—— 安装 rootfs 时直接填下面的下载链接
- Termux 的 proot-distro
- 任何自己拼 proot 启动脚本的场景

## 包清单

十一个发行版 × 最多两个架构 × 三个档位。

| 发行版 | 版本 | 包管理器 | 架构 | 说明 |
|---|---|---|---|---|
| Debian | 12 `bookworm` | apt | arm64 / amd64 | 支持到 2028-06 |
| Debian | 13 `trixie` | apt | arm64 / amd64 | 当前 stable |
| Ubuntu | 24.04 LTS `noble` | apt | arm64 / amd64 | RikkaHub 默认下载的就是这个 |
| Ubuntu | 26.04 LTS `resolute` | apt | arm64 / amd64 | |
| Alpine | 3.24 | apk | arm64 / amd64 | 最小，musl + busybox，不是 glibc |
| Void Linux | rolling（glibc） | xbps | arm64 / amd64 | runit，没有 systemd；只做 glibc 版，musl 版的 wheel 覆盖率差 |
| openSUSE | Tumbleweed | zypper | arm64 / amd64 | 滚动更新；`/etc` 是 usr-merge 布局（`nsswitch.conf` 在 `/usr/etc`） |
| AlmaLinux | 9 | dnf | arm64 / amd64 | RHEL 9 兼容重建版 |
| OpenCloudOS | 9.6 Minimal | dnf | arm64 / amd64 | 腾讯主导的 CentOS 替代 |
| Kali NetHunter | current（minimal） | apt | arm64 / amd64 | 就是 Termux 上那套 NetHunter rootfs；取 minimal 不取 full |
| Arch Linux | ARM rolling | pacman | **仅 arm64** | x86 版官方只给 `.tar.zst`，应用端解不了 |

| 档位 | 里面有什么 |
|---|---|
| `min` | 包管理器 + `ca-certificates` + `tzdata`。Debian/Ubuntu 自带 `bash`；**Alpine 的 `min` 只有 busybox `ash`，没有 bash**；Arch 的 `min` 就是官方基础镜像原样（它已经自带 coreutils / file / less / procps） |
| `base` | 加 curl / wget / git / less / vim / jq / tree / htop / unzip / zip / xz / procps / psmisc / iproute2 / net-tools / ssh 客户端 / gnupg / bash-completion |
| `dev` | 加 gcc / make / python3 / pip / venv / cmake / sqlite3 / 常用 `-dev` 头文件（Debian 系是 `build-essential`，Arch/Void 是 `base-devel`，RHEL 系拆成 `gcc gcc-c++ make`） |

`min ⊂ base ⊂ dev`，后一档包含前一档。包名按各发行版的实际签名单独维护，不是一套名字套到底。

### 体积参考（arm64）

| 发行版 | 源包 / 成品 | 备注 |
|---|---|---|
| Alpine 3.24 `min` | **4.1 MB** | 实测成品 |
| openSUSE Tumbleweed `base` | 源包 **38.9 MB** | 装完 `base` 后会增长 |
| OpenCloudOS 9.6 `base` | 源包 **35.4 MB** | 同上 |
| Void Linux `base` | 源包 **43.7 MB** | 同上 |
| Ubuntu 24.04 `base` | **58 MB** | 实测成品 |
| Debian 12 `base` | **70 MB** | 实测成品 |
| Debian 13 `base` | **76 MB** | 实测成品 |
| AlmaLinux 9 `base` | 源包 **98.9 MB** | 同上 |
| Kali NetHunter `base` | 源包 **120 MB** | 同上 |
| Arch Linux `base` | 源包 **791 MB** | 最大的一份 |

`dev` 档一般再增加 60~150 MB。完整清单见 [`docs/包清单.md`](docs/包清单.md)。

## 包是怎么来的

| 来源 | 用于 | 说明 |
|---|---|---|
| `mmdebstrap` 从官方归档 bootstrap | Debian、Ubuntu | 从零装起，内容和体积完全由脚本决定 |
| Alpine 官方 minirootfs | Alpine | 官方 3~4 MB 的根文件系统，再 `apk add` |
| [images.linuxcontainers.org](https://images.linuxcontainers.org/) | AlmaLinux、openSUSE | LXC / Incus 官方镜像服务器，每天构建，自带 `SHA256SUMS` |
| 发行版官方 rootfs 压缩包 | Arch Linux ARM、Kali NetHunter、Void | 官方直接提供，下载后校验 |
| 官方容器镜像（`docker save` 格式） | OpenCloudOS | 展开其中的 `layer.tar` 得到根文件系统 |

后三类不是我们自己 bootstrap 的，是取官方产物再统一做 proot 适配 —— 重写 `/etc/resolv.conf` 为普通文件、补 `/etc/hosts` 与 `/etc/hostname`、设定 locale、按档位补装常用工具、清缓存、裁剪文档。这样既省构建时间，也少一层「我装的和你官方的不一样」的疑虑。

## 下载

文件名规则：`<发行版>-<版本>-<架构>-<档位>.tar.gz`

每个发行版单独一个 release，标签固定为 `<发行版>-<版本>`；重新构建时原地替换文件，链接永久有效：

```
https://github.com/ziwa0213-crypto/android-proot-rootfs/releases/download/debian-12/debian-12-arm64-base.tar.gz
https://github.com/ziwa0213-crypto/android-proot-rootfs/releases/download/ubuntu-24.04/ubuntu-24.04-arm64-base.tar.gz
https://github.com/ziwa0213-crypto/android-proot-rootfs/releases/download/alpine-3.24/alpine-3.24-arm64-min.tar.gz
```

> 手机几乎都是 `arm64`。`amd64` 是给模拟器 / WSA / 桌面容器用的。

每个文件旁边有同名 `.sha256`，装之前可以对一下：

```bash
sha256sum -c debian-12-arm64-base.tar.gz.sha256
```

## 自己构建

需要一台 Linux 机器和 root（Ubuntu / Debian 都行，x86_64 或 arm64 都可以）：

```bash
sudo ./build.sh debian-12 arm64 base
sudo ./build.sh almalinux-9 arm64 base
sudo ./build.sh void amd64 dev
```

→ **全部发行版**（11 × 2 架构 × 3 档 = 66 个包，很重）：

```bash
sudo ./build.sh all
```

→ **只跑 2026-11 新增的 6 个**：

```bash
sudo ./build.sh new-all
```

→ 只跑某一档：

```bash
ONLY_TIERS=base sudo ./build.sh new-all
```

同一份源包在 `min` / `base` / `dev` 之间复用，缓存在 `.work/cache/`，不会重复下载。

完整步骤、镜像地址、耗时参考和常见错误见 [docs/构建.md](docs/构建.md)。

## 已知限制

- **Alpine 是 musl，不是 glibc**。很多预编译二进制（Python 的 manylinux wheel、部分闭源工具）在它上面装不了。它适合「小、快、够用」，正经开发还是 Debian / Ubuntu。同理，Void 只提供 glibc 版。
- **Arch 只有 arm64**。Arch Linux ARM 是独立项目，只发 aarch64；官方 x86 版是 `archlinux-bootstrap-x86_64.tar.zst`，`.zst` 应用端不支持。
- **Kali NetHunter 的 rootfs 是给 Termux 用的**。里面可能有预置的 `kali` 用户和 Termux 相关约定，本仓库只重写网络与 locale 配置，其余保持原样。
- **RHEL 系 / openSUSE 装包比 apt 慢**。`dnf` 和 `zypper` 的元数据动辄几十 MB，proot 里更明显；第一次 `install` 慢是正常的。
- **包内不含 `/proc` `/sys` `/dev` 的内容**，这三个由 proot 从宿主机的挂进去。
- **必须用 `.tar.gz` 而不是 `.tar.xz`**。应用端是纯 Java 解压，xz 在手机上慢 5~10 倍（源包是 xz 的，构建时会重新用 gzip 打一遍）。

## 许可证

构建脚本：[MIT](LICENSE)。

各 rootfs 包内的软件分别遵循其原有许可证（Debian / Ubuntu / Alpine / openSUSE / AlmaLinux / OpenCloudOS / Void / Arch Linux ARM / Kali 各自的版权体系），
`/usr/share/doc/*/copyright` 已保留，源码见各发行版官方归档。本项目与上述发行版官方无隶属关系。
