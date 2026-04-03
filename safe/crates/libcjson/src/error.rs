use std::os::raw::c_char;
use std::sync::atomic::{AtomicUsize, Ordering};

static GLOBAL_PARSE_ERROR: AtomicUsize = AtomicUsize::new(0);

pub fn clear_parse_error() {
    GLOBAL_PARSE_ERROR.store(0, Ordering::Relaxed);
}

pub fn set_parse_error(pointer: *const c_char) {
    GLOBAL_PARSE_ERROR.store(pointer as usize, Ordering::Relaxed);
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_GetErrorPtr() -> *const c_char {
    GLOBAL_PARSE_ERROR.load(Ordering::Relaxed) as *const c_char
}
