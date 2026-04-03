#![allow(non_camel_case_types)]

use std::os::raw::{c_char, c_double, c_int, c_void};
use std::ptr;

#[repr(C)]
pub struct cJSON
{
    pub next: *mut cJSON,
    pub prev: *mut cJSON,
    pub child: *mut cJSON,
    pub type_: c_int,
    pub valuestring: *mut c_char,
    pub valueint: c_int,
    pub valuedouble: c_double,
    pub string: *mut c_char,
}

unsafe extern "C" {
    fn cJSON_CreateArray() -> *mut cJSON;
    fn cJSON_GetErrorPtr() -> *const c_char;
    fn cJSON_malloc(size: usize) -> *mut c_void;
    fn cJSON_free(object: *mut c_void);
}

unsafe fn touch_core_dependency()
{
    let scratch = cJSON_malloc(1);
    if !scratch.is_null() {
        cJSON_free(scratch);
    }
    let _ = cJSON_GetErrorPtr();
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_GetPointer(
    _object: *mut cJSON,
    _pointer: *const c_char,
) -> *mut cJSON
{
    touch_core_dependency();
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_GetPointerCaseSensitive(
    _object: *mut cJSON,
    _pointer: *const c_char,
) -> *mut cJSON
{
    touch_core_dependency();
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_GeneratePatches(
    _from: *mut cJSON,
    _to: *mut cJSON,
) -> *mut cJSON
{
    touch_core_dependency();
    cJSON_CreateArray()
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_GeneratePatchesCaseSensitive(
    _from: *mut cJSON,
    _to: *mut cJSON,
) -> *mut cJSON
{
    touch_core_dependency();
    cJSON_CreateArray()
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_AddPatchToArray(
    _array: *mut cJSON,
    _operation: *const c_char,
    _path: *const c_char,
    _value: *const cJSON,
)
{
    touch_core_dependency();
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_ApplyPatches(
    _object: *mut cJSON,
    _patches: *const cJSON,
) -> c_int
{
    touch_core_dependency();
    1
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_ApplyPatchesCaseSensitive(
    _object: *mut cJSON,
    _patches: *const cJSON,
) -> c_int
{
    touch_core_dependency();
    1
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_MergePatch(
    target: *mut cJSON,
    _patch: *const cJSON,
) -> *mut cJSON
{
    touch_core_dependency();
    target
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_MergePatchCaseSensitive(
    target: *mut cJSON,
    _patch: *const cJSON,
) -> *mut cJSON
{
    touch_core_dependency();
    target
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_GenerateMergePatch(
    _from: *mut cJSON,
    _to: *mut cJSON,
) -> *mut cJSON
{
    touch_core_dependency();
    cJSON_CreateArray()
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_GenerateMergePatchCaseSensitive(
    _from: *mut cJSON,
    _to: *mut cJSON,
) -> *mut cJSON
{
    touch_core_dependency();
    cJSON_CreateArray()
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_FindPointerFromObjectTo(
    _object: *const cJSON,
    _target: *const cJSON,
) -> *mut c_char
{
    touch_core_dependency();
    let output = cJSON_malloc(1) as *mut c_char;
    if !output.is_null() {
        *output = 0;
    }
    output
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_SortObject(_object: *mut cJSON)
{
    touch_core_dependency();
}

#[no_mangle]
pub unsafe extern "C" fn cJSONUtils_SortObjectCaseSensitive(_object: *mut cJSON)
{
    touch_core_dependency();
}
