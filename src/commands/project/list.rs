use crate::commands::{project::Projects, TerminalSize};
use clap::ArgMatches;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;

pub fn handle(namespace: &str, matches: ArgMatches, projects_file: PathBuf, terminal_size: TerminalSize) {
    let projects: Projects = Figment::new()
        .merge(Toml::file(&projects_file))
        .extract()
        .unwrap_or_else(|_| Projects::new());

    if matches.get_flag("raw") {
        println!("{}", projects.to_listed(Some(namespace)));
    } else {
        println!("{}", projects.to_table(terminal_size, Some(namespace)));
    }
}
