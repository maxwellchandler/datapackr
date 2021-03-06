#' @export
#' @importFrom utils capture.output
#' @title Unpack a Data Pack sheet.
#'
#' @description Within a submitted Data Pack or Site Tool (directed to by
#'    \code{d$keychain$submission_path}), extract data from a single sheet specified
#'    in \code{d$data$sheet}.
#'
#' @param d Datapackr object.
#' @param sheet Sheet to unpack.
#'
#' @return d
#'
unPackDataPackSheet <- function(d, sheet) {
  header_row <- headerRow(tool = "Data Pack", cop_year = d$info$cop_year)

  d$data$extract <-
    readxl::read_excel(
      path = d$keychain$submission_path,
      sheet = sheet,
      range = readxl::cell_limits(c(header_row, 1), c(NA, NA)),
      col_types = "text",
      .name_repair = "minimal"
    )

  # Run structural checks ####
  d <- checkColStructure(d, sheet)

  # Remove duplicate columns (Take the first example)
  duplicate_cols <- duplicated(names(d$data$extract))

  if (any(duplicate_cols)) {
    d$data$extract <- d$data$extract[,-which(duplicate_cols)]
  }

  # Make sure no blank column names
  d$data$extract %<>%
    tibble::as_tibble(.name_repair = "unique")

  # if tab has no target related content, send d back
  if (NROW(d$data$extract) == 0) {
    d$data$extract <- NULL
    return(d)
  }

  # TEST TX_NEW <1 from somewhere other than EID ####
  if (sheet == "TX") {

    d$tests$tx_new_invalid_lt1_sources <- d$data$extract %>%
      dplyr::select(PSNU, Age, Sex, TX_NEW.N.Age_Sex_HIVStatus.T,
        TX_NEW.N.IndexRate, TX_NEW.N.TBRate, TX_NEW.N.PMTCTRate,
        TX_NEW.N.PostANC1Rate, TX_NEW.N.EIDRate, TX_NEW.N.VMMCRateNew,
        TX_NEW.N.prevDiagnosedRate) %>%
      dplyr::filter(Age == "<01",
                    TX_NEW.N.Age_Sex_HIVStatus.T > 0) %>%
      dplyr::filter_at(dplyr::vars(-PSNU,-Age,-Sex, -TX_NEW.N.EIDRate,
                                   -TX_NEW.N.Age_Sex_HIVStatus.T),
                       dplyr::any_vars(.>0))
    attr(d$tests$tx_new_invalid_lt1_sources,"test_name")<-"Invalid TX <01 data source"


    if (NROW(d$tests$tx_new_invalid_lt1_sources) > 0) {
      warning_msg <-
        paste0(
          "WARNING! In tab TX",
          ": TX_NEW for <01 year olds being targeted through method other than EID.",
          " MER Guidance recommends all testing for <01 year olds be performed through EID rather than HTS",
          "\n")

      d$info$warning_msg <- append(d$info$warning_msg, warning_msg)
    }
  }

  # List Target Columns
  target_cols <- d$info$schema %>%
    dplyr::filter(sheet_name == sheet
                  & col_type == "target"
  # Filter by what's in submission to avoid unknown column warning messages
                  & indicator_code %in% colnames(d$data$extract)) %>%
    dplyr::pull(indicator_code)

  # Add cols to allow compiling with other sheets ####
  d$data$extract %<>%
    addcols(c("KeyPop", "Age", "Sex")) %>%
  # Select only target-related columns
    dplyr::select(PSNU, Age, Sex, KeyPop,
                  dplyr::one_of(target_cols)) %>%
  # Drop rows where entire row is NA
    dplyr::filter_all(dplyr::any_vars(!is.na(.))) %>%
    # Extract PSNU uid
    dplyr::mutate(
      psnuid = stringr::str_extract(PSNU, "(?<=(\\(|\\[))([A-Za-z][A-Za-z0-9]{10})(?=(\\)|\\])$)"),
      # Tag sheet name
      sheet_name = sheet
    ) %>%
    dplyr::select(PSNU, psnuid, sheet_name, Age, Sex, KeyPop,
                  dplyr::everything())
  
  # TEST: No missing metadata ####
  d <- checkMissingMetadata(d, sheet)
  
  # If PSNU has been deleted, drop the row
  d$data$extract %<>%
    dplyr::filter(!is.na(PSNU))
  
  # Check for Formula changes ####
  d <- checkFormulas(d, sheet)

  # Gather all indicators as single column for easier processing
  d$data$extract %<>%
    tidyr::gather(key = "indicator_code",
                  value = "value",
                  -PSNU, -psnuid, -Age, -Sex, -KeyPop, -sheet_name) %>%
    dplyr::select(PSNU, psnuid, sheet_name, indicator_code, Age, Sex, KeyPop, value)

  # TEST that all Prioritizations completed ####
  if (sheet == "Prioritization") {
    blank_prioritizations <- d$data$extract %>%
      dplyr::filter(is.na(value)) %>%
      dplyr::select(PSNU)

    if (NROW(blank_prioritizations) > 0) {

      d$tests$blank_prioritizations <- blank_prioritizations
      attr(d$tests$blank_prioritizations ,"test_name") <- "Blank prioritization levels"

      warning_msg <-
        paste0(
          "ERROR! In tab ",
          sheet,
          ": MISSING PRIORITIZATIONS. You must enter a prioritization value for",
          " the following PSNUs -> \n\t* ",
          paste(blank_prioritizations$PSNU, collapse = "\n\t* "),
          "\n")

      d$info$warning_msg <- append(d$info$warning_msg, warning_msg)
      d$info$has_error <- TRUE

    }
  # Remove _Military district from Prioritization extract as this can't be assigned a prioritization ####
    d$data$extract %<>%
      dplyr::filter(!stringr::str_detect(PSNU, "^_Military"),

  # Excuse valid NA Prioritizations
                    value != "NA")

    # Test that no non-Military district is categorized as "M"
    invalid_prioritizations <- d$data$extract %>%
      dplyr::filter(value == "M" & !stringr::str_detect(PSNU, "^_Military"))

    if (NROW(invalid_prioritizations) > 0) {
      d$tests$invalid_prioritizations <- invalid_prioritizations

      invalid_prioritizations_strings <- invalid_prioritizations %>%
        tidyr::unite(row_id, c(PSNU, value), sep = ":  ") %>%
        dplyr::arrange(row_id) %>%
        dplyr::pull(row_id)

      warning_msg <-
        paste0(
          "ERROR! In tab ",
          sheet,
          ": INVALID PRIORITIZATIONS. The following Prioritizations are not valid for",
          " the listed PSNUs -> \n\t* ",
          paste(invalid_prioritizations_strings, collapse = "\n\t* "),
          "\n")

      d$info$warning_msg <- append(d$info$warning_msg, warning_msg)
      d$info$has_error <- TRUE
    }

    # Convert Prioritization from text to short-number.
    # d$data$extract %<>%
    #   dplyr::mutate(
    #     value = dplyr::case_when(
    #       stringr::str_detect(indicator_code,"IMPATT.PRIORITY_SNU")
    #         ~ stringr::str_sub(value, start = 1, end = 2),
    #       TRUE ~ value
    #       )
    #     )
  }

  # Drop NAs ####
  d$data$extract %<>%
    tidyr::drop_na(value)

  # TEST for non-numeric values ####
  non_numeric <- d$data$extract %>%
    dplyr::mutate(value_numeric = suppressWarnings(as.numeric(value))) %>%
    dplyr::filter(is.na(value_numeric)) %>%
    dplyr::select(indicator_code, value) %>%
    dplyr::distinct() %>%
    dplyr::group_by(indicator_code) %>%
    dplyr::arrange(value) %>%
    dplyr::summarise(values = paste(value, collapse = ", ")) %>%
    dplyr::mutate(row_id = paste(indicator_code, values, sep = ":  ")) %>%
    dplyr::arrange(row_id) %>%
    dplyr::select(row_id) %>%
    dplyr::mutate(sheet=sheet)

  d$tests$non_numeric<-dplyr::bind_rows(d$tests$non_numeric,non_numeric)
  attr(d$tests$non_numeric,"test_name")<-"Non-numeric values"

  if(NROW(non_numeric) > 0) {

    warning_msg <-
      paste0(
        "WARNING! In tab ",
        sheet,
        ": NON-NUMERIC VALUES found! ->  \n\t* ",
        paste(non_numeric$row_id, collapse = "\n\t* "),
        "\n")

    d$info$warning_msg <- append(d$info$warning_msg, warning_msg)
  }

  # Now that non-numeric cases noted, convert all to numeric & drop non-numeric ####
  d$data$extract %<>%
    dplyr::mutate(value = suppressWarnings(as.numeric(value))) %>%
    tidyr::drop_na(value) %>%
  # Filter out zeros ####
    dplyr::filter(value != 0)

  # TEST: No invalid org units ####
  d <- checkInvalidOrgUnits(d, sheet)

  # TEST for Negative values ####
  negative_values <- d$data$extract %>%
    dplyr::filter(value < 0)

  d$tests$negative_values<-dplyr::bind_rows(d$test$negative_values,negative_values)
  attr(d$tests$negative_values,"test_name")<-"Negative values"

  if ( NROW(negative_values) > 0  ) {

    warning_msg <-
      paste0(
        "ERROR! In tab ",
        sheet,
        ": NEGATIVE VALUES found in the following columns! These will be removed. -> \n\t* ",
        paste(unique(d$tests$negative_values$indicator_code), collapse = "\n\t* "),
        "\n")

    d$info$warning_msg <- append(d$info$warning_msg, warning_msg)
    d$info$has_error <- TRUE
  }

  # TEST for Decimal values ####
  decimals_allowed <- d$info$schema %>%
    dplyr::filter(sheet_name == sheet
                  & col_type == "target"
                  # Filter by what's in submission to avoid unknown column warning messages
                  & indicator_code %in% unique(d$data$extract$indicator_code)
                  & value_type == "percentage") %>%
    dplyr::pull(indicator_code)

  decimal_cols <- d$data$extract %>%
    dplyr::filter(value %% 1 != 0
                  & !indicator_code %in% decimals_allowed) %>%
    dplyr::rename(sheet = sheet_name)

    d$tests$decimal_values<-dplyr::bind_rows(d$tests$decimal_cols,decimal_cols)
    attr(d$tests$decimal_values,"test_name")<-"Decimal values"

  if (NROW(decimal_cols) > 0) {

    warning_msg <-
      paste0(
        "WARNING! In tab ",
        sheet,
        ": DECIMAL VALUES found in the following columns! These will be rounded. -> \n\t* ",
        paste(unique(decimal_cols$indicator_code), collapse = "\n\t* "),
        "\n")

    d$info$warning_msg <- append(d$info$warning_msg, warning_msg)
  }

  # TEST for duplicates ####
  d <- checkDuplicateRows(d, sheet)

  # TEST for defunct disaggs ####
  d <- defunctDisaggs(d, sheet)

  # Aggregate OVC_HIVSTAT
  if (sheet == "OVC") {
    d$data$extract %<>%
      dplyr::mutate(
        Age = dplyr::case_when(
          stringr::str_detect(indicator_code, "OVC_HIVSTAT") ~ NA_character_,
          TRUE ~ Age),
        Sex = dplyr::case_when(
          stringr::str_detect(indicator_code, "OVC_HIVSTAT") ~ NA_character_,
          TRUE ~ Sex)) %>%
      dplyr::group_by(PSNU, psnuid, sheet_name, indicator_code, Age, Sex, KeyPop) %>%
      dplyr::summarise(value = sum(value)) %>%
      dplyr::ungroup()
  }

  # Add ages to PMTCT_EID
  if (sheet == "PMTCT_EID") {
    d$data$extract %<>%
      dplyr::mutate(
        Age = dplyr::case_when(
          stringr::str_detect(indicator_code, "PMTCT_EID(.)+2to12mo") ~ "02 - 12 months",
          stringr::str_detect(indicator_code, "PMTCT_EID(.)+2mo") ~ "<= 02 months",
          TRUE ~ Age
        )
      )
  }

  if (sheet == "KP") {
    d$data$extract %<>%
      dplyr::mutate(
        Sex = dplyr::case_when(indicator_code == "KP_MAT.N.Sex.T"
            ~ stringr::str_replace(KeyPop, " PWID", ""),
          TRUE ~ Sex),
        KeyPop = dplyr::case_when(indicator_code == "KP_MAT.N.Sex.T" ~ NA_character_,
          TRUE ~ KeyPop)
      )
  }

  return(d)

}



