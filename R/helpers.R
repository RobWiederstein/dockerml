tm <- function(...){
targets::tar_make(...)
}
tv <- function(...){
  targets::tar_visnetwork(targets_only = T)
}

# Function to wrap a single target name in the desired format with newlines
print_chunks <- function(){
wrap_target_name <- function(name) {
  glue::glue("\n```{{r}}\n #label: {name}\n{name} \n```\n\n")
}
lapply(list.files("./_targets/objects") %>% dput(), wrap_target_name) %>% unlist() %>% cat()
}
