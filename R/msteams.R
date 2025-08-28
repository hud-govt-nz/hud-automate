# Module for sending messages to a Teams Channel
# This needs to be setup on the Teams side with a [Workflows webhook](https://support.microsoft.com/en-us/office/create-incoming-webhooks-with-workflows-for-microsoft-teams-8ae491c7-0394-4861-ba59-055e33f75498)

#' Underlying function for sending cards
#'
#' Sends Teams AdaptiveCards using the Workflow webhook to a specific channel.
#' The webhook should expect to receive messages containing AdaptiveCard
#' attachments.
#'
#' The payload needs to be in JSON, but we are generating JSON-like structures
#' in R (using list() to describe dictionaries and arrays) and then converting
#' it into a JSON string. The content also needs to follow very specific rules.
#' See make_card_payload() to understand how to attach an AdaptiveCard to a
#' message, and use the WYSIWYG designer to understand how to create an
#' AdaptiveCard: https://adaptivecards.microsoft.com/designer.html
#'
#' If you run into trouble, test with a JSON string that is known to work and
#' step up from there, e.g.:
#' '[{ "type": "TextBlock", "text": "Hello World!" }]'
#'
#' In R JSON-like structure, this is:
#' list(list(type = "TextBlock", text = "Hello World!"))
#'
#' @name send_card
#' @param body Body of AdaptiveCard (list of AdaptiveCard elements expected)
#' @param ping Ping users in this message using their emails (case sensitive) as identifiers
#' @param summary Summary message that'll be displayed on previews
#' @export
send_card <- function(body, ping = NULL, summary = "") {
    # Deal with pings
    entities <-
        lapply(ping, function(e) {
            list(
                type = "mention",
                text = paste0("<at>", e$name, "</at>"),
                mentioned = e)
        })
    if (length(ping) > 0) {
        ping_names <- lapply(entities, function(e) e[["text"]])
        body <- c(
            body,
            list(list(
                type = "TextBlock",
                text = paste0("Ping ", paste(ping_names, collapse = ", ")))))
    }
    # Create payload
    payload <-
        list(
            type = "message",
            summary = summary,
            attachments = list(list(
                contentType = "application/vnd.microsoft.card.adaptive",
                content = list(
                    type = "AdaptiveCard",
                    body = body,
                    msteams = list(width = "Full", entities = entities)))))
    # Send
    res <- httr::POST(
        url = Sys.getenv("TEAMS_WEBHOOK"),
        body = jsonlite::toJSON(payload, auto_unbox = TRUE),
        httr::content_type_json())
    if (httr::status_code(res) %in% c(200, 201, 202)) {
        message("\033[32mMessage sent.\033[0m")
    } else {
        message("\033[31;1mFailed to send message: ", httr::content(res, "text"), "\033[0m")
    }
}

#' Send a simple message
#'
#' Sends a simple Teams message inside an AdaptiveCards using the Workflow
#' webhook to a specific channel.
#'
#' @name send_msg
#' @param msg Message to send
#' @param ping Ping users in this message using their emails (case sensitive) as identifiers
#' @param summary Summary message that'll be displayed on previews
#' @export
send_msg <- function(msg, ...) {
    body <- list(list(type = "TextBlock", text = msg))
    send_card(body, ...)
}

#' Make card wrapper
#' 
#' Creates message and card wrappers around the content of a card. Designed to
#' be part of a card creator.
#' 
#' @name make_base_card
#' @param task_name Task name
#' @param status Task status
#' @param items List of objects to go into a card body (see https://adaptivecards.microsoft.com/designer.html)
#' @export
make_base_card <- function(task_name, status, items = NULL) {
    # Determine overall status
    status <- ifelse(is.character(status) & status != "", status, "error")
    color <- dplyr::case_when(
        status == "success" ~ "good",
        status == "skipped" ~ "accent",
        TRUE ~ "attention")
    # Create card
    payload <-
        list(list(
            type = "Container",
            style = color,
            bleed = TRUE,
            items = list(
                list(
                    type = "TextBlock",
                    size = "small",
                    weight = "bolder",
                    text = task_name),
                list(
                    type = "TextBlock",
                    size = "large",
                    weight = "bolder",
                    spacing = "none",
                    color = color,
                    text = toupper(status)))))
    # Add items
    payload[[1]]$items <- c(payload[[1]]$items, items)
    return(payload)
}

#' Make columnset
#' 
#' Turn dataframe columns into a columnset for AdapativeCards.
#' 
#' @name make_columnset
#' @param targ_df Dataframe to generate the columnset from
#' @param cols Names of the columns to use
#' @export
make_columnset <- function(targ_df, cols) {
    columns <- lapply(cols, function(col_name) {
        cells <- lapply(
            targ_df[[col_name]],
            function(x) {
                list(
                    type = "TextBlock",
                    text = stringr::str_replace(x, "NA", "-"),
                    spacing = "none",
                    color = dplyr::case_when(
                        x == "errored" ~ "attention",
                        x == "skipped" ~ "accent",
                        x == "completed" ~ "good",
                        TRUE ~ "Default"))
            })
        header <- list(
            type = "TextBlock",
            text = col_name,
            weight = "bolder")
        column <- list(
            type = "Column",
            items = c(list(header), cells))
        return(column)
    }) 
    columnset <- list(type = "ColumnSet", columns = columns)
    return(columnset)
}
