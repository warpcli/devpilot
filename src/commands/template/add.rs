use crate::commands::{template::{Template, Templates}, TerminalSize};
use clap::ArgMatches;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;

pub fn handle(matches: ArgMatches, templates_file: PathBuf, _terminal_size: TerminalSize) {
    let mut templates: Templates = Figment::new()
        .merge(Toml::file(&templates_file))
        .extract()
        .unwrap_or_else(|_| Templates::new());

    let name = matches.get_one::<String>("name").unwrap();
    let description = matches.get_one::<String>("description").unwrap();
    let path = matches.get_one::<String>("path").unwrap();
    let language = matches.get_one::<String>("language");
    let framework = matches.get_one::<String>("framework");
    let tags = matches.get_many::<String>("tags")
        .map(|vals| vals.cloned().collect())
        .unwrap_or_default();

    // Check if template already exists
    if templates.find_template(name).is_some() {
        eprintln!("Template '{}' already exists", name);
        return;
    }

    // Validate that the template path exists
    let template_path = PathBuf::from(path);
    if !template_path.exists() {
        eprintln!("Template path '{}' does not exist", path);
        return;
    }

    let new_template = Template::new(
        name.clone(),
        description.clone(),
        path.clone(),
        language.cloned(),
        framework.cloned(),
        tags,
    );

    templates.add_template(new_template);

    let toml = toml::to_string_pretty(&templates).unwrap();
    std::fs::write(&templates_file, toml).expect("Could not write to templates file");
    
    println!("Template '{}' added successfully", name);
}
