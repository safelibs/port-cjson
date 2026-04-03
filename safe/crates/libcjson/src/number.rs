use std::ffi::CStr;
use std::os::raw::{c_char, c_double, c_int, c_void};
use std::ptr;

use crate::abi::{cJSON, cJSON_IsReference, cJSON_String};
use crate::hooks::{deallocate, duplicate_c_string};

pub fn saturating_valueint(number: c_double) -> c_int {
    if number >= c_int::MAX as c_double {
        c_int::MAX
    } else if number <= c_int::MIN as c_double {
        c_int::MIN
    } else {
        number as c_int
    }
}

pub unsafe fn set_number_fields(item: *mut cJSON, number: c_double) {
    (*item).valueint = saturating_valueint(number);
    (*item).valuedouble = number;
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_SetNumberHelper(object: *mut cJSON, number: c_double) -> c_double {
    if object.is_null() {
        return number;
    }

    set_number_fields(object, number);
    (*object).valuedouble
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_SetValuestring(
    object: *mut cJSON,
    valuestring: *const c_char,
) -> *mut c_char {
    let old_length: usize;
    let new_length: usize;
    let copy: *mut c_char;

    if object.is_null()
        || ((*object).type_ & cJSON_String) == 0
        || ((*object).type_ & cJSON_IsReference) != 0
    {
        return ptr::null_mut();
    }

    if (*object).valuestring.is_null() || valuestring.is_null() {
        return ptr::null_mut();
    }

    old_length = CStr::from_ptr((*object).valuestring).to_bytes().len();
    new_length = CStr::from_ptr(valuestring).to_bytes().len();
    if new_length <= old_length {
        ptr::copy_nonoverlapping(valuestring, (*object).valuestring, new_length + 1);
        return (*object).valuestring;
    }

    copy = duplicate_c_string(valuestring);
    if copy.is_null() {
        return ptr::null_mut();
    }

    deallocate((*object).valuestring as *mut c_void);
    (*object).valuestring = copy;

    copy
}
