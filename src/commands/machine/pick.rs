use crate::commands::{machine::Machines, TerminalSize};
extern crate directories;
use clap::ArgMatches;
use directories::ProjectDirs;
use figment::{
    providers::{Format, Toml},
    Figment,
};
use std::path::PathBuf;

use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::Span,
    widgets::{Block, Borders, List, ListItem, ListState},
    Terminal,
};
use std::{error::Error, io};

/// Main event loop for our TUI
fn run_app(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    menu_items: Vec<&str>,
    list_state: &mut ListState,
) -> Result<(), Box<dyn Error>> {
    loop {
        // Draw the UI
        terminal.draw(|f| {
            let size = f.size();

            // Split the layout if you want multiple sections, but here we just use one
            let chunks = Layout::default()
                .direction(Direction::Vertical)
                .margin(1)
                .constraints([Constraint::Min(0)].as_ref())
                .split(size);

            // Prepare list items
            let items: Vec<ListItem> = menu_items
                .iter()
                .map(|item| ListItem::new(Span::raw(*item)))
                .collect();

            // Create the list widget
            let list = List::new(items)
                .block(
                    Block::default()
                        .title("Ratatui List Selector")
                        .borders(Borders::ALL),
                )
                .highlight_style(
                    Style::default()
                        .fg(Color::Yellow)
                        .add_modifier(Modifier::BOLD),
                )
                .highlight_symbol(">> ");

            // Render the stateful list widget
            f.render_stateful_widget(list, chunks[0], list_state);
        })?;

        // Handle input
        if crossterm::event::poll(std::time::Duration::from_millis(100))? {
            if let Event::Key(key) = event::read()? {
                match key.code {
                    KeyCode::Up => {
                        // Move selection up
                        let i = match list_state.selected() {
                            Some(i) => {
                                if i == 0 {
                                    menu_items.len() - 1
                                } else {
                                    i - 1
                                }
                            }
                            None => 0,
                        };
                        list_state.select(Some(i));
                    }
                    KeyCode::Down => {
                        // Move selection down
                        let i = match list_state.selected() {
                            Some(i) => {
                                if i >= menu_items.len() - 1 {
                                    0
                                } else {
                                    i + 1
                                }
                            }
                            None => 0,
                        };
                        list_state.select(Some(i));
                    }
                    KeyCode::Char('q') => {
                        // Quit on 'q'
                        return Ok(());
                    }
                    KeyCode::Enter => {
                        // If you want to handle pressing Enter on a selection,
                        // you could do so here.
                        if let Some(selected) = list_state.selected() {
                            println!("You selected: {}", menu_items[selected]);
                            return Ok(());
                        }
                    }
                    _ => {}
                }
            }
        }
    }
}

fn run() -> Result<(), Box<dyn Error>> {
    // Set up the terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create application state
    let menu_items = vec!["Option 1", "Option 2", "Option 3", "Option 4", "Option 5"];
    let mut list_state = ListState::default();
    // By default, select the first item
    list_state.select(Some(0));

    // Main loop
    let res = run_app(&mut terminal, menu_items, &mut list_state);

    // Restore the terminal
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    // If there was an error inside the TUI, return it
    if let Err(err) = res {
        println!("{:?}", err)
    }

    Ok(())
}

pub fn handle(matches: ArgMatches, machines_file: PathBuf, terminal_size: TerminalSize) {
    if let Some(proj_dirs) = ProjectDirs::from("com", "bresilla", "dotpilot") {
        proj_dirs.config_dir();
    }

    let machines: Machines = Figment::new()
        .merge(Toml::file(&machines_file))
        .extract()
        .unwrap();

    run().unwrap();
}
