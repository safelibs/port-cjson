use std::ffi::CStr;

use crate::abi::{
    bool_to_cjson, cJSON, cJSON_Array, cJSON_False, cJSON_NULL, cJSON_Number, cJSON_Object,
    cJSON_Raw, cJSON_String, cJSON_True, cJSON_bool, TYPE_MASK,
};
use crate::list::get_object_item;
use crate::number::compare_double;

unsafe fn compare_items(lhs: *const cJSON, rhs: *const cJSON, case_sensitive: bool) -> bool {
    if lhs.is_null() || rhs.is_null() || ((*lhs).type_ & TYPE_MASK) != ((*rhs).type_ & TYPE_MASK) {
        return false;
    }

    match (*lhs).type_ & TYPE_MASK {
        cJSON_False | cJSON_True | cJSON_NULL | cJSON_Number | cJSON_String | cJSON_Raw
        | cJSON_Array | cJSON_Object => {}
        _ => return false,
    }

    if lhs == rhs {
        return true;
    }

    match (*lhs).type_ & TYPE_MASK {
        cJSON_False | cJSON_True | cJSON_NULL => true,
        cJSON_Number => compare_double((*lhs).valuedouble, (*rhs).valuedouble),
        cJSON_String | cJSON_Raw => {
            if (*lhs).valuestring.is_null() || (*rhs).valuestring.is_null() {
                return false;
            }

            CStr::from_ptr((*lhs).valuestring).to_bytes()
                == CStr::from_ptr((*rhs).valuestring).to_bytes()
        }
        cJSON_Array => {
            let mut lhs_element = (*lhs).child;
            let mut rhs_element = (*rhs).child;

            while !lhs_element.is_null() && !rhs_element.is_null() {
                if !compare_items(lhs_element, rhs_element, case_sensitive) {
                    return false;
                }

                lhs_element = (*lhs_element).next;
                rhs_element = (*rhs_element).next;
            }

            lhs_element == rhs_element
        }
        cJSON_Object => {
            let mut lhs_element = (*lhs).child;
            let mut rhs_element = (*rhs).child;

            while !lhs_element.is_null() {
                let matched = get_object_item(rhs, (*lhs_element).string, case_sensitive);
                if matched.is_null() || !compare_items(lhs_element, matched, case_sensitive) {
                    return false;
                }

                lhs_element = (*lhs_element).next;
            }

            while !rhs_element.is_null() {
                let matched = get_object_item(lhs, (*rhs_element).string, case_sensitive);
                if matched.is_null() || !compare_items(rhs_element, matched, case_sensitive) {
                    return false;
                }

                rhs_element = (*rhs_element).next;
            }

            true
        }
        _ => false,
    }
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Compare(
    a: *const cJSON,
    b: *const cJSON,
    case_sensitive: cJSON_bool,
) -> cJSON_bool {
    bool_to_cjson(compare_items(a, b, case_sensitive != 0))
}
