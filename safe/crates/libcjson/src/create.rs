use std::os::raw::{c_char, c_double, c_int};
use std::ptr;
use std::slice;

use crate::abi::{
    cJSON, cJSON_Array, cJSON_False, cJSON_IsReference, cJSON_NULL, cJSON_Number, cJSON_Object,
    cJSON_Raw, cJSON_String, cJSON_True,
};
use crate::delete::delete_item;
use crate::hooks::{duplicate_c_string, new_item};
use crate::list::add_item_to_array_internal;
use crate::number::set_number_fields;
use crate::tree::cast_away_const;

fn new_typed_item(item_type: c_int) -> *mut cJSON {
    let item = unsafe { new_item() };
    if item.is_null() {
        return ptr::null_mut();
    }

    unsafe {
        (*item).type_ = item_type;
    }
    item
}

fn create_number_item(number: c_double) -> *mut cJSON {
    let item = new_typed_item(cJSON_Number);
    if item.is_null() {
        return ptr::null_mut();
    }

    unsafe {
        set_number_fields(item, number);
    }
    item
}

unsafe fn create_string_item(string: *const c_char, item_type: c_int) -> *mut cJSON {
    let item = new_typed_item(item_type);
    if item.is_null() {
        return ptr::null_mut();
    }

    (*item).valuestring = duplicate_c_string(string);
    if !(*item).valuestring.is_null() {
        return item;
    }

    delete_item(item);
    ptr::null_mut()
}

#[no_mangle]
pub extern "C" fn cJSON_CreateNull() -> *mut cJSON {
    new_typed_item(cJSON_NULL)
}

#[no_mangle]
pub extern "C" fn cJSON_CreateTrue() -> *mut cJSON {
    new_typed_item(cJSON_True)
}

#[no_mangle]
pub extern "C" fn cJSON_CreateFalse() -> *mut cJSON {
    new_typed_item(cJSON_False)
}

#[no_mangle]
pub extern "C" fn cJSON_CreateBool(boolean: c_int) -> *mut cJSON {
    if boolean == 0 {
        cJSON_CreateFalse()
    } else {
        cJSON_CreateTrue()
    }
}

#[no_mangle]
pub extern "C" fn cJSON_CreateNumber(num: c_double) -> *mut cJSON {
    create_number_item(num)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateString(string: *const c_char) -> *mut cJSON {
    create_string_item(string, cJSON_String)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateRaw(raw: *const c_char) -> *mut cJSON {
    create_string_item(raw, cJSON_Raw)
}

#[no_mangle]
pub extern "C" fn cJSON_CreateArray() -> *mut cJSON {
    new_typed_item(cJSON_Array)
}

#[no_mangle]
pub extern "C" fn cJSON_CreateObject() -> *mut cJSON {
    new_typed_item(cJSON_Object)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateStringReference(string: *const c_char) -> *mut cJSON {
    let item = new_item();
    if !item.is_null() {
        (*item).type_ = cJSON_String | cJSON_IsReference;
        (*item).valuestring = cast_away_const(string);
    }

    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateObjectReference(child: *const cJSON) -> *mut cJSON {
    let item = new_item();
    if !item.is_null() {
        (*item).type_ = cJSON_Object | cJSON_IsReference;
        (*item).child = cast_away_const(child);
    }

    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateArrayReference(child: *const cJSON) -> *mut cJSON {
    let item = new_item();
    if !item.is_null() {
        (*item).type_ = cJSON_Array | cJSON_IsReference;
        (*item).child = cast_away_const(child);
    }

    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateIntArray(numbers: *const c_int, count: c_int) -> *mut cJSON {
    let array: *mut cJSON;

    if count < 0 || numbers.is_null() {
        return ptr::null_mut();
    }

    array = cJSON_CreateArray();
    if array.is_null() {
        return ptr::null_mut();
    }

    for number in slice::from_raw_parts(numbers, count as usize) {
        let item = cJSON_CreateNumber(*number as c_double);
        if item.is_null() || add_item_to_array_internal(array, item) == 0 {
            delete_item(array);
            return ptr::null_mut();
        }
    }

    array
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateFloatArray(numbers: *const f32, count: c_int) -> *mut cJSON {
    let array: *mut cJSON;

    if count < 0 || numbers.is_null() {
        return ptr::null_mut();
    }

    array = cJSON_CreateArray();
    if array.is_null() {
        return ptr::null_mut();
    }

    for number in slice::from_raw_parts(numbers, count as usize) {
        let item = cJSON_CreateNumber(*number as c_double);
        if item.is_null() || add_item_to_array_internal(array, item) == 0 {
            delete_item(array);
            return ptr::null_mut();
        }
    }

    array
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateDoubleArray(
    numbers: *const c_double,
    count: c_int,
) -> *mut cJSON {
    let array: *mut cJSON;

    if count < 0 || numbers.is_null() {
        return ptr::null_mut();
    }

    array = cJSON_CreateArray();
    if array.is_null() {
        return ptr::null_mut();
    }

    for number in slice::from_raw_parts(numbers, count as usize) {
        let item = cJSON_CreateNumber(*number);
        if item.is_null() || add_item_to_array_internal(array, item) == 0 {
            delete_item(array);
            return ptr::null_mut();
        }
    }

    array
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateStringArray(
    strings: *const *const c_char,
    count: c_int,
) -> *mut cJSON {
    let array: *mut cJSON;

    if count < 0 || strings.is_null() {
        return ptr::null_mut();
    }

    array = cJSON_CreateArray();
    if array.is_null() {
        return ptr::null_mut();
    }

    for string in slice::from_raw_parts(strings, count as usize) {
        let item = cJSON_CreateString(*string);
        if item.is_null() || add_item_to_array_internal(array, item) == 0 {
            delete_item(array);
            return ptr::null_mut();
        }
    }

    array
}
