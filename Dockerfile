FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    fzf \
    neovim \
    ripgrep \
    build-essential \
    pkg-config \
    libssl-dev \
    cmake \
    clang \
    llvm \
    lld \
    protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf \
    https://sh.rustup.rs | sh -s -- -y

ENV PATH="/root/.cargo/bin:${PATH}"

# Rust components
RUN rustup component add \
    rustfmt \
    clippy

# Install LazyVim
RUN git clone https://github.com/LazyVim/starter /root/.config/nvim \
    && rm -rf /root/.config/nvim/.git

WORKDIR /workspace

CMD ["nvim"]
