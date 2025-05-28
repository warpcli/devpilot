use crate::commands::TerminalSize;
use clap::ArgMatches;
use directories::BaseDirs;
use serde::{Deserialize, Serialize};
use std::borrow::Cow;
use std::path::PathBuf;
use tabled::{
    settings::{style::Style, Height, Width},
    Table, Tabled,
};
use chrono::{DateTime, Utc};

mod add;
mod info;
mod list;
mod apply;

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct Template {
    name: String,
    description: String,
    path: String,
    language: Option<String>,
    framework: Option<String>,
    tags: Vec<String>,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

impl Template {
    pub fn new(
        name: String,
        description: String,
        path: String,
        language: Option<String>,
        framework: Option<String>,
        tags: Vec<String>,
    ) -> Self {
        let now = Utc::now();
        Template {
            name,
            description,
            path,
            language,
            framework,
            tags,
            created_at: now,
            updated_at: now,
        }
    }

    pub fn to_detailed_string(&self) -> String {
        format!(
            "Template: {}\nDescription: {}\nPath: {}\nLanguage: {}\nFramework: {}\nTags: {}\nCreated: {}\nUpdated: {}",
            self.name,
            self.description,
            self.path,
            self.language.as_ref().unwrap_or(&String::from("None")),
            self.framework.as_ref().unwrap_or(&String::from("None")),
            if self.tags.is_empty() { "None".to_string() } else { self.tags.join(", ") },
            self.created_at.format("%Y-%m-%d %H:%M:%S UTC"),
            self.updated_at.format("%Y-%m-%d %H:%M:%S UTC")
        )
    }
}

impl std::fmt::Display for Template {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}: {}", self.name, self.description)
    }
}

impl Tabled for Template {
    const LENGTH: usize = 6;
    fn headers() -> Vec<Cow<'static, str>> {
        vec![
            "Name".into(),
            "Description".into(),
            "Language".into(),
            "Framework".into(),
            "Tags".into(),
            "Created".into(),
        ]
    }

    fn fields(&self) -> Vec<Cow<'_, str>> {
        vec![
            self.name.clone().into(),
            self.description.clone().into(),
            self.language.as_ref().unwrap_or(&String::from("None")).clone().into(),
            self.framework.as_ref().unwrap_or(&String::from("None")).clone().into(),
            if self.tags.is_empty() { "None".to_string() } else { self.tags.join(", ") }.into(),
            self.created_at.format("%Y-%m-%d").to_string().into(),
        ]
    }
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct Templates {
    templates: Vec<Template>,
}

impl Templates {
    pub fn new() -> Self {
        Templates {
            templates: Vec::new(),
        }
    }

    pub fn add_template(&mut self, template: Template) {
        self.templates.push(template);
    }

    pub fn find_template(&self, name: &str) -> Option<&Template> {
        self.templates.iter().find(|t| t.name == name)
    }

    pub fn to_table(&self, ts: TerminalSize) -> String {
        let mut table = Table::new(self.templates.clone());
        table
            .with(Width::wrap(ts.0))
            .with(Height::limit(ts.1))
            .with(Style::modern());
        table.to_string()
    }

    pub fn to_listed(&self) -> String {
        self.templates
            .iter()
            .map(|t| format!("{}\t{}\t{}", t.name, t.language.as_ref().unwrap_or(&String::from("unknown")), t.path))
            .collect::<Vec<String>>()
            .join("\n")
    }
}

pub fn handle(matches: ArgMatches, terminal_size: TerminalSize) {
    let mut templates_file: PathBuf = PathBuf::new();
    if let Some(proj_dirs) = BaseDirs::new() {
        let projd = proj_dirs.data_dir().join("devpilot");
        if !projd.exists() {
            std::fs::create_dir_all(projd.clone()).expect("Could not create config directory");
        }

        templates_file = projd.join("templates.toml");
        if !templates_file.exists() || templates_file.metadata().unwrap().len() == 0 {
            let templates = Templates::new();
            let toml = toml::to_string(&templates).unwrap();
            std::fs::write(&templates_file, toml).expect("Could not create templates file");
        }
    }

    if templates_file == PathBuf::new() {
        eprintln!("Error: Could not create templates file");
        return;
    }

    match matches.subcommand() {
        Some(("add", args)) => {
            add::handle(args.clone(), templates_file, terminal_size);
        }
        Some(("info", args)) => {
            info::handle(args.clone(), templates_file, terminal_size);
        }
        Some(("list", args)) => {
            list::handle(args.clone(), templates_file, terminal_size);
        }
        Some(("apply", args)) => {
            apply::handle(args.clone(), templates_file, terminal_size);
        }
        _ => unreachable!("UNREACHABLE"),
    }
}