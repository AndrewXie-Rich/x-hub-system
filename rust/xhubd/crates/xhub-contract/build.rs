use std::env;
use std::error::Error;
use std::path::PathBuf;

fn main() -> Result<(), Box<dyn Error>> {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR")?);
    let root_dir = manifest_dir
        .join("../..")
        .canonicalize()
        .unwrap_or_else(|_| manifest_dir.join("../.."));
    let proto_dir = root_dir.join("assets").join("proto");
    let proto_path = proto_dir.join("hub_protocol_v1.proto");

    println!("cargo:rerun-if-changed={}", proto_path.display());

    tonic_build::configure()
        .build_client(true)
        .build_server(true)
        .compile_protos(&[proto_path], &[proto_dir])?;

    Ok(())
}
