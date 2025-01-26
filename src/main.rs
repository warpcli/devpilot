use std::env;

mod arguments;
mod commands;

fn main() {
    let show_logo = if env::args().len() > 1 { false } else { true };
    let matches = arguments::cli(show_logo).get_matches();
    commands::handle(matches);
}
