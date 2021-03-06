#' @export
#' @title Unpack data from Data Pack or Site Tool sheets.
#'
#' @description
#' Loops through all critical sheets in a submitted Data Pack or
#' Site Tool and extracts data, then compiles into single flat dataframe.
#'
#' @param d Datapackr object
#' 
#' @return d
#' 
unPackSheets <- function(d) {

  # Get sheets list
  sheets <- d$info$schema %>%
    dplyr::select(sheet_name) %>%
    dplyr::distinct() %>%
    dplyr::filter(
      !sheet_name %in% skip_tabs(tool = d$info$tool, cop_year = d$info$cop_year)
        & !sheet_name %in% c("SNU x IM","PSNUxIM")) %>%
    dplyr::pull(sheet_name)
  
  actual_sheets <- readxl::excel_sheets(d$keychain$submission_path)
  sheets_to_read <- sheets[sheets %in% actual_sheets]
  
  d$data$targets <- NULL
  
  for (i in 1:length(sheets_to_read)) {
    sheet = sheets_to_read[i]
    interactive_print(sheet)
    
    if (d$info$tool == "Data Pack") {
      d <- unPackDataPackSheet(d, sheet = sheet)
    } else if (d$info$tool == "Site Tool") {
      d <- unPackSiteToolSheet(d, sheet = sheet)
    } else {stop("Cannot process that kind of tool. :(")}
    
    if (!is.null(d$data$extract)) {
      d$data$targets <- dplyr::bind_rows(d$data$targets, d$data$extract)
    }
  }
  
  return(d)
}
