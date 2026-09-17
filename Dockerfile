##############################################################################
# 基于 LazyVim 的 Rust 开发容器
#
# 构建（镜像跟人无关，团队里所有人共用同一个镜像，build 一次就够了）：
#   docker build -t rust-lazyvim .
#
# 运行（把当前目录挂进容器的 /workspace）：
#   docker run -it --rm \
#     -v "$(pwd)":/workspace \
#     -v rust-lazyvim-cargo-registry:/home/dev/.cargo/registry \
#     -v rust-lazyvim-cargo-target:/workspace/target \
#     rust-lazyvim
#
# 容器里的用户 UID/GID 会在启动时（entrypoint.sh）自动对齐 /workspace 挂载目录
# 的属主——也就是你宿主机当前用户，不用关心用户名叫什么、不用为每个人重新 build。
# 极少数场景需要手动指定的话，可以 -e LOCAL_UID=xxxx -e LOCAL_GID=xxxx 覆盖。
#
# 进容器后：
#   nvim .        # 打开 LazyVim，第一次进入会自动收尾插件/解析器安装
#   cargo build   # 正常用 cargo
#   <leader>gg    # nvim 里打开 lazygit（<leader>gG 打开当前文件所在目录的 lazygit）
##############################################################################
FROM debian:bookworm-slim

ARG NVIM_VERSION=v0.12.5
ARG LAZYGIT_VERSION=0.65.1
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TERM=xterm-256color

#------------------------------------------------------------------------------
# 系统依赖
#   build-essential/pkg-config/libssl-dev  : 编译大多数纯 Rust / 链接系统 openssl 的 crate
#   git/curl/unzip/xz-utils                 : lazy.nvim、rustup、nvim 安装需要
#   ripgrep/fd-find                         : fzf-lua（LazyVim 默认模糊搜索）依赖
#   cmake                                   : 依赖 CMake 构建的 *-sys crate（如 rocksdb）
#   clang/libclang-dev                      : bindgen 生成 FFI 绑定需要 libclang
#   protobuf-compiler                       : prost-build/tonic-build 编译 .proto 用
#   perl                                    : openssl-sys 开 vendored feature 时需要
# 用不到某个工具的话可以从下面这个列表里删掉对应行，缩小镜像体积
#------------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        libssl-dev \
        cmake \
        clang \
        libclang-dev \
        protobuf-compiler \
        perl \
        git \
        curl \
        unzip \
        xz-utils \
        ripgrep \
        fd-find \
        ca-certificates \
        locales \
        sudo \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

#------------------------------------------------------------------------------
# 安装 Neovim —— apt 源里的版本太旧，rustaceanvim 要求 Neovim >= 0.12
#------------------------------------------------------------------------------
RUN curl -fsSL -o /tmp/nvim.tar.gz \
        "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.tar.gz" \
    && tar -C /opt -xzf /tmp/nvim.tar.gz \
    && ln -s /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim \
    && rm /tmp/nvim.tar.gz

#------------------------------------------------------------------------------
# 安装 lazygit —— LazyVim 核心已经内置了它的按键映射（<leader>gg 等），
# 只要 PATH 上有这个二进制就会自动启用，不需要额外开 extra 或写配置。
# apt 源里没有这个包，直接从 GitHub Releases 拉最新的预编译二进制。
#------------------------------------------------------------------------------
RUN LAZYGIT_ARCH=$(uname -m | sed -e 's/aarch64/arm64/' -e 's/x86_64/x86_64/') \
    && curl -fsSL -o /tmp/lazygit.tar.gz \
        "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_${LAZYGIT_ARCH}.tar.gz" \
    && tar -C /tmp -xzf /tmp/lazygit.tar.gz lazygit \
    && install /tmp/lazygit /usr/local/bin/lazygit \
    && rm -f /tmp/lazygit /tmp/lazygit.tar.gz

#------------------------------------------------------------------------------
# 非 root 用户 —— 这里的 UID/GID 只是镜像里的默认值/占位符，
# 真正生效的值由 entrypoint.sh 在容器启动时按挂载目录动态调整。
# sudoers 规则用 "#UID" 匹配而不是用户名，UID 被 entrypoint 改掉之后依然有效
#------------------------------------------------------------------------------
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} \
    && echo "#${USER_UID} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

USER ${USERNAME}
ENV HOME=/home/${USERNAME} \
    PATH=/home/${USERNAME}/.cargo/bin:$PATH
WORKDIR ${HOME}

#------------------------------------------------------------------------------
# Rust 工具链
#------------------------------------------------------------------------------
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile default \
    && rustup component add rust-analyzer rustfmt clippy

#------------------------------------------------------------------------------
# LazyVim（官方 starter 模板）+ 开启 lang.rust / lang.toml extra
# lang.rust 这个 extra 会自动带上 rustaceanvim、crates.nvim、
# treesitter 的 rust/ron parser，以及 mason 的 codelldb
#------------------------------------------------------------------------------
RUN git clone --depth 1 https://github.com/LazyVim/starter "${HOME}/.config/nvim" \
    && rm -rf "${HOME}/.config/nvim/.git" \
    && printf '%s\n' \
        '{' \
        '  "extras": [' \
        '    "lazyvim.plugins.extras.lang.rust",' \
        '    "lazyvim.plugins.extras.lang.toml"' \
        '  ],' \
        '  "news": {}' \
        '}' > "${HOME}/.config/nvim/lazyvim.json"

# 让 headless 安装 codelldb 时等它真正下载完才退出（Mason 默认是异步安装的）
COPY --chown=${USERNAME}:${USERNAME} mason-install.lua /tmp/mason-install.lua

#------------------------------------------------------------------------------
# 构建期预装插件 + codelldb，容器一起来就是热的（都需要联网）
#------------------------------------------------------------------------------
RUN nvim --headless "+Lazy! sync" +qa \
    && nvim --headless -c "luafile /tmp/mason-install.lua" \
    && nvim --headless -c "TSUpdate" -c "qa" || true

WORKDIR /workspace

#------------------------------------------------------------------------------
# entrypoint 需要以 root 启动，才能在容器启动时 usermod/groupmod 调整 UID/GID，
# 调整完之后再用 runuser 降权到 dev 用户执行真正的命令（nvim/cargo/bash 都不会
# 以 root 身份运行，只有 entrypoint 这一小段初始化逻辑是 root）
#------------------------------------------------------------------------------
USER root
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
