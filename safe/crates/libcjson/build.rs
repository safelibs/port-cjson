use std::env;

fn is_truthy(value: &str) -> bool
{
    matches!(value, "1" | "ON" | "On" | "on" | "TRUE" | "True" | "true")
}

fn main()
{
    println!("cargo:rerun-if-env-changed=CJSON_ENABLE_LOCALES");
    println!("cargo:rerun-if-env-changed=CJSON_SONAME");

    if let Ok(value) = env::var("CJSON_ENABLE_LOCALES") {
        if is_truthy(&value) {
            println!("cargo:rustc-cfg=cjson_enable_locales");
        }
    }

    if let Ok(soname) = env::var("CJSON_SONAME") {
        println!("cargo:rustc-link-arg-cdylib=-Wl,-soname,{soname}");
    }
}
