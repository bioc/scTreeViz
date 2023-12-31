.check_alternate <- function(sub_df, all_df) {
  #check where clusters from not-core edges should actually belong
  assign_df <- data.frame(
    "Sink_node_res" = character(),
    "Sink_node_clust" = character(),
    "Assign_from_res" = character(),
    "Assign_from_clust" = character(),
    "Assign_to_res" = character(),
    "Assign_to_clust" = character(),
    stringsAsFactors = FALSE
  )
  for (i in seq_len(nrow(sub_df))) {
    for (j in seq_len(nrow(all_df))) {
      if (sub_df$to_node[i] == all_df$to_node[j]) {
        assign_df[nrow(assign_df) + 1, ] <-
          c(
            sub_df$to_cluster[i],
            sub_df$to_clust[i],
            sub_df$from_cluster[i],
            sub_df$from_clust[i],
            all_df$from_cluster[j],
            all_df$from_clust[j]
          )
      }
    }
  }
  
  assign_df
}


.change_assignment <- function(graph, cluster_obj) {
  #for each row in the core edge false dataset, find out corresponding
  #source and sink in Seurat, and change accordingly
  for (i in seq_len(nrow(graph))) {
    sink_res = match(paste0('cluster', graph$`Sink_node_res`[i]),
                     colnames(cluster_obj))
    source_res = match(paste0('cluster', graph$`Assign_from_res`[i]),
                       colnames(cluster_obj))
    
    
    for (j in seq_len(nrow(cluster_obj))) {
      
      if (as.numeric(as.character(cluster_obj[[j, sink_res]])) == as.numeric(graph$Sink_node_clust[i])  &&
          as.numeric(as.character(cluster_obj[[j, source_res]])) == as.numeric(graph$Assign_from_clust[i])) {
        cluster_obj[[j, source_res]] <-
          as.factor(graph$`Assign_to_clust`[i])
      }
      
    }
  }
  
  return (cluster_obj)
}

#' @importFrom utils str
#' @import igraph
.check_cycle <- function(pruned_graph) {
  # Check if a diamond or circle still exists in tree
  delete_set_vertices <- vector('numeric')
  ver_list <- V(pruned_graph)
  
  for (nodes in ver_list) {
    adj_edge <- incident(pruned_graph, nodes, mode = "in")
    
    if (length(adj_edge) > 1) {
      # Not a Tree yet
      adj_ver <-
        adjacent_vertices(pruned_graph, nodes, mode = "in")
      adj_ver <- as_ids(adj_ver[[1]])
      str(adj_ver)
      remove_node <- sample(adj_ver, 1)
      
      remove_edge <-
        incident(pruned_graph, remove_node, mode = "all")
      
      pruned_graph <- delete_edges(pruned_graph, remove_edge)
      delete_set_vertices <-
        c(delete_set_vertices, remove_node)
      
    }
  }
  pruned_graph <- delete.vertices(pruned_graph, delete_set_vertices)
}

.prune_tree <- function(graph, cluster_df) {
  # Prune the tree so only core edges remain
  
  repeat {
    # drop duplicated columns (Throws error otherwise)
    
    graph <- graph[!duplicated(names(graph))]
    
    # See number of core edges at each iter
    # No False edges acyclic tree
    if (nrow(graph[graph$is_core == FALSE, ]) == 0) {
      ngraph <-
        clustree(
          cluster_df ,
          prefix = "cluster",
          prop_filter = 0,
          return = "graph"
        )
      break
    }
    
    # Apply function
    assign_df <-
      .check_alternate(graph[graph$is_core == FALSE, ], graph[graph$is_core == TRUE, ])
    
    cluster_df <- .change_assignment(assign_df, cluster_df)
    ngraph <-
      clustree(
        cluster_df ,
        prefix = "cluster",
        prop_filter = 0,
        return = "graph"
      )
    
    graph <- as_long_data_frame(ngraph)
  }
  
  ngraph <- .check_cycle(ngraph)
  
  result <-
    list("Cluster_obj" = cluster_df, "Clustree_obj" = ngraph)
  result
}

