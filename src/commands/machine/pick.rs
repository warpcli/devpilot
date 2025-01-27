use crate::commands::{machine::Machines, TerminalSize};
extern crate directories;
use clap::ArgMatches;
use directories::ProjectDirs;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;

extern crate skim;
use skim::prelude::*;
use std::io::Cursor;

pub fn handle(_matches: ArgMatches, machines_file: PathBuf, _terminal_size: TerminalSize) {
    if let Some(proj_dirs) = ProjectDirs::from("com", "bresilla", "dotpilot") {
        proj_dirs.config_dir();
    }

    let options = SkimOptionsBuilder::default()
        .height(String::from("100%"))
        .multi(true)
        .build()
        .unwrap();

    let machines: Machines = Figment::new()
        .merge(Toml::file(&machines_file))
        .extract()
        .unwrap();

    let item_reader = SkimItemReader::default();
    let items = item_reader.of_bufread(Cursor::new(machines.to_listed()));

    // `run_with` would read and show items from the stream
    let selected_items = Skim::run_with(&options, Some(items))
        .map(|out| out.selected_items)
        .unwrap_or_else(|| Vec::new());

    for item in selected_items.iter() {
        println!("{}", item.output());
    }
}
