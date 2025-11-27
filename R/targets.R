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
send_run_report <- function(project_name, run_name, ping, err_msg = NULL) {
    # Core report
    report <- get_target_report()
    items <- list(
        make_columnset(report, c("name", "progress", "minutes")))
    # Add error block
    if (!is.null(err_msg)) {
        items <- append(items, list(make_error_block(err_msg)))
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
#' @param upload_targets Vector of name-strings for targets that should be uploaded
#' @param upload_folders Vector of name-strings for folders that should be uploaded
#' @param forced Overwrite blob version
#' @export
store_run_data <- function(run_name, project_name, container_url, upload_targets = c(), upload_folders = c(), update = TRUE, forced = FALSE) {
    blob_path <- stringr::str_glue("{project_name}/outputs/{run_name}")

    for (tn in upload_targets) {
        local_fn <-
            hud.keep::store_data(
                targets::tar_read_raw(tn),
                stringr::str_glue("{blob_path}/{tn}.rds"),
                container_url, update = update, forced = forced)
    }

    for (fn in upload_folders) {
        hud.keep::store_folder(
            fn,
            blob_path,
            container_url, update = update, forced = forced)
    }

    local_fn <-
        hud.keep::store_data(
            get_target_report(),
            stringr::str_glue("{blob_path}/run_report.rds"),
            container_url, update = update, forced = forced)
}

#' Wrapper for running targets
#'
#' Wrapper for automated target runs. Runs tar_make() and sends a Teams
#' message, even on failures.
#'
#' @name run_targets
#' @param run_name Run name
#' @param project_name Project name
#' @param ping Ping users in this message using their emails (case sensitive) as identifiers
#' @export
run_targets <- function(run_name, project_name, ping = c()) {
    targets::tar_prune()
    sitrep <- targets::tar_sitrep()
    pending <- sitrep %>% filter(if_any(-c(name, never)))

    if (nrow(pending) == 0) {
        message("\033[33;1mNothing to do. Do you need to invalidate the previous run?\033[0m")
        return(NULL)
    }
    if (all(sitrep$meta)) {
        message("\033[32;1mStarting new run '", run_name, "'...\033[0m")
    } else {
        message("\033[33mResuming run '", run_name, "'...\033[0m")
    }
    message(nrow(pending), " out of ", nrow(sitrep), " tasks pending...")

    tryCatch({
        targets::tar_make()
        send_run_report(project_name, run_name, ping)
        message("\033[1;32mRun '", run_name, "' finished\033[0m")
    }, error = function(e) {
        send_run_report(project_name, run_name, ping, e[[1]])
        print(e)
        stop(e)
    })
}
