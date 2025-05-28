use crate::commands::{machine::Machines, TerminalSize};
use clap::ArgMatches;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;

pub fn handle(matches: ArgMatches, machines_file: PathBuf, _terminal_size: TerminalSize) {
    let machine_name = matches.get_one::<String>("machine_name").unwrap();
    
    let mut machines: Machines = Figment::new()
        .merge(Toml::file(&machines_file))
        .extract()
        .unwrap();

    // Find and remove the machine
    if let Some(pos) = machines.machines.iter().position(|m| m.name == *machine_name) {
        machines.machines.remove(pos);
        
        let toml = toml::to_string_pretty(&machines).unwrap();
        std::fs::write(&machines_file, toml).expect("Could not write to config file");
        
        println!("Machine '{}' removed successfully", machine_name);
    } else {
        eprintln!("Machine '{}' not found", machine_name);
    }
}
