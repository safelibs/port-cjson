use std::ptr;

use crate::abi::{cJSON, cJSON_IsReference};
use crate::hooks::new_item;

#[inline]
pub unsafe fn cast_away_const<T>(pointer: *const T) -> *mut T {
    pointer as *mut T
}

pub unsafe fn create_reference(item: *const cJSON) -> *mut cJSON {
    let reference: *mut cJSON;

    if item.is_null() {
        return ptr::null_mut();
    }

    reference = new_item();
    if reference.is_null() {
        return ptr::null_mut();
    }

    ptr::copy_nonoverlapping(item, reference, 1);
    (*reference).string = ptr::null_mut();
    (*reference).type_ |= cJSON_IsReference;
    (*reference).next = ptr::null_mut();
    (*reference).prev = ptr::null_mut();

    reference
}
