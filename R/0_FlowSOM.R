# FlowSOM object
# List containing the following
# 
# after ReadInput:
#     data: matrix containing all the concatenated data files
#     metaData: a list, containing start and end indices for each file
#     compensate: logical, is the data compensated
#     spillover: spillover matrix the data is compensated with
#     transform: logical, is the data transformed with a logicle transform
#     toTransform: column names or indices are transformed
#     scale: logical, is the data rescaled
#     scaled.center: parameter used to rescale
#     scaled.scale: parameter used to rescale


#' Run the FlowSOM algorithm
#'
#' Method to run general FlowSOM workflow. 
#' Will scale the data and uses consensus meta-clustering by default.
#'
#' @param input         a flowFrame, a flowSet or an array of paths to files or 
#'                      directories
#' @param pattern       if input is an array of file- or directorynames, select 
#'                      only files containing pattern
#' @param compensate    logical, does the data need to be compensated
#' @param spillover     spillover matrix to compensate with
#'                      If NULL and compensate=TRUE, we will look for $SPILL 
#'                      description in fcs file.
#' @param transform     logical, does the data need to be transformed with a
#'                      logicle transform
#' @param toTransform   column names or indices that need to be transformed.
#'                      If \code{NULL} and transform = \code{TRUE}, column
#'                      names of \code{$SPILL} description in fcs file will
#'                      be used.
#' @param transformFunction Defaults to logicleTransform()
#' @param scale         logical, does the data needs to be rescaled
#' @param scaled.center see \code{\link{scale}}
#' @param scaled.scale  see \code{\link{scale}}
#' @param silent        if \code{TRUE}, no progress updates will be printed
#' @param colsToUse     column names or indices to use for building the SOM
#' @param importance    array with numeric values. Parameters will be scaled 
#'                      according to importance
#' @param nClus         Exact number of clusters for meta-clustering. 
#'                      If \code{NULL}, several options will be tried 
#'                      (\code{1:maxMeta})
#' @param maxMeta       Maximum number of clusters to try out for 
#'                      meta-clustering. Ignored if nClus is specified
#' @param seed          Set a seed for reproducible results
#' @param ...           options to pass on to the SOM function 
#'                      (xdim, ydim, rlen, mst, alpha, radius, init, distf)
#'
#' @return A \code{list} with two items: the first is the flowSOM object 
#'         containing all information (see the vignette for more detailed 
#'         information about this object), the second is the metaclustering of 
#'         the nodes of the grid. This is a wrapper function for 
#'         \code{\link{ReadInput}}, \code{\link{BuildSOM}}, 
#'         \code{\link{BuildMST}} and \code{\link{MetaClustering}}. 
#'         Executing them separately may provide more options.
#'
#' @seealso \code{\link{scale}},\code{\link{ReadInput}},\code{\link{BuildSOM}},
#'          \code{\link{BuildMST}},\code{\link{MetaClustering}}
#' @examples
#' # Read from file
#' fileName <- system.file("extdata","lymphocytes.fcs",package="FlowSOM")
#' flowSOM.res <- FlowSOM(fileName, compensate=TRUE,transform=TRUE,
#'                       scale=TRUE,colsToUse=c(9,12,14:18),maxMeta=10)
#' # Or read from flowFrame object
#' ff <- flowCore::read.FCS(fileName)
#' ff <- flowCore::compensate(ff,ff@@description$SPILL)
#' ff <- flowCore::transform(ff,
#'          flowCore::transformList(colnames(ff@@description$SPILL),
#'                                 flowCore::logicleTransform()))
#' flowSOM.res <- FlowSOM(ff,scale=TRUE,colsToUse=c(9,12,14:18),maxMeta=10)
#' 
#' # Plot results
#' PlotStars(flowSOM.res[[1]])
#' 
#' # Get metaclustering per cell
#' flowSOM.clustering <- flowSOM.res[[2]][flowSOM.res[[1]]$map$mapping[,1]]
#' 
#' 
#' 
#' @importFrom flowCore read.FCS compensate transform logicleTransform exprs 
#'             transformList write.FCS 'exprs<-'
#' @importFrom igraph graph.adjacency minimum.spanning.tree layout.kamada.kawai
#'             plot.igraph add.vertex.shape get.edges shortest.paths E V 'V<-'
#'             igraph.shape.noclip
#' @importFrom tsne tsne
#' @importFrom ConsensusClusterPlus ConsensusClusterPlus
#' @importFrom BiocGenerics colnames
#' 
#' @importFrom flowUtils read.gatingML
#' @importFrom XML xmlToList xmlParse
#' 
#' @export
FlowSOM <- function(input, pattern=".fcs", compensate=FALSE, spillover=NULL, 
                    transform=FALSE, toTransform=NULL, 
                    transformFunction=flowCore::logicleTransform(), scale=TRUE, 
                    scaled.center=TRUE, scaled.scale=TRUE, silent=TRUE, 
                    colsToUse, nClus=NULL, maxMeta, importance=NULL, 
                    seed = NULL, ...){
    # Method to run general FlowSOM workflow. 
    # Will scale the data and uses consensus meta-clustering by default.
    #
    # Args:
    #    input: dirName, fileName, array of fileNames, flowFrame or 
    #           array of flowFrames
    #    colsToUse: column names or indices to use for building the SOM
    #    maxMeta: maximum number of clusters for meta-clustering
    #
    # Returns:
    #    list with the FlowSOM object and an array with final clusterlabels
    if(!is.null(seed)){
        set.seed(seed)
    }
    
    t <- system.time(fsom <- ReadInput(input, pattern=pattern, 
                                        compensate=compensate, 
                                        spillover=spillover, 
                                        transform=transform, 
                                        toTransform=toTransform, 
                                        transformFunction = transformFunction, 
                                        scale=scale,
                                        scaled.center=scaled.center, 
                                        scaled.scale=scaled.scale, 
                                        silent=silent))
    if(!silent) message(t[3],"\n")
    t <- system.time(fsom <- BuildSOM(fsom, colsToUse, silent=silent, 
                                        importance=importance, ...))
    if(!silent) message(t[3],"\n")
    t <- system.time(fsom <- BuildMST(fsom, silent=silent))
    if(!silent) message(t[3],"\n")
    if(is.null(nClus)){
        t <- system.time(cl <- as.factor(MetaClustering(fsom$map$codes,
                                        "metaClustering_consensus", maxMeta)))
    } else {
        t <- system.time(cl <- as.factor(
            metaClustering_consensus(fsom$map$codes, nClus,seed = seed)))
    }
    if(!silent) message(t[3],"\n")
    list("FlowSOM"=fsom, "metaclustering"=cl)
}

