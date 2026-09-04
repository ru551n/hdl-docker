# hdl-docker

A Docker image bundling [Yosys](https://github.com/YosysHQ/yosys),
[GHDL](https://github.com/ghdl/ghdl), [NVC](https://github.com/nickg/nvc),
[vhdl_ls](https://github.com/VHDL-LS/rust_hdl) and
[veridian](https://github.com/vivekmalneedi/veridian).
GHDL is wired in as a Yosys synthesis plugin via
[ghdl-yosys-plugin](https://github.com/ghdl/ghdl-yosys-plugin), so you can
synthesize VHDL designs directly with `yosys -m ghdl`. NVC is included as a
fast, standalone VHDL simulator alongside GHDL's own simulation mode.
vhdl_ls and veridian are language servers (VHDL and SystemVerilog
respectively) for editor/IDE integration.

## Image

Published to Docker Hub as [`ru551n/hdl-docker`](https://hub.docker.com/r/ru551n/hdl-docker).

Tags:
- `latest` — most recent tagged release
- `vX.Y.Z` — a specific release (matches the git tag)

## Usage

```sh
docker run --rm -it -v "$PWD":/work ru551n/hdl-docker bash

# Inside the container:
ghdl --version
nvc --version
yosys -m ghdl -p 'ghdl design.vhdl -e top; synth_ice40 -json design.json'

# Simulate with NVC instead of/in addition to GHDL:
nvc -a design.vhdl -e top -r

# Language servers (for editor/IDE integration, not typically run by hand):
vhdl_ls --help
veridian --help
```

Or run a single command directly:

```sh
docker run --rm -v "$PWD":/work ru551n/hdl-docker \
    yosys -m ghdl -p 'ghdl design.vhdl -e top; synth_ice40 -json design.json'
```

## Components & versions

Pinned in [`Dockerfile`](./Dockerfile) build args:

| Component          | Source                                                          |
|---------------------|------------------------------------------------------------------|
| GHDL                 | prebuilt release tarball (`mcode` backend)                       |
| Yosys                | built from source at a pinned tag                                 |
| ghdl-yosys-plugin    | built from source against the GHDL/Yosys above, at a pinned ref  |
| NVC                  | prebuilt `.deb` release package                                  |
| vhdl_ls              | prebuilt release zip                                              |
| veridian             | built from source at a pinned commit (no stable releases exist)  |

Install convention: use a prebuilt release when the upstream project
publishes one for Linux x86_64/ubuntu24.04; otherwise build from source at a
pinned tag/commit.

## Building locally

```sh
docker build -t hdl-docker .
```

## Releasing

Pushing a git tag matching `v*` (e.g. `v1.0.0`) triggers
[`.github/workflows/docker-publish.yml`](./.github/workflows/docker-publish.yml),
which builds the image and pushes `ru551n/hdl-docker:vX.Y.Z` and
`ru551n/hdl-docker:latest` to Docker Hub.

This requires the following repository secrets to be set (Settings ->
Secrets and variables -> Actions):

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN` — a Docker Hub [access token](https://hub.docker.com/settings/security)
