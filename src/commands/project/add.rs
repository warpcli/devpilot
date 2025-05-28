use crate::commands::{project::{Project, Projects}, TerminalSize};
use clap::ArgMatches;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;
use std::env;

pub fn handle(namespace: &str, matches: ArgMatches, projects_file: PathBuf, _terminal_size: TerminalSize) {
    let mut projects: Projects = Figment::new()
        .merge(Toml::file(&projects_file))
        .extract()
        .unwrap_or_else(|_| Projects::new());

    let name = matches.get_one::<String>("name").unwrap();
    let path = matches.get_one::<String>("path")
        .map(|p| PathBuf::from(p))
        .unwrap_or_else(|| env::current_dir().unwrap());
    let template = matches.get_one::<String>("template");
    let description = matches.get_one::<String>("description");
    let language = matches.get_one::<String>("language");
    let framework = matches.get_one::<String>("framework");
    let tags = matches.get_many::<String>("tags")
        .map(|vals| vals.cloned().collect())
        .unwrap_or_default();

    // Check if project already exists
    if projects.find_project(name, namespace).is_some() {
        eprintln!("Project '{}' already exists in namespace '{}'", name, namespace);
        return;
    }

    let new_project = Project::new(
        name.clone(),
        path.to_string_lossy().to_string(),
        namespace.to_string(),
        template.cloned(),
        description.cloned(),
        language.cloned(),
        framework.cloned(),
        tags,
    );

    projects.add_project(new_project);

    let toml = toml::to_string_pretty(&projects).unwrap();
    std::fs::write(&projects_file, toml).expect("Could not write to projects file");
    
    println!("Project '{}' added successfully to namespace '{}'", name, namespace);
}
