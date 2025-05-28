use crate::commands::{workspace::Workspaces, TerminalSize};
use clap::ArgMatches;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;

pub fn handle(matches: ArgMatches, workspaces_file: PathBuf, terminal_size: TerminalSize) {
    let workspaces: Workspaces = Figment::new()
        .merge(Toml::file(&workspaces_file))
        .extract()
        .unwrap_or_else(|_| Workspaces::new());

    if matches.get_flag("raw") {
        println!("{}", workspaces.to_listed());
    } else {
        println!("{}", workspaces.to_table(terminal_size));
    }
}
