# Docker on Honor V8 KNT-UL10 — 成功方案（Phase 36 最终）

- 日期: 2026-10-07
- 结果: **Docker Engine 26.1.4 可运行容器**（`hello-world` / `alpine` 均成功，cgroup 隔离生效）

## 1. 内核（已刷入并稳定）
- 镜像: `kernel-docker-crash-fix/boot/boot-knt-ul10-docker-crashfix-05-padded.img`
  - sha256 `50ba26a83ed324d77488b21e47e8682ffcbb82b56a7acbdf85dfad2a6a85f699`
- 版本 `4.4.197-eco`（2026-10-07 23:03 构建），头参数/cmdline 与正常镜像一致
- 关键配置:
  - `CONFIG_NAMESPACES=y` + `UTS_NS/IPC_NS/PID_NS/NET_NS=y`
  - `CONFIG_CGROUPS=y`, `CGROUP_SCHED=y`, `CGROUP_CPUACCT=y`, `CPUSETS=y`, `CGROUP_DEVICE=y`, `CGROUP_FREEZER=y`, `HW_CGROUP_PIDS=y`, `CFS_BANDWIDTH=y`
  - `CONFIG_OVERLAY_FS=y`, `SECCOMP=y`, `KEYS=y`, `TMPFS=y`, `DEVPTS_MULTIPLE_INSTANCES=y`, `BLK_DEV_LOOP=y`, `EXT4_FS=y`
  - netfilter/conntrack/NAT/iptables（基线已有）
- **源码补丁**: `patches/cpuset.c.patched`（唯一改动）
  - 在 `kernel/cpuset.c` 的 cpuset 文件表中，新增 `cpuset.cpus` / `cpuset.mems` 别名（index 与原有 `cpus`/`mems` 相同处理函数）。
  - 原因: 华为以 `cpuset_noprefix` 挂载 cpuset，文件名为 `cpus`/`mems`；而 runc 硬编码访问 `cpuset.cpus`/`cpuset.mems` → 找不到。加别名后 Android(`cpus`) 与 runc(`cpuset.cpus`) 同时可用。

## 2. 为什么之前崩溃（根因链）
1. 最初 Docker 配置加了 `NET_NS` + `VETH/BRIDGE/BRIDGE_NETFILTER/NETFILTER_XT_MATCH_ADDRTYPE`；其中网络组触发华为**手写汇编 netfilter hook** `net_hw_hook_localout` 空指针 Oops → `Kernel panic` → bootloop/重启。
2. 二分结论: **`NET_NS` 单独安全**（crashfix-04 验证）；崩溃来自 `VETH/BRIDGE/...` 组。
3. `MEMCG/CGROUP_DEVICE` 与崩溃无关（曾误判）。

## 3. 用户态（chroot / 容器运行时）
设备内有 `/data/local/ubuntu-rootfs`（Ubuntu 24.04），Docker 26.1.4 + containerd 1.7.18 + runc 1.1.12。
使用脚本 **`docker-kernel-work/start-docker.sh`**（已推送到设备 `/data/local/tmp/start-docker.sh`）完成：
1. 挂载 Ubuntu chroot（`sh /data/local/ubuntu start`）。
2. 安装 `runc --no-pivot` wrapper（`/usr/bin/runc-nopivot`）——解决 chroot 内 `pivot_root: invalid argument`。
3. 写 `daemon.json`：国内 **registry-mirrors**（docker.m.daocloud.io / 1ms.run / 1panel.live / dockerproxy.net）+ `default-runtime=runc-nopivot`。
   - 因 Docker Hub 被墙，镜像加速必需。
4. 在 chroot 挂载 ns 内挂 cgroup：`tmpfs /sys` → `mkdir /sys/fs/cgroup` → 挂 `cpuacct cpu cpuset blkio freezer pids devices`（避开 Android 的新 sysfs 无 `/sys/fs/cgroup` 问题）。
5. 启动 `dockerd --iptables=false --ip-forward=false --bridge=none`。

## 4. 验证结果
```
docker version            -> client=26.1.4 server=26.1.4
docker info               -> Storage=overlay2(backing f2fs) Cgroup=cgroupfs/v1 Kernel=4.4.197-eco
docker run --rm --network host hello-world   -> Hello from Docker!
docker run --rm --network host alpine uname  -> Linux ... aarch64
容器内 /proc/self/cgroup  -> 9:devices:/docker/<id>  8:pids:...  7:freezer:...
```

## 5. 限制 / 已知缺陷
- **无容器网络命名空间之外的容器网络**: 已移除 `VETH/BRIDGE`（其触发华为汇编 hook Oops）→ Docker **只能 `--network host`**；不能使用默认 bridge/自定义网络/端口映射。
- **无内存 cgroup**: 未启用 `MEMCG` → `--memory` 限制无效（dockerd 有告警）。
- **无 USER_NS**: 不支持 rootless Docker。
- **无 cgroup v2**: 仅 v1（cgroupfs）。
- **dockerd 非开机自启**: 每次重启需运行 `start-docker.sh`（chroot cgroup 挂载是运行时的）。
- runc 必须走 `--no-pivot` wrapper（chroot 内 pivot_root 不可用）。

## 6. 回滚
- 正常内核: `work/plan2/output/boot-knt-ul10-custom-padded.img`（sha `9b24d8af…`）
- 或原厂: `backup/kernel.img`（sha `71a3c8bd…`）
- 刷写: `fastboot flash kernel <img>`

## 7. 产物清单
- 内核补丁: `kernel-docker-crash-fix/patches/cpuset.c.patched`
- 配置: `configs/config-fixed03/04/05.config`
- boot 镜像: `boot/boot-knt-ul10-docker-crashfix-0{1..5}[-padded].img`
- 启动脚本: `docker-kernel-work/start-docker.sh`
- 崩溃证据: `investigation/pstore-crash-20261007/`、`investigation/pstore-crash2-20261007/`
