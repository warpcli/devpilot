use crate::commands::{template::Templates, TerminalSize};
use clap::ArgMatches;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;

pub fn handle(matches: ArgMatches, templates_file: PathBuf, _terminal_size: TerminalSize) {
    let template_name = matches.get_one::<String>("template_name").unwrap();
    
    let templates: Templates = Figment::new()
        .merge(Toml::file(&templates_file))
        .extract()
        .unwrap_or_else(|_| Templates::new());

    if let Some(template) = templates.find_template(template_name) {
        println!("{}", template.to_detailed_string());
    } else {
        eprintln!("Template '{}' not found", template_name);
    }
}
