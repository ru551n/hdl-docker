# syntax=docker/dockerfile:1
#
# hdl-docker: Yosys + GHDL, with GHDL loaded into Yosys as a synthesis
# frontend via ghdl-yosys-plugin (VHDL -> Yosys netlist).
#
# Pinned component versions:
#   - GHDL:              prebuilt release tarball (mcode backend, no LLVM/GNAT needed at runtime)
#   - Yosys:              built from source at a pinned tag
#   - ghdl-yosys-plugin:  built from source against the two above, at a pinned ref
#   - NVC:                prebuilt .deb release package (standalone VHDL simulator)

ARG GHDL_VERSION=6.0.0
ARG YOSYS_VERSION=v0.68
ARG GHDL_YOSYS_PLUGIN_REF=ghdl-v6.0.0
ARG NVC_VERSION=1.22.1

ARG GHDL_PREFIX=/opt/ghdl
ARG YOSYS_PREFIX=/opt/yosys

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
# Stage: build ghdl-yosys-plugin against the GHDL + Yosys built above
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
# Stage: final runtime image
##############################################################################
FROM ubuntu:24.04 AS final
ARG GHDL_PREFIX
ARG YOSYS_PREFIX

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

ENV PATH="${YOSYS_PREFIX}/bin:${GHDL_PREFIX}/bin:${PATH}"

# Sanity checks: the ghdl plugin loads cleanly inside yosys, and nvc runs.
RUN yosys -m ghdl -p 'help ghdl' > /dev/null \
    && nvc --version

WORKDIR /work
USER hdl

CMD ["bash"]
