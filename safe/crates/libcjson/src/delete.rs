use std::os::raw::c_void;

use crate::abi::{cJSON, cJSON_IsReference, cJSON_StringIsConst};
use crate::hooks::deallocate;

pub unsafe fn delete_item(mut item: *mut cJSON) {
    while !item.is_null() {
        let next = (*item).next;

        if ((*item).type_ & cJSON_IsReference) == 0 && !(*item).child.is_null() {
            delete_item((*item).child);
        }

        if ((*item).type_ & cJSON_IsReference) == 0 && !(*item).valuestring.is_null() {
            deallocate((*item).valuestring as *mut c_void);
        }

        if ((*item).type_ & cJSON_StringIsConst) == 0 && !(*item).string.is_null() {
            deallocate((*item).string as *mut c_void);
        }

        deallocate(item as *mut c_void);
        item = next;
    }
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Delete(item: *mut cJSON) {
    delete_item(item);
}
