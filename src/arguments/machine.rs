use clap::{Arg, ArgAction, Command};
use std::env;

extern crate interfaces;
use interfaces::Interface;

pub fn cmd() -> Command {
    let _username = env::var("USER").unwrap_or_else(|_| String::from("root"));

    Command::new("machine")
        .about("Add or edit hostnames and ssh")
        .aliases(&["m", "machines", "host", "hosts"])
        .subcommand_required(true)
        .arg_required_else_help(true)
        .subcommand(
            Command::new("add")
                .about("Add a new machine")
                .aliases(["a", "new"])
                .arg_required_else_help(true)
                .arg(
                    Arg::new("name")
                        .help("Name of the machine")
                        .value_name("MACHINE_NAME"),
                )
                .arg(
                    Arg::new("host")
                        .help("ip:port:iface of the machine")
                        .value_name("IP:PORT:IFACE")
                        .num_args(1..=10)
                        .action(ArgAction::Append)
                        .value_parser(|v: &str| {
                            let ifs = Interface::get_all().expect("could not get interfaces");

                            let parts: Vec<&str> = v.split(":").collect();
                            if parts.len() < 3 {
                                let mut port: String = String::from("22");
                                let mut iface: String = String::from("local");
                                if parts[0].parse::<std::net::IpAddr>().is_err() {
                                    return Err(String::from("Invalid ip format"));
                                }
                                if parts.len() == 3 {
                                    if parts[1].parse::<u16>().is_err() {
                                        return Err(String::from("Invalid port format"));
                                    }
                                    port = parts[1].to_string();
                                    //chekc if iface exists in the system
                                    if !ifs.iter().any(|i| i.name == parts[2]) {
                                        return Err(String::from("Invalid iface name"));
                                    }
                                    iface = parts[2].to_string();
                                } else if parts.len() == 2 {
                                    if !ifs.iter().any(|i| i.name == parts[1]) {
                                        return Err(String::from("Invalid iface name"));
                                    }
                                    iface = parts[1].to_string();
                                }
                                return Ok((parts[0].to_string(), port, iface));
                            }
                            Err(String::from("Invalid ip:port format"))
                        }),
                )
                .arg(
                    Arg::new("username")
                        .help("Username to use for ssh")
                        .short('u')
                        .long("username")
                        .value_name("USERNAME")
                        // .default_value("root")
                        .conflicts_with("interactive"),
                )
                .arg(
                    Arg::new("key")
                        .help("Path to the ssh key")
                        .short('k')
                        .long("key")
                        .value_name("KEY_PATH")
                        .default_value("~/.ssh/id_rsa"),
                ),
        )
        .subcommand(
            Command::new("list")
                .about("List all machines")
                .aliases(["l", "ls"])
                // .arg_required_else_help(true)
                .arg(
                    Arg::new("raw")
                        .help("Raw mode")
                        .short('r')
                        .long("raw")
                        .action(ArgAction::SetTrue),
                )
                .arg(
                    Arg::new("hosty")
                        .help("Hostname ready mode")
                        .short('h')
                        .long("hosty")
                        .action(ArgAction::SetTrue),
                ),
        )
        .subcommand(
            Command::new("pick")
                .about("Pick a machine")
                .aliases(["p", "select"])
                .arg(
                    Arg::new("name")
                        .help("Name of the machine")
                        .value_name("MACHINE_NAME"),
                ),
        )
}
