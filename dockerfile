# Complete Dockerfile — flattens the cloned repo into /opt/eDNA and provides a robust micromamba-based entrypoint.
# Expects a local micromamba tarball in the build context (default name via --build-arg MICROMAMBA_FILE).
FROM ubuntu:22.04

LABEL maintainer="Carl Llewellyn"

ENV DEBIAN_FRONTEND=noninteractive
ENV MAMBA_DIR=/opt/conda
ENV PATH=$MAMBA_DIR/bin:$PATH
ENV MICROMAMBA_BIN=/usr/local/bin/micromamba

# Install system packages (including BLAST via apt) and utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git bzip2 tar xz-utils build-essential \
    default-jre unzip libxml2-dev zlib1g-dev pkg-config ncbi-blast+ \
    python3-pip nano vim && \
    rm -rf /var/lib/apt/lists/*

# Copy local micromamba tarball into the image and extract the micromamba binary.
# Provide the tarball name with --build-arg MICROMAMBA_FILE=micromamba-2.4.0-1.tar.bz2
ARG MICROMAMBA_FILE=micromamba-2.4.0-1.tar.bz2
COPY ${MICROMAMBA_FILE} /tmp/micromamba.tar.bz2

RUN mkdir -p /opt/micromamba && \
    tar -xjf /tmp/micromamba.tar.bz2 -C /opt/micromamba && \
    find /opt/micromamba -type f -name micromamba -exec mv {} ${MICROMAMBA_BIN} \; && \
    chmod +x ${MICROMAMBA_BIN} && \
    rm -rf /opt/micromamba /tmp/micromamba.tar.bz2

# Create a conda prefix with mamba using micromamba (prefix install)
RUN ${MICROMAMBA_BIN} create -y -p $MAMBA_DIR python=3.10 mamba -c conda-forge && \
    rm -rf /root/.cache

SHELL ["/bin/bash", "-lc"]
ENV MAMBA_EXE="$MAMBA_DIR/bin/mamba"

# Force conda-forge + bioconda only for reproducible resolution
RUN printf "channels:\n  - conda-forge\n  - bioconda\nchannel_priority: strict\n" > $MAMBA_DIR/.condarc && chmod 0644 $MAMBA_DIR/.condarc

# Create Python3 environment 'edna' for Python 3 tools.
# Keep obitools (Python2) out of this env.
RUN $MAMBA_EXE create -y -n edna \
      python=3.10 \
      vsearch \
      cutadapt \
      swarm \
      r-base \
      r-rcolorbrewer \
      r-dplyr \
      r-stringr \
      r-tidyverse \
      biopython \
      -c conda-forge -c bioconda

# Create Python2 env 'py2' for obitools and legacy Python2-only packages.
RUN $MAMBA_EXE create -y -n py2 python=2.7 obitools cython biopython=1.76 -c conda-forge -c bioconda

# Clean caches
RUN $MAMBA_EXE clean -afy || true

# Expose OBItools commands on PATH with their normal names.
RUN for f in /opt/conda/envs/py2/bin/obi*; do \
      if [ -f "$f" ]; then ln -sf "$f" "/usr/local/bin/$(basename "$f")"; fi; \
    done

# Convenience wrapper to run Python 2 scripts from the py2 env.
RUN printf '%s\n' "#!/bin/sh" \
  "exec /opt/conda/envs/py2/bin/python \"\$@\"" > /usr/local/bin/python2 && \
  chmod +x /usr/local/bin/python2

# Create robust entrypoint that initializes micromamba safely and activates edna (non-fatal)
RUN printf '%s\n' "#!/bin/bash" \
    "# Robust micromamba entrypoint: initialize shell hook and try to activate edna (do not fail on issues)" \
    "set -e" \
    "" \
    "# If micromamba exists initialize shell hook safely (avoid nounset failures from the hook)" \
    "if command -v ${MICROMAMBA_BIN} >/dev/null 2>&1; then" \
    "  # disable nounset while running the hook (the hook may reference variables not yet set)" \
    "  set +u || true" \
    "  eval \"\$(${MICROMAMBA_BIN} shell hook -s bash)\" || true" \
    "  # ensure variable that some hooks reference exists" \
    "  export MAMBA_ROOT_PREFIX=\"${MAMBA_DIR}\"" \
    "  # attempt to activate the edna env; don't abort if activation fails" \
    "  micromamba activate -p ${MAMBA_DIR} -n edna >/dev/null 2>&1 || true" \
    "  # re-enable nounset for safety in remainder of script" \
    "  set -u || true" \
    "fi" \
    "" \
    "exec \"\$@\"" > /usr/local/bin/edna-entrypoint.sh && chmod +x /usr/local/bin/edna-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/edna-entrypoint.sh"]
CMD ["bash"]

# Clone the pipeline repo into a temporary location and flatten into /opt/eDNA.
# This handles repos whose top-level content is inside a folder named eDNA_metabarcoding_pipeline_V2.
ARG REPO_URL="https://github.com/ViralChris/eDNA_metabarcoding_pipeline_V2.git"
ARG REPO_REF="5e509b4f46eb67e32a90bfb38ffbd1c61d2a050b"
RUN rm -rf /tmp/repo && \
    git clone "${REPO_URL}" /tmp/repo && \
    cd /tmp/repo && git fetch --all --tags && git checkout "${REPO_REF}" || true && \
    mkdir -p /opt/eDNA && \
    if [ -d /tmp/repo/eDNA_metabarcoding_pipeline_V2 ]; then \
        cp -a /tmp/repo/eDNA_metabarcoding_pipeline_V2/. /opt/eDNA/ ; \
    else \
        cp -a /tmp/repo/. /opt/eDNA/ ; \
    fi && \
    rm -rf /tmp/repo

# Ensure expected data directories exist so users can mount into them without hiding the repo.
RUN mkdir -p /opt/eDNA/02_raw_data /opt/eDNA/01_eDNA /opt/eDNA/blastdb && chown -R root:root /opt/eDNA

WORKDIR /opt/eDNA

# Mandatory MEGAN installation at build-time using local installer .sh in build context.
ARG MEGAN_INSTALLER_FILE="MEGAN_Community_unix_6_25_10.sh"
COPY ${MEGAN_INSTALLER_FILE} /tmp/megan_installer.sh
RUN if [ -z "$MEGAN_INSTALLER_FILE" ]; then \
      echo "ERROR: MEGAN_INSTALLER_FILE is required (provide --build-arg MEGAN_INSTALLER_FILE=...)" >&2; \
      exit 10; \
    fi && \
    chmod +x /tmp/megan_installer.sh && \
    printf 'o\n1\n\n\n\n\n\nn' | bash /tmp/megan_installer.sh --mode unattended --prefix /opt/megan && \
    rm -f /tmp/megan_installer.sh

ENV PATH=/opt/megan/bin:/opt/conda/envs/edna/bin:$PATH

# Final smoke checks (non-fatal) using micromamba run to avoid relying on conda shell state.
RUN bash -lc "\
  echo '--- smoke checks ---'; \
  if command -v ${MICROMAMBA_BIN} >/dev/null 2>&1; then \
    eval \"\$(${MICROMAMBA_BIN} shell hook -s bash)\" || true; \
    echo 'envs:'; micromamba env list -p ${MAMBA_DIR} || true; \
    echo 'edna (py3) python:'; micromamba run -p ${MAMBA_DIR} -n edna -- python --version || true; \
    micromamba run -p ${MAMBA_DIR} -n edna -- vsearch --version || echo 'vsearch missing'; \
    micromamba run -p ${MAMBA_DIR} -n edna -- cutadapt --version || echo 'cutadapt missing'; \
    echo 'py2 (obitools) python:'; micromamba run -p ${MAMBA_DIR} -n py2 -- python --version || true; \
  else \
    echo 'micromamba not found'; \
  fi; \
  echo 'BLAST (apt):'; blastn -version || true; \
  echo '--- done ---'"
