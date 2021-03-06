% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/adornMechanisms.R
\name{getMechanismView}
\alias{getMechanismView}
\title{getMechanismView()}
\usage{
getMechanismView()
}
\arguments{
\item{d}{}
}
\value{
Modified d object with d$data$analtyics
}
\description{
Retreives a view of mechanisms with partners and agencies
The function will attempt to read from a cached file, if defined in 
the support_files_directory option has been set, and the mechs.rds file
is available to be read. Otherwise, if the user is logged in, the view 
will be obtained from DATIM. Otherwise, an empty dataframe is returned.
}
