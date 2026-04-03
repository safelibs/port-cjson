use std::env;
use std::path::PathBuf;

fn is_truthy(value: &str) -> bool
{
    matches!(value, "1" | "ON" | "On" | "on" | "TRUE" | "True" | "true")
}

fn main()
{
    println!("cargo:rerun-if-env-changed=CJSON_ENABLE_LOCALES");
    println!("cargo:rerun-if-env-changed=CJSON_CORE_EXPORT_MAP");
    println!("cargo:rerun-if-env-changed=CJSON_SONAME");
    println!("cargo:rustc-check-cfg=cfg(cjson_enable_locales)");

    if let Ok(value) = env::var("CJSON_ENABLE_LOCALES") {
        if is_truthy(&value) {
            println!("cargo:rustc-cfg=cjson_enable_locales");
        }
    }

    if let Ok(path) = env::var("CJSON_CORE_EXPORT_MAP") {
        let export_map = PathBuf::from(path);
        if export_map.exists() {
            println!(
                "cargo:rustc-link-arg-cdylib=-Wl,--version-script={}",
                export_map.display()
            );
        }
    }

    if let Ok(soname) = env::var("CJSON_SONAME") {
        println!("cargo:rustc-link-arg-cdylib=-Wl,-soname,{soname}");
    }
}
