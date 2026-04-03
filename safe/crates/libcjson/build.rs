use std::env;
use std::ffi::OsString;
use std::process::Command;

fn is_truthy(value: &str) -> bool
{
    matches!(value, "1" | "ON" | "On" | "on" | "TRUE" | "True" | "true")
}

fn cargo_supports_check_cfg() -> bool
{
    let cargo = env::var_os("CARGO").unwrap_or_else(|| OsString::from("cargo"));
    let output = match Command::new(cargo).arg("--version").output() {
        Ok(output) => output,
        Err(_) => return false,
    };
    let version = match String::from_utf8(output.stdout) {
        Ok(version) => version,
        Err(_) => return false,
    };
    let mut components = match version.split_whitespace().nth(1) {
        Some(version) => version.split('.'),
        None => return false,
    };
    let major = match components.next().and_then(|value| value.parse::<u32>().ok()) {
        Some(major) => major,
        None => return false,
    };
    let minor = match components.next().and_then(|value| value.parse::<u32>().ok()) {
        Some(minor) => minor,
        None => return false,
    };

    major > 1 || (major == 1 && minor >= 80)
}

fn main()
{
    println!("cargo:rerun-if-env-changed=CARGO");
    println!("cargo:rerun-if-env-changed=CJSON_ENABLE_LOCALES");
    println!("cargo:rerun-if-env-changed=CJSON_SONAME");
    if cargo_supports_check_cfg() {
        println!("cargo:rustc-check-cfg=cfg(cjson_enable_locales)");
    }

    if let Ok(value) = env::var("CJSON_ENABLE_LOCALES") {
        if is_truthy(&value) {
            println!("cargo:rustc-cfg=cjson_enable_locales");
        }
    }

    if let Ok(soname) = env::var("CJSON_SONAME") {
        println!("cargo:rustc-link-arg-cdylib=-Wl,-soname,{soname}");
    }
}
