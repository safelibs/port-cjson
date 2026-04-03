use std::os::raw::{c_char, c_double, c_int, c_void};
use std::ptr;

use crate::abi::{cJSON, cJSON_StringIsConst};
use crate::create;
use crate::delete::delete_item;
use crate::hooks::{deallocate, duplicate_c_string};
use crate::list::{
    add_item_to_array_internal, detach_item_via_pointer_internal, get_object_item,
    replace_item_via_pointer_internal,
};
use crate::tree::{cast_away_const, create_reference};

pub unsafe fn add_item_to_object_internal(
    object: *mut cJSON,
    string: *const c_char,
    item: *mut cJSON,
    constant_key: bool,
) -> c_int {
    let new_key: *mut c_char;
    let new_type: c_int;

    if object.is_null() || string.is_null() || item.is_null() || object == item {
        return 0;
    }

    if constant_key {
        new_key = cast_away_const(string);
        new_type = (*item).type_ | cJSON_StringIsConst;
    } else {
        new_key = duplicate_c_string(string);
        if new_key.is_null() {
            return 0;
        }

        new_type = (*item).type_ & !cJSON_StringIsConst;
    }

    if ((*item).type_ & cJSON_StringIsConst) == 0 && !(*item).string.is_null() {
        deallocate((*item).string as *mut c_void);
    }

    (*item).string = new_key;
    (*item).type_ = new_type;

    add_item_to_array_internal(object, item)
}

unsafe fn replace_item_in_object(
    object: *mut cJSON,
    string: *const c_char,
    replacement: *mut cJSON,
    case_sensitive: bool,
) -> c_int {
    if object.is_null() || replacement.is_null() || string.is_null() || object == replacement {
        return 0;
    }

    let item: *mut cJSON = get_object_item(object, string, case_sensitive);
    if item.is_null() {
        return 0;
    }

    let new_key: *mut c_char = duplicate_c_string(string);
    if new_key.is_null() {
        return 0;
    }

    if ((*replacement).type_ & cJSON_StringIsConst) == 0 && !(*replacement).string.is_null() {
        deallocate((*replacement).string as *mut c_void);
    }

    (*replacement).string = new_key;
    (*replacement).type_ &= !cJSON_StringIsConst;

    replace_item_via_pointer_internal(object, item, replacement)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddItemToObject(
    object: *mut cJSON,
    string: *const c_char,
    item: *mut cJSON,
) -> c_int {
    add_item_to_object_internal(object, string, item, false)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddItemToObjectCS(
    object: *mut cJSON,
    string: *const c_char,
    item: *mut cJSON,
) -> c_int {
    add_item_to_object_internal(object, string, item, true)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddItemReferenceToArray(
    array: *mut cJSON,
    item: *mut cJSON,
) -> c_int {
    if array.is_null() || array == item {
        return 0;
    }

    let reference: *mut cJSON = create_reference(item);
    if reference.is_null() {
        return 0;
    }

    if add_item_to_array_internal(array, reference) == 0 {
        delete_item(reference);
        return 0;
    }

    1
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddItemReferenceToObject(
    object: *mut cJSON,
    string: *const c_char,
    item: *mut cJSON,
) -> c_int {
    if object.is_null() || string.is_null() || object == item {
        return 0;
    }

    let reference: *mut cJSON = create_reference(item);
    if reference.is_null() {
        return 0;
    }

    if add_item_to_object_internal(object, string, reference, false) == 0 {
        delete_item(reference);
        return 0;
    }

    1
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddNullToObject(
    object: *mut cJSON,
    name: *const c_char,
) -> *mut cJSON {
    let item = create::cJSON_CreateNull();
    if add_item_to_object_internal(object, name, item, false) != 0 {
        return item;
    }

    delete_item(item);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddTrueToObject(
    object: *mut cJSON,
    name: *const c_char,
) -> *mut cJSON {
    let item = create::cJSON_CreateTrue();
    if add_item_to_object_internal(object, name, item, false) != 0 {
        return item;
    }

    delete_item(item);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddFalseToObject(
    object: *mut cJSON,
    name: *const c_char,
) -> *mut cJSON {
    let item = create::cJSON_CreateFalse();
    if add_item_to_object_internal(object, name, item, false) != 0 {
        return item;
    }

    delete_item(item);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddBoolToObject(
    object: *mut cJSON,
    name: *const c_char,
    boolean: c_int,
) -> *mut cJSON {
    let item = create::cJSON_CreateBool(boolean);
    if add_item_to_object_internal(object, name, item, false) != 0 {
        return item;
    }

    delete_item(item);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddNumberToObject(
    object: *mut cJSON,
    name: *const c_char,
    number: c_double,
) -> *mut cJSON {
    let item = create::cJSON_CreateNumber(number);
    if add_item_to_object_internal(object, name, item, false) != 0 {
        return item;
    }

    delete_item(item);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddStringToObject(
    object: *mut cJSON,
    name: *const c_char,
    string: *const c_char,
) -> *mut cJSON {
    let item = create::cJSON_CreateString(string);
    if add_item_to_object_internal(object, name, item, false) != 0 {
        return item;
    }

    delete_item(item);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddRawToObject(
    object: *mut cJSON,
    name: *const c_char,
    raw: *const c_char,
) -> *mut cJSON {
    let item = create::cJSON_CreateRaw(raw);
    if add_item_to_object_internal(object, name, item, false) != 0 {
        return item;
    }

    delete_item(item);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddObjectToObject(
    object: *mut cJSON,
    name: *const c_char,
) -> *mut cJSON {
    let item = create::cJSON_CreateObject();
    if add_item_to_object_internal(object, name, item, false) != 0 {
        return item;
    }

    delete_item(item);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddArrayToObject(
    object: *mut cJSON,
    name: *const c_char,
) -> *mut cJSON {
    let item = create::cJSON_CreateArray();
    if add_item_to_object_internal(object, name, item, false) != 0 {
        return item;
    }

    delete_item(item);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_DetachItemFromObject(
    object: *mut cJSON,
    string: *const c_char,
) -> *mut cJSON {
    detach_item_via_pointer_internal(object, get_object_item(object, string, false))
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_DetachItemFromObjectCaseSensitive(
    object: *mut cJSON,
    string: *const c_char,
) -> *mut cJSON {
    detach_item_via_pointer_internal(object, get_object_item(object, string, true))
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_DeleteItemFromObject(object: *mut cJSON, string: *const c_char) {
    delete_item(cJSON_DetachItemFromObject(object, string));
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_DeleteItemFromObjectCaseSensitive(
    object: *mut cJSON,
    string: *const c_char,
) {
    delete_item(cJSON_DetachItemFromObjectCaseSensitive(object, string));
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ReplaceItemInObject(
    object: *mut cJSON,
    string: *const c_char,
    newitem: *mut cJSON,
) -> c_int {
    replace_item_in_object(object, string, newitem, false)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ReplaceItemInObjectCaseSensitive(
    object: *mut cJSON,
    string: *const c_char,
    newitem: *mut cJSON,
) -> c_int {
    replace_item_in_object(object, string, newitem, true)
}
