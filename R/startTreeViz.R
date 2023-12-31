.register_all_treeviz_things <- function(app) {
  
  app$server$register_action("registerChartTypes", function(request_data) {
    app$chart_mgr$.register_available_chart_types(request_data$data)
  })
  
  app$server$register_action("getHierarchy", function(request_data) {
    datasource = request_data$datasourceGroup
    nodeId = request_data$nodeId
    obj <- app$data_mgr$.find_datasource(datasource)
    if (is.null(obj)) {
      stop("cannot find datasource", datasource)
    }
    obj$getHierarchy(nodeId)
  })
  
  app$server$register_action("propagateHierarchyChanges", function(request_data) {
    
    datasource = request_data$datasourceGroup
    selection = request_data$selection
    order = request_data$order
    selectedLevels <- request_data$selectedLevels
    
    obj <- app$data_mgr$.find_datasource(datasource)
    if (is.null(obj)) {
      stop("cannot find datasource", datasource)
    }
    
    obj$propagateHierarchyChanges(selection, order, selectedLevels)
  })
  
  app$server$register_action("getRows", function(request_data) {
    datasource <- request_data$datasource
    seqName <- request_data$seqName
    start <- request_data$start
    end <- request_data$end
    metadata <- request_data$metadata
    
    obj <- app$data_mgr$.find_datasource(datasource)
    if (is.null(obj)) {
      stop("cannot find datasource", datasource)
    }
    obj$getRows(seqName, start, end, metadata)
  })
  
  app$server$register_action("getValues", function(request_data) {
    datasource <- request_data$datasource
    measurement <- request_data$measurement
    seqName <- request_data$seqName
    start <- request_data$start
    end <- request_data$end
    
    obj <- app$data_mgr$.find_datasource(datasource)
    if (is.null(obj)) {
      stop("cannot find datasource", datasource)
    }
    obj$getValues(measurement, seqName, start, end)
  })
  
  app$server$register_action("getCombined", function(request_data) {
    
    measurementsList <- request_data$measurements
    result <- lapply(names(measurementsList), function(m) {
      seqName <- request_data$seqName
      start <- request_data$start
      end <- request_data$end
      order <- request_data$order
      nodeSelection <- request_data$selection
      selectedLevels <- request_data$selectedLevels
      measurements <- measurementsList[[m]]
      
      if(is.null(start)) {
        start <- 0
      }
      else {
        start <- start
      }
      
      if(is.null(end)) {
        end <- 100000
      }
      else {
        end <- end
      }
      
      obj <- app$data_mgr$.find_datasource(m)
      if (is.null(obj)) {
        stop("cannot find datasource", m)
      }
      res <- obj$getCombined(measurements, seqName, start, end, order, nodeSelection, selectedLevels)
      res
    })
    names(result) <- names(measurementsList)
    result
  })
  
  app$server$register_action("splinesSettings", function(request_data) {
    updateAlpha <- as.double(request_data$settings$alpha)
    names_list <- ls(app$data_mgr$.ms_list)
    class_list <- lapply(names_list, function(i) {class(app$data_mgr$.get_ms_object(i))})
    obj <- app$data_mgr$.get_ms_object(names_list[which(class_list == "EpivizMetagenomicsDataTimeSeries")][1])
    obj$updateSplineAlpha(updateAlpha)
    return(list())
  })
  
  app$server$register_action("getSeqInfos", function(request_data) {
    return(list(
      "treevizr" = c(0, 100000)
    ))
  })
  
  app$server$register_action("partitions", function(request_data) {
    return(list(
      "treevizr" = c(0, 100000)
    ))
  })
  
  app$server$register_action("getPCA", function(request_data) {
    
    obj <- app$data_mgr$.find_datasource(request_data$datasource)
    if (is.null(obj)) {
      stop("cannot find datasource", request_data$measurements)
    }
    
    result <- obj$getReducedDim(method=request_data$measurements[[request_data$datasource]][1],
                                gene=request_data$gene)
    result <- list(data = result)
    names(result) <- request_data$datasource
    result
    
  })
  
  app$server$register_action("getDiversity", function(request_data) {
    
    measurementsList <- request_data$measurements
    result <- lapply(names(measurementsList), function(m) {
      seqName <- request_data$seqName
      measurements <- measurementsList[[m]]
      
      obj <- app$data_mgr$.find_datasource(m)
      if (is.null(obj)) {
        stop("cannot find datasource", m)
      }
      obj$getGeneExpr(measurements)
    })
    names(result) <- names(measurementsList)
    result
    
  })
  
  app$server$register_action("search", function(request_data) {
    query <- request_data$q
    max_results <- request_data$maxResults
    datasource = request_data$datasourceGroup
    
    obj <- app$data_mgr$.find_datasource(datasource)
    if (is.null(obj)) {
      stop("cannot find datasource", datasource)
    }
    
    list(nodes = obj$searchTaxonomy(query, max_results))
  })
  
  app$server$register_action("setChartSettings", function(request_data) {
    app$chart_mgr$.update_chart_settings(request_data)
  })
}

