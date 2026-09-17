#!/usr/bin/env bash
# 容器启动时跑一次，把镜像里固定叫 "dev" 的这个账号的 UID/GID
# 对齐到当前是谁在跑这个容器 —— 不管宿主机上那个人的用户名叫什么，
# 只要 /workspace 挂载目录本身的属主 UID/GID 是对的，这里就自动跟着对。
#
# 优先级：显式传入的 LOCAL_UID/LOCAL_GID > /workspace 目录的属主 > 默认 1000
set -euo pipefail

USERNAME=dev
WORKDIR=/workspace

DETECTED_UID="$(stat -c '%u' "$WORKDIR" 2>/dev/null || echo 1000)"
DETECTED_GID="$(stat -c '%g' "$WORKDIR" 2>/dev/null || echo 1000)"

# /workspace 没挂载真实目录进来的话，属主是 root(0)——这种情况不能照抄，
# 否则容器里的 dev 账号就变成 UID 0，等价于 root 了
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

# UID/GID 变过之后，家目录（含 ~/.cargo、~/.rustup、~/.config/nvim 等）
# 原来属主是旧 UID，要一并改掉，否则 dev 用户反而读不到自己的东西
if [ "$TARGET_UID" != "$CURRENT_UID" ] || [ "$TARGET_GID" != "$CURRENT_GID" ]; then
    chown -R "$TARGET_UID:$TARGET_GID" "/home/${USERNAME}" 2>/dev/null || true
fi

# sudoers 规则按新 UID 重新写一份（构建时写的是镜像默认 UID，这里要跟着更新）
echo "#${TARGET_UID} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"
chmod 0440 "/etc/sudoers.d/${USERNAME}"

# 降权到 dev 用户执行真正的命令（默认是 CMD ["bash"]）
exec runuser -u "$USERNAME" -- "$@"
