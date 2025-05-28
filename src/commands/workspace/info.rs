use crate::commands::{workspace::Workspaces, TerminalSize};
use clap::ArgMatches;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;

pub fn handle(matches: ArgMatches, workspaces_file: PathBuf, _terminal_size: TerminalSize) {
    let workspace_name = matches.get_one::<String>("workspace_name").unwrap();
    
    let workspaces: Workspaces = Figment::new()
        .merge(Toml::file(&workspaces_file))
        .extract()
        .unwrap_or_else(|_| Workspaces::new());

    if let Some(workspace) = workspaces.find_workspace(workspace_name) {
        println!("{}", workspace.to_detailed_string());
    } else {
        eprintln!("Workspace '{}' not found", workspace_name);
    }
}