.wait_until_connected <- function(server, timeout=60L) {
  ptm <- proc.time()
  while (!server$is_socket_connected() && (proc.time() - ptm < timeout)["elapsed"]) {
    Sys.sleep(0.001)
    server$service()
  }
  if (!server$is_socket_connected()) {
    stop("[epivizrStandalone] Error starting app. UI unable to connect to websocket server.")
  }
  invisible()
}

.delay_requests <- function(server, timeout=2L) {
  ptm <- proc.time()
  
  while ((proc.time() - ptm < timeout)["elapsed"]) {
    Sys.sleep(0.001)
    server$service()
  }
  invisible()
}

.viewer_option_browse_fun <- function(url) {
  viewer <- getOption("viewer")
  if (is.null(viewer)) {
    utils::browseURL(url)
  } else {
    viewer(url)
  }
}


#' Start treeviz app and create \code{\link[scTreeViz]{TreeVizApp}} object to manage connection.
#'
#' @param data TreeViz object to explore
#' @param genes (character vector) genes (rownames) to include in heatmap
#' @param top_genes (integer) number of top variable genes to include in the heatmap 
#' @param host (character) host address to launch.
#' @param register_function (function) function used to register actions and charts on the treeviz app.
#' @param delay (integer) number of seconds to wait for application to load in browser
#' @param ... additional parameters passed to \code{\link[epivizr]{startEpiviz}}.
#'
#' @return An object of class \code{\link[scTreeViz]{TreeVizApp}}
#'
#' @import epivizr
#' @import sys
#'
#' @seealso \code{\link[scTreeViz]{TreeVizApp}}
#' @examples
#' # see package vignette for example usage
#' app <- startTreeviz(non_interactive=TRUE, open_browser=FALSE)
#' app$stop_app()
#'
#' @export
startTreeviz <- function(data = NULL, genes=NULL, top_genes=100, host="http://epiviz.cbcb.umd.edu/treeviz",
                         register_function = .register_all_treeviz_things, delay=2L,
                         ...) {
  chr="treevizr"
  start <- 0
  end <- 100000
  app <- startEpiviz(host = host, register_function = register_function,
                     chr=chr, start=start, end=end, ...)
  mApp <- TreeVizApp$new(.url_parms=app$.url_parms, .browser_fun=app$.browser_fun,
                         server=app$server, data_mgr=app$data_mgr, chart_mgr=app$chart_mgr)
  
  tryCatch({
    
    send_request <- mApp$server$is_interactive()
    
    if (mApp$server$is_interactive()) {
      .wait_until_connected(mApp$server)
    }
    
    if (!is.null(data)) {
      
      if (!is.null(genes)) {
        data <- set_gene_list(data, genes)
      } else {
        data <- .find_top_variable_genes(data, top_genes)
      }

      if (!("reduced_dim"  %in% names(metadata(data)))) {
        data <- .calculate_tsne(data)
      }
      
      mApp$navigate(chr, start, end)
      mApp$server$wait_to_clear_requests()
      .delay_requests(mApp$server, timeout =  delay)
      
      # facetZoom
      facetZoom <- mApp$data_mgr$add_measurements(data, datasource_name = "SCRNA", tree = "col", datasource_origin_name="scrna", send_request=send_request)
      mApp$server$wait_to_clear_requests()
      .delay_requests(mApp$server, timeout = delay)
      
      ms_list <- facetZoom$get_measurements()
      mea <- ms_list[[1]]
      mea@id <- "all"
      
      mApp$chart_mgr$visualize(chart_type = "epiviz.ui.charts.tree.Icicle",  measurements = list(mea))
      mApp$server$wait_to_clear_requests()
      .delay_requests(mApp$server, timeout = delay)
      
      mApp$chart_mgr$visualize(chart_type = "HeatmapPlot",  measurements = list(mea))
      mApp$server$wait_to_clear_requests()
      .delay_requests(mApp$server, timeout=delay)
      
      if ("reduced_dim" %in% names(metadata(data))) {
        for (dim in names(metadata(data)$reduced_dim)) {
          ms_list <- facetZoom$get_measurements()
          mea <- ms_list[[1]]
          mea@id <- dim
          
          # TSNE
          mApp$chart_mgr$visualize(chart_type = "TSNEPlot", measurements = list(mea))
          mApp$server$wait_to_clear_requests()
          .delay_requests(mApp$server, timeout=delay)
        }        
      }
    }
  }, error=function(e) {
    mApp$stop_app()
    stop(e)
  })
  
  mApp
}


.viewer_option_browse_fun <- function(url) {
  viewer <- getOption("viewer")
  if (is.null(viewer)) {
    utils::browseURL(url)
  } else {
    viewer(url)
  }
}
