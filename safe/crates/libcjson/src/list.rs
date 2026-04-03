use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use std::ptr;

use crate::abi::{bool_to_cjson, cJSON, cJSON_bool};
use crate::delete::delete_item;

pub unsafe fn suffix_object(prev: *mut cJSON, item: *mut cJSON) {
    (*prev).next = item;
    (*item).prev = prev;
}

pub unsafe fn case_insensitive_strcmp(string1: *const c_char, string2: *const c_char) -> c_int {
    let mut index = 0usize;

    if string1.is_null() || string2.is_null() {
        return 1;
    }

    if string1 == string2 {
        return 0;
    }

    loop {
        let lhs = (*string1.add(index) as u8).to_ascii_lowercase();
        let rhs = (*string2.add(index) as u8).to_ascii_lowercase();

        if lhs != rhs {
            return lhs as c_int - rhs as c_int;
        }

        if lhs == 0 {
            return 0;
        }

        index += 1;
    }
}

pub unsafe fn get_array_item(array: *const cJSON, mut index: usize) -> *mut cJSON {
    let mut current_child: *mut cJSON;

    if array.is_null() {
        return ptr::null_mut();
    }

    current_child = (*array).child;
    while !current_child.is_null() && index > 0 {
        index -= 1;
        current_child = (*current_child).next;
    }

    current_child
}

pub unsafe fn get_object_item(
    object: *const cJSON,
    name: *const c_char,
    case_sensitive: bool,
) -> *mut cJSON {
    let mut current_element: *mut cJSON;

    if object.is_null() || name.is_null() {
        return ptr::null_mut();
    }

    current_element = (*object).child;
    if case_sensitive {
        let wanted = CStr::from_ptr(name).to_bytes();
        while !current_element.is_null()
            && !(*current_element).string.is_null()
            && CStr::from_ptr((*current_element).string).to_bytes() != wanted
        {
            current_element = (*current_element).next;
        }
    } else {
        while !current_element.is_null()
            && case_insensitive_strcmp(name, (*current_element).string) != 0
        {
            current_element = (*current_element).next;
        }
    }

    if current_element.is_null() || (*current_element).string.is_null() {
        return ptr::null_mut();
    }

    current_element
}

pub unsafe fn add_item_to_array_internal(array: *mut cJSON, item: *mut cJSON) -> cJSON_bool {
    let child: *mut cJSON;

    if item.is_null() || array.is_null() || array == item {
        return 0;
    }

    child = (*array).child;
    if child.is_null() {
        (*array).child = item;
        (*item).prev = item;
        (*item).next = ptr::null_mut();
    } else if !(*child).prev.is_null() {
        (*item).next = ptr::null_mut();
        suffix_object((*child).prev, item);
        (*array).child = child;
        (*child).prev = item;
    }

    1
}

pub unsafe fn detach_item_via_pointer_internal(parent: *mut cJSON, item: *mut cJSON) -> *mut cJSON {
    if parent.is_null() || item.is_null() {
        return ptr::null_mut();
    }

    if item != (*parent).child {
        (*(*item).prev).next = (*item).next;
    }

    if !(*item).next.is_null() {
        (*(*item).next).prev = (*item).prev;
    }

    if item == (*parent).child {
        (*parent).child = (*item).next;
    } else if (*item).next.is_null() {
        (*(*parent).child).prev = (*item).prev;
    }

    (*item).prev = ptr::null_mut();
    (*item).next = ptr::null_mut();

    item
}

pub unsafe fn replace_item_via_pointer_internal(
    parent: *mut cJSON,
    item: *mut cJSON,
    replacement: *mut cJSON,
) -> cJSON_bool {
    if parent.is_null()
        || (*parent).child.is_null()
        || replacement.is_null()
        || item.is_null()
        || parent == replacement
    {
        return 0;
    }

    if replacement == item {
        return 1;
    }

    (*replacement).next = (*item).next;
    (*replacement).prev = (*item).prev;

    if !(*replacement).next.is_null() {
        (*(*replacement).next).prev = replacement;
    }

    if (*parent).child == item {
        if (*(*parent).child).prev == (*parent).child {
            (*replacement).prev = replacement;
        }

        (*parent).child = replacement;
    } else {
        if !(*replacement).prev.is_null() {
            (*(*replacement).prev).next = replacement;
        }

        if (*replacement).next.is_null() {
            (*(*parent).child).prev = replacement;
        }
    }

    (*item).next = ptr::null_mut();
    (*item).prev = ptr::null_mut();
    delete_item(item);

    1
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_GetArraySize(array: *const cJSON) -> c_int {
    let mut size = 0;
    let mut child: *mut cJSON;

    if array.is_null() {
        return 0;
    }

    child = (*array).child;
    while !child.is_null() {
        size += 1;
        child = (*child).next;
    }

    size
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_GetArrayItem(array: *const cJSON, index: c_int) -> *mut cJSON {
    if index < 0 {
        return ptr::null_mut();
    }

    get_array_item(array, index as usize)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_GetObjectItem(
    object: *const cJSON,
    string: *const c_char,
) -> *mut cJSON {
    get_object_item(object, string, false)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_GetObjectItemCaseSensitive(
    object: *const cJSON,
    string: *const c_char,
) -> *mut cJSON {
    get_object_item(object, string, true)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_HasObjectItem(
    object: *const cJSON,
    string: *const c_char,
) -> cJSON_bool {
    bool_to_cjson(!get_object_item(object, string, false).is_null())
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddItemToArray(array: *mut cJSON, item: *mut cJSON) -> cJSON_bool {
    add_item_to_array_internal(array, item)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_DetachItemViaPointer(
    parent: *mut cJSON,
    item: *mut cJSON,
) -> *mut cJSON {
    detach_item_via_pointer_internal(parent, item)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_DetachItemFromArray(array: *mut cJSON, which: c_int) -> *mut cJSON {
    if which < 0 {
        return ptr::null_mut();
    }

    detach_item_via_pointer_internal(array, get_array_item(array, which as usize))
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_DeleteItemFromArray(array: *mut cJSON, which: c_int) {
    delete_item(cJSON_DetachItemFromArray(array, which));
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_InsertItemInArray(
    array: *mut cJSON,
    which: c_int,
    newitem: *mut cJSON,
) -> cJSON_bool {
    let after_inserted: *mut cJSON;

    if which < 0 || newitem.is_null() || array.is_null() || array == newitem {
        return 0;
    }

    after_inserted = get_array_item(array, which as usize);
    if after_inserted.is_null() {
        return add_item_to_array_internal(array, newitem);
    }

    if after_inserted != (*array).child && (*after_inserted).prev.is_null() {
        return 0;
    }

    (*newitem).next = after_inserted;
    (*newitem).prev = (*after_inserted).prev;
    (*after_inserted).prev = newitem;

    if after_inserted == (*array).child {
        (*array).child = newitem;
    } else {
        (*(*newitem).prev).next = newitem;
    }

    1
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ReplaceItemViaPointer(
    parent: *mut cJSON,
    item: *mut cJSON,
    replacement: *mut cJSON,
) -> cJSON_bool {
    replace_item_via_pointer_internal(parent, item, replacement)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ReplaceItemInArray(
    array: *mut cJSON,
    which: c_int,
    newitem: *mut cJSON,
) -> cJSON_bool {
    if which < 0 {
        return 0;
    }

    replace_item_via_pointer_internal(array, get_array_item(array, which as usize), newitem)
}
