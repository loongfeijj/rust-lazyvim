#!/usr/bin/env bash
# 容器启动时跑一次，把镜像构建时配置的账号（默认 dev）的 UID/GID
# 对齐到当前是谁在跑这个容器 —— 不管宿主机上那个人的用户名叫什么，
# 只要 /workspace 挂载目录本身的属主 UID/GID 是对的，这里就自动跟着对。
#
# 优先级：显式传入的 LOCAL_UID/LOCAL_GID > /workspace 目录的属主 > 默认 1000
set -euo pipefail

USERNAME="${USERNAME:-dev}"
WORKDIR=/workspace

DETECTED_UID="$(stat -c '%u' "$WORKDIR" 2>/dev/null || echo 1000)"
DETECTED_GID="$(stat -c '%g' "$WORKDIR" 2>/dev/null || echo 1000)"

# /workspace 没挂载真实目录进来的话，属主是 root(0)——这种情况不能照抄，
# 否则容器里的开发账号就变成 UID 0，等价于 root 了
[ "$DETECTED_UID" = "0" ] && DETECTED_UID=1000
[ "$DETECTED_GID" = "0" ] && DETECTED_GID=1000

TARGET_UID="${LOCAL_UID:-$DETECTED_UID}"
TARGET_GID="${LOCAL_GID:-$DETECTED_GID}"

CURRENT_UID="$(id -u "$USERNAME")"
CURRENT_GID="$(id -g "$USERNAME")"

if [ "$TARGET_GID" != "$CURRENT_GID" ]; then
    groupmod -o -g "$TARGET_GID" "$USERNAME"
fi

if [ "$TARGET_UID" != "$CURRENT_UID" ]; then
    usermod -o -u "$TARGET_UID" "$USERNAME"
fi

# UID/GID 变化时，修复家目录里仍属于旧 UID/GID 的用户文件。
if [ "$TARGET_UID" != "$CURRENT_UID" ] || [ "$TARGET_GID" != "$CURRENT_GID" ]; then
    chown -R "$TARGET_UID:$TARGET_GID" "/home/${USERNAME}"
fi

# 独立挂载的缓存 volume 可能由 root 创建，即使 UID/GID 没变也需要修复。
# 只处理这两个缓存挂载点，避免递归修改 /workspace 中宿主机项目文件的属主。
for cache_dir in "/home/${USERNAME}/.cargo/registry" "$WORKDIR/target"; do
    if mountpoint -q "$cache_dir"; then
        chown -R "$TARGET_UID:$TARGET_GID" "$cache_dir"
    fi
done

# sudoers 规则按新 UID 重新写一份（构建时写的是镜像默认 UID，这里要跟着更新）
echo "#${TARGET_UID} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"
chmod 0440 "/etc/sudoers.d/${USERNAME}"

# 降权到配置的用户执行真正的命令（默认是 CMD ["bash"]）
exec runuser -u "$USERNAME" -- "$@"
