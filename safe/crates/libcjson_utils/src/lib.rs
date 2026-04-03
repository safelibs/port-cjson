#![allow(non_camel_case_types)]
#![allow(non_upper_case_globals)]

use std::ffi::CStr;
use std::os::raw::{c_char, c_double, c_int, c_void};
use std::ptr;

mod merge_patch;
mod patch;
mod pointer;
mod sort;

pub type cJSON_bool = c_int;

pub const cJSON_Invalid: c_int = 0;
pub const cJSON_False: c_int = 1 << 0;
pub const cJSON_True: c_int = 1 << 1;
pub const cJSON_NULL: c_int = 1 << 2;
pub const cJSON_Number: c_int = 1 << 3;
pub const cJSON_String: c_int = 1 << 4;
pub const cJSON_Array: c_int = 1 << 5;
pub const cJSON_Object: c_int = 1 << 6;
pub const cJSON_Raw: c_int = 1 << 7;
pub const cJSON_IsReference: c_int = 256;
pub const cJSON_StringIsConst: c_int = 512;
pub const TYPE_MASK: c_int = 0xFF;

#[repr(C)]
pub struct cJSON {
    pub next: *mut cJSON,
    pub prev: *mut cJSON,
    pub child: *mut cJSON,
    pub type_: c_int,
    pub valuestring: *mut c_char,
    pub valueint: c_int,
    pub valuedouble: c_double,
    pub string: *mut c_char,
}

extern "C" {
    fn cJSON_CreateArray() -> *mut cJSON;
    fn cJSON_CreateNull() -> *mut cJSON;
    fn cJSON_CreateObject() -> *mut cJSON;
    fn cJSON_CreateString(string: *const c_char) -> *mut cJSON;
    fn cJSON_GetObjectItem(object: *const cJSON, string: *const c_char) -> *mut cJSON;
    fn cJSON_GetObjectItemCaseSensitive(object: *const cJSON, string: *const c_char) -> *mut cJSON;
    fn cJSON_AddItemToArray(array: *mut cJSON, item: *mut cJSON) -> cJSON_bool;
    fn cJSON_AddItemToObject(object: *mut cJSON, string: *const c_char, item: *mut cJSON) -> c_int;
    fn cJSON_DetachItemFromObject(object: *mut cJSON, string: *const c_char) -> *mut cJSON;
    fn cJSON_DetachItemFromObjectCaseSensitive(
        object: *mut cJSON,
        string: *const c_char,
    ) -> *mut cJSON;
    fn cJSON_DeleteItemFromObject(object: *mut cJSON, string: *const c_char);
    fn cJSON_DeleteItemFromObjectCaseSensitive(object: *mut cJSON, string: *const c_char);
    fn cJSON_Duplicate(item: *const cJSON, recurse: c_int) -> *mut cJSON;
    fn cJSON_Delete(item: *mut cJSON);
    fn cJSON_malloc(size: usize) -> *mut c_void;
    fn cJSON_free(object: *mut c_void);
}

pub(crate) unsafe fn bytes_from_c_string<'a>(string: *const c_char) -> &'a [u8] {
    CStr::from_ptr(string).to_bytes()
}

pub(crate) fn nul_terminated(bytes: &[u8]) -> Vec<u8> {
    let mut output = Vec::with_capacity(bytes.len() + 1);
    output.extend_from_slice(bytes);
    output.push(0);
    output
}

pub(crate) unsafe fn duplicate_bytes(bytes: &[u8]) -> *mut c_char {
    let output = cJSON_malloc(bytes.len() + 1) as *mut c_char;
    if output.is_null() {
        return ptr::null_mut();
    }

    if !bytes.is_empty() {
        ptr::copy_nonoverlapping(bytes.as_ptr() as *const c_char, output, bytes.len());
    }
    *output.add(bytes.len()) = 0;

    output
}

pub(crate) fn compare_bytes(left: &[u8], right: &[u8], case_sensitive: bool) -> c_int {
    let mut index = 0usize;

    loop {
        let left_byte = left.get(index).copied().unwrap_or(0);
        let right_byte = right.get(index).copied().unwrap_or(0);
        let lhs = if case_sensitive {
            left_byte
        } else {
            left_byte.to_ascii_lowercase()
        };
        let rhs = if case_sensitive {
            right_byte
        } else {
            right_byte.to_ascii_lowercase()
        };

        if lhs != rhs {
            return lhs as c_int - rhs as c_int;
        }

        if left_byte == 0 && right_byte == 0 {
            return 0;
        }

        index += 1;
    }
}

