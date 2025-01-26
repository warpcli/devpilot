use crate::commands::TerminalSize;
use clap::ArgMatches;
use directories::BaseDirs;
use hostname;
use serde::{Deserialize, Serialize};
use std::borrow::Cow;
use std::env;
use std::iter;
use std::path::PathBuf;
use tabled::{
    settings::{object::Rows, style::Style, Disable, Height, Width},
    Table, Tabled,
};

mod add;
mod list;

#[derive(Debug, Deserialize, Serialize)]
struct Host {
    ip: String,
    port: String,
    iface: String,
}

impl std::fmt::Display for Host {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}:{}:{}", self.ip, self.port, self.iface)
    }
}

impl Clone for Host {
    fn clone(&self) -> Self {
        Host {
            ip: self.ip.clone(),
            port: self.port.clone(),
            iface: self.iface.clone(),
        }
    }
}

impl Tabled for Host {
    const LENGTH: usize = 42;
    fn headers() -> Vec<Cow<'static, str>> {
        vec!["IP".into(), "Port".into(), "Interface".into()]
    }

    fn fields(&self) -> Vec<Cow<'_, str>> {
        vec![
            self.ip.clone().into(),
            self.port.clone().into(),
            self.iface.clone().into(),
        ]
    }
}

#[derive(Debug, Deserialize, Serialize)]
struct Machine {
    name: String,
    username: String,
    key: Option<String>,
    hosts: Vec<Host>,
}

impl Machine {
    fn new() -> Machine {
        Machine {
            name: String::new(),
            username: String::new(),
            key: None,
            hosts: Vec::new(),
        }
    }

    fn set_name(&mut self, name: &String) {
        self.name = name.clone();
    }

    fn set_username(&mut self, username: &String) {
        self.username = username.clone();
    }

    fn add_host(&mut self, ip: &String, port: &String, iface: &String) {
        self.hosts.push(Host {
            ip: ip.clone(),
            port: port.clone(),
            iface: iface.clone(),
        });
    }

    fn set_key(&mut self, key: &String) {
        self.key = Some(key.clone());
    }
}

impl Clone for Machine {
    fn clone(&self) -> Self {
        Machine {
            name: self.name.clone(),
            username: self.username.clone(),
            key: self.key.clone(),
            hosts: self.hosts.clone(),
        }
    }
}

impl std::fmt::Display for Machine {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(
            f,
            "Machine: {}\nUsername: {}\nHosts: {}\nKey: {}",
            self.name,
            self.username,
            self.hosts
                .iter()
                .map(|h| h.to_string())
                .collect::<Vec<String>>()
                .join(", "),
            self.key.as_ref().unwrap_or(&String::from("None"))
        )
    }
}

impl Tabled for Machine {
    const LENGTH: usize = 42;
    fn headers() -> Vec<Cow<'static, str>> {
        vec![
            "Name".into(),
            "Username".into(),
            "Hosts".into(),
            "Key".into(),
        ]
    }

    fn fields(&self) -> Vec<Cow<'_, str>> {
        let mut hosts_table = Table::new(self.hosts.clone());
        hosts_table
            .with(Style::modern())
            .with(Disable::row(Rows::first()));
        vec![
            self.name.clone().into(),
            self.username.clone().into(),
            hosts_table.to_string().into(),
            self.key
                .as_ref()
                .unwrap_or(&String::from("None"))
                .clone()
                .into(),
        ]
    }
}

#[derive(Debug, Deserialize, Serialize)]
struct Machines {
    machines: Vec<Machine>,
}

impl Machines {
    fn _new() -> Machines {
        Machines {
            machines: Vec::new(),
        }
    }

    fn to_table(&self, ts: TerminalSize) -> String {
        let mut table = Table::new(self.clone());
        table
            .with(Width::wrap(ts.0))
            .with(Height::limit(ts.1))
            .with(Style::modern());
        // table.with(Style::modern()).with(
        //     ColumnNames::default()
        //         .color(Color::BOLD | Color::BG_BLUE | Color::FG_WHITE)
        //         .alignment(Alignment::center()),
        // );
        table.to_string()
    }

