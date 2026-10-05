# Clean-machine environment for scripts/reproduce_paper_tables.sh. Ubuntu
# 24.04's R 4.3.3 with its system GDAL 3.8.4, GEOS 3.12.1 and PROJ 9.4.0, as
# on the benchmark workstation, and the R packages pinned to the versions the
# tables were computed with (docs/model-provenance.json). CPU only.
#   docker build -t lidar-tree-benchmark-reproduce reproduce
#   docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/repo:ro \
#     -v <archive>:/archive:ro -v <parent of OUT>:/out \
#     lidar-tree-benchmark-reproduce \
#     bash scripts/reproduce_paper_tables.sh ARCHIVE=/archive OUT=/out/run CORES=8
FROM ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive
ARG PPM_SNAPSHOT=https://packagemanager.posit.co/cran/__linux__/noble/2026-10-01
ARG LASR_REF=34a79f05ed61f0f443f2833b07dc1da4bb714a58
ARG LIDRPLUGINS_REF=567592acea4363dce635eb39e6ed3fbedfe5cee9

RUN apt-get update && apt-get install -y --no-install-recommends \
      r-base-core r-base-dev r-recommended libgdal-dev libgeos-dev libproj-dev \
      libudunits2-dev libssl-dev libcurl4-openssl-dev libxml2-dev libfontconfig1-dev \
      libfreetype-dev libharfbuzz-dev libfribidi-dev libpng-dev libtiff-dev \
      libjpeg-dev libglu1-mesa-dev git rsync ca-certificates locales \
 && rm -rf /var/lib/apt/lists/* \
 && locale-gen en_US.UTF-8 \
 && R --version | head -1 | grep -q "R version 4.3.3"
# The workstation's locale: frozen-clip manifests store CRS WKT with UTF-8
# degree signs, and string collation orders some tables.
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

ENV MAKEFLAGS=-j8
RUN printf '%s\n' \
      "options(repos = c(CRAN = '${PPM_SNAPSHOT}'), Ncpus = 8L)" \
      "options(HTTPUserAgent = sprintf('R/%s R (%s)', getRversion(), paste(getRversion(), R.version\$platform, R.version\$arch, R.version\$os)))" \
      >> /usr/lib/R/etc/Rprofile.site
COPY install_packages.R /tmp/install_packages.R
RUN Rscript /tmp/install_packages.R

# lasR: the pre-devel build with ws-as-a-function local maxima (not CRAN).
RUN git clone https://github.com/r-lidar/lasR /tmp/lasR \
 && git -C /tmp/lasR checkout "$LASR_REF" \
 && R CMD INSTALL /tmp/lasR && rm -rf /tmp/lasR

# lidRplugins: GitHub only; its retired rgeos/rgdal and the unused EBImage and
# rgl imports are dropped from DESCRIPTION, as on the benchmark workstation.
RUN git clone https://github.com/Jean-Romain/lidRplugins /tmp/lidRplugins \
 && git -C /tmp/lidRplugins checkout "$LIDRPLUGINS_REF" \
 && Rscript -e 'f <- "/tmp/lidRplugins/DESCRIPTION"; d <- read.dcf(f); \
      imp <- trimws(strsplit(d[, "Imports"], ",")[[1]]); \
      d[, "Imports"] <- paste(setdiff(imp, c("rgeos", "rgdal", "EBImage", "rgl")), collapse = ", "); \
      write.dcf(d, f)' \
 && R CMD INSTALL /tmp/lidRplugins && rm -rf /tmp/lidRplugins

WORKDIR /repo
