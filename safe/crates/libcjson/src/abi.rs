use std::os::raw::{c_char, c_double, c_int, c_void};

pub type cJSON_bool = c_int;
pub type malloc_fn = unsafe extern "C" fn(usize) -> *mut c_void;
pub type free_fn = unsafe extern "C" fn(*mut c_void);
pub type realloc_fn = unsafe extern "C" fn(*mut c_void, usize) -> *mut c_void;

pub const cJSON_Invalid: c_int = 0;
pub const cJSON_False: c_int = 1 << 0;
pub const cJSON_True: c_int = 1 << 1;
pub const cJSON_NULL: c_int = 1 << 2;
pub const cJSON_Number: c_int = 1 << 3;
pub const cJSON_String: c_int = 1 << 4;
pub const cJSON_Array: c_int = 1 << 5;
pub const cJSON_Object: c_int = 1 << 6;
pub const cJSON_Raw: c_int = 1 << 7;
pub const cJSON_IsReference: c_int = 256;
pub const cJSON_StringIsConst: c_int = 512;
pub const TYPE_MASK: c_int = 0xFF;

pub const VERSION: &[u8] = b"1.7.17\0";

#[repr(C)]
pub struct cJSON {
    pub next: *mut cJSON,
    pub prev: *mut cJSON,
    pub child: *mut cJSON,
    pub type_: c_int,
    pub valuestring: *mut c_char,
    pub valueint: c_int,
    pub valuedouble: c_double,
    pub string: *mut c_char,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct cJSON_Hooks {
    pub malloc_fn: Option<malloc_fn>,
    pub free_fn: Option<free_fn>,
}

#[inline]
pub fn bool_to_cjson(value: bool) -> cJSON_bool {
    if value {
        1
    } else {
        0
    }
}
