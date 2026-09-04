# syntax=docker/dockerfile:1
#
# hdl-docker: Yosys + GHDL, with GHDL loaded into Yosys as a synthesis
# frontend via ghdl-yosys-plugin (VHDL -> Yosys netlist).
#
# Install convention: grab a prebuilt release for a tool if the upstream
# project publishes one for our target (Linux x86_64/ubuntu24.04); otherwise
# build it from source at a pinned tag/commit. Every version is pinned to
# the latest available tag (or, for tools with no stable releases, the
# latest commit) at the time this image was last updated.
#
# Pinned component versions:
#   - GHDL:                prebuilt release tarball (mcode backend, no LLVM/GNAT needed at runtime)
#   - Yosys:                built from source at a pinned tag (no prebuilt releases published)
#   - ghdl-yosys-plugin:    built from source against the two above, at a pinned ref (no prebuilt releases)
#   - NVC:                  prebuilt .deb release package (standalone VHDL simulator)
#   - vhdl_ls:               prebuilt release zip (VHDL language server, bundles vhdl_libraries)
#   - veridian:              built from source at a pinned commit (SystemVerilog language server;
#                            upstream only publishes a mutable "nightly" prerelease, no stable tags)

ARG GHDL_VERSION=6.0.0
ARG YOSYS_VERSION=v0.68
ARG GHDL_YOSYS_PLUGIN_REF=ghdl-v6.0.0
ARG NVC_VERSION=1.22.1
ARG VHDL_LS_VERSION=0.88.0
ARG VERIDIAN_REF=0c5776a4a4e08fd00b90d91ad3cd2ec10315d2bd

ARG GHDL_PREFIX=/opt/ghdl
ARG YOSYS_PREFIX=/opt/yosys
ARG VHDL_LS_PREFIX=/opt/vhdl_ls
ARG VERIDIAN_PREFIX=/opt/veridian

##############################################################################
# Stage: fetch prebuilt GHDL (mcode backend, relocatable, ubuntu24.04 x86_64)
##############################################################################
FROM ubuntu:24.04 AS ghdl-fetch
ARG GHDL_VERSION
ARG GHDL_PREFIX

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/ghdl.tar.gz \
        "https://github.com/ghdl/ghdl/releases/download/v${GHDL_VERSION}/ghdl-mcode-${GHDL_VERSION}-ubuntu24.04-x86_64.tar.gz" \
    && mkdir -p "${GHDL_PREFIX}" \
    && tar -xzf /tmp/ghdl.tar.gz --strip-components=1 -C "${GHDL_PREFIX}" \
    && rm /tmp/ghdl.tar.gz \
    && "${GHDL_PREFIX}/bin/ghdl" --version

##############################################################################
# Stage: fetch prebuilt NVC .deb (standalone VHDL simulator, unrelated to GHDL)
##############################################################################
FROM ubuntu:24.04 AS nvc-fetch
ARG NVC_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/nvc.deb \
        "https://github.com/nickg/nvc/releases/download/r${NVC_VERSION}/nvc_${NVC_VERSION}-1_amd64_ubuntu-24.04.deb"

