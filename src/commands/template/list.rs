use crate::commands::{template::Templates, TerminalSize};
use clap::ArgMatches;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;

pub fn handle(matches: ArgMatches, templates_file: PathBuf, terminal_size: TerminalSize) {
    let templates: Templates = Figment::new()
        .merge(Toml::file(&templates_file))
        .extract()
        .unwrap_or_else(|_| Templates::new());

    if matches.get_flag("raw") {
        println!("{}", templates.to_listed());
    } else {
        println!("{}", templates.to_table(terminal_size));
    }
}
