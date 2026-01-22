# eDNA metabarcoding pipeline Docker

Docker image and helper scripts to run the eDNA metabarcoding pipeline with conda environments, MEGAN, BLAST, and OBItools.

Set up for: https://github.com/ViralChris/eDNA_metabarcoding_pipeline_V2

## Quick start
- Place `micromamba-2.4.0-1.tar.bz2` and `MEGAN_Community_unix_6_25_10.sh` in this directory.
- Build: `./setup_edna.sh build`
- Run (interactive): `./setup_edna.sh run`
- Persistent container: `./run.sh` (or just use your own docker commands)
- Rebuild (clean): `./delete_and_rebuild_container.sh`

## Changing BLAST DB and MEGAN locations
- BLAST DB mount: use `--blastdb HOST[:CONTAINER]` on `run.sh`/`setup_edna.sh`, or edit `HOST_BLASTDB`/`CONTAINER_BLASTDB` in `run.sh` and `BLASTDB_HOST`/`BLASTDB_CONTAINER` in `setup_edna.sh`.
- BLASTDB env: use `--blastdb-env VALUE` on `run.sh`/`setup_edna.sh`, or edit `BLASTDB_ENV` in those scripts.
- MEGAN install location: edit the `--prefix /opt/megan` argument in `dockerfile`, then rebuild.

## Defaults
- Host data mount: `/home/deegc@ENT/Documents/01_eDNA` -> `/opt/eDNA/01_eDNA`
- BLAST DB mount: `/data/blastdb` -> `/opt/eDNA/blastdb`
- MEGAN installs to `/opt/megan` and is on `PATH`.
- Image tag: `edna_pipeline:latest`
- Container name: `edna_session`
- BLASTDB env: `/opt/eDNA/blastdb/ntdatabase:/opt/eDNA/blastdb/IYS_APC`

## Script flags

### setup_edna.sh
Usage:
```
./setup_edna.sh build [--tag TAG] [--micromamba-file FILE] [--megan-file FILE] [--no-cache]
./setup_edna.sh run   [--tag TAG] [--micromamba-file FILE] [--mount HOST[:CONTAINER]] [--blastdb HOST[:CONTAINER]] [--blastdb-env VALUE] [--megan-file FILE] [--no-cache]
./setup_edna.sh build-and-run ...
```

Flags:
- `--tag TAG` Image tag (default: `edna_pipeline:latest`).
- `--micromamba-file FILE` Local micromamba tar.bz2 filename (default: `micromamba-2.4.0-1.tar.bz2`).
- `--megan-file FILE` MEGAN installer `.sh` filename in build context (default: `MEGAN_Community_unix_6_25_10.sh`).
- `--mount HOST[:CONTAINER]` Host path to mount; if only HOST is provided, it mounts to `/opt/eDNA/01_eDNA`. Mounting over `/opt/eDNA` is blocked.
- `--blastdb HOST[:CONTAINER]` Host BLAST DB path to mount (default: `/data/blastdb` -> `/opt/eDNA/blastdb`).
- `--blastdb-env VALUE` BLASTDB env value (default: `/opt/eDNA/blastdb/ntdatabase:/opt/eDNA/blastdb/IYS_APC`).
- `--no-cache` Force a fresh Docker build.

### run.sh
Usage:
```
./run.sh [--data HOST[:CONTAINER]] [--blastdb HOST[:CONTAINER]] [--blastdb-env VALUE] [HOST_DATA_DIR]
```

Behavior:
- Creates/starts a persistent container `edna_session` (detached).
- If a TTY is available, it execs into the container; otherwise it exits after starting it.
- Default host data dir: `/home/deegc@ENT/Documents/01_eDNA` -> `/opt/eDNA/01_eDNA`.
- Default BLAST DB mount: `/data/blastdb` -> `/opt/eDNA/blastdb`.

## MEGAN install automation
- The MEGAN installer is driven by piped `printf` responses during the Docker build to accept prompts and defaults.

## Python/R
- Python 3 env: `edna`
- Python 2 env: `py2`
- `python2` wrapper runs `/opt/conda/envs/py2/bin/python`.
- OBItools are exposed on `PATH` (symlinked from `py2`).

## Notes
- Licensed installers (`MEGAN_Community_unix_6_25_10.sh`) and the micromamba tarball are excluded from git.
