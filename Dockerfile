# Combined Dockerfile
ARG R_VERSION=4.4.0
FROM rocker/r-base:${R_VERSION}

# Install essential system dependencies
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    make \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libcairo2-dev \
    libxt-dev \
    libfreetype6-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libbz2-dev \
    libpng-dev \
    libtiff-dev \
    libjpeg-dev \
    git \
    tree \
    wget \
    ca-certificates \
    pkg-config \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install specific Quarto CLI version (using amd64 to match base image)
ARG QUARTO_VERSION="1.4.554" # Or your desired 1.4.x version
RUN _FORCED_ARCH="amd64" && \
    QUARTO_DL_URL="https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-${_FORCED_ARCH}.deb" && \
    wget "${QUARTO_DL_URL}" -O quarto.deb && \
    dpkg -i quarto.deb && \
    rm quarto.deb

# Set PATH for Quarto (adjust if installation path differs)
ENV PATH="/opt/quarto/bin:${PATH}"

# Install renv R package
RUN R -e "install.packages('renv', repos = 'https://cloud.r-project.org/')"

# --- Steps from original pipeline Dockerfile ---

# Set working directory
WORKDIR /app

# Copy renv files first for caching
COPY .Rprofile .
COPY renv.lock .
COPY renv/activate.R renv/activate.R

# Restore packages from lockfile (will use cache if lockfile unchanged)
RUN Rscript -e "renv::restore()"

# Copy remaining project files
COPY R R/
COPY _targets.R .
COPY index.qmd .
COPY resources resources/
COPY _extensions .
COPY entrypoint.sh /entrypoint.sh

# Make entrypoint executable
RUN chmod +x /entrypoint.sh

# Set default command
CMD ["/entrypoint.sh"]
