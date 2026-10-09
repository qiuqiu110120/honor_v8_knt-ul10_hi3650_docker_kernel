# Honor V8 KNT-UL10 — Docker-capable Kernel (Linux 4.4.197-eco)

为 **荣耀 V8 KNT-UL10 (HiSilicon HI3650)** 适配的、可运行 Docker 的自编译内核。

- 内核: `Linux 4.4.197-eco` (aarch64, GCC 4.9.x)
- 基类: [dcionline/eco_kernel_hi3650_eva](https://github.com/dcionline/eco_kernel_hi3650_eva)（P9/EVA EMUI8 开源内核）
- 分支: `main`
- 稳定版本标识: **crashfix-05**

---

## 1. 为什么做这个内核

原厂/其它自定义内核在开启 Docker 所需能力时，本机（华为汇编 netfilter hook `net_hw_hook_localout`）会出现内核 Oops/开机重启。本内核通过以下方式让 **Docker 能跑且系统稳定**：

1. 保留 Docker 内核前置能力：
   - namespaces：`UTS/IPC/PID/NET_NS`
   - cgroup v1：`cpu / cpuacct / cpuset / blkio / freezer / pids(HW) / devices` + `CFS_BANDWIDTH`
   - `overlayfs`（Docker overlay2 存储）、`seccomp`、`keys`、`devpts 多实例`、`loop`
   - netfilter / conntrack / NAT / iptables（系统原有）
2. 移除会导致厂商汇编 hook 崩溃的网络组：`BRIDGE / VETH / BRIDGE_NETFILTER / NETFILTER_XT_MATCH_ADDRTYPE`
   - 代价：容器网络只能 `--network host`（不能建 bridge/veth 容器网络）
3. 源码补丁（`kernel/cpuset.c`）：
   - 新增 `cpuset.cpus` / `cpuset.mems` 前缀别名
   - 原因：华为以 `cpuset_noprefix` 挂载 cpuset（文件名为 `cpus`/`mems`），而 runc 硬编码访问 `cpuset.cpus`/`cpuset.mems`
   - 补丁后 Android(`cpus`) 与 runc(`cpuset.cpus`) 可同时使用

## 2. 已确认可用

- Android 正常启动、稳定（连续运行无重启）；Wi-Fi/蓝牙/相机/触摸/音频/存储正常
- `dockerd 26.1.4` 运行（overlay2 / cgroupfs v1 / runc-nopivot）
- 容器可运行：`docker run --rm --network host hello-world`、`alpine`
- 外部访问：容器以 `--network host` 监听端口后，局域网可用 `手机IP:端口` 访问（实测 nginx 200）
- 镜像加速：Docker Hub 被墙，已在 `start-docker.sh` 配置国内镜像加速

## 3. 已知限制

- 无容器 bridge/veth 网络 → **只能用 `--network host`**，不能用 `-p` 端口映射
- 无 `MEMCG` → `--memory` 限制无效（dockerd 有告警）
- 无 `USER_NS` → 不支持 rootless Docker
- 无 cgroup v2（仅 v1）
- `dockerd` 非开机自启：每次重启需执行 `start-docker.sh`

## 4. 刷入（fastboot）

```bash
# 设备进 bootloader（Vol- + Power，或 adb reboot bootloader）
fastboot devices
fastboot flash kernel artifacts/boot-knt-ul10-docker-crashfix-05-padded.img
fastboot reboot
```

回滚可用内核：请见 `artifacts/README_DOCKER.md` 或联系维护者。

## 5. 启动 Docker（设备端，root）

把 `artifacts/start-docker.sh` 放到设备上并执行：

```bash
su -c 'sh /data/local/start-docker.sh'
# 验证
docker info
docker run --rm --network host hello-world
```

## 6. 目录结构

```
arch/arm64/configs/knt_ul10_defconfig   # KNT-UL10 专用 defconfig
kernel/cpuset.c                         # 已打 cpuset 别名补丁
artifacts/
  boot-knt-ul10-docker-crashfix-05-padded.img  # 可刷入 kernel 分区的镜像
  Image.gz                                      # 原始内核镜像
  System.map / config-fixed05 / cpuset.c.patched
  start-docker.sh / README_DOCKER.md / ARTIFACTS.txt
```

## 7. 关于

仅供学习研究。刷机有风险，请自行备份原厂镜像并承担风险。
