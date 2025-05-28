use crate::commands::{workspace::{Workspace, Workspaces}, TerminalSize};
use clap::ArgMatches;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;
use std::env;

pub fn handle(matches: ArgMatches, workspaces_file: PathBuf, _terminal_size: TerminalSize) {
    let mut workspaces: Workspaces = Figment::new()
        .merge(Toml::file(&workspaces_file))
        .extract()
        .unwrap_or_else(|_| Workspaces::new());

    let name = matches.get_one::<String>("name").unwrap();
    let path = matches.get_one::<String>("path")
        .map(|p| PathBuf::from(p))
        .unwrap_or_else(|| env::current_dir().unwrap());
    let description = matches.get_one::<String>("description");
    let projects = matches.get_many::<String>("projects")
        .map(|vals| vals.cloned().collect())
        .unwrap_or_default();

    // Check if workspace already exists
    if workspaces.find_workspace(name).is_some() {
        eprintln!("Workspace '{}' already exists", name);
        return;
    }

    let new_workspace = Workspace::new(
        name.clone(),
        path.to_string_lossy().to_string(),
        description.cloned(),
        projects,
    );

    workspaces.add_workspace(new_workspace);

    let toml = toml::to_string_pretty(&workspaces).unwrap();
    std::fs::write(&workspaces_file, toml).expect("Could not write to workspaces file");
    
    println!("Workspace '{}' added successfully", name);
}
