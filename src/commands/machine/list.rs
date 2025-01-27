use crate::commands::{machine::Machines, TerminalSize};
extern crate directories;
use clap::ArgMatches;
use directories::ProjectDirs;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;

pub fn handle(matches: ArgMatches, machines_file: PathBuf, terminal_size: TerminalSize) {
    if let Some(proj_dirs) = ProjectDirs::from("com", "bresilla", "dotpilot") {
        proj_dirs.config_dir();
    }
    let machines: Machines = Figment::new()
        .merge(Toml::file(&machines_file))
        .extract()
        .unwrap();

    if matches.get_flag("raw") {
        println!("{}", machines.to_listed());
    } else {
        println!("{}", machines.to_table(terminal_size));
    }
}
