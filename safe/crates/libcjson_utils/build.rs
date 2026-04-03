use std::env;
use std::path::PathBuf;

fn main()
{
    println!("cargo:rerun-if-env-changed=CJSON_CORE_LIBRARY_DIR");
    println!("cargo:rerun-if-env-changed=CJSON_UTILS_EXPORT_MAP");
    println!("cargo:rerun-if-env-changed=CJSON_UTILS_SONAME");

    if let Ok(path) = env::var("CJSON_CORE_LIBRARY_DIR") {
        let library_dir = PathBuf::from(path);
        println!("cargo:rustc-link-search=native={}", library_dir.display());
        println!("cargo:rustc-link-lib=dylib=cjson");
    }

    if let Ok(path) = env::var("CJSON_UTILS_EXPORT_MAP") {
        let export_map = PathBuf::from(path);
        if export_map.exists() {
            println!(
                "cargo:rustc-link-arg-cdylib=-Wl,--version-script={}",
                export_map.display()
            );
        }
    }

    if let Ok(soname) = env::var("CJSON_UTILS_SONAME") {
        println!("cargo:rustc-link-arg-cdylib=-Wl,-soname,{soname}");
    }
}
