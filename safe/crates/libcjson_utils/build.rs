use std::env;

fn main()
{
    println!("cargo:rerun-if-env-changed=CJSON_CORE_LIBRARY_DIR");
    println!("cargo:rerun-if-env-changed=CJSON_UTILS_SONAME");

    if let Ok(path) = env::var("CJSON_CORE_LIBRARY_DIR") {
        println!("cargo:rustc-link-search=native={path}");
        println!("cargo:rustc-link-lib=dylib=cjson");
    }

    if let Ok(soname) = env::var("CJSON_UTILS_SONAME") {
        println!("cargo:rustc-link-arg-cdylib=-Wl,-soname,{soname}");
    }
}
