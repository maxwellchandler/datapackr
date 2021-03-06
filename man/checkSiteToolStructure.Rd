% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/parseSiteTool.R
\name{checkSiteToolStructure}
\alias{checkSiteToolStructure}
\title{checkSiteToolStructure(d)}
\usage{
checkSiteToolStructure(d)
}
\arguments{
\item{d}{datapackr list object containing at least d$keychain$submission_path
& d$info$warningMsg.}
}
\value{
A datapackr list object, \code{d}, storing a warning message of all
   issues related to Data Pack or Site Tool tab names or order.
}
\description{
Checks structural integrity of tabs for SiteTool
}
