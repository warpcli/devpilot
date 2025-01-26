use crate::commands::{machine::Machines, TerminalSize};
extern crate directories;
use directories::ProjectDirs;
use clap::ArgMatches;
use std::path::PathBuf;
use figment::{providers::{Format, Toml}, Figment};


pub fn handle(matches: ArgMatches, machines_file: PathBuf, terminal_size: TerminalSize){
    if let Some(proj_dirs) = ProjectDirs::from("com", "bresilla", "dotpilot") {
        proj_dirs.config_dir();
    }
    let machines: Machines = Figment::new()
        .merge(Toml::file(&machines_file))
        .extract().unwrap();

    if matches.get_flag("raw") {
        println!("{}", machines.to_listed());
    } else {
        println!("{}", machines.to_table(terminal_size));
    }
}
