//! Stamp the fork's commit into the binary so every report identifies the
//! exact build that produced it. Missing git or a dirty checkout is not an
//! error: reports then carry the all-zero fallback.

fn main() {
    let sha = std::process::Command::new("git")
        .args(["rev-parse", "HEAD"])
        .output()
        .ok()
        .filter(|out| out.status.success())
        .map(|out| String::from_utf8_lossy(&out.stdout).trim().to_owned())
        .filter(|sha| sha.len() >= 7 && sha.bytes().all(|b| b.is_ascii_hexdigit()))
        .unwrap_or_else(|| "0000000".to_owned());
    println!("cargo:rustc-env=VICTORY_TELEMETRY_GIT_SHA={sha}");
}