#' Aggregate multiple fcs files together
#' 
#' Aggregate multiple fcs files to analyze them simultaneously. 
#' A new fcs file is written, which contains about \code{cTotal} cells,
#' with \code{ceiling(cTotal/nFiles)} cells from each file. Two new columns
#' are added: a column indicating the original file by index, and a noisy 
#' version of this for better plotting opportunities (index plus or minus a 
#' value between 0 and 0.1).
#' 
#' @param fileNames   Character vector containing full paths to the fcs files
#'                    to aggregate
#' @param cTotal      Total number of cells to write to the output file
#' @param writeOutput Whether to write the resulting flowframe to a file
#' @param outputFile  Full path to output file
#' @param writeMeta   If TRUE, files with the indices of the selected cells are
#'                    generated
#'                  
#' @return This function does not return anything, but will write a file with
#'         about \code{cTotal} cells to \code{outputFile}
#'
#' @seealso \code{\link{ceiling}}
#'
#' @examples
#' # Define filename
#' fileName <- system.file("extdata","lymphocytes.fcs",package="FlowSOM")
#' # This example will sample 2 times 500 cells.
#' ff_new <- AggregateFlowFrames(c(fileName,fileName),1000)
#' 
#' @export
AggregateFlowFrames <- function(fileNames, cTotal,
                            writeOutput = FALSE, outputFile="aggregate.fcs", 
                            writeMeta=FALSE){
    
    nFiles <- length(fileNames)
    cFile <- ceiling(cTotal/nFiles)
    
    flowFrame <- NULL
    
    for(i in seq_len(nFiles)){
        f <- flowCore::read.FCS(fileNames[i])
        c <- sample(seq_len(nrow(f)),min(nrow(f),cFile))
        if(writeMeta){
            #<path_to_outputfile>/<filename>_selected_<outputfile>.txt
            utils::write.table(c,paste(gsub("[^/]*$","",outputFile),
                            gsub("\\.[^.]*$","",gsub(".*/","",fileNames[i])),
                            "_selected_",
                            gsub("\\.[^.]*$","",gsub(".*/","",outputFile)),
                            ".txt",sep=""))
        }
        m <- matrix(rep(i,min(nrow(f),cFile)))
        m2 <- m + stats::rnorm(length(m),0,0.1)
        m <- cbind(m,m2)
        colnames(m) <- c("File","File_scattered")
        f <- flowCore::cbind2(f[c,],m)
        if(is.null(flowFrame)){
            flowFrame <- f
            flowFrame@description$`$FIL` <- gsub(".*/","",outputFile)
            flowFrame@description$`FILENAME` <- gsub(".*/","",outputFile)
        }
        else {
            flowCore::exprs(flowFrame) <- rbind(flowCore::exprs(flowFrame), 
                                        flowCore::exprs(f))
        }
    }
    
    flowFrame@description[[
        paste("flowCore_$P",ncol(flowFrame)-1,"Rmin",sep="")]] <- 0
    flowFrame@description[[
        paste("flowCore_$P",ncol(flowFrame)-1,"Rmax",sep="")]] <- nFiles+1
    flowFrame@description[[
        paste("flowCore_$P",ncol(flowFrame),"Rmin",sep="")]] <- 0
    flowFrame@description[[
        paste("flowCore_$P",ncol(flowFrame),"Rmax",sep="")]] <- nFiles+1  
    flowFrame@description[[paste("$P", ncol(flowFrame) - 1, 
                                 "B", sep = "")]] <- 32
    flowFrame@description[[paste("$P", ncol(flowFrame), 
                                 "B", sep = "")]] <- 32
    
    flowFrame@description$FIL <- gsub(".*/","",outputFile)
    if(writeOutput){
        flowCore::write.FCS(flowFrame,filename=outputFile)
    }
    
    flowFrame
}