    fn to_listed(&self) -> String {
        let mut new_str: String = String::new();
        for machine in self.machines.iter() {
            for host in machine.hosts.iter() {
                // new_vec.push(format!("{}:{}:{}:{}:{}\n", machine.name, machine.username, host.ip, host.port, host.iface));
                new_str.push_str(&format!(
                    "{}\t{}\t{}\t{}\t{}\n",
                    machine.name, machine.username, host.ip, host.port, host.iface
                ));
            }
        }
        new_str
    }
}

impl iter::IntoIterator for Machines {
    type Item = Machine;
    type IntoIter = std::vec::IntoIter<Self::Item>;
    fn into_iter(self) -> Self::IntoIter {
        self.machines.into_iter()
    }
}

impl Clone for Machines {
    fn clone(&self) -> Self {
        Machines {
            machines: self.machines.clone(),
        }
    }
}

impl std::fmt::Display for Machines {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(
            f,
            "{}",
            self.machines
                .iter()
                .map(|m| m.to_string())
                .collect::<Vec<String>>()
                .join("\n")
        )
    }
}

impl Tabled for Machines {
    const LENGTH: usize = 42;
    fn headers() -> Vec<Cow<'static, str>> {
        vec![
            "Name".into(),
            "Username".into(),
            "Hosts".into(),
            "Key".into(),
        ]
    }

    fn fields(&self) -> Vec<Cow<'_, str>> {
        vec![
            self.machines
                .iter()
                .map(|m| m.name.clone())
                .collect::<Vec<String>>()
                .join(", ")
                .into(),
            self.machines
                .iter()
                .map(|m| m.username.clone())
                .collect::<Vec<String>>()
                .join(", ")
                .into(),
            self.machines
                .iter()
                .map(|m| {
                    m.hosts
                        .iter()
                        .map(|h| h.to_string())
                        .collect::<Vec<String>>()
                        .join(", ")
                })
                .collect::<Vec<String>>()
                .join(", ")
                .into(),
            self.machines
                .iter()
                .map(|m| m.key.as_ref().unwrap_or(&String::from("None")).clone())
                .collect::<Vec<String>>()
                .join(", ")
                .into(),
        ]
    }
}

pub fn handle(matches: ArgMatches, terminal_size: TerminalSize) {
    let mut machines_file: PathBuf = PathBuf::new();
    if let Some(proj_dirs) = BaseDirs::new() {
        let projd = proj_dirs.data_dir().join("devpilot");
        if !projd.exists() {
            std::fs::create_dir_all(projd.clone()).expect("Could not create config directory");
        }

        //NOTE: println!("{:?}", proj_dirs.data_local_dir());
        println!("{:?}", projd.join("machines.toml"));

        machines_file = projd.join("machines.toml");
        if !machines_file.exists() || machines_file.metadata().unwrap().len() == 0 {
            std::fs::write(&machines_file, "").expect("Could not create config file");
            let hostn = hostname::get().unwrap().into_string().unwrap();
            let usrn = env::var("USER").unwrap_or_else(|_| String::from("root"));
            let machines = Machines {
                machines: vec![Machine {
                    name: String::from(hostn.to_owned()),
                    username: String::from(usrn),
                    hosts: vec![Host {
                        ip: String::from("127.0.0.1"),
                        port: String::from("22"),
                        iface: String::from("local"),
                    }],
                    key: None,
                }],
            };
            let toml = toml::to_string(&machines).unwrap();
            std::fs::write(&machines_file, toml).expect("Could not write to config file");
        }
    }

    if machines_file == PathBuf::new() {
        eprintln!("Error: Could not create config file");
        return;
    }

    match matches.subcommand() {
        Some(("add", args)) => {
            add::handle(args.clone(), machines_file, terminal_size);
        }
        Some(("list", args)) => {
            list::handle(args.clone(), machines_file, terminal_size);
        }
        _ => unreachable!("UNREACHABLE"),
    }
}
