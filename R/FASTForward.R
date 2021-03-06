#' @export
#' @title FASTforward(d)
#'
#' @description Takes the output of the \code{\link{unPackSheets}} function and
#'     recompiles this to contain only data relevant for and in same structure
#'     as the PEPFAR FAST Tool.
#'
#' @param d Datapackr object
#' 
#' @return d
#' 
FASTforward <- function(d) {
  d$data$FAST <- d$data$distributedMER %>%
    dplyr::filter(
  # Detect HTS_TST & HTS_TST_POS cases
      stringr::str_detect(
        indicator_code,
        "HTS_TST(.)+Age|(PMTCT|TB)_STAT\\.N(.)+(NewNeg|NewPos)$|VMMC_CIRC\\.(.)+(Negative|Positive)|HTS_INDEX"
      )
  # Detect OVC_SERV, TB_PREV, TX_CURR, TX_NEW, VMMC_CIRC cases
      |
        stringr::str_detect(
          indicator_code,
          "OVC_SERV|TB_PREV\\.N|TX_CURR\\.|TX_NEW\\.N\\.Age|VMMC_CIRC\\."
        )
    ) %>%
    dplyr::mutate(indicator = NULL) %>%
    dplyr::bind_rows(
      .,
  # Copy for HTS_TST
      ((.) %>%
         dplyr::filter(
           stringr::str_detect(indicator_code, "VMMC_CIRC(.)+(Negative|Positive)")
         ) %>%
         dplyr::mutate(indicator = "HTS_TST")
      ),
  # Copy for HTS_TST_POS
      ((.) %>%
         dplyr::filter(
           stringr::str_detect(
             indicator_code,
             "(VMMC_CIRC|HTS_TST)(.)+Positive|(HTS_INDEX|PMTCT_STAT|TB_STAT)(.)+NewPos$"
           )
         ) %>%
         dplyr::mutate(indicator = "HTS_TST_POS")
      )
    ) %>%
    dplyr::mutate(
      indicator = dplyr::case_when(
        !is.na(indicator) ~ indicator,
        stringr::str_detect(indicator_code, "PMTCT_STAT|TB_STAT|HTS_INDEX") ~ "HTS_TST",
        TRUE ~ stringr::str_extract(
          indicator_code,
          "OVC_SERV|HTS_TST|TB_PREV|TX_CURR|TX_NEW|VMMC_CIRC"
        )
      ),
      disag = dplyr::case_when(
        indicator %in% c("HTS_TST", "HTS_TST_POS", "TX_CURR", "TX_NEW") &
          CoarseAge == "15+" & Sex == "Male" ~ "Adult Men",
        indicator %in% c("HTS_TST", "HTS_TST_POS", "TX_CURR", "TX_NEW") &
          CoarseAge == "15+" & Sex == "Female" ~ "Adult Women",
        indicator %in% c("HTS_TST", "HTS_TST_POS", "TX_CURR", "TX_NEW") &
          CoarseAge %in% c("<15", "01-04") ~ "Peds",
        TRUE ~ ""
      )
    ) %>%
    dplyr::select(mechanismid = mechanism_code, indicator, disag, value) %>%
    dplyr::group_by(mechanismid, indicator, disag) %>%
    dplyr::summarise(targets = round_trunc(sum(value))) %>%
    dplyr::ungroup() %>%
    tidyr::drop_na(mechanismid) %>%
    dplyr::arrange(mechanismid, indicator, disag)
  
  return(d)
}
