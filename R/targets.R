#' Get target report
#'
#' Generate a report for targets using both the progress and metadata reports.
#'
#' @name get_target_report
#' @export
get_target_report <- function() {
    report <-
        dplyr::left_join(
            targets::tar_progress(),
            targets::tar_meta(),
            by = "name",
            relationship = "one-to-one")

    report$minutes <- format(round(report$seconds / 60, 1))
    report$minutes[report$progress != "completed"] <- "-"
    return(report)
}

#' Send run report
#'
#' Generate and send a fancy formatted Teams message describing the outcome of
#' a targets run.
#'
#' @name send_run_report
#' @param project_name Project name
#' @param run_name Run name
#' @param ping Ping users in this message using their emails (case sensitive) as identifiers
#' @param err_msg Error message ($message component of error object)
#' @export
send_run_report <- function(project_name, run_name, ping, err_msg) {
    # Core report
    report <- get_target_report()
    items <- list(
        make_columnset(report, c("name", "progress", "minutes")))
    # Add error block
    if (!is.null(err_msg)) {
        items <- append(items, make_error_block(err_msg))
    }
    body <- make_base_card(
        task_name = paste(project_name, run_name, sep = "/"),
        status = dplyr::case_when(
            all(report$progress == "skipped") ~ "skipped",
            any(report$progress == "errored") ~ "failed",
            TRUE ~ "success"),
        items = items)
    send_card(body, ping)
}

#' Store files from targets run
#'
#' Stores a specific list of upload targets, validation files and metadata.
#'
#' @name store_run_data
#' @param run_name Run name
#' @param project_name Project name
#' @param container_url Azure container URL
#' @param upload_targets Name-strings of targets that should be uploaded
#' @param forced Overwrite blob version
#' @export
store_run_data <- function(run_name, project_name, container_url, upload_targets = c(), forced = FALSE) {
    blob_path <- stringr::str_glue("{project_name}/outputs/{run_name}")

    for (tn in upload_targets) {
        message(stringr::str_glue("Uploading '{tn}'..."))
        hud.keep::store_data(
            targets::tar_read_raw(tn),
            stringr::str_glue("{blob_path}/{tn}.rds"),
            container_url, forced = forced)
    }

    message("Uploading validation files...")
    hud.keep::store_folder(
        "validation",
        stringr::str_glue("{blob_path}/validation"),
        container_url, forced = forced)

    message("Uploading metadata...")
    hud.keep::store_data(
        get_target_report(),
        stringr::str_glue("{blob_path}/run_report.rds"),
        container_url, forced = forced)
}

#' Wrapper for running targets
#'
#' A complete wrapper for automated/one-touch target runs. Runs tar_make(),
#' checks for errors, then upload files and sends a Teams message.
#'
#' @name run_targets
#' @param run_name Run name
#' @param project_name Project name
#' @param container_url Azure container URL
#' @param upload_targets Name-strings of targets that should be uploaded
#' @param ping Ping users in this message using their emails (case sensitive) as identifiers
#' @param invalidate Re-run every target
#' @param forced Overwrite blob version
#' @export
run_targets <- function(run_name, project_name, container_url, upload_targets = c(), ping = c(), invalidate = FALSE, forced = FALSE) {
    message("Starting run '", run_name, "'...")
    if (invalidate) {
        message("\033[33;1m*** THIS WILL OVERWRITE THE OLD DATA, YOU HAVE 5 SECONDS TO ABORT ***\033[0m")
        Sys.sleep(5)
        message("\033[33mInvalidating old data...\033[0m")
        targets::tar_invalidate(everything())
    }

    message("\033[32mRunning targets...\033[0m")
    run_report <-
        tryCatch({
            targets::tar_make()
            targets::tar_progress()
        }, error = function(e) {
            message(e[1])
            return(e)
        })

    if ("error" %in% class(run_report)) {
        message("\033[31;1mtar_make() failed!\033[0m")
    }
    else if (all(run_report$progress == "skipped")) {
        message("\033[33;1mNothing to do. Do you need to invalidate the previous run?\033[0m")
    }
    else {
        message("\033[32;1mRun successful!\033[0m")
        store_run_data(run_name, project_name, container_url, upload_targets, forced)
        send_run_report(project_name, run_name, maintainers)
        message("\033[1;32mDone.\033[0m")
    }
}

