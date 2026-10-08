#!/system/bin/sh
# Phase36 - Start Docker (Honor V8 KNT-UL10) inside the Ubuntu chroot.
# Requires kernel crashfix-05 (NET_NS + cgroup devices + cpuset prefix alias).
R=/data/local/ubuntu-rootfs
echo "[1] mount Ubuntu chroot"
sh /data/local/ubuntu start >/dev/null 2>&1
sleep 2

echo "[2] install runc --no-pivot wrapper"
cat > "$R/usr/bin/runc-nopivot" <<'EOF'
#!/bin/bash
args=("$@"); out=(); ins=0
for a in "${args[@]}"; do
  out+=("$a")
  if [ "$ins" -eq 0 ]; then
    case "$a" in create|run|restore) out+=("--no-pivot"); ins=1 ;; esac
  fi
done
exec /usr/bin/runc "${out[@]}"
EOF
chmod 755 "$R/usr/bin/runc-nopivot"

echo "[3] write daemon.json (mirror + default runtime)"
printf '%s\n' '{"registry-mirrors":["https://docker.m.daocloud.io","https://docker.1ms.run","https://docker.1panel.live","https://dockerproxy.net"],"default-runtime":"runc-nopivot","runtimes":{"runc-nopivot":{"path":"/usr/bin/runc-nopivot"}}}' > "$R/etc/docker/daemon.json"

echo "[4] start dockerd (cgroup mounts inside chroot view)"
chroot "$R" /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
mount -t tmpfs tmpfs /sys 2>/dev/null
mkdir -p /sys/fs/cgroup
for c in cpuacct cpu cpuset blkio freezer pids devices; do mkdir -p /sys/fs/cgroup/$c; mount -t cgroup -o $c none /sys/fs/cgroup/$c 2>/dev/null; done
pkill -x dockerd 2>/dev/null; pkill -x containerd 2>/dev/null; sleep 1
setsid dockerd --iptables=false --ip-forward=false --bridge=none >/tmp/dockerd.log 2>&1 </dev/null &
sleep 6
docker info --format "OK server={{.ServerVersion}} storage={{.Driver}} runtime={{.DefaultRuntime}}" 2>&1'
echo "[done]"
