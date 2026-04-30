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
    # Check code status
    uncommitted <- gert::git_status()
    if (nrow(uncommitted) > 0) {
        print(uncommitted)
        message("\033[33;1mThere are uncommitted files!\033[0m")
    }
    # Check workflow status
    targets::tar_prune()
    sitrep <- targets::tar_sitrep()
    pending <- sitrep %>% filter(if_any(-c(name, never)))
    if (nrow(pending) == 0) {
        message("\033[33;1mNothing to do. Do you need to invalidate the previous run?\033[0m")
    } else {
        if (all(sitrep$meta)) {
            message("\033[32;1mStarting new run '", run_name, "'...\033[0m")
        } else {
            message("\033[33mResuming run '", run_name, "'...\033[0m")
        }
        message(nrow(pending), " out of ", nrow(sitrep), " tasks pending...")
    }
    # Run and report
    tryCatch({
        targets::tar_make()
        send_run_report(run_name, project_name, ping)
        message("\033[1;32mRun '", run_name, "' finished.\033[0m")
    }, error = function(e) {
        send_run_report(run_name, project_name, ping, e[[1]])
        stop(e)
    })
}

#' Send run report
#'
#' Generate and send a fancy formatted Teams message describing the outcome of
#' a targets run.
#'
#' @name send_run_report
#' @param run_name Run name
#' @param project_name Project name
#' @param ping Ping users in this message using their emails (case sensitive) as identifiers
#' @param err_msg Error message ($message component of error object)
#' @export
send_run_report <- function(run_name, project_name, ping, err_msg = NULL) {
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
            all(report$progress == "skipped", na.rm = TRUE) ~ "skipped",
            any(report$progress == "errored", na.rm = TRUE) ~ "failed",
            TRUE ~ "success"),
        items = items)
    send_card(body, ping)
}

#' Save files from current targets run
#'
#' Saves copies files from target folder into a named folder
#'
#' @name save_run_data
#' @param run_name Run name
#' @param output_path Base output folder
#' @export
save_run_data <- function(run_name, output_path = "outputs", curr_name = "current") {
    curr_path <- file.path(output_path, curr_name)
    run_path <- file.path(output_path, run_name)
    message("\033[33mSaving run to '", run_path, "'...\033[0m")
    # Save output data
    dir.create(run_path, showWarnings = FALSE)
    fs::dir_copy(curr_path, run_path, overwrite = TRUE)
    # Write reports
    write_tsv(
        get_git_summary(),
        file.path(run_path, "git_summary.tsv"))
    write_tsv(
        get_target_report(),
        file.path(run_path, "run_report.tsv"))
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
#' @param output_path Base path for output folder
#' @param forced Overwrite blob version
#' @export
store_run_data <- function(run_name, project_name, container_url, upload_targets = c(), output_path = "outputs", update = TRUE, forced = FALSE) {
    run_path <- file.path(output_path, run_name)
    blob_path <- stringr::str_glue("{project_name}/{output_path}/{run_name}")
    message("\033[33mStoring run at '", blob_path, "'...\033[0m")
    # Upload specified targets objects
    for (tn in upload_targets) {
        local_fn <-
            hud.keep::store_data(
                targets::tar_read_raw(tn),
                stringr::str_glue("{blob_path}/{tn}.rds"),
                container_url, update = update, forced = forced)
    }
    # Upload output folder
    hud.keep::store_folder(
        run_path, blob_path,
        container_url, update = update, forced = forced)
}

#' Get target report
#'
#' Generate a report for targets using both the progress and metadata reports.
#'
#' @name get_target_report
#' @export
get_target_report <- function() {
    report <-
        dplyr::left_join(
            targets::tar_meta(targets_only = TRUE),
            targets::tar_progress(),
            by = "name",
            relationship = "one-to-one")

    report$minutes <- format(round(report$seconds / 60, 1))
    report$minutes[report$progress != "completed"] <- "-"
    return(report)
}

#' Get Git summary
#'
#' Summarise current state of repo.
#'
#' @name get_git_summary
#' @export
get_git_summary <- function() {
    uncommitted <-
        gert::git_status() %>%
        dplyr::summarise(
            .by = status,
            files = paste(file, collapse = ",")) %>%
        tidyr::pivot_wider(names_from = status, values_from = files)

    git_summary <-
        gert::git_commit_info() %>%
        purrr::map(as.character) %>%
        dplyr::as_tibble() %>%
        dplyr::mutate(
            url = gert::git_remote_info()$url,
            branch = gert::git_branch(),
            .before = 1) %>%
        dplyr::mutate(message = stringr::str_trim(message))
    
    if (nrow(uncommitted) > 0) {
        git_summary <- git_summary %>% mutate(uncommitted)
    }
    return(git_summary %>% tidyr::pivot_longer(tidyselect::everything()))
}
