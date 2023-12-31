#' show object
#' @param object TreeViz object
#' @importFrom methods show
#' @importFrom S4Vectors metadata
#' @export
#' 
#' @describeIn TreeViz-methods
#' 
#' @return describe a TreeIndex object
setMethod("show", signature("TreeViz"),
          function(object) {
            cat("class: TreeViz \n", sep = " ")
            cat("dim:", nrow(object), ncol(object), "\n", sep = " ")
            cat("metadata:\n")
            cat(show(names(metadata(object))))
            cat("rowData:\n")
            cat(show(rowData(object)), "\n")
            cat("colData:\n")
            cat(show(colnames(colData(object))))
          })

#' Method to aggregate a TreeViz object
#' @param x object
#' @param ... other params to the function
#' 
#' @describeIn TreeViz-methods
#' 
#' @examples
#' \donttest{ 
#' library(metagenomeSeq)
#' data(mouseData)
#' counts <- MRcounts(mouseData)
#' hierarchy <- fData(mouseData)
#' tree <- TreeIndex(hierarchy)
#' mbiome <- TreeViz(SimpleList(counts=counts), rowData=tree)
#' aggregateTree(mbiome)
#' }
#' @return a generic
#' @export
setGeneric("aggregateTree", signature = "x",
           function(x, ...)
             standardGeneric("aggregateTree"))

#' Method to aggregate a TreeViz object
#' @param x TreeViz object
#' @param selectedLevel level to select nodes from
#' @param selectedNodes used to set states on individual nodes to define a cut on the tree
#' @param start,end indices to filter nodes
#' @param by "row" to aggregate the TreeIndex on rowData, "col" to aggregate TreeIndex on colData
#' @param aggFun aggregate function to use, by default colSums if by="row", rowSums if by="col"
#' @param format return format can be one of "counts" or "TreeViz"
#' @importFrom Matrix rowSums colSums
#' @return a Treeviz object or type specified by format
#' 
#' @describeIn TreeViz-methods
#' 
#' @examples
#' \donttest{ 
#' library(metagenomeSeq)
#' data(mouseData)
#' counts <- MRcounts(mouseData)
#' hierarchy <- fData(mouseData)
#' tree <- TreeIndex(hierarchy)
#' mbiome <- TreeViz(SimpleList(counts=counts), rowData=tree)
#' aggregateTree(mbiome)
#' }
#' @export
setMethod("aggregateTree", "TreeViz",
          function(x,
                   selectedLevel = 3,
                   selectedNodes = NULL,
                   aggFun = colSums,
                   start = 1,
                   end = NULL,
                   by = "row",
                   format = "TreeViz") {
            if (is.null(end) || missing(end)) {
              end <- nrow(x)
            }
            
            if(is(selectedNodes, "data.table")) {
              node_ids <- selectedNodes$id
              snodes <- rep(1, length(node_ids))
              
              if("state" %in% colnames(selectedNodes)) {
                snodes <- selectedNodes$state
              }
              names(snodes) <- node_ids
              selectedNodes <- snodes
            }
            
            if (by == "row") {
              aggFun <- colSums
              groups <-
                splitAt(
                  rowData(x),
                  selectedLevel = selectedLevel,
                  selectedNodes = selectedNodes,
                  start = start,
                  end = end,
                  format = "list"
                )
              counts <-  assays(x)$counts
              
              newMat <- array(NA, dim = c(length(groups), ncol(x)))
              for (i in seq_along(groups)) {
                indices <- groups[[i]]
                if (length(indices) == 1) {
                  newMat[i, ] = counts[indices, ]
                }
                else {
                  newMat[i, ] = aggFun(counts[indices, ])
                }
              }
              
              rownames(newMat) <- names(groups)
              colnames(newMat) <- colnames(x)
              
            }
            else if (by == "col") {
              aggFun <- rowSums
              groups <-
                splitAt(
                  colData(x),
                  selectedLevel = selectedLevel,
                  selectedNodes = selectedNodes,
                  start = start,
                  end = end,
                  format = "list"
                )
              counts <-  assays(x)$counts
              
              newMat <- array(NA, dim = c(nrow(x), length(groups)))
              for (i in seq_along(groups)) {
                indices <- groups[[i]]
                if (length(indices) == 1) {
                  newMat[, i] = counts[, indices]
                }
                else {
                  newMat[, i] = aggFun(counts[, indices])
                }
              }
              
              colnames(newMat) <- names(groups)
              rownames(newMat) <- rownames(x)
            }
            
            if(!is.null(selectedNodes)) {
              return(newMat)
            }
            
            if (format == "TreeViz") {
              if (by == "row") {
                newRowData <-
                  splitAt(
                    rowData(x),
                    selectedLevel = selectedLevel,
                    selectedNodes = selectedNodes,
                    start = start,
                    end = end,
                    format = "TreeIndex"
                  )
                
                newColData <- colData(x)
              }
              else if (by == "col") {
                newRowData <- rowData(x)
                newColData <-
                  splitAt(
                    colData(x),
                    selectedLevel = selectedLevel,
                    selectedNodes = selectedNodes,
                    start = start,
                    end = end,
                    format = "TreeIndex"
                  )
              }
              
              newSumExp <-
                SummarizedExperiment(SimpleList(counts = newMat), rowData = newRowData, colData = newColData)
              
              newTreeSE <- new("TreeViz", newSumExp)
              
              return(newTreeSE)
            }
            else if (format == "counts") {
              return(newMat)
            }
          })

