FROM robwiederstein/r-ml-base:4.4.0

WORKDIR /app

COPY .Rprofile .
COPY renv.lock .
COPY renv/activate.R renv/activate.R
RUN Rscript -e "renv::restore()"
COPY R R/
COPY _targets.R .
COPY index.qmd .
COPY resources resources/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
