.buildSNNGraph <- function(x, k=10, d=50, transposed=FALSE, pc.approx=FALSE,
                           rand.seed=1000, irlba.args=list(), subset.row=NULL, 
                           BPPARAM=SerialParam()) 
# Builds a shared nearest-neighbor graph, where edges are present between each 
# cell and any other cell with which it shares at least one neighbour. Each edges 
# is weighted based on the ranks of the shared nearest neighbours of the two cells, 
# as described in the SNN-Cliq paper.
#
# written by Aaron Lun
# created 3 April 2017
# last modified 16 November 2017    
{ 
    nn.out <- .setup_knn_data(x=x, subset.row=subset.row, d=d, transposed=transposed,
        pc.approx=pc.approx, rand.seed=rand.seed, irlba.args=irlba.args, 
        k=k, BPPARAM=BPPARAM) 

    # Building the SNN graph.
    g.out <- .Call(cxx_build_snn, nn.out$nn.index)
    edges <- g.out[[1]] 
    weights <- g.out[[2]]

    g <- make_graph(edges, directed=FALSE)
    E(g)$weight <- weights
    g <- simplify(g, edge.attr.comb="first") # symmetric, so doesn't really matter.
    return(g)
}

.buildKNNGraph <- function(x, k=10, d=50, directed=FALSE,
                           transposed=FALSE, pc.approx=FALSE,
                           rand.seed=1000, irlba.args=list(), subset.row=NULL,
                           BPPARAM=SerialParam()) 
# Builds a k-nearest-neighbour graph, where edges are present between each
# cell and its 'k' nearest neighbours. Undirected unless specified otherwise.
#
# written by Aaron Lun, Jonathan Griffiths
# created 16 November 2017
{ 
    nn.out <- .setup_knn_data(x=x, subset.row=subset.row, d=d, transposed=transposed,
        pc.approx=pc.approx, rand.seed=rand.seed, irlba.args=irlba.args,
        k=k, BPPARAM=BPPARAM) 

    # Building the KNN graph.
    start <- as.vector(row(nn.out$nn.index))
    end <- as.vector(nn.out$nn.index)
    interleaved <- as.vector(rbind(start, end))
    
    if (directed) { 
        g <- make_graph(interleaved, directed=TRUE)
    } else {
        g <- make_graph(interleaved, directed=FALSE)
        g <- simplify(g, edge.attr.comb = "first")
    }
    return(g)
}

######################
# Internal functions #
######################

.setup_knn_data <- function(x, subset.row, d, transposed, pc.approx, rand.seed, irlba.args, k, BPPARAM) {
    ncells <- ncol(x)
    if (!is.null(subset.row)) {
        x <- x[.subset_to_index(subset.row, x, byrow=TRUE),,drop=FALSE]
    }
    
    if (!transposed) {
        x <- t(x)
    } 
    
    # Reducing dimensions, if 'd' is less than the number of genes.
    if (!is.na(d) && d < ncol(x)) {
        if (pc.approx) {
            if (!is.na(rand.seed)) {
                set.seed(rand.seed)
            }
            pc <- do.call(irlba::prcomp_irlba, c(list(x=x, n=d, scale.=FALSE, center=TRUE, retx=TRUE), irlba.args))
        } else {
            pc <- prcomp(x, rank.=d, scale.=FALSE, center=TRUE)
        }
        x <- pc$x
    }
   
    # Finding the KNNs. 
    .find_knn(x, k=k, BPPARAM=BPPARAM, algorithm="cover_tree") 
}

.find_knn <- function(incoming, k, BPPARAM, ..., force=FALSE) {
    # Some checks to avoid segfaults in get.knn(x).
    ncells <- nrow(incoming)
    if (ncol(incoming)==0L || ncells==0L) { 
        return(list(nn.index=matrix(0L, ncells, 0), nn.dist=matrix(0, ncells, 0)))
    }
    if (k >= nrow(incoming)) {
        warning("'k' set to the number of cells minus 1")
        k <- nrow(incoming) - 1L
    }

    nworkers <- bpworkers(BPPARAM)
    if (!force && nworkers==1L) {
        # Simple call with one core.
        nn.out <- get.knn(incoming, k=k, ...)
    } else {
        # Splitting up the query cells across multiple cores.
        by.group <- .worker_assign(ncells, BPPARAM)
        x.by.group <- vector("list", nworkers)
        for (j in seq_along(by.group)) {
            x.by.group[[j]] <- incoming[by.group[[j]],,drop=FALSE]
        } 
        all.out <- bplapply(x.by.group, FUN=get.knnx, data=incoming, k=k+1, ..., BPPARAM=BPPARAM)
        
        # Some work to get rid of self as a nearest neighbour.
        for (j in seq_along(all.out)) {
            cur.out <- all.out[[j]]
            is.self <- cur.out$nn.index==by.group[[j]]
            ngenes <- nrow(is.self)
            no.hits <- which(rowSums(is.self)==0)
            to.discard <- c(which(is.self), no.hits + k*ngenes) # getting rid of 'k+1'th, if self is not present.

            new.nn.index <- cur.out$nn.index[-to.discard]
            new.nn.dist <- cur.out$nn.dist[-to.discard]
            dim(new.nn.index) <- dim(new.nn.dist) <- c(ngenes, k)
            cur.out$nn.index <- new.nn.index
            cur.out$nn.dist <- new.nn.dist
            all.out[[j]] <- cur.out
        }

        # rbinding everything together.
        nn.out <- do.call(mapply, c(all.out, FUN=rbind, SIMPLIFY=FALSE))
    }
    return(nn.out)
}

#########################
# S4 method definitions #
#########################

setGeneric("buildSNNGraph", function(x, ...) standardGeneric("buildSNNGraph"))

setMethod("buildSNNGraph", "ANY", .buildSNNGraph)

setMethod("buildSNNGraph", "SingleCellExperiment", 
          function(x, ..., subset.row=NULL, assay.type="logcounts", get.spikes=FALSE, use.dimred=NULL) {
              
    subset.row <- .SCE_subset_genes(subset.row, x=x, get.spikes=get.spikes)
    if (!is.null(use.dimred)) {
        out <- .buildSNNGraph(reducedDim(x, use.dimred), d=NA, transposed=TRUE, ..., subset.row=NULL)
    } else {
        out <- .buildSNNGraph(assay(x, i=assay.type), transposed=FALSE, ..., subset.row=subset.row)
    }
    return(out)
})

setGeneric("buildKNNGraph", function(x, ...) standardGeneric("buildKNNGraph"))

setMethod("buildKNNGraph", "ANY", .buildKNNGraph)

setMethod("buildKNNGraph", "SingleCellExperiment", 
          function(x, ..., subset.row=NULL, assay.type="logcounts", get.spikes=FALSE, use.dimred=NULL) {
              
    subset.row <- .SCE_subset_genes(subset.row, x=x, get.spikes=get.spikes)
    if (!is.null(use.dimred)) {
        out <- .buildKNNGraph(reducedDim(x, use.dimred), d=NA, transposed=TRUE, ..., subset.row=NULL)
    } else {
        out <- .buildKNNGraph(assay(x, i=assay.type), transposed=FALSE, ..., subset.row=subset.row)
    }
    return(out)
})