#' @export
#' @title unPackSiteToolSheet(d, sheet)
#'
#' @description Within a submitted Site Tool (directed to by
#'    \code{d$keychain$submission_path}), extract data from a single sheet specified
#'    in \code{sheet}.
#'
#' @param d Datapackr object.
#' @param sheet Sheet to unpack.
#'
#' @return d
#'
unPackSiteToolSheet <- function(d, sheet) {

  d$data$extract <-
    readxl::read_excel(
      path = d$keychain$submission_path,
      sheet = sheet,
      range = readxl::cell_limits(c(5, 1), c(NA, NA)),
      col_types = "text"
    )

  # Run structural checks before any filtering
  d <- checkColStructure(d, sheet)

  # List Target Columns
  targetCols <- datapackr::site_tool_schema %>%
    dplyr::filter(sheet_name == sheet,
                  col_type == "Target") %>%
    dplyr::pull(indicator_code)

  # Handle empty tabs ####
  d$data$extract %<>%
    dplyr::select(-Status) %>%
    dplyr::filter_all(., dplyr::any_vars(!is.na(.)))

  if (NROW(d$data$extract) == 0) {
    d$data$extract <- NULL
    return(d)
  }

  # Add cols to allow compiling with other sheets
  d$data$extract %<>%
    addcols(c("KeyPop", "Age", "Sex")) %>%
  # Extract Site id & Mech Code
    dplyr::mutate(
      site_uid = stringr::str_extract(Site, "(?<=\\[)([A-Za-z][A-Za-z0-9]{10})(?=\\]$)"),
      Mechanism = stringr::str_replace(Mechanism, "Dedupe", "00000 - Deduplication"),
      mech_code = stringi::stri_extract_first_regex(Mechanism, "^[0-9]{4,6}(?=\\s-)"),
  # Tag sheet name
      sheet_name = sheet
      ) %>%
  # Select only target-related columns
    dplyr::select(Site,
                  site_uid,
                  mech_code,
                  Type,
                  sheet_name,
                  Age,
                  Sex,
                  KeyPop,
                  dplyr::one_of(targetCols)) %>%
  # Gather all indicators in single column for easier processing
    tidyr::gather(key = "indicator_code",
                  value = "value",
                  -Site,
                  -site_uid,
                  -mech_code,
                  -Type,
                  -Age,
                  -Sex,
                  -KeyPop,
                  -sheet_name) %>%
    dplyr::select(Site, site_uid,mech_code,Type, sheet_name, indicator_code,
                  Age, Sex, KeyPop, value) %>%
  # Drop where value is zero, NA, dash, or space-only entry ####
    #TODO Add non-numeric test
    tidyr::drop_na(value) %>%
    dplyr::filter(
      !is.na(suppressWarnings(as.numeric(value)))) %>%
    dplyr::mutate(value = as.numeric(value))

  # Check for non-sites ####
  d$tests$unallocated_data <- grepl("NOT YET DISTRIBUTED", d$data$extract$Site)

  if (any(d$tests$unallocated_data)) {
    warning_msg <-
      paste0(
        "ERROR! In tab ",
        sheet,
        ": Values not allocated to Site level!")
    d$info$warning_msg <- append(d$info$warning_msg, warning_msg)
    d$info$has_error <- TRUE
  }

  # Proceed by removing unallocated rows ####
  d$data$extract %<>%
    dplyr::filter(stringr::str_detect(Site, "NOT YET DISTRIBUTED", negate = TRUE))

  # Filter target zeros, allowing for zero-value dedupes ####
  d$data$extract %<>%
    dplyr::filter(value != 0 | stringr::str_detect("00000", mech_code))

  # TEST for Negative values in non-dedupe mechanisms ####
  d$tests$has_negative_nondedupes <-
    ( d$data$extract$value < 0 ) &
    stringr::str_detect("00000", d$data$extract$mech_code, negate = TRUE)

  if (any(d$tests$has_negative_nondedupes)) {
    d$tests$neg_cols <- d$data$extract %>%
      dplyr::filter( d$tests$has_negative_nondedupes) %>%
      dplyr::pull(indicator_code) %>%
      unique() %>%
      paste(collapse = ", ")

    warning_msg <-
      paste0(
        "ERROR! In tab ",
        sheet,
        ": NEGATIVE VALUES found! -> ",
        d$tests$neg_cols,
        "")
    d$info$warning_msg <- append(d$info$warning_msg, warning_msg)
    d$info$has_error <- TRUE
  }

  # TEST for positive values in dedupe mechanisms ####
  d$tests$has_positive_dedupes <-
    (d$data$extract$value > 0) &
    stringr::str_detect("00000", d$data$extract$mech_code)

  if ( any( d$tests$has_positive_dedupes ) ) {
    d$tests$pos_cols <- d$data$extract %>%
      dplyr::filter(d$tests$has_positive_dedupes) %>%
      dplyr::pull(indicator_code) %>%
      unique() %>%
      paste(collapse = ", ")

    warning_msg <- paste0("ERROR! In tab ", d$data$sheet,
                  ": POSITIVE DEDUPE VALUES found! -> ",
                  d$tests$pos_cols,
                  "")
    d$info$warning_msg <- append(d$info$warning_msg, warning_msg)
    d$info$has_error <- TRUE
  }

  # TEST for decimals ####
  d$tests$has_decimals <- d$data$extract$value %% 1 != 0

  if (any(d$tests$has_decimals)){

    d$tests$decimals_found <- d$data$extract %>%
      dplyr::select(value) %>%
      dplyr::filter(value %% 1 != 0) %>%
      dplyr::distinct %>%
      dplyr::pull(value) %>%
      paste(collapse = ", ")

    warning_msg <-
      paste0(
        "ERROR! In tab ",
        sheet,
        ": " ,
        sum(d$tests$has_decimals),
        " DECIMAL VALUES found!: ",
        d$tests$decimals_found)
    d$info$warning_msg <- append(d$info$warning_msg, warning_msg)
    d$info$has_error <- TRUE
  }


  # TEST for duplicates ####
  duplicate_target_rows <- d$data$extract %>%
    dplyr::select(sheet_name, site_uid, mech_code, Age, Sex, KeyPop, Type, indicator_code) %>%
    dplyr::group_by(sheet_name, site_uid, mech_code, Age, Sex, KeyPop, Type, indicator_code) %>%
    dplyr::summarise(n = (dplyr::n())) %>%
    dplyr::filter(n > 1) %>%
    dplyr::ungroup() %>%
    dplyr::distinct() %>%
    dplyr::mutate(row_id = paste(site_uid, mech_code, Age, Sex, KeyPop, Type, indicator_code, sep = "    ")) %>%
    dplyr::arrange(row_id) %>%
    dplyr::select(row_id) %>%
    dplyr::mutate(sheet=sheet)

  d$tests$duplicate_target_rows<-dplyr::bind_rows(d$tests$duplicate_target_rows,duplicate_target_rows)
  attr(d$tests$duplicate_target_rows)<-"Duplicate target rows"

  if (NROW(duplicates) > 0) {
    warning_msg <-
      paste0(
        "In tab ",
        sheet,
        ":" ,
        NROW(d$tests$duplicates),
        " DUPLICATE ROWS. These will be aggregated!" )
    d$info$warning_msg <- append(d$info$warning_msg, warning_msg)
  }

  # TEST for defunct disaggs ####
  d$tests$defunct <- defunctDisaggs(d)

  if (NROW(defunct) > 0) {
    defunct_msg <- d$tests$defunct %>%
      dplyr::mutate(
        msg = stringr::str_squish(
          paste(paste0(indicator_code, ":"), Age, Sex, KeyPop)
          )
        ) %>%
      dplyr::pull(msg) %>%
      paste(collapse = ",")

    warning_msg <-
      paste0(
        "ERROR! In tab ",
        sheet,
        ": INVALID DISAGGS ",
        "(Check MER Guidance for correct alternatives) ->",
        defunct_msg)

    d$info$warning_msg <- append(d$info$warning_msg, warning_msg)
    d$info$has_error <- TRUE
  }

  # TEST for any missing mechanisms ####
  d$tests$missing_mechs <- d$data$extract %>%
    dplyr::select(sheet_name, PSNU, Age, Sex, KeyPop, indicator_code) %>%
    dplyr::group_by(sheet_name, PSNU, Age, Sex, KeyPop, indicator_code) %>%
    dplyr::summarise(n = (dplyr::n())) %>%
    dplyr::filter(n > 1) %>%
    dplyr::ungroup() %>%
    dplyr::distinct() %>%
    dplyr::mutate(row_id = paste(PSNU, Age, Sex, KeyPop, indicator_code, sep = "    ")) %>%
    dplyr::arrange(row_id) %>%
    dplyr::pull(row_id)

    dplyr::filter(is.na(mech_code)) %>%


  if (any(is.na(d$data$extract$mech_code)) ) {
    warning_msg <-
      paste0(
        "ERROR! In tab ",
        sheet,
        ": BLANK MECHANISMS found!")

    d$info$warning_msg <- append(d$info$warning_msg, warning_msg)
    d$info$has_error <- TRUE
  }

  #TEST for any missing Types ####
  if (any(is.na(d$data$extract$Type)) ) {
    msg <-
      paste0(
        "ERROR! In tab ",
        sheet,
        ": MISSING DSD/TA ATTRIBUTION found!")

    d$info$warning_msg <- append(msg,d$info$warning_msg)
    d$info$has_error <- TRUE
  }

  return(d)

}