.collapse_tree <- function(original_graph) {
  #find all roots
  root_list <- which(
    vapply(
      V(original_graph),
      function(x) {
        length(neighbors(original_graph, x, mode = "in")) == 0
      },
      logical(1)
    ))
  
  delete_set_vertices <- vector('numeric')
  for (roots in root_list) {
    node_dists <- distances(original_graph, to = roots)
    layered_dist <- unique(distances(original_graph, to = roots))
    
    layered_dist <- layered_dist[is.finite(layered_dist) == TRUE]
    # Vertex and edge lists of the graph from which we will construct the collapsed graph
    
    ver_list <-
      igraph::as_data_frame(original_graph, what = "vertices")
    
    
    i <- length(layered_dist)
    while (i >= 2) {
      prev_layer <- which(node_dists == layered_dist[i - 1])
      current_layer <- which(node_dists == layered_dist[i])
      
      if (length(prev_layer) == length(current_layer)) {
        while (length(prev_layer) == length(current_layer)) {
          delete_set_vertices <- c(delete_set_vertices, prev_layer)
          i <- i - 1
          
          prev_layer <-
            which(node_dists == layered_dist[i - 1])
          
        }
      }
      i <- i - 1
    }
  }
  
  if (length(delete_set_vertices) != 0) {
    message("Collapsing the graph by removing redundant nodes")
    ver_list <- ver_list[-delete_set_vertices, ]
  }
  ver_list
}

.checkRoot <- function(cluster_df) {
  # Handle Forests
  cols <- colnames(cluster_df)
  if (length(unique(cluster_df[[1]])) > 1) {
    message("Given Tree is a Forest\n Adding extra root")
    cluster_df$root <- "ClusterAllClusters"
    cols <- c("root", cols)
  }
  
  cluster_df[cols]
}

.check_unique_parent <- function(clusterdata) {
  #check if user provided data has unique parents at each level
  for (i in seq(2, ncol(clusterdata))) {
    childs <- unique(clusterdata[[i]])
    for (values in childs) {
      subsetted_list <-
        clusterdata[clusterdata[[colnames(clusterdata)[[i]]]] == values, ]
      
      
      parent <- length(unique(subsetted_list[[i - 1]]))
      
      if (parent > 1) {
        message(
          "Not a tree, some nodes with multiple parents in level ",
          i,
          "\n Performing Cluster reassignment "
        )
        return (FALSE)
      }
    }
  }
  return(TRUE)
}


.rename_clusters <- function(clusterdata) {
  message("Renaming cluster Levels...")
  message("Previous Level names ", paste(colnames(clusterdata), collapse = "\t"))
  
  clusnames <- seq_len(length(colnames(clusterdata)))
  clusnames <- paste0("cluster", clusnames)
  colnames(clusterdata) <- clusnames
  message("New Level names ", paste(colnames(clusterdata), collapse = "\t"))
  clusterdata
}


#' @import clustree
#' @importFrom data.table setorder
#' @importFrom igraph as_long_data_frame
.preprocessAndCreateTreeViz <- function(clusters, counts) {
  clusters <- .rename_clusters(clusters)
  setorder(clusters)
  counts <- counts[, rownames(clusters)]
  
  # Create clustree object
  clustree_graph <-
    clustree(
      clusters,
      prefix = "cluster",
      prop_filter = 0,
      return = "graph"
    )
  
  graph_df <- as_long_data_frame(clustree_graph)
  
  # prune the graph with only core edges (this makes it a ~tree)
  modified_obj <- .prune_tree(graph_df, clusters)
  
  # modified graph and seurat object
  modified_graph <- modified_obj$Clustree_obj
  clusters_new <-  modified_obj$Cluster_obj
  
  # collapses tree if the levels are the same at different resolutions
  collapsed_graph <- .collapse_tree(modified_graph)
  cluster_names <- unique(vapply(strsplit(collapsed_graph$node, "C"), '[', chracter(1), 1))
  clusters_new <- clusters_new[, cluster_names]
  
  for (clusnames in names(clusters_new)) {
    clusters_new[[clusnames]] <-
      paste(clusnames, clusters_new[[clusnames]], sep = 'C')
  }
  
  samples <- rownames(clusters_new)
  clusters_new <- cbind(clusters_new, samples)
  clusters_new <- .checkRoot(clusters_new)
  
  tree <- TreeIndex(clusters_new)
  rownames(tree) <- rownames(clusters_new)
  
  treeviz <- TreeViz(SimpleList(counts = counts), colData = tree)
  treeviz
}

