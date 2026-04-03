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

#[cfg(test)]
mod tests {
    use std::mem::{offset_of, size_of};
    use std::os::raw::c_int;

    use super::{
        cJSON, cJSON_Array, cJSON_False, cJSON_Hooks, cJSON_Invalid, cJSON_IsReference, cJSON_NULL,
        cJSON_Number, cJSON_Object, cJSON_Raw, cJSON_String, cJSON_StringIsConst, cJSON_True,
        cJSON_bool,
    };

    #[test]
    fn cjson_layout_matches_public_header() {
        assert_eq!(size_of::<cJSON_bool>(), size_of::<c_int>());
        assert_eq!(size_of::<cJSON_Hooks>(), size_of::<usize>() * 2);
        assert_eq!(offset_of!(cJSON_Hooks, malloc_fn), 0);
        assert_eq!(offset_of!(cJSON_Hooks, free_fn), size_of::<usize>());

        if size_of::<usize>() == 8 {
            assert_eq!(size_of::<cJSON>(), 64);
            assert_eq!(offset_of!(cJSON, next), 0);
            assert_eq!(offset_of!(cJSON, prev), 8);
            assert_eq!(offset_of!(cJSON, child), 16);
            assert_eq!(offset_of!(cJSON, type_), 24);
            assert_eq!(offset_of!(cJSON, valuestring), 32);
            assert_eq!(offset_of!(cJSON, valueint), 40);
            assert_eq!(offset_of!(cJSON, valuedouble), 48);
            assert_eq!(offset_of!(cJSON, string), 56);
        } else if size_of::<usize>() == 4 {
            assert_eq!(size_of::<cJSON>(), 36);
            assert_eq!(offset_of!(cJSON, next), 0);
            assert_eq!(offset_of!(cJSON, prev), 4);
            assert_eq!(offset_of!(cJSON, child), 8);
            assert_eq!(offset_of!(cJSON, type_), 12);
            assert_eq!(offset_of!(cJSON, valuestring), 16);
            assert_eq!(offset_of!(cJSON, valueint), 20);
            assert_eq!(offset_of!(cJSON, valuedouble), 24);
            assert_eq!(offset_of!(cJSON, string), 32);
        } else {
            panic!("unsupported pointer size for cJSON ABI layout tests");
        }
    }

    #[test]
    fn cjson_flag_constants_match_public_header() {
        assert_eq!(cJSON_Invalid, 0);
        assert_eq!(cJSON_False, 1);
        assert_eq!(cJSON_True, 2);
        assert_eq!(cJSON_NULL, 4);
        assert_eq!(cJSON_Number, 8);
        assert_eq!(cJSON_String, 16);
        assert_eq!(cJSON_Array, 32);
        assert_eq!(cJSON_Object, 64);
        assert_eq!(cJSON_Raw, 128);
        assert_eq!(cJSON_IsReference, 256);
        assert_eq!(cJSON_StringIsConst, 512);
    }
}
