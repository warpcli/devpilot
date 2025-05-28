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

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct Project {
    name: String,
    path: String,
    namespace: String,
    template: Option<String>,
    description: Option<String>,
    language: Option<String>,
    framework: Option<String>,
    tags: Vec<String>,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

impl Project {
    pub fn new(
        name: String,
        path: String,
        namespace: String,
        template: Option<String>,
        description: Option<String>,
        language: Option<String>,
        framework: Option<String>,
        tags: Vec<String>,
    ) -> Self {
        let now = Utc::now();
        Project {
            name,
            path,
            namespace,
            template,
            description,
            language,
            framework,
            tags,
            created_at: now,
            updated_at: now,
        }
    }

    pub fn to_detailed_string(&self) -> String {
        format!(
            "Project: {}\nPath: {}\nNamespace: {}\nTemplate: {}\nDescription: {}\nLanguage: {}\nFramework: {}\nTags: {}\nCreated: {}\nUpdated: {}",
            self.name,
            self.path,
            self.namespace,
            self.template.as_ref().unwrap_or(&String::from("None")),
            self.description.as_ref().unwrap_or(&String::from("None")),
            self.language.as_ref().unwrap_or(&String::from("None")),
            self.framework.as_ref().unwrap_or(&String::from("None")),
            if self.tags.is_empty() { "None".to_string() } else { self.tags.join(", ") },
            self.created_at.format("%Y-%m-%d %H:%M:%S UTC"),
            self.updated_at.format("%Y-%m-%d %H:%M:%S UTC")
        )
    }
}

impl std::fmt::Display for Project {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}: {} ({})", self.name, self.path, self.namespace)
    }
}

impl Tabled for Project {
    const LENGTH: usize = 8;
    fn headers() -> Vec<Cow<'static, str>> {
        vec![
            "Name".into(),
            "Path".into(),
            "Namespace".into(),
            "Template".into(),
            "Language".into(),
            "Framework".into(),
            "Tags".into(),
            "Created".into(),
        ]
    }

    fn fields(&self) -> Vec<Cow<'_, str>> {
        vec![
            self.name.clone().into(),
            self.path.clone().into(),
            self.namespace.clone().into(),
            self.template.as_ref().unwrap_or(&String::from("None")).clone().into(),
            self.language.as_ref().unwrap_or(&String::from("None")).clone().into(),
            self.framework.as_ref().unwrap_or(&String::from("None")).clone().into(),
            if self.tags.is_empty() { "None".to_string() } else { self.tags.join(", ") }.into(),
            self.created_at.format("%Y-%m-%d").to_string().into(),
        ]
    }
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct Projects {
    projects: Vec<Project>,
}

impl Projects {
    pub fn new() -> Self {
        Projects {
            projects: Vec::new(),
        }
    }

    pub fn add_project(&mut self, project: Project) {
        self.projects.push(project);
    }

    pub fn find_project(&self, name: &str, namespace: &str) -> Option<&Project> {
        self.projects.iter().find(|p| p.name == name && p.namespace == namespace)
    }

    pub fn to_table(&self, ts: TerminalSize, namespace: Option<&str>) -> String {
        let filtered_projects: Vec<&Project> = if let Some(ns) = namespace {
            self.projects.iter().filter(|p| p.namespace == ns).collect()
        } else {
            self.projects.iter().collect()
        };

        let mut table = Table::new(filtered_projects);
        table
            .with(Width::wrap(ts.0))
            .with(Height::limit(ts.1))
            .with(Style::modern());
        table.to_string()
    }

    pub fn to_listed(&self, namespace: Option<&str>) -> String {
        let filtered_projects: Vec<&Project> = if let Some(ns) = namespace {
            self.projects.iter().filter(|p| p.namespace == ns).collect()
        } else {
            self.projects.iter().collect()
        };

        filtered_projects
            .iter()
            .map(|p| format!("{}\t{}\t{}\t{}", p.name, p.namespace, p.path, p.language.as_ref().unwrap_or(&String::from("unknown"))))
            .collect::<Vec<String>>()
            .join("\n")
    }
}

pub fn handle(_parent_matches: ArgMatches, matches: ArgMatches, terminal_size: TerminalSize) {
    // Extract namespace from project command matches
    let default_namespace = String::from("default");
    let namespace = matches.get_one::<String>("namespace").unwrap_or(&default_namespace);

    let mut projects_file: PathBuf = PathBuf::new();
    if let Some(proj_dirs) = BaseDirs::new() {
        let projd = proj_dirs.data_dir().join("devpilot");
        if !projd.exists() {
            std::fs::create_dir_all(projd.clone()).expect("Could not create config directory");
        }

        projects_file = projd.join("projects.toml");
        if !projects_file.exists() || projects_file.metadata().unwrap().len() == 0 {
            let projects = Projects::new();
            let toml = toml::to_string(&projects).unwrap();
            std::fs::write(&projects_file, toml).expect("Could not create projects file");
        }
    }

    if projects_file == PathBuf::new() {
        eprintln!("Error: Could not create projects file");
        return;
    }

    match matches.subcommand() {
        Some(("add", args)) => {
            add::handle(namespace, args.clone(), projects_file, terminal_size);
        }
        Some(("info", args)) => {
            info::handle(namespace, args.clone(), projects_file, terminal_size);
        }
        Some(("list", args)) => {
            list::handle(namespace, args.clone(), projects_file, terminal_size);
        }
        _ => unreachable!("UNREACHABLE"),
    }
}