#' Process a gatingML file
#' 
#' Reads a gatingML file using the \code{\link{flowUtils}} library and
#' returns a list with a matrix containing filtering results for each specified
#' gate and a vector with a label for each cell
#' 
#' @param flowFrame     The flowFrame to apply the gating on
#' @param gatingFile    The gatingML file to read
#' @param gateIDs       Named vector containing ids to extract from the 
#'                      gatingML file to use in the matrix
#' @param cellTypes     Cell types to use for labeling the cells. Should be a
#'                      subset of the names of the gateIDs
#' @param silent        If FALSE, show messages of which gates are being
#'                      processed
#'                  
#' @return This function returns a list in which the first element ("matrix") 
#' is a matrix containing filtering results for each specified gate and the 
#' second element ("manual") is a vector which assigns a label to each cell
#'
#' @seealso \code{\link{PlotPies}}
#'
#' @examples
#' 
#'    # Read the flowFrame
#'    fileName <- system.file("extdata","lymphocytes.fcs",package="FlowSOM")
#'    ff <- flowCore::read.FCS(fileName)
#'    ff_c <- flowCore::compensate(ff,flowCore::description(ff)$SPILL)
#'    flowCore::colnames(ff_c)[8:18] <- paste("Comp-",
#'                                      flowCore::colnames(ff_c)[8:18],
#'                                      sep="")
#'        
#'    # Specify the gating file and the gates of interest
#'    gatingFile <- system.file("extdata","manualGating.xml", 
#'                              package="FlowSOM")
#'    gateIDs <- c( "B cells"=8,
#'                  "ab T cells"=10,
#'                  "yd T cells"=15,
#'                  "NK cells"=5,
#'                  "NKT cells"=6)
#'    cellTypes <- c("B cells","ab T cells","yd T cells",
#'                  "NK cells","NKT cells")
#'    gatingResult <- ProcessGatingML(ff_c, gatingFile, gateIDs, cellTypes)
#'    
#'    
#'    # Build a FlowSOM tree
#'    flowSOM.res <- FlowSOM(ff_c,compensate=FALSE,transform=TRUE,
#'                          toTransform=8:18,colsToUse=c(9,12,14:18),nClus=10)
#'    # Plot pies indicating the percentage of cell types present in the nodes
#'    PlotPies(flowSOM.res[[1]],gatingResult$manual)
#'
#' @export
ProcessGatingML <- function(flowFrame,gatingFile,gateIDs,
                            cellTypes,silent=FALSE){
    gating_xml <- XML::xmlToList(XML::xmlParse(gatingFile))
    flowEnv <- new.env()
    flowUtils::read.gatingML(gatingFile, flowEnv)
    #  A. Read the gates from xml
    filterList <- list()
    for(cellType in names(gateIDs)){
        filterList[[cellType]] <-  flowEnv[[
            as.character(gating_xml[[gateIDs[cellType]]]$.attrs["id"])
            ]]
    }
    #  B. Process the fcs file for all specified gates
    results <- matrix(NA,nrow=nrow(flowFrame),ncol=length(gateIDs),
                        dimnames = list(NULL,names(gateIDs)))
    for(cellType in names(gateIDs)){
        if(!silent){message(paste0("Processing ",cellType))}
        results[,cellType] <- flowCore::filter(flowFrame,
                                                filterList[[cellType]])@subSet
    }
    #  C. Assign one celltype to each cell
    manual <- rep("Unknown",nrow(flowFrame))
    for(celltype in cellTypes){
        manual[results[,celltype]] <- celltype
    }
    manual <- factor(manual,levels = c("Unknown",cellTypes))
    
    list("matrix"=results,"manual"=manual)
}