use std::os::raw::{c_char, c_double, c_int};
use std::ptr;

use crate::abi::{
    bool_to_cjson, cJSON, cJSON_Array, cJSON_False, cJSON_Invalid, cJSON_NULL, cJSON_Number,
    cJSON_Object, cJSON_Raw, cJSON_String, cJSON_True, TYPE_MASK, VERSION,
};

#[no_mangle]
pub unsafe extern "C" fn cJSON_Version() -> *const c_char {
    VERSION.as_ptr() as *const c_char
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_GetStringValue(item: *const cJSON) -> *mut c_char {
    if cJSON_IsString(item) == 0 {
        return ptr::null_mut();
    }

    (*item).valuestring
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_GetNumberValue(item: *const cJSON) -> c_double {
    if cJSON_IsNumber(item) == 0 {
        return f64::NAN;
    }

    (*item).valuedouble
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_IsInvalid(item: *const cJSON) -> c_int {
    if item.is_null() {
        return 0;
    }

    bool_to_cjson(((*item).type_ & TYPE_MASK) == cJSON_Invalid)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_IsFalse(item: *const cJSON) -> c_int {
    if item.is_null() {
        return 0;
    }

    bool_to_cjson(((*item).type_ & TYPE_MASK) == cJSON_False)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_IsTrue(item: *const cJSON) -> c_int {
    if item.is_null() {
        return 0;
    }

    bool_to_cjson(((*item).type_ & TYPE_MASK) == cJSON_True)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_IsBool(item: *const cJSON) -> c_int {
    if item.is_null() {
        return 0;
    }

    bool_to_cjson(((*item).type_ & (cJSON_True | cJSON_False)) != 0)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_IsNull(item: *const cJSON) -> c_int {
    if item.is_null() {
        return 0;
    }

    bool_to_cjson(((*item).type_ & TYPE_MASK) == cJSON_NULL)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_IsNumber(item: *const cJSON) -> c_int {
    if item.is_null() {
        return 0;
    }

    bool_to_cjson(((*item).type_ & TYPE_MASK) == cJSON_Number)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_IsString(item: *const cJSON) -> c_int {
    if item.is_null() {
        return 0;
    }

    bool_to_cjson(((*item).type_ & TYPE_MASK) == cJSON_String)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_IsArray(item: *const cJSON) -> c_int {
    if item.is_null() {
        return 0;
    }

    bool_to_cjson(((*item).type_ & TYPE_MASK) == cJSON_Array)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_IsObject(item: *const cJSON) -> c_int {
    if item.is_null() {
        return 0;
    }

    bool_to_cjson(((*item).type_ & TYPE_MASK) == cJSON_Object)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_IsRaw(item: *const cJSON) -> c_int {
    if item.is_null() {
        return 0;
    }

    bool_to_cjson(((*item).type_ & TYPE_MASK) == cJSON_Raw)
}
