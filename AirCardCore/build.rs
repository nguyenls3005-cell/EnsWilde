use std::env;
use std::path::PathBuf;

fn main() {
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    
    // Compile GrappaHelper.m
    cc::Build::new()
        .file("GrappaHelper.m")
        .flag("-fobjc-arc")
        .compile("GrappaHelper");

    // Copy headers ra ngoài OUT_DIR
    std::fs::copy("airlift.h", out_dir.join("airlift.h")).unwrap();
    std::fs::copy("GrappaHelper.h", out_dir.join("GrappaHelper.h")).unwrap();
    
    println!("cargo:rerun-if-changed=GrappaHelper.m");
    println!("cargo:rerun-if-changed=airlift.h");
}