use crate::commands::{workspace::{Workspaces, Component}, TerminalSize};
use clap::ArgMatches;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;

pub fn handle(matches: ArgMatches, workspaces_file: PathBuf, _terminal_size: TerminalSize) {
    let mut workspaces: Workspaces = Figment::new()
        .merge(Toml::file(&workspaces_file))
        .extract()
        .unwrap_or_else(|_| Workspaces::new());

    let workspace_name = matches.get_one::<String>("workspace_name").unwrap();
    let default_action = String::from("list");
    let action = matches.get_one::<String>("action").unwrap_or(&default_action);
    
    let workspace = match workspaces.find_workspace_mut(workspace_name) {
        Some(ws) => ws,
        None => {
            eprintln!("Workspace '{}' not found", workspace_name);
            return;
        }
    };

    match action.as_str() {
        "add" => {
            if let Some(component_name) = matches.get_one::<String>("component_name") {
                let default_type = String::from("project");
                let component_type = matches.get_one::<String>("component_type")
                    .unwrap_or(&default_type);
                let component_path = matches.get_one::<String>("component_path");
                
                let component = Component::new(
                    component_name.clone(),
                    component_type.clone(),
                    component_path.cloned(),
                );
                
                workspace.add_component(component);
                
                let toml = toml::to_string_pretty(&workspaces).unwrap();
                std::fs::write(&workspaces_file, toml).expect("Could not write to workspaces file");
                
                println!("Component '{}' added to workspace '{}'", component_name, workspace_name);
            } else {
                eprintln!("Component name is required for add action");
            }
        }
        "remove" => {
            if let Some(component_name) = matches.get_one::<String>("component_name") {
                if workspace.remove_component(component_name) {
                    let toml = toml::to_string_pretty(&workspaces).unwrap();
                    std::fs::write(&workspaces_file, toml).expect("Could not write to workspaces file");
                    
                    println!("Component '{}' removed from workspace '{}'", component_name, workspace_name);
                } else {
                    eprintln!("Component '{}' not found in workspace '{}'", component_name, workspace_name);
                }
            } else {
                eprintln!("Component name is required for remove action");
            }
        }
        "list" | _ => {
            println!("Components in workspace '{}':", workspace_name);
            for component in &workspace.components {
                println!("  - {}: {} ({})", component.name, component.component_type, 
                    component.path.as_ref().unwrap_or(&String::from("no path")));
            }
        }
    }
}
