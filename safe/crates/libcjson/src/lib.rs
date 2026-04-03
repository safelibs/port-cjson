#![allow(non_camel_case_types)]
#![allow(non_upper_case_globals)]

mod abi;
mod create;
mod delete;
mod duplicate;
mod hooks;
mod list;
mod mutate;
mod number;
mod tree;
mod typecheck;

use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use std::ptr;

use abi::{
    bool_to_cjson, cJSON, cJSON_Array, cJSON_False, cJSON_NULL, cJSON_Number, cJSON_Object,
    cJSON_Raw, cJSON_String, cJSON_True, cJSON_bool, TYPE_MASK,
};
use hooks::{duplicate_c_string, set_parse_error};
use list::get_object_item;

const PRINT_STUB: &[u8] = b"null\0";

#[cfg(cjson_enable_locales)]
const LOCALES_ENABLED: bool = true;
#[cfg(not(cjson_enable_locales))]
const LOCALES_ENABLED: bool = false;

unsafe fn print_stub() -> *mut c_char {
    duplicate_c_string(PRINT_STUB.as_ptr() as *const c_char)
}

unsafe fn print_into_buffer(buffer: *mut c_char, length: c_int) -> cJSON_bool {
    if buffer.is_null() || length < PRINT_STUB.len() as c_int {
        return 0;
    }

    ptr::copy_nonoverlapping(
        PRINT_STUB.as_ptr() as *const c_char,
        buffer,
        PRINT_STUB.len(),
    );
    1
}

unsafe fn compare_items(lhs: *const cJSON, rhs: *const cJSON, case_sensitive: bool) -> bool {
    let lhs_type: c_int;
    let rhs_type: c_int;

    if lhs.is_null() || rhs.is_null() {
        return false;
    }

    lhs_type = (*lhs).type_ & TYPE_MASK;
    rhs_type = (*rhs).type_ & TYPE_MASK;
    if lhs_type != rhs_type {
        return false;
    }

    match lhs_type {
        cJSON_False | cJSON_True | cJSON_NULL => true,
        cJSON_Number => (*lhs).valuedouble == (*rhs).valuedouble,
        cJSON_String | cJSON_Raw => {
            if (*lhs).valuestring.is_null() || (*rhs).valuestring.is_null() {
                return false;
            }

            CStr::from_ptr((*lhs).valuestring).to_bytes()
                == CStr::from_ptr((*rhs).valuestring).to_bytes()
        }
        cJSON_Array => {
            let mut lhs_child = (*lhs).child;
            let mut rhs_child = (*rhs).child;

            while !lhs_child.is_null() && !rhs_child.is_null() {
                if !compare_items(lhs_child, rhs_child, case_sensitive) {
                    return false;
                }

                lhs_child = (*lhs_child).next;
                rhs_child = (*rhs_child).next;
            }

            lhs_child.is_null() && rhs_child.is_null()
        }
        cJSON_Object => {
            let mut lhs_child = (*lhs).child;
            let mut rhs_child = (*rhs).child;

            while !lhs_child.is_null() {
                let matched = get_object_item(rhs, (*lhs_child).string, case_sensitive);
                if matched.is_null() || !compare_items(lhs_child, matched, case_sensitive) {
                    return false;
                }

                lhs_child = (*lhs_child).next;
            }

            while !rhs_child.is_null() {
                let matched = get_object_item(lhs, (*rhs_child).string, case_sensitive);
                if matched.is_null() || !compare_items(rhs_child, matched, case_sensitive) {
                    return false;
                }

                rhs_child = (*rhs_child).next;
            }

            true
        }
        _ => false,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Parse(value: *const c_char) -> *mut cJSON {
    set_parse_error(value);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ParseWithLength(
    value: *const c_char,
    _buffer_length: usize,
) -> *mut cJSON {
    set_parse_error(value);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ParseWithOpts(
    value: *const c_char,
    return_parse_end: *mut *const c_char,
    _require_null_terminated: cJSON_bool,
) -> *mut cJSON {
    if !return_parse_end.is_null() {
        *return_parse_end = value;
    }

    set_parse_error(value);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ParseWithLengthOpts(
    value: *const c_char,
    _buffer_length: usize,
    return_parse_end: *mut *const c_char,
    _require_null_terminated: cJSON_bool,
) -> *mut cJSON {
    if !return_parse_end.is_null() {
        *return_parse_end = value;
    }

    set_parse_error(value);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Print(item: *const cJSON) -> *mut c_char {
    if item.is_null() {
        return ptr::null_mut();
    }

    print_stub()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_PrintUnformatted(item: *const cJSON) -> *mut c_char {
    cJSON_Print(item)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_PrintBuffered(
    item: *const cJSON,
    _prebuffer: c_int,
    _fmt: cJSON_bool,
) -> *mut c_char {
    cJSON_Print(item)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_PrintPreallocated(
    item: *mut cJSON,
    buffer: *mut c_char,
    length: c_int,
    _format: cJSON_bool,
) -> cJSON_bool {
    if item.is_null() {
        return 0;
    }

    print_into_buffer(buffer, length)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Compare(
    a: *const cJSON,
    b: *const cJSON,
    case_sensitive: cJSON_bool,
) -> cJSON_bool {
    bool_to_cjson(compare_items(a, b, case_sensitive != 0))
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Minify(_json: *mut c_char) {
    let _ = LOCALES_ENABLED;
}
