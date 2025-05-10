deps <- renv::dependencies()
pkgs <- setdiff(unique(deps$Package), "R")
bibtex::write.bib(entry = pkgs, file = "./resources/bibs/packages.bib", append = FALSE)
