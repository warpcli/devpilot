use crate::commands::{template::Templates, TerminalSize};
use clap::ArgMatches;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;
use std::fs;

pub fn handle(matches: ArgMatches, templates_file: PathBuf, _terminal_size: TerminalSize) {
    let template_name = matches.get_one::<String>("template_name").unwrap();
    let target_path = matches.get_one::<String>("target_path").unwrap();
    let project_name = matches.get_one::<String>("project_name");
    
    let templates: Templates = Figment::new()
        .merge(Toml::file(&templates_file))
        .extract()
        .unwrap_or_else(|_| Templates::new());

    let template = match templates.find_template(template_name) {
        Some(t) => t,
        None => {
            eprintln!("Template '{}' not found", template_name);
            return;
        }
    };

    let target_dir = PathBuf::from(target_path);
    
    // Create target directory if it doesn't exist
    if !target_dir.exists() {
        if let Err(e) = fs::create_dir_all(&target_dir) {
            eprintln!("Failed to create target directory: {}", e);
            return;
        }
    }

    // Copy template files to target directory
    let template_path = PathBuf::from(&template.path);
    
    if template_path.is_dir() {
        // Copy entire directory
        if let Err(e) = copy_dir_recursive(&template_path, &target_dir) {
            eprintln!("Failed to copy template: {}", e);
            return;
        }
    } else if template_path.is_file() {
        // Copy single file
        let file_name = template_path.file_name().unwrap();
        let target_file = target_dir.join(file_name);
        if let Err(e) = fs::copy(&template_path, &target_file) {
            eprintln!("Failed to copy template file: {}", e);
            return;
        }
    } else {
        eprintln!("Template path '{}' does not exist", template.path);
        return;
    }

    // If project name is provided, replace placeholders
    if let Some(proj_name) = project_name {
        replace_placeholders(&target_dir, proj_name);
    }

    println!("Template '{}' successfully applied to '{}'", template_name, target_path);
}

fn copy_dir_recursive(src: &PathBuf, dst: &PathBuf) -> Result<(), Box<dyn std::error::Error>> {
    if !dst.exists() {
        fs::create_dir_all(dst)?;
    }

    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());

        if src_path.is_dir() {
            copy_dir_recursive(&src_path, &dst_path)?;
        } else {
            fs::copy(&src_path, &dst_path)?;
        }
    }

    Ok(())
}

fn replace_placeholders(target_dir: &PathBuf, project_name: &str) {
    // Common placeholders to replace
    let project_name_kebab = project_name.replace("_", "-");
    let project_name_kebab_lower = project_name.replace("_", "-").to_lowercase();
    let placeholders = vec![
        ("{{PROJECT_NAME}}", project_name),
        ("{{project_name}}", project_name),
        ("{{PROJECT-NAME}}", &project_name_kebab),
        ("{{project-name}}", &project_name_kebab_lower),
    ];

    if let Ok(entries) = fs::read_dir(target_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_file() {
                if let Ok(content) = fs::read_to_string(&path) {
                    let original_content = content.clone();
                    let mut new_content = content;
                    for (placeholder, replacement) in &placeholders {
                        new_content = new_content.replace(placeholder, replacement);
                    }
                    if new_content != original_content {
                        let _ = fs::write(&path, new_content);
                    }
                }
            } else if path.is_dir() {
                replace_placeholders(&path, project_name);
            }
        }
    }
}
