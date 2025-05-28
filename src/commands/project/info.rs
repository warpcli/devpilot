use crate::commands::{project::Projects, TerminalSize};
use clap::ArgMatches;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;

pub fn handle(namespace: &str, matches: ArgMatches, projects_file: PathBuf, _terminal_size: TerminalSize) {
    let project_name = matches.get_one::<String>("project_name").unwrap();
    
    let projects: Projects = Figment::new()
        .merge(Toml::file(&projects_file))
        .extract()
        .unwrap_or_else(|_| Projects::new());

    if let Some(project) = projects.find_project(project_name, namespace) {
        println!("{}", project.to_detailed_string());
    } else {
        eprintln!("Project '{}' not found in namespace '{}'", project_name, namespace);
    }
}
