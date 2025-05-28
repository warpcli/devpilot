use crate::commands::{machine::Machines, TerminalSize};
use clap::ArgMatches;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;
use std::process::Command;

pub fn handle(matches: ArgMatches, machines_file: PathBuf, _terminal_size: TerminalSize) {
    let machine_name = matches.get_one::<String>("machine_name").unwrap();
    let interface = matches.get_one::<String>("interface");
    let command = matches.get_one::<String>("command");
    
    let machines: Machines = Figment::new()
        .merge(Toml::file(&machines_file))
        .extract()
        .unwrap();

    // Find the machine
    let machine = machines.machines.iter().find(|m| m.name == *machine_name);
    let machine = match machine {
        Some(m) => m,
        None => {
            eprintln!("Machine '{}' not found", machine_name);
            return;
        }
    };

    // Find the appropriate host
    let host = if let Some(iface) = interface {
        machine.hosts.iter().find(|h| h.iface == *iface)
    } else {
        machine.hosts.first()
    };

    let host = match host {
        Some(h) => h,
        None => {
            eprintln!("No suitable host found for machine '{}'", machine_name);
            return;
        }
    };

    // Build SSH command
    let mut ssh_cmd = Command::new("ssh");
    
    // Add key if specified
    if let Some(key_path) = &machine.key {
        ssh_cmd.arg("-i").arg(key_path);
    }
    
    // Add connection string
    let connection_string = format!("{}@{}", machine.username, host.ip);
    ssh_cmd.arg(&connection_string);
    
    // Add port if not default
    if host.port != "22" {
        ssh_cmd.arg("-p").arg(&host.port);
    }
    
    // Add command if specified
    if let Some(cmd) = command {
        ssh_cmd.arg(cmd);
    }

    println!("Connecting to {} via {}...", machine_name, host.iface);
    
    // Execute SSH command
    let status = ssh_cmd.status();
    match status {
        Ok(exit_status) => {
            if !exit_status.success() {
                eprintln!("SSH connection failed");
            }
        }
        Err(e) => {
            eprintln!("Failed to execute SSH command: {}", e);
        }
    }
}
