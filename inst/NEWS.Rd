\name{scrannews}
\title{scran News}
\encoding{UTF-8}

\section{Version 1.1.8}{\itemize{
\item
Added 'min' argument to testVar().

\item
Transformed correlations to a metric distance in quickCluster().

\item 
Removed normalize() in favour of scater's normalize().

\item 
Switched isSpike()<- to accept a character vector rather than a logical vector, to enforce naming of spike-in sets.
Also added warning code when the specified spike-in sets overlap.

\item
Allowed compute*Factors() functions to directly return the size factors.

\item 
Added selectorPlot() function for interactive plotting.

\item 
Switched to a group-based weighted correlation for one-way layouts in correlatePairs() and correlateNull(),
and to a correlation of residuals for more complex design matrices.

\item
Added phase assignments to the cyclone() output.

\item
Implemented Brennecke et al.'s method in the technicalCV2() function.

\item
Updated convertTo() to store spike-in-specific size factors as offsets.

\item
Moved code and subsetting into C++ to improve memory efficiency.

\item
Switched to loess-based trend fitting as the default in trendVar().

\item
Updated documentation and tests.
}}

\section{Version 1.0.0}{\itemize{
\item
New package scran, for low-level analyses of single-cell RNA sequencing data.
}}
