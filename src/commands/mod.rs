use clap::ArgMatches;

mod machine;
mod project;
mod template;
mod workspace;

struct TerminalSize(pub usize, pub usize);

fn get_terminal_size() -> TerminalSize {
    let size = crossterm::terminal::size().expect("failed to obtain a terminal size");
    TerminalSize(size.0.into(), size.1.into())
}

pub fn handle(matches: ArgMatches) {
    let terminal_size = get_terminal_size();
    match matches.subcommand() {
        Some(("workspace", submatch)) => {
            workspace::handle(submatch.clone());
        }
        Some(("project", submatch)) => {
            project::handle(submatch.clone());
        }
        Some(("template", submatch)) => {
            template::handle(submatch.clone());
        }
        Some(("machine", submatch)) => {
            machine::handle(submatch.clone(), terminal_size);
        }
        _ => unreachable!("UNREACHABLE"),
    };
}
