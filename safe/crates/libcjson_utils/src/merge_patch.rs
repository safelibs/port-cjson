use std::ptr;

use crate::patch::compare_json;
use crate::sort::sort_object;
use crate::{
    cJSON, cJSON_AddItemToObject, cJSON_CreateNull, cJSON_CreateObject, cJSON_Delete,
    cJSON_DeleteItemFromObject, cJSON_DeleteItemFromObjectCaseSensitive,
    cJSON_DetachItemFromObject, cJSON_DetachItemFromObjectCaseSensitive, cJSON_Duplicate,
    compare_strings, is_null, is_object,
};

pub(crate) unsafe fn merge_patch(
    mut target: *mut cJSON,
    patch: *const cJSON,
    case_sensitive: bool,
) -> *mut cJSON {
    let mut patch_child;

    if !is_object(patch) {
        cJSON_Delete(target);
        return cJSON_Duplicate(patch, 1);
    }

    if !is_object(target) {
        cJSON_Delete(target);
        target = cJSON_CreateObject();
    }

    if target.is_null() {
        return ptr::null_mut();
    }

    patch_child = (*patch).child;
    while !patch_child.is_null() {
        if is_null(patch_child) {
            if case_sensitive {
                cJSON_DeleteItemFromObjectCaseSensitive(target, (*patch_child).string);
            } else {
                cJSON_DeleteItemFromObject(target, (*patch_child).string);
            }
        } else {
            let replace_me = if case_sensitive {
                cJSON_DetachItemFromObjectCaseSensitive(target, (*patch_child).string)
            } else {
                cJSON_DetachItemFromObject(target, (*patch_child).string)
            };
            let replacement = merge_patch(replace_me, patch_child, case_sensitive);

            if replacement.is_null() {
                cJSON_Delete(target);
                return ptr::null_mut();
            }

            cJSON_AddItemToObject(target, (*patch_child).string, replacement);
        }

        patch_child = (*patch_child).next;
    }

    target
}

pub(crate) unsafe fn generate_merge_patch(
    from: *mut cJSON,
    to: *mut cJSON,
    case_sensitive: bool,
) -> *mut cJSON {
    let mut from_child;
    let mut to_child;

    if to.is_null() {
        return cJSON_CreateNull();
    }

    if !is_object(to) || !is_object(from) {
        return cJSON_Duplicate(to, 1);
    }

    sort_object(from, case_sensitive);
    sort_object(to, case_sensitive);

    let patch = cJSON_CreateObject();
    if patch.is_null() {
        return ptr::null_mut();
    }

    from_child = (*from).child;
    to_child = (*to).child;
    while !from_child.is_null() || !to_child.is_null() {
        let diff = if !from_child.is_null() {
            if !to_child.is_null() {
                compare_strings((*from_child).string, (*to_child).string, case_sensitive)
            } else {
                -1
            }
        } else {
            1
        };

        if diff < 0 {
            cJSON_AddItemToObject(patch, (*from_child).string, cJSON_CreateNull());
            from_child = (*from_child).next;
        } else if diff > 0 {
            cJSON_AddItemToObject(patch, (*to_child).string, cJSON_Duplicate(to_child, 1));
            to_child = (*to_child).next;
        } else {
            if !compare_json(from_child, to_child, case_sensitive) {
                cJSON_AddItemToObject(
                    patch,
                    (*to_child).string,
                    generate_merge_patch(from_child, to_child, case_sensitive),
                );
            }

            from_child = (*from_child).next;
            to_child = (*to_child).next;
        }
    }

    if (*patch).child.is_null() {
        cJSON_Delete(patch);
        return ptr::null_mut();
    }

    patch
}