##############################################################################
# Stage: fetch prebuilt vhdl_ls (VHDL language server; zip bundles bin/ and
# vhdl_libraries/ side by side, which is exactly the layout vhdl_ls expects
# relative to its own binary)
##############################################################################
FROM ubuntu:24.04 AS vhdl-ls-fetch
ARG VHDL_LS_VERSION
ARG VHDL_LS_PREFIX

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/vhdl_ls.zip \
        "https://github.com/VHDL-LS/rust_hdl/releases/download/v${VHDL_LS_VERSION}/vhdl_ls-x86_64-unknown-linux-gnu.zip" \
    && mkdir -p /tmp/vhdl_ls_extract "${VHDL_LS_PREFIX}" \
    && unzip -q /tmp/vhdl_ls.zip -d /tmp/vhdl_ls_extract \
    && mv /tmp/vhdl_ls_extract/vhdl_ls-x86_64-unknown-linux-gnu/* "${VHDL_LS_PREFIX}/" \
    && chmod +x "${VHDL_LS_PREFIX}/bin/vhdl_ls" \
    && rm -rf /tmp/vhdl_ls.zip /tmp/vhdl_ls_extract \
    && "${VHDL_LS_PREFIX}/bin/vhdl_ls" --help > /dev/null

##############################################################################
# Stage: build Yosys from source
##############################################################################
FROM ubuntu:24.04 AS yosys-build
ARG YOSYS_VERSION
ARG YOSYS_PREFIX

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git gawk cmake make python3 bison flex g++ pkg-config \
        libffi-dev libfl-dev libreadline-dev tcl-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${YOSYS_VERSION}" --recurse-submodules --shallow-submodules \
        https://github.com/YosysHQ/yosys.git /src/yosys

WORKDIR /src/yosys
RUN cmake -B build . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${YOSYS_PREFIX}" \
    && cmake --build build --parallel "$(nproc)" \
    && cmake --install build --strip

##############################################################################
# Stage: build ghdl-yosys-plugin against the GHDL + Yosys above
##############################################################################
FROM ubuntu:24.04 AS plugin-build
ARG GHDL_YOSYS_PLUGIN_REF
ARG GHDL_PREFIX
ARG YOSYS_PREFIX

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git make g++ pkg-config \
        libffi-dev libreadline-dev tcl-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghdl-fetch ${GHDL_PREFIX} ${GHDL_PREFIX}
COPY --from=yosys-build ${YOSYS_PREFIX} ${YOSYS_PREFIX}
ENV PATH="${YOSYS_PREFIX}/bin:${GHDL_PREFIX}/bin:${PATH}"

RUN git clone https://github.com/ghdl/ghdl-yosys-plugin.git /src/ghdl-yosys-plugin \
    && cd /src/ghdl-yosys-plugin \
    && git checkout "${GHDL_YOSYS_PLUGIN_REF}"

WORKDIR /src/ghdl-yosys-plugin
RUN make GHDL=ghdl YOSYS_CONFIG=yosys-config \
    && mkdir -p /opt/plugin \
    && cp ghdl.so /opt/plugin/ghdl.so

##############################################################################
# Stage: build veridian from source (SystemVerilog language server). No
# stable release exists upstream (only a mutable "nightly" prerelease tag
# whose asset gets overwritten in place), so pin to a specific commit SHA
# instead for reproducible builds.
#
# Toolchain pinned to 1.82.0 (not "stable"): veridian's transitive
# dependency sv-parser 0.8.3 (unmaintained) has an ambiguous glob
# re-export that current stable rustc now rejects as a hard error (E0659,
# https://github.com/rust-lang/rust/issues/145575) - this used to be
# tolerated. 1.82.0 predates that resolver change.
# `cargo install --locked` (below) is required too: without it, cargo
# re-resolves dependencies against current crates.io and picks a newer
# `idna_adapter` that requires the (still-unstable-on-1.82.0) edition2024
# Cargo feature. The pinned commit's checked-in Cargo.lock predates that
# dependency entirely.
##############################################################################
FROM ubuntu:24.04 AS veridian-build
ARG VERIDIAN_REF
ARG VERIDIAN_PREFIX
ARG VERIDIAN_RUST_VERSION=1.82.0

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git build-essential pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --default-toolchain "${VERIDIAN_RUST_VERSION}"
ENV PATH="/root/.cargo/bin:${PATH}"

RUN git clone https://github.com/vivekmalneedi/veridian.git /src/veridian \
    && cd /src/veridian \
    && git checkout "${VERIDIAN_REF}"

WORKDIR /src/veridian
RUN cargo install --locked --path . --root "${VERIDIAN_PREFIX}" \
    && "${VERIDIAN_PREFIX}/bin/veridian" --help > /dev/null

##############################################################################
# Stage: final runtime image
##############################################################################
FROM ubuntu:24.04 AS final
ARG GHDL_PREFIX
ARG YOSYS_PREFIX
ARG VHDL_LS_PREFIX
ARG VERIDIAN_PREFIX

LABEL org.opencontainers.image.title="hdl-docker" \
      org.opencontainers.image.description="Yosys + GHDL, with GHDL wired in as a Yosys synthesis plugin (VHDL synthesis)" \
      org.opencontainers.image.source="https://github.com/ru551n/hdl-docker"

COPY --from=nvc-fetch /tmp/nvc.deb /tmp/nvc.deb

RUN apt-get update && apt-get install -y --no-install-recommends \
        libffi8 zlib1g libtcl8.6 libreadline8 libtinfo6 ca-certificates \
        libgnat-13 \
        /tmp/nvc.deb \
    && rm -rf /var/lib/apt/lists/* /tmp/nvc.deb \
    && useradd --create-home --shell /bin/bash hdl

COPY --from=ghdl-fetch ${GHDL_PREFIX} ${GHDL_PREFIX}
COPY --from=yosys-build ${YOSYS_PREFIX} ${YOSYS_PREFIX}
COPY --from=plugin-build /opt/plugin/ghdl.so ${YOSYS_PREFIX}/share/yosys/plugins/ghdl.so
COPY --from=vhdl-ls-fetch ${VHDL_LS_PREFIX} ${VHDL_LS_PREFIX}
COPY --from=veridian-build ${VERIDIAN_PREFIX} ${VERIDIAN_PREFIX}

ENV PATH="${YOSYS_PREFIX}/bin:${GHDL_PREFIX}/bin:${VHDL_LS_PREFIX}/bin:${VERIDIAN_PREFIX}/bin:${PATH}"

# Sanity checks: the ghdl plugin loads cleanly inside yosys, and the
# simulators/language servers all start up.
RUN yosys -m ghdl -p 'help ghdl' > /dev/null \
    && nvc --version \
    && vhdl_ls --help > /dev/null \
    && veridian --help > /dev/null

WORKDIR /work
USER hdl

CMD ["bash"]
