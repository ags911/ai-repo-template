# Image for scripts/local-ci/run.sh: every lane runs in a container from it, so install every
# tool lanes.conf calls. The lane runner needs bash and git.
#
# run.sh tags the image with a hash of this file and of anything in an image/ folder beside
# it (the build context; put files you COPY there). Editing either builds a new image, prunes
# the old one, and reruns every step. Pin versions so a rebuild gives the same tools.
FROM node:26-bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends bash ca-certificates git \
 && rm -rf /var/lib/apt/lists/*

# uv installs the Python version pyproject.toml asks for, during the "sync" step.
COPY --from=ghcr.io/astral-sh/uv:0.11.8 /uv /uvx /usr/local/bin/

# Only the lane's volume (/work, which holds the clone) outlives a container. Keep uv's
# Python and the download caches there, so a resumed lane still finds what earlier steps
# installed, and a new clone reuses the downloads.
ENV UV_PYTHON_INSTALL_DIR=/work/.uv/python \
    UV_CACHE_DIR=/work/.uv/cache \
    npm_config_cache=/work/.npm
