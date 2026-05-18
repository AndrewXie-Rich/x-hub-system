use std::env;
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

const SERVICE_NAME: &str = "xtd";

fn main() {
    let args: Vec<String> = env::args().collect();
    let command = args.get(1).map(String::as_str).unwrap_or("health");

    match command {
        "health" => {
            println!("{}", health_json());
        }
        "version" | "--version" | "-V" => {
            println!("{} {}", SERVICE_NAME, env!("CARGO_PKG_VERSION"));
        }
        "run-once" => {
            println!("{}", run_once_json());
        }
        "help" | "--help" | "-h" => {
            print_help();
        }
        other => {
            eprintln!("unknown command: {}", other);
            print_help();
            process::exit(2);
        }
    }
}

fn health_json() -> String {
    format!(
        "{{\"service\":\"{}\",\"status\":\"ok\",\"version\":\"{}\",\"epoch_ms\":{}}}",
        SERVICE_NAME,
        env!("CARGO_PKG_VERSION"),
        epoch_ms()
    )
}

fn run_once_json() -> String {
    format!(
        "{{\"service\":\"{}\",\"mode\":\"run_once\",\"status\":\"idle\",\"epoch_ms\":{}}}",
        SERVICE_NAME,
        epoch_ms()
    )
}

fn epoch_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0)
}

fn print_help() {
    println!(
        "{} {}\n\nCommands:\n  health     Print a JSON health snapshot\n  run-once   Execute one placeholder runtime tick\n  version    Print version\n  help       Show this help\n",
        SERVICE_NAME,
        env!("CARGO_PKG_VERSION")
    );
}
