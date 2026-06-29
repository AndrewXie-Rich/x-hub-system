mod attestation;
mod capability;
mod cli;
mod codec;
mod manifest;
mod receipt;

use clap::Parser;

fn main() -> anyhow::Result<()> {
    cli::Cli::parse().run()
}