pub(crate) unsafe fn compare_strings(
    left: *const c_char,
    right: *const c_char,
    case_sensitive: bool,
) -> c_int {
    if left.is_null() || right.is_null() {
        return 1;
    }

    if left == right {
        return 0;
    }

    compare_bytes(
        bytes_from_c_string(left),
        bytes_from_c_string(right),
        case_sensitive,
    )
}

pub(crate) fn compare_double(left: c_double, right: c_double) -> bool {
    let max_value = left.abs().max(right.abs());
    (left - right).abs() <= max_value * c_double::EPSILON
}

pub(crate) unsafe fn get_object_item(
    object: *const cJSON,
    name: *const c_char,
    case_sensitive: bool,
) -> *mut cJSON {
    if case_sensitive {
        cJSON_GetObjectItemCaseSensitive(object, name)
    } else {
        cJSON_GetObjectItem(object, name)
    }
}

#[inline]
pub(crate) unsafe fn item_type(item: *const cJSON) -> c_int {
    if item.is_null() {
        cJSON_Invalid
    } else {
        (*item).type_ & TYPE_MASK
    }
}

#[inline]
pub(crate) unsafe fn is_array(item: *const cJSON) -> bool {
    item_type(item) == cJSON_Array
}

#[inline]
pub(crate) unsafe fn is_object(item: *const cJSON) -> bool {
    item_type(item) == cJSON_Object
}

#[inline]
pub(crate) unsafe fn is_string(item: *const cJSON) -> bool {
    item_type(item) == cJSON_String
}

#[inline]
pub(crate) unsafe fn is_null(item: *const cJSON) -> bool {
    item_type(item) == cJSON_NULL
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_GetPointer(
    object: *mut cJSON,
    pointer: *const c_char,
) -> *mut cJSON {
    pointer::get_item_from_pointer(object, pointer, false)
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_GetPointerCaseSensitive(
    object: *mut cJSON,
    pointer: *const c_char,
) -> *mut cJSON {
    pointer::get_item_from_pointer(object, pointer, true)
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_GeneratePatches(
    from: *mut cJSON,
    to: *mut cJSON,
) -> *mut cJSON {
    patch::generate_patches(from, to, false)
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_GeneratePatchesCaseSensitive(
    from: *mut cJSON,
    to: *mut cJSON,
) -> *mut cJSON {
    patch::generate_patches(from, to, true)
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_AddPatchToArray(
    array: *mut cJSON,
    operation: *const c_char,
    path: *const c_char,
    value: *const cJSON,
) {
    patch::add_patch_to_array(array, operation, path, value);
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_ApplyPatches(
    object: *mut cJSON,
    patches: *const cJSON,
) -> c_int {
    patch::apply_patches(object, patches, false)
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_ApplyPatchesCaseSensitive(
    object: *mut cJSON,
    patches: *const cJSON,
) -> c_int {
    patch::apply_patches(object, patches, true)
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_MergePatch(
    target: *mut cJSON,
    patch: *const cJSON,
) -> *mut cJSON {
    merge_patch::merge_patch(target, patch, false)
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_MergePatchCaseSensitive(
    target: *mut cJSON,
    patch: *const cJSON,
) -> *mut cJSON {
    merge_patch::merge_patch(target, patch, true)
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_GenerateMergePatch(
    from: *mut cJSON,
    to: *mut cJSON,
) -> *mut cJSON {
    merge_patch::generate_merge_patch(from, to, false)
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_GenerateMergePatchCaseSensitive(
    from: *mut cJSON,
    to: *mut cJSON,
) -> *mut cJSON {
    merge_patch::generate_merge_patch(from, to, true)
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_FindPointerFromObjectTo(
    object: *const cJSON,
    target: *const cJSON,
) -> *mut c_char {
    pointer::find_pointer_from_object_to(object, target)
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_SortObject(object: *mut cJSON) {
    sort::sort_object(object, false);
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_SortObjectCaseSensitive(object: *mut cJSON) {
    sort::sort_object(object, true);
}
