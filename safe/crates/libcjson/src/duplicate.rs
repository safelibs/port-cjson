use std::os::raw::c_int;
use std::ptr;

use crate::abi::{cJSON, cJSON_IsReference, cJSON_StringIsConst};
use crate::delete::delete_item;
use crate::hooks::{duplicate_c_string, new_item};

#[no_mangle]
pub unsafe extern "C" fn cJSON_Duplicate(item: *const cJSON, recurse: c_int) -> *mut cJSON {
    let mut child: *mut cJSON;
    let mut next: *mut cJSON = ptr::null_mut();
    let mut newchild: *mut cJSON;

    if item.is_null() {
        return ptr::null_mut();
    }

    let newitem: *mut cJSON = new_item();
    if newitem.is_null() {
        return ptr::null_mut();
    }

    (*newitem).type_ = (*item).type_ & !cJSON_IsReference;
    (*newitem).valueint = (*item).valueint;
    (*newitem).valuedouble = (*item).valuedouble;

    if !(*item).valuestring.is_null() {
        (*newitem).valuestring = duplicate_c_string((*item).valuestring);
        if (*newitem).valuestring.is_null() {
            delete_item(newitem);
            return ptr::null_mut();
        }
    }

    if !(*item).string.is_null() {
        (*newitem).string = if ((*item).type_ & cJSON_StringIsConst) != 0 {
            (*item).string
        } else {
            duplicate_c_string((*item).string)
        };

        if (*newitem).string.is_null() {
            delete_item(newitem);
            return ptr::null_mut();
        }
    }

    if recurse == 0 {
        return newitem;
    }

    child = (*item).child;
    while !child.is_null() {
        newchild = cJSON_Duplicate(child, 1);
        if newchild.is_null() {
            delete_item(newitem);
            return ptr::null_mut();
        }

        if !next.is_null() {
            (*next).next = newchild;
            (*newchild).prev = next;
            next = newchild;
        } else {
            (*newitem).child = newchild;
            next = newchild;
        }

        child = (*child).next;
    }

    if !(*newitem).child.is_null() {
        (*(*newitem).child).prev = next;
    }

    newitem
}