.generate_walktrap_hierarchy <- function(object, nsteps = 7) {
  
  message("calculating walktrap clusters")
  SNN_Graph <- scran::buildSNNGraph(object)
  clusters <- igraph::cluster_walktrap(SNN_Graph, steps = nsteps)
  modularity <- c()
  
  for (i in seq_len(length(clusters))) {
    modularity[i] <-
      igraph::modularity(SNN_Graph, igraph::cut_at(clusters, n = i))
  }
  
  monotonic_index <- match(unique(cummax(modularity)), modularity)
  cluster_data =  list()
  for (i in seq_along(monotonic_index)) {
    cluster_data[[i]] =  list(igraph::cut_at(clusters, n = monotonic_index[i]))
  }
  
  cluster_data <- as.data.frame(cluster_data)
  colnames(cluster_data) <- paste0("cluster", monotonic_index)
  cluster_data$samples <- rownames(cluster_data) <- colnames(object)
  cluster_data
}

#' Creates a `TreeViz` object from `Seurat`
#'
#' @param object `Seurat` class containing cluster information at different resolutions
#' @param check_metadata whether to metaData of `Seurat` object for cluster information or not
#' @param col_regex common regular expression shared across all columns with cluster information
#' @param columns vector containing columns with cluster information
#' @param reduced_dim Vector of Dimensionality reduction information provided in `Seurat` object to be added in `TreeViz` (if exists)
#' @return `TreeViz` Object
#' @examples
#' library(Seurat)
#' data(pbmc_small)
#' pbmc <- pbmc_small
#' treeviz<- createFromSeurat(pbmc, check_metadata = TRUE, reduced_dim = c("pca","tsne"))
#' @importFrom Seurat as.SingleCellExperiment
#' @importFrom Seurat GetAssayData
#' @importFrom Seurat Reductions
#' @export
createFromSeurat <- function(object,
                             check_metadata = FALSE,
                             col_regex = "*snn*",
                             columns = NULL,
                             reduced_dim = c("TSNE")) {
  
  if (check_metadata==FALSE) {
    message("No default clusters provided")
    object.sce <- as.SingleCellExperiment(object)
    clusterdata <- .generate_walktrap_hierarchy(object.sce)
    clusterdata <- ClusterHierarchy(clusterdata)
  }
  else{
    clusterdata <- object@meta.data
    clusterdata$samples <- rownames(clusterdata) <- colnames(object)
    clusterdata <- ClusterHierarchy(clusterdata, col_regex, columns)
  }
  
  treeviz <- createTreeViz(clusterdata, GetAssayData(object))
  
  for (dim_names in reduced_dim) {
    if (dim_names %in% Reductions(object)) {
      reducdim <- Reductions(object, slot = dim_names)
      
      metadata(treeviz)$reduced_dim[[dim_names]] <- reducdim@cell.embeddings[, c(1,2)]
      rownames(metadata(treeviz)$reduced_dim[[dim_names]]) <- colnames(object)
    }
  }
  
  print(names(metadata(treeviz)$reduced_dim))
  treeviz
}

#' Creates a `TreeViz`` object from `SingleCellExperiment`. Generates
#' clusters based on Walktrap algorithm if no default is provided
#' @param object `SingleCellExperiment` object to be visualized
#' @param check_coldata whether to colData of `SingeCellExperiment` object for cluster information or not
#' @param col_regex common regular expression shared across all columns with cluster information
#' @param columns vector containing columns with cluster information
#' @param reduced_dim Vector of Dimensionality reduction information provided in `SingeCellExperiment` object to be added in `TreeViz` (if exists)
#' @return `TreeViz` Object
#' @examples
#' library(SingleCellExperiment)
#' library(scater)
#' sce <- mockSCE()
#' sce <- logNormCounts(sce)
#' sce <- runTSNE(sce)
#' sce <- runUMAP(sce)
#' set.seed(1000)
#' for (i in  seq_len(5)) {
#' clust.kmeans <- kmeans(reducedDim(sce, "TSNE"), centers = i)
#' sce[[paste0("clust", i)]] <- factor(clust.kmeans$cluster)
#' }
#' treeviz <-createFromSCE(sce, check_coldata = TRUE, col_regex = "clust", reduced_dim = c("TSNE", "UMAP"))
#' 
#' @import SingleCellExperiment
#' @export
createFromSCE <-
  function(object,
           check_coldata = FALSE,
           col_regex = NULL,
           columns = NULL,
           reduced_dim = c("TSNE")) {
    
    if (check_coldata == TRUE) {
      clusterdata <- colData(object)
      clusterdata$samples <- rownames(clusterdata) <- colnames(object)
      clusterdata <- ClusterHierarchy(clusterdata, col_regex, columns)
    }
    else{
      message("No default clusters provided")
      clusterdata <- .generate_walktrap_hierarchy(object)
      clusterdata$samples <- rownames(clusterdata) <- colnames(object)
      clusterdata <- ClusterHierarchy(clusterdata)
    }
    
    count <- counts(object)
    rownames(count) <- rownames(counts(object))
    
    treeviz <- createTreeViz(clusterdata, count)
    for (dim_names in reduced_dim) {
      if (dim_names %in% reducedDimNames(object)) {
        metadata(treeviz)$reduced_dim[[dim_names]] <-
          reducedDims(object)[[dim_names]][, c(1,2)]
        
        rownames(metadata(treeviz)$reduced_dim[[dim_names]]) <- colnames(object)
      }
    }
    
    treeviz
  }

