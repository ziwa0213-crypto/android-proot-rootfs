# android-proot-rootfs

[English](README_EN.md) · 简体中文

给 Android 上跑的 [proot](https://proot-me.github.io/) 环境用的 Linux rootfs 镜像。

不需要 root、不需要刷内核，解压即用。每个包都自带 `apt` / `apk`、`ca-certificates` 和一套常用命令行工具，装完就能继续 `apt install` 或 `pip install`。

## 为什么自己做

Android 上现成的 rootfs 包通常有三个毛病：

- **是给容器用的**：缺 `bash`、缺证书、`/etc/resolv.conf` 是指向 `127.0.0.53` 的软链 —— 在 proot 里没有 systemd-resolved，DNS 直接全挂，`apt` / `git` / `pip` 全部连不上网。
- **下载源不稳定**：下到一半断掉，安装时报 `unexpected end of stream` 或者一串看不懂的 tar 解析错误。
- **不知道里面装了什么**：装完才发现没有编辑器、没有 curl、没有证书。

这个仓库从发行版官方归档直接 bootstrap，包的内容、体积、校验和都是确定的，构建过程可复现。

## 用在哪

- [RikkaHub Work](https://github.com/ziwa0213-crypto/rikkahub_work) 的「工作区」—— 安装 rootfs 时直接填下面的下载链接
- Termux 的 proot-distro
- 任何自己拼 proot 启动脚本的场景

## 包清单

五个发行版 × 两个架构 × 三个档位。

| 发行版 | 版本 | 说明 |
|---|---|---|
| Debian | 12 `bookworm` | 支持到 2028-06 |
| Debian | 13 `trixie` | 当前 stable |
| Ubuntu | 24.04 LTS `noble` | RikkaHub 默认下载的就是这个 |
| Ubuntu | 26.04 LTS `resolute` | |
| Alpine | 3.24 | 最小，musl + busybox，不是 glibc |

| 档位 | 体积（arm64，约） | 里面有什么 |
|---|---|---|
| `min` | 4~45 MB | 包管理器 + ca-certificates + tzdata。Debian/Ubuntu 自带 `bash`；**Alpine 的 `min` 只有 busybox `ash`，没有 bash** |
| `base` | 55~75 MB | 加 curl / wget / git / less / vim-tiny / jq / unzip / zip / xz / procps / openssh-client / gnupg / htop / tree / bash-completion |
| `dev` | 170~220 MB | 加 build-essential / gcc / make / python3 / pip / venv / cmake / sqlite3 / 常用 `-dev` 头文件 |

`min ⊂ base ⊂ dev`，后一档包含前一档。

当前实测（arm64）：Alpine 3.22 `min` **4.1 MB**、Ubuntu 24.04 `base` **58 MB**、Debian 12 `base` **70 MB**、Debian 13 `base` **76 MB**。完整清单见 [`docs/包清单.md`](docs/包清单.md)。

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
```

完整步骤、镜像地址、耗时参考和常见错误见 [docs/构建.md](docs/构建.md)。

## 已知限制

- **Alpine 是 musl，不是 glibc**。很多预编译二进制（Python 的 manylinux wheel、部分闭源工具）在它上面装不了。它适合「小、快、够用」，正经开发还是 Debian / Ubuntu。
- **包内不含 `/proc` `/sys` `/dev` 的内容**，这三个由 proot 从宿主机的挂进去。
- **必须用 `.tar.gz` 而不是 `.tar.xz`**。应用端是纯 Java 解压，xz 在手机上慢 5~10 倍。

## 许可证

构建脚本：[MIT](LICENSE)。

各 rootfs 包内的软件分别遵循其原有许可证（Debian / Ubuntu / Alpine 各自的版权体系），
`/usr/share/doc/*/copyright` 已保留，源码见各发行版官方归档。本项目与上述发行版官方无隶属关系。
