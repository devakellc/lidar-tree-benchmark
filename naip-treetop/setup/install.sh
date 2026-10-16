#!/usr/bin/env bash
# Environment for the NAIP tree-top experiment. Tested on Ubuntu 24.04 (R 4.3.3).
set -euo pipefail

# R and geospatial headers (lidR is optional; the plan does not need it)
sudo apt-get update
sudo apt-get install -y r-base-core r-base-dev r-cran-rcpp r-cran-terra r-cran-sf \
  r-cran-data.table r-cran-clue r-cran-testthat r-cran-jsonlite \
  libgdal-dev libproj-dev libgeos-dev libsqlite3-dev git

# lasR must be the pre-devel build (ws as a function; EPT reader).
tmp=$(mktemp -d)
git clone --depth 1 -b pre-devel https://github.com/r-lidar/lasR "$tmp/lasR"
MAKEFLAGS="-j$(nproc)" sudo R CMD INSTALL "$tmp/lasR"
Rscript -e 'library(lasR); cat("lasR", as.character(packageVersion("lasR")), "\n")'

# Python side (use a venv; install the CUDA torch build that matches the GPU driver)
python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
pip install torch torchvision  # pick the CUDA wheel index for your driver
pip install numpy scipy rasterio pyproj pystac-client planetary-computer transformers pytest
# DINOv3: clone https://github.com/facebookresearch/dinov3 and download the
# ViT-B/16 checkpoint after accepting the licence; the weights are gated.