#' Creates `TreeViz` object from hierarchy and count matrix
#' 
#' Provided with a count matrix and a dataframe or `ClusterHierarchy` object, this module 
#' runs the necessary checks on the dataframe and tries to convert it to a tree by making necessary changes.
#' Returns the `TreeViz` object if a tree is successfully generated from dataframe, throws error otherwise
#' @param clusters `ClusterHierarchy` object or a dataframe containing cluster information at different resolutions
#' @param counts matrix Dense or sparse matrix containing the count matrix
#' @return `TreeViz`` Object
#' @examples
#' n=64
#' # create a hierarchy
#' df<- data.frame(cluster0=rep(1,n))
#' for(i in seq_len(5)){
#'   df[[paste0("cluster",i)]]<- rep(seq(1:(2**i)),each=ceiling(n/(2**i)),len=n)
#' }
#' # generate a count matrix
#' counts <- matrix(rpois(6400, lambda = 10), ncol=n, nrow=100)
#' colnames(counts)<- seq_len(64)
#' # create a `TreeViz` object
#' treeViz <- createTreeViz(df, counts)
#' 
#' @export
createTreeViz <- function(clusters, counts) {
  
  if (is(clusters,"data.frame") ){
    clusters$samples <- rownames(clusters) <- colnames(counts)
    clusters <- ClusterHierarchy(clusters)
  }
  
  
  if (!is(clusters, "ClusterHierarchy")) {
    stop("clusters is not a ClusterHierarchy class")
  }
  
  counts <- counts[,clusters$samples]
  column_names <- colnames(clusters)
  clusters <- as.data.frame(clusters)
  colnames(clusters) <- column_names
  
  tree <- TreeIndex(clusters)
  rownames(tree) <- rownames(clusters)
  treeviz <- TreeViz(SimpleList(counts = counts), colData = tree)
  treeviz
}


#' @importFrom scran getTopHVGs
#' @importFrom scran modelGeneVar
.find_top_variable_genes <- function(treeviz, top = 100) {
  dec.treeviz <- modelGeneVar(assays(treeviz)$counts)
  top_n <- getTopHVGs(dec.treeviz, n = top)
  metadata(treeviz)$top_variable <- top_n
  
  treeviz
}

#' Sets gene list for visualization
#' @param treeviz TreeViz object
#' @param genes list of genes to use
#' @return TreeViz object set with gene list
set_gene_list <- function(treeviz, genes) {
  genes_in_assay  <- rownames(assays(treeviz)$counts)
  metadata(treeviz)$top_variable <- intersect(genes_in_assay, genes)
  
  treeviz
}

#' @importFrom scater calculateTSNE
.calculate_tsne <- function(treeviz) {
  message("No defaults dimensionality reductions provided")
  message("Calculating TSNE")
  tsne <- calculateTSNE(assays(treeviz)$counts)
  metadata(treeviz)$reduced_dim[['TSNE']] <- tsne[, c(1,2)]
  rownames(metadata(treeviz)$reduced_dim[['TSNE']]) <- colnames(treeviz)
  message("adding tsne to reduced dim slots")
  treeviz
}