extern crate directories;
use crate::commands::{
    machine::{Machine, Machines},
    TerminalSize,
};
use clap::ArgMatches;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::env;
use std::path::PathBuf;
use std::string::String;
use toml;

pub fn handle(matches: ArgMatches, machines_file: PathBuf, _terminal_size: TerminalSize) {
    let mut machines: Machines = Figment::new()
        .merge(Toml::file(&machines_file))
        .extract()
        .unwrap();

    let mut new_machine = Machine::new();
    let name = matches.get_one::<String>("name").unwrap();
    new_machine.set_name(name);

    let host = matches.get_many::<(String, String, String)>("host");
    for i in host.unwrap() {
        new_machine.add_host(&i.0, &i.1, &i.2);
    }

    let usrn = env::var("USER").unwrap_or_else(|_| String::from("root"));
    let username = matches.get_one::<String>("username");
    match username {
        Some(u) => new_machine.set_username(u),
        None => new_machine.set_username(&usrn),
    }

    let key = matches.get_one::<String>("key").unwrap();
    new_machine.set_key(key);

    if let Some(m) = machines
        .machines
        .iter_mut()
        .find(|m| m.name == new_machine.name)
    {
        for h in new_machine.hosts.iter() {
            if m.hosts.iter().find(|host| host.iface == h.iface).is_some() {
                eprintln!(
                    "Error: Machine with name {} and interface {} already exists",
                    m.name, h.iface
                );
                return;
            }
        }
        m.hosts.append(&mut new_machine.hosts);
    } else {
        machines.machines.push(new_machine);
    }

    let toml = toml::to_string_pretty(&machines).unwrap();
    std::fs::write(&machines_file, toml).expect("Could not write to config file");
}
