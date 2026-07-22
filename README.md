# HUD automation tools
**CAUTION: This repo is public. Do not include sensitive data or key materials.**

Tools for managing a [{targets}](https://docs.ropensci.org/targets/) run:
* Run `tar_make()`
* Upload outputs files, specified target objects, and reports of the state of the code + data
* Sends a message on Teams to maintainers


## Teams Webhook
The `msteams` functions need a [Workflows webhook](https://support.microsoft.com/en-us/office/create-incoming-webhooks-with-workflows-for-microsoft-teams-8ae491c7-0394-4861-ba59-055e33f75498) set up to work. There should already be one that goes to the `Bot Health Channel`.

I recommend that you send the message to a dedicated channel like `Bot Health Channel`, so that if automation goes wrong you don't end up spamming your colleagues. (Guess who accidentally DDOSed the Herald's main newsroom channel during COVID.)

If you're writing your own payloads, you want to use the [AdaptiveCard designer](https://adaptivecards.microsoft.com/designer.html) to understand its structure.


## Installation
You'll need `devtools::install_github` to install the package:
```R
devtools::install_github("hud-govt-nz/hud-automate")
```


## Usage
Example:
```R
hud.automate::run(
    project_name,
    # Target objects to store with each run
    upload_targets = c(
        "title_spine", "title_snapshots", "titles_spatial",
        "cluster_spine", "cluster_snapshots", "clusters_spatial"),
    # Blob storage container where the files will be stored
    container_url = "https://dlprojectsdataprod.blob.core.windows.net/projects",
    # Maintainers will be alerted on update
    maintainers = list(
        list(id = "keith.ng@mcert.govt.nz", name = "Keith Ng")))
```

When writing targets for `run()`, follow these rules:
* There should be a `run_name` object which is just the current `YYYY-MM-DD`. `hud.keep::find_latest()` will look for last (A-Z sorted) folder with a matching structure. If you name the run something else, `hud.keep::find_latest()` will not find it (this may be desirable, if you want it to NOT be used by automated processes which rely on `hud.keep::find_latest()`). You can also use static run names during development.
* `project_name` should be kebab-case, and identical to the repository name (which should be kebab-case). This allows someone looking for the outputs of a project to find it easily on the blob.

For your own safety, `hud-automate` does not invalidate old runs. You'll have to invalidate old runs manually with `targets::tar_invalidate(everything())` to start a new run.


## Maintaining this package
If you make changes to this package, you'll need to rerun document from the root directory to update all the R generated files.
```R
roxygen2::roxygenise()
```
