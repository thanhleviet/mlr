#' @title Calculates feature filter values.
#'
#' @description
#' Calculates numerical filter values for features.
#' For a list of features, use \code{\link{listFilterMethods}}.
#'
#' @family generate_plot_data
#' @family filter
#' @aliases FilterValues
#'
#' @template arg_task
#' @param method [\code{character}]\cr
#'   Filter method(s), see above.
#'   Default is \dQuote{randomForestSRC.rfsrc}.
#' @param nselect [\code{integer(1)}]\cr
#'   Number of scores to request. Scores are getting calculated for all features per default.
#' @param ... [any]\cr
#'   Passed down to selected method. Can only be use if \code{method} contains one element.
#' @param more.args [named list]\cr
#'   Extra args passed down to filter methods. List elements are named with the filter
#'   \code{method} name the args should be passed down to.
#'   A more general and flexible option than \code{...}.
#'   Default is empty list.
#' @return [\code{FilterValues}]. A \code{list} containing:
#'   \item{task.desc}{[\code{\link{TaskDesc}}]\cr
#'	   Task description.}
#'   \item{data}{[\code{data.frame}] with columns:
#'     \itemize{
#'       \item \code{name} Name of feature.
#'       \item \code{type} Feature column type.
#'       \item A column for each \code{method} with
#'                   the feature importance values.
#'     }}
#' @export
generateFilterValuesData = function(task, method = "randomForestSRC.rfsrc", nselect = getTaskNFeats(task), ..., more.args = list()) {
  assert(checkClass(task, "ClassifTask"), checkClass(task, "RegrTask"), checkClass(task, "SurvTask"))
  assertSubset(method, choices = ls(.FilterRegister), empty.ok = FALSE)
  td = getTaskDescription(task)
  filter = lapply(method, function(x) .FilterRegister[[x]])
  if (!(any(sapply(filter, function(x) !isScalarNA(filter$pkg)))))
    lapply(filter, function(x) requirePackages(x$pkg, why = "generateFilterValuesData", default.method = "load"))
  check_task = sapply(filter, function(x) td$type %nin% x$supported.tasks)
  if (any(check_task))
    stopf("Filter(s) %s not compatible with task of type '%s'",
          stri_paste("'", method[check_task], "'", collapse = ", "), td$type)

  check_feat = lapply(filter, function(x) setdiff(names(td$n.feat[td$n.feat > 0L]), x$supported.features))
  check_length = sapply(check_feat, length) > 0L
  if (any(check_length)) {
    stopf("Filter(s) %s not compatible with features of type %s respectively",
          stri_paste("'", method[check_length], "'", collapse = ", "),
          stri_paste(sapply(check_feat[check_length], function(x) stri_paste("'", x, "'", collapse = ", ")), collapse = ", and "))
  }
  assertCount(nselect)
  assertList(more.args, names = "unique", max.len = length(method))
  assertSubset(names(more.args), method)
  dot.args = list(...)
  if (length(dot.args) > 0L && length(more.args) > 0L)
    stopf("Do not use both 'more.args' and '...' here!")

  # we have dot.args, so we cannot have more.args. either complain (> 1 method) or
  # auto-setup more.args as list
  if (length(dot.args) > 0L) {
    if (length(method) == 1L)
     more.args = namedList(method, dot.args)
    else
      stopf("You use more than 1 filter method. Please pass extra arguments via 'more.args' and not '...' to filter methods!")
  }

  fn = getTaskFeatureNames(task)

  fval = lapply(filter, function(x) {
    x = do.call(x$fun, c(list(task = task, nselect = nselect), more.args[[x$name]]))
    missing.score = setdiff(fn, names(x))
    x[missing.score] = NA_real_
    x[match(fn, names(x))]
  })

  fval = do.call(cbind, fval)
  colnames(fval) = method
  types = vcapply(getTaskData(task, target.extra = TRUE)$data[fn], getClass1)
  out = data.frame(name = row.names(fval),
                   type = types,
                   fval, row.names = NULL, stringsAsFactors = FALSE)
  makeS3Obj("FilterValues",
            task.desc = td,
            data = out)
}
#' @export
print.FilterValues = function(x, ...) {
  catf("FilterValues:")
  catf("Task: %s", x$task.desc$id)
  printHead(x$data)
}
#' @title Calculates feature filter values.
#'
#' @family filter
#' @family generate_plot_data
#'
#' @description
#' Calculates numerical filter values for features.
#' For a list of features, use \code{\link{listFilterMethods}}.
#'
#' @template arg_task
#' @param method [\code{character(1)}]\cr
#'   Filter method, see above.
#'   Default is \dQuote{randomForestSRC.rfsrc}.
#' @param nselect [\code{integer(1)}]\cr
#'   Number of scores to request. Scores are getting calculated for all features per default.
#' @param ... [any]\cr
#'   Passed down to selected method.
#' @return [\code{\link{FilterValues}}].
#' @note \code{getFilterValues} is deprecated in favor of \code{\link{generateFilterValuesData}}.
#' @family filter
#' @export
getFilterValues = function(task, method = "randomForestSRC.rfsrc", nselect = getTaskNFeats(task), ...) {
  .Deprecated("generateFilterValuesData")
  assertChoice(method, choices = ls(.FilterRegister))
  out = generateFilterValuesData(task, method, nselect, ...)
  colnames(out$data)[3] = "val"
  out$data = out$data[, c(1,3,2)]
  makeS3Obj("FilterValues",
            task.desc = out$task.desc,
            method = method,
            data = out$data)
}
#' Plot filter values using ggplot2.
#'
#' @family filter
#' @family generate_plot_data
#'
#' @param fvalues [\code{\link{FilterValues}}]\cr
#'   Filter values.
#' @param sort [\code{character(1)}]\cr
#'   Sort features like this.
#'   \dQuote{dec} = decreasing, \dQuote{inc} = increasing, \dQuote{none} = no sorting.
#'   Default is decreasing.
#' @param n.show [\code{integer(1)}]\cr
#'   Number of features (maximal) to show.
#'   Default is 20.
#' @param feat.type.cols [\code{logical(1)}]\cr
#'   Colors for factor and numeric features.
#'   \code{FALSE} means no colors.
#'   Default is \code{FALSE}.
#' @template arg_facet_nrow_ncol
#' @template ret_gg2
#' @export
#' @examples
#' fv = generateFilterValuesData(iris.task, method = "chi.squared")
#' plotFilterValues(fv)
plotFilterValues = function(fvalues, sort = "dec", n.show = 20L, feat.type.cols = FALSE, facet.wrap.nrow = NULL, facet.wrap.ncol = NULL) {
  assertClass(fvalues, classes = "FilterValues")
  assertChoice(sort, choices = c("dec", "inc", "none"))
  if (!(is.null(fvalues$method)))
    stop("fvalues must be generated by generateFilterValuesData, not getFilterValues, which is deprecated.")

  n.show = asCount(n.show)

  data = fvalues$data
  methods = colnames(data[, -which(colnames(data) %in% c("name", "type")), drop = FALSE])
  n.show = min(n.show, max(sapply(methods, function(x) sum(!is.na(data[[x]])))))
  data = melt(as.data.table(data), id.vars = c("name", "type"), variable = "method")

  if (sort != "none")
    data = do.call(rbind, lapply(methods, function(x)
      head(sortByCol(data[data$method == x, ], "value", (sort == "inc")), n.show)))

  data$name = factor(data$name, levels = as.character(unique(data$name)))
  if (feat.type.cols)
    mp = aes_string(x = "name", y = "value", fill = "type")
  else
    mp = aes_string(x = "name", y = "value")
  plt = ggplot(data = data, mapping = mp)
  plt = plt + geom_bar(position = "identity", stat = "identity")
  if (length(unique(data$method)) > 1L) {
    plt = plt + facet_wrap(~ method, scales = "free_y",
      nrow = facet.wrap.nrow, ncol = facet.wrap.ncol)
    plt = plt + labs(title = sprintf("%s (%i features)",
                                              fvalues$task.desc$id,
                                              sum(fvalues$task.desc$n.feat)),
                              x = "", y = "")
  } else {
    plt = plt + labs(title = sprintf("%s (%i features), filter = %s",
                                              fvalues$task.desc$id,
                                              sum(fvalues$task.desc$n.feat),
                                              methods),
                              x = "", y = "")
  }
  plt = plt + theme(axis.text.x = element_text(angle = 45, hjust = 1))
  return(plt)
}
#' Plot filter values using ggvis.
#'
#' @family plot
#' @family filter
#'
#' @param fvalues [\code{\link{FilterValues}}]\cr
#'   Filter values.
#' @param feat.type.cols [\code{logical(1)}]\cr
#'   Colors for factor and numeric features.
#'   \code{FALSE} means no colors.
#'   Default is \code{FALSE}.
#' @template ret_ggv
#' @export
#' @examples \dontrun{
#' fv = generateFilterValuesData(iris.task, method = "chi.squared")
#' plotFilterValuesGGVIS(fv)
#' }
plotFilterValuesGGVIS = function(fvalues, feat.type.cols = FALSE) {
  assertClass(fvalues, classes = "FilterValues")
  if (!(is.null(fvalues$method)))
    stop("fvalues must be generated by generateFilterValuesData, not getFilterValues, which is deprecated.")

  data = fvalues$data
  data = setDF(melt(as.data.table(data), id.vars = c("name", "type"), variable = "method"))

  create_plot = function(data, feat.type.cols) {
    if (feat.type.cols)
      plt = ggvis::ggvis(data, ggvis::prop("x", as.name("name")),
                         ggvis::prop("y", as.name("value")),
                         ggvis::prop("fill", as.name("type")))
    else
      plt = ggvis::ggvis(data, ggvis::prop("x", as.name("name")),
                         ggvis::prop("y", as.name("value")))

    plt = ggvis::layer_bars(plt)
    plt = ggvis::add_axis(plt, "y", title = "")
    plt = ggvis::add_axis(plt, "x", title = "")
    return(plt)
  }

  gen_plot_data = function(data, sort_type, value_column, factor_column, n_show) {
    if (sort_type != "none") {
      data = head(sortByCol(data, "value", FALSE), n = n_show)
      data[[factor_column]] = factor(data[[factor_column]],
                                     levels = data[[factor_column]][order(data[[value_column]],
                                                                          decreasing = sort_type == "decreasing")])
    }
    data
  }

  header = shiny::headerPanel(sprintf("%s (%i features)", fvalues$task.desc$id, sum(fvalues$task.desc$n.feat)))
  method_input = shiny::selectInput("level_variable", "choose a filter method",
                                    unique(levels(data[["method"]])))
  sort_input = shiny::radioButtons("sort_type", "sort features", c("increasing", "decreasing", "none"))
  n_show_input = shiny::numericInput("n_show", "number of features to show",
                                     value = sum(fvalues$task.desc$n.feat),
                                     min = 1,
                                     max = sum(fvalues$task.desc$n.feat),
                                     step = 1)
  ui = shiny::shinyUI(
    shiny::pageWithSidebar(
      header,
      shiny::sidebarPanel(method_input, sort_input, n_show_input),
      shiny::mainPanel(shiny::uiOutput("ggvis_ui"), ggvis::ggvisOutput("ggvis"))
    )
  )
  server = shiny::shinyServer(function(input, output) {
    plt = shiny::reactive(
      create_plot(
        data = gen_plot_data(
          data[which(data[["method"]] == input$level_variable), ],
          input$sort_type,
          "value",
          "name",
          input$n_show
        ),
        feat.type.cols
      )
    )
    ggvis::bind_shiny(plt, "ggvis", "ggvis_ui")
  })
  shiny::shinyApp(ui, server)
}