#' Generic method to register data to the epiviz data server
#'
#' @param object The object to register to data server
#' @param tree Is tree over rows or columns of the object (default: "row")
#' @param columns Name of columns containing data to register
#' @param ... Additional arguments passed to object constructors
#' @return An \code{\link{EpivizTreeData-class}} object
#' 
#' @describeIn TreeViz-methods
#' 
#' @importMethodsFrom epivizrData register
#'
setMethod("register", "TreeViz", function(object, tree="row", columns=NULL, ...) {
  return(EpivizTreeData$new(object=object, tree=tree, columns=columns, ...))
})

#' plot tree from TreeViz
#'
#' @param x treeviz object
#' @param y none
#' @return Dataframe containing cluster information at different resolutions
#' 
#' @import ggraph
#' @importFrom igraph graph_from_data_frame
#' @importFrom ggplot2 aes
#' 
#' @describeIn TreeViz-methods
#' 
#' @examples
#' \donttest{
#' library(metagenomeSeq)
#' data(mouseData)
#' counts <- MRcounts(mouseData)
#' hierarchy <- fData(mouseData)
#' tree <- TreeIndex(hierarchy)
#' mbiome <- TreeViz(SimpleList(counts=counts), rowData=tree)
#' plot(mbiome)
#' }
#' @export
#' 
setMethod("plot", "TreeViz", function(x, y) {
  object <- x
  
  if(is(colData(object), "TreeIndex")) {
    hierarchydf <- colData(object)@hierarchy_tree
  }
  else {
    hierarchydf <- rowData(object)@hierarchy_tree
  }
  
  
  hierarchydf <- hierarchydf[, !colnames(hierarchydf) %in% c("samples", "otu_index")]
  
  df <- data.frame(from = numeric(), to = numeric())
  
  for (i in seq_len(ncol(hierarchydf) - 1)) {
    edges<- hierarchydf[,c(i,i+1)]
    edges<-unique(edges)
    colnames(edges)<- c("from","to")
    df <- rbind(df, edges)
  }
  
  mygraph <- graph_from_data_frame(df)
  .nms <- V(mygraph)$name
  .nm_suffix <- vapply(.nms, function(nm) substring(nm, first=length(nm)-4, last=length(nm)), character(1))
  V(mygraph)$plot_label <- 
    paste0(substring(.nms, first=1, last=4), "...", .nm_suffix)


  fig <- ggraph(mygraph, layout = 'dendrogram', circular = FALSE) +
    ggraph::geom_edge_diagonal() +
    ggraph::geom_node_point(show.legend = TRUE) +
    ggplot2::theme_void()
  show(fig)
  
})
