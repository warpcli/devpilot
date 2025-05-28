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
mod component;

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct Component {
    name: String,
    component_type: String, // project, tool, config, etc.
    path: Option<String>,
}

impl Component {
    pub fn new(name: String, component_type: String, path: Option<String>) -> Self {
        Component {
            name,
            component_type,
            path,
        }
    }
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct Workspace {
    name: String,
    path: String,
    description: Option<String>,
    components: Vec<Component>,
    projects: Vec<String>, // Project names associated with this workspace
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

impl Workspace {
    pub fn new(
        name: String,
        path: String,
        description: Option<String>,
        projects: Vec<String>,
    ) -> Self {
        let now = Utc::now();
        Workspace {
            name,
            path,
            description,
            components: Vec::new(),
            projects,
            created_at: now,
            updated_at: now,
        }
    }

    pub fn add_component(&mut self, component: Component) {
        self.components.push(component);
        self.updated_at = Utc::now();
    }

    pub fn remove_component(&mut self, component_name: &str) -> bool {
        if let Some(pos) = self.components.iter().position(|c| c.name == component_name) {
            self.components.remove(pos);
            self.updated_at = Utc::now();
            true
        } else {
            false
        }
    }

    pub fn to_detailed_string(&self) -> String {
        let components_str = if self.components.is_empty() {
            "None".to_string()
        } else {
            self.components
                .iter()
                .map(|c| format!("{}: {} ({})", c.name, c.component_type, 
                    c.path.as_ref().unwrap_or(&String::from("no path"))))
                .collect::<Vec<String>>()
                .join("\n  ")
        };

        format!(
            "Workspace: {}\nPath: {}\nDescription: {}\nProjects: {}\nComponents:\n  {}\nCreated: {}\nUpdated: {}",
            self.name,
            self.path,
            self.description.as_ref().unwrap_or(&String::from("None")),
            if self.projects.is_empty() { "None".to_string() } else { self.projects.join(", ") },
            components_str,
            self.created_at.format("%Y-%m-%d %H:%M:%S UTC"),
            self.updated_at.format("%Y-%m-%d %H:%M:%S UTC")
        )
    }
}

impl std::fmt::Display for Workspace {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}: {}", self.name, self.path)
    }
}

impl Tabled for Workspace {
    const LENGTH: usize = 6;
    fn headers() -> Vec<Cow<'static, str>> {
        vec![
            "Name".into(),
            "Path".into(),
            "Description".into(),
            "Projects".into(),
            "Components".into(),
            "Created".into(),
        ]
    }

    fn fields(&self) -> Vec<Cow<'_, str>> {
        vec![
            self.name.clone().into(),
            self.path.clone().into(),
            self.description.as_ref().unwrap_or(&String::from("None")).clone().into(),
            if self.projects.is_empty() { "None".to_string() } else { self.projects.join(", ") }.into(),
            self.components.len().to_string().into(),
            self.created_at.format("%Y-%m-%d").to_string().into(),
        ]
    }
}

#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct Workspaces {
    workspaces: Vec<Workspace>,
}

impl Workspaces {
    pub fn new() -> Self {
        Workspaces {
            workspaces: Vec::new(),
        }
    }

    pub fn add_workspace(&mut self, workspace: Workspace) {
        self.workspaces.push(workspace);
    }

    pub fn find_workspace(&self, name: &str) -> Option<&Workspace> {
        self.workspaces.iter().find(|w| w.name == name)
    }

    pub fn find_workspace_mut(&mut self, name: &str) -> Option<&mut Workspace> {
        self.workspaces.iter_mut().find(|w| w.name == name)
    }

    pub fn to_table(&self, ts: TerminalSize) -> String {
        let mut table = Table::new(self.workspaces.clone());
        table
            .with(Width::wrap(ts.0))
            .with(Height::limit(ts.1))
            .with(Style::modern());
        table.to_string()
    }

    pub fn to_listed(&self) -> String {
        self.workspaces
            .iter()
            .map(|w| format!("{}\t{}\t{}", w.name, w.path, w.projects.join(",")))
            .collect::<Vec<String>>()
            .join("\n")
    }
}

pub fn handle(matches: ArgMatches, terminal_size: TerminalSize) {
    let mut workspaces_file: PathBuf = PathBuf::new();
    if let Some(proj_dirs) = BaseDirs::new() {
        let projd = proj_dirs.data_dir().join("devpilot");
        if !projd.exists() {
            std::fs::create_dir_all(projd.clone()).expect("Could not create config directory");
        }

        workspaces_file = projd.join("workspaces.toml");
        if !workspaces_file.exists() || workspaces_file.metadata().unwrap().len() == 0 {
            let workspaces = Workspaces::new();
            let toml = toml::to_string(&workspaces).unwrap();
            std::fs::write(&workspaces_file, toml).expect("Could not create workspaces file");
        }
    }

    if workspaces_file == PathBuf::new() {
        eprintln!("Error: Could not create workspaces file");
        return;
    }

    match matches.subcommand() {
        Some(("add", args)) => {
            add::handle(args.clone(), workspaces_file, terminal_size);
        }
        Some(("info", args)) => {
            info::handle(args.clone(), workspaces_file, terminal_size);
        }
        Some(("list", args)) => {
            list::handle(args.clone(), workspaces_file, terminal_size);
        }
        Some(("component", args)) => {
            component::handle(args.clone(), workspaces_file, terminal_size);
        }
        _ => unreachable!("UNREACHABLE"),
    }
}