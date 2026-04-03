use std::os::raw::{c_char, c_int, c_void};
use std::ptr;

use crate::pointer::{
    decode_array_index_from_pointer, decode_pointer_token, detach_path_bytes,
    encode_string_as_pointer, get_item_from_pointer_bytes,
};
use crate::sort::sort_object;
use crate::{
    bytes_from_c_string, cJSON, cJSON_AddItemToArray, cJSON_AddItemToObject, cJSON_Array,
    cJSON_CreateArray, cJSON_CreateObject, cJSON_CreateString, cJSON_Delete,
    cJSON_DeleteItemFromObject, cJSON_DeleteItemFromObjectCaseSensitive, cJSON_Duplicate,
    cJSON_Invalid, cJSON_IsReference, cJSON_Number, cJSON_Object, cJSON_String,
    cJSON_StringIsConst, cJSON_free, compare_double, compare_strings, get_object_item, is_array,
    is_object, is_string, item_type, nul_terminated,
};

const OP_KEY: &[u8] = b"op\0";
const PATH_KEY: &[u8] = b"path\0";
const VALUE_KEY: &[u8] = b"value\0";
const FROM_KEY: &[u8] = b"from\0";

const ADD_OP: &[u8] = b"add";
const REMOVE_OP: &[u8] = b"remove";
const REPLACE_OP: &[u8] = b"replace";
const MOVE_OP: &[u8] = b"move";
const COPY_OP: &[u8] = b"copy";
const TEST_OP: &[u8] = b"test";

#[derive(Clone, Copy, PartialEq, Eq)]
enum PatchOperation {
    Invalid,
    Add,
    Remove,
    Replace,
    Move,
    Copy,
    Test,
}

unsafe fn get_patch_member(patch: *const cJSON, key: &[u8], case_sensitive: bool) -> *mut cJSON {
    get_object_item(patch, key.as_ptr() as *const c_char, case_sensitive)
}

unsafe fn decode_patch_operation(patch: *const cJSON, case_sensitive: bool) -> PatchOperation {
    let operation = get_patch_member(patch, OP_KEY, case_sensitive);
    let operation_name = if is_string(operation) && !(*operation).valuestring.is_null() {
        bytes_from_c_string((*operation).valuestring)
    } else {
        return PatchOperation::Invalid;
    };

    if operation_name == ADD_OP {
        PatchOperation::Add
    } else if operation_name == REMOVE_OP {
        PatchOperation::Remove
    } else if operation_name == REPLACE_OP {
        PatchOperation::Replace
    } else if operation_name == MOVE_OP {
        PatchOperation::Move
    } else if operation_name == COPY_OP {
        PatchOperation::Copy
    } else if operation_name == TEST_OP {
        PatchOperation::Test
    } else {
        PatchOperation::Invalid
    }
}

pub(crate) unsafe fn compare_json(
    mut left: *mut cJSON,
    mut right: *mut cJSON,
    case_sensitive: bool,
) -> bool {
    if left.is_null() || right.is_null() || item_type(left) != item_type(right) {
        return false;
    }

    match item_type(left) {
        cJSON_Number => {
            (*left).valueint == (*right).valueint
                && compare_double((*left).valuedouble, (*right).valuedouble)
        }
        cJSON_String => {
            if (*left).valuestring.is_null() || (*right).valuestring.is_null() {
                return false;
            }

            bytes_from_c_string((*left).valuestring) == bytes_from_c_string((*right).valuestring)
        }
        cJSON_Array => {
            left = (*left).child;
            right = (*right).child;

            while !left.is_null() && !right.is_null() {
                if !compare_json(left, right, case_sensitive) {
                    return false;
                }

                left = (*left).next;
                right = (*right).next;
            }

            left.is_null() && right.is_null()
        }
        cJSON_Object => {
            sort_object(left, case_sensitive);
            sort_object(right, case_sensitive);

            left = (*left).child;
            right = (*right).child;

            while !left.is_null() && !right.is_null() {
                if compare_strings((*left).string, (*right).string, case_sensitive) != 0 {
                    return false;
                }
                if !compare_json(left, right, case_sensitive) {
                    return false;
                }

                left = (*left).next;
                right = (*right).next;
            }

            left.is_null() && right.is_null()
        }
        _ => true,
    }
}

unsafe fn insert_item_in_array(array: *mut cJSON, mut which: usize, newitem: *mut cJSON) -> bool {
    let mut child = if array.is_null() {
        ptr::null_mut()
    } else {
        (*array).child
    };

    while !child.is_null() && which > 0 {
        child = (*child).next;
        which -= 1;
    }

    if which > 0 {
        return false;
    }

    if child.is_null() {
        return cJSON_AddItemToArray(array, newitem) != 0;
    }

    (*newitem).next = child;
    (*newitem).prev = (*child).prev;
    (*child).prev = newitem;

    if child == (*array).child {
        (*array).child = newitem;
    } else {
        (*(*newitem).prev).next = newitem;
    }

    true
}

unsafe fn free_item_storage(item: *mut cJSON) {
    if item.is_null() {
        return;
    }

    if ((*item).type_ & cJSON_StringIsConst) == 0 && !(*item).string.is_null() {
        cJSON_free((*item).string as *mut c_void);
    }
    if ((*item).type_ & cJSON_IsReference) == 0 && !(*item).valuestring.is_null() {
        cJSON_free((*item).valuestring as *mut c_void);
    }
    if ((*item).type_ & cJSON_IsReference) == 0 && !(*item).child.is_null() {
        cJSON_Delete((*item).child);
    }
}

unsafe fn overwrite_item(root: *mut cJSON, replacement: cJSON) {
    if root.is_null() {
        return;
    }

    free_item_storage(root);
    ptr::write(root, replacement);
}

fn split_parent_child(path: &[u8]) -> Option<(&[u8], &[u8])> {
    let slash_index = path.iter().rposition(|byte| *byte == b'/')?;
    Some((&path[..slash_index], &path[(slash_index + 1)..]))
}

unsafe fn apply_patch(object: *mut cJSON, patch: *const cJSON, case_sensitive: bool) -> c_int {
    let path = get_patch_member(patch, PATH_KEY, case_sensitive);
    let path_bytes;
    let opcode;
    let mut value: *mut cJSON;
    let mut status = 0;

    if object.is_null() {
        return 9;
    }

    if !is_string(path) || (*path).valuestring.is_null() {
        return 2;
    }

    path_bytes = bytes_from_c_string((*path).valuestring);
    opcode = decode_patch_operation(patch, case_sensitive);
    if opcode == PatchOperation::Invalid {
        return 3;
    }

    if opcode == PatchOperation::Test {
        return if compare_json(
            get_item_from_pointer_bytes(object, path_bytes, case_sensitive),
            get_patch_member(patch, VALUE_KEY, case_sensitive),
            case_sensitive,
        ) {
            0
        } else {
            1
        };
    }

    if path_bytes.is_empty() {
        if opcode == PatchOperation::Remove {
            let invalid = cJSON {
                next: ptr::null_mut(),
                prev: ptr::null_mut(),
                child: ptr::null_mut(),
                type_: cJSON_Invalid,
                valuestring: ptr::null_mut(),
                valueint: 0,
                valuedouble: 0.0,
                string: ptr::null_mut(),
            };

            overwrite_item(object, invalid);
            return 0;
        }

        if opcode == PatchOperation::Replace || opcode == PatchOperation::Add {
            let replacement = get_patch_member(patch, VALUE_KEY, case_sensitive);
            let duplicated;
            let replacement_item;

            if replacement.is_null() {
                return 7;
            }

            duplicated = cJSON_Duplicate(replacement, 1);
            if duplicated.is_null() {
                return 8;
            }

            replacement_item = ptr::read(duplicated);
            overwrite_item(object, replacement_item);
            cJSON_free(duplicated as *mut c_void);

            if !(*object).string.is_null() {
                if ((*object).type_ & cJSON_StringIsConst) == 0 {
                    cJSON_free((*object).string as *mut c_void);
                }
                (*object).string = ptr::null_mut();
                (*object).type_ &= !cJSON_StringIsConst;
            }

            return 0;
        }
    }

    if opcode == PatchOperation::Remove || opcode == PatchOperation::Replace {
        let old_item = detach_path_bytes(object, path_bytes, case_sensitive);
        if old_item.is_null() {
            return 13;
        }

        cJSON_Delete(old_item);
        if opcode == PatchOperation::Remove {
            return 0;
        }
    }

    if opcode == PatchOperation::Move || opcode == PatchOperation::Copy {
        let from = get_patch_member(patch, FROM_KEY, case_sensitive);
        let from_bytes = if !from.is_null() && !(*from).valuestring.is_null() {
            Some(bytes_from_c_string((*from).valuestring))
        } else {
            None
        };

        if from.is_null() {
            return 4;
        }

        value = match (opcode, from_bytes) {
            (PatchOperation::Move, Some(pointer)) => {
                detach_path_bytes(object, pointer, case_sensitive)
            }
            (PatchOperation::Copy, Some(pointer)) => {
                get_item_from_pointer_bytes(object, pointer, case_sensitive)
            }
            _ => ptr::null_mut(),
        };

        if value.is_null() {
            return 5;
        }

        if opcode == PatchOperation::Copy {
            value = cJSON_Duplicate(value, 1);
        }

        if value.is_null() {
            return 6;
        }
    } else {
        value = get_patch_member(patch, VALUE_KEY, case_sensitive);
        if value.is_null() {
            return 7;
        }

        value = cJSON_Duplicate(value, 1);
        if value.is_null() {
            return 8;
        }
    }

    match split_parent_child(path_bytes) {
        Some((parent_pointer, child_pointer)) => {
            let parent = get_item_from_pointer_bytes(object, parent_pointer, case_sensitive);
            let decoded_child = match decode_pointer_token(child_pointer) {
                Some(decoded_child) => decoded_child,
                None => {
                    status = 9;
                    goto_cleanup(&mut value);
                    return status;
                }
            };

            if parent.is_null() {
                status = 9;
            } else if is_array(parent) {
                if decoded_child == b"-" {
                    cJSON_AddItemToArray(parent, value);
                    value = ptr::null_mut();
                } else {
                    let index = match decode_array_index_from_pointer(&decoded_child) {
                        Some(index) => index,
                        None => {
                            status = 11;
                            goto_cleanup(&mut value);
                            return status;
                        }
                    };

                    if !insert_item_in_array(parent, index, value) {
                        status = 10;
                    } else {
                        value = ptr::null_mut();
                    }
                }
            } else if is_object(parent) {
                let child_name = nul_terminated(&decoded_child);
                if case_sensitive {
                    cJSON_DeleteItemFromObjectCaseSensitive(
                        parent,
                        child_name.as_ptr() as *const c_char,
                    );
                } else {
                    cJSON_DeleteItemFromObject(parent, child_name.as_ptr() as *const c_char);
                }

                cJSON_AddItemToObject(parent, child_name.as_ptr() as *const c_char, value);
                value = ptr::null_mut();
            } else {
                status = 9;
            }
        }
        None => status = 9,
    }

    goto_cleanup(&mut value);
    status
}

unsafe fn goto_cleanup(value: &mut *mut cJSON) {
    if !(*value).is_null() {
        cJSON_Delete(*value);
        *value = ptr::null_mut();
    }
}

fn compose_patch(
    patches: *mut cJSON,
    operation: &[u8],
    path: &[u8],
    suffix: Option<&[u8]>,
    value: *const cJSON,
) {
    unsafe {
        let patch = cJSON_CreateObject();
        let operation_c = nul_terminated(operation);
        let mut full_path = Vec::new();

        if patches.is_null() {
            return;
        }

        if patch.is_null() {
            return;
        }

        cJSON_AddItemToObject(
            patch,
            OP_KEY.as_ptr() as *const c_char,
            cJSON_CreateString(operation_c.as_ptr() as *const c_char),
        );

        if let Some(suffix) = suffix {
            full_path.reserve(path.len() + suffix.len() + 1);
            full_path.extend_from_slice(path);
            full_path.push(b'/');
            encode_string_as_pointer(&mut full_path, suffix);
        } else {
            full_path.extend_from_slice(path);
        }

        {
            let full_path_c = nul_terminated(&full_path);
            cJSON_AddItemToObject(
                patch,
                PATH_KEY.as_ptr() as *const c_char,
                cJSON_CreateString(full_path_c.as_ptr() as *const c_char),
            );
        }

        if !value.is_null() {
            cJSON_AddItemToObject(
                patch,
                VALUE_KEY.as_ptr() as *const c_char,
                cJSON_Duplicate(value, 1),
            );
        }

        cJSON_AddItemToArray(patches, patch);
    }
}

pub(crate) unsafe fn add_patch_to_array(
    array: *mut cJSON,
    operation: *const c_char,
    path: *const c_char,
    value: *const cJSON,
) {
    if array.is_null() || operation.is_null() || path.is_null() {
        return;
    }

    compose_patch(
        array,
        bytes_from_c_string(operation),
        bytes_from_c_string(path),
        None,
        value,
    );
}

unsafe fn create_patches(
    patches: *mut cJSON,
    path: &[u8],
    from: *mut cJSON,
    to: *mut cJSON,
    case_sensitive: bool,
) {
    if from.is_null() || to.is_null() {
        return;
    }

    if item_type(from) != item_type(to) {
        compose_patch(patches, REPLACE_OP, path, None, to);
        return;
    }

    match item_type(from) {
        cJSON_Number => {
            if (*from).valueint != (*to).valueint
                || !compare_double((*from).valuedouble, (*to).valuedouble)
            {
                compose_patch(patches, REPLACE_OP, path, None, to);
            }
        }
        cJSON_String => {
            if (*from).valuestring.is_null()
                || (*to).valuestring.is_null()
                || bytes_from_c_string((*from).valuestring)
                    != bytes_from_c_string((*to).valuestring)
            {
                compose_patch(patches, REPLACE_OP, path, None, to);
            }
        }
        cJSON_Array => {
            let mut index = 0usize;
            let mut from_child = (*from).child;
            let mut to_child = (*to).child;

            while !from_child.is_null() && !to_child.is_null() {
                let mut new_path = Vec::with_capacity(path.len() + 24);
                let index_string = index.to_string();

                new_path.extend_from_slice(path);
                new_path.push(b'/');
                new_path.extend_from_slice(index_string.as_bytes());

                create_patches(patches, &new_path, from_child, to_child, case_sensitive);

                from_child = (*from_child).next;
                to_child = (*to_child).next;
                index += 1;
            }

            while !from_child.is_null() {
                let index_string = index.to_string();
                compose_patch(
                    patches,
                    REMOVE_OP,
                    path,
                    Some(index_string.as_bytes()),
                    ptr::null(),
                );
                from_child = (*from_child).next;
            }

            while !to_child.is_null() {
                compose_patch(patches, ADD_OP, path, Some(b"-"), to_child);
                to_child = (*to_child).next;
            }
        }
        cJSON_Object => {
            let mut from_child;
            let mut to_child;

            sort_object(from, case_sensitive);
            sort_object(to, case_sensitive);

            from_child = (*from).child;
            to_child = (*to).child;

            while !from_child.is_null() || !to_child.is_null() {
                let diff = if from_child.is_null() {
                    1
                } else if to_child.is_null() {
                    -1
                } else {
                    compare_strings((*from_child).string, (*to_child).string, case_sensitive)
                };

                if diff == 0 {
                    let mut new_path = Vec::with_capacity(path.len() + 1);
                    if (*from_child).string.is_null() {
                        return;
                    }

                    new_path.extend_from_slice(path);
                    new_path.push(b'/');
                    encode_string_as_pointer(
                        &mut new_path,
                        bytes_from_c_string((*from_child).string),
                    );

                    create_patches(patches, &new_path, from_child, to_child, case_sensitive);

                    from_child = (*from_child).next;
                    to_child = (*to_child).next;
                } else if diff < 0 {
                    if (*from_child).string.is_null() {
                        return;
                    }

                    compose_patch(
                        patches,
                        REMOVE_OP,
                        path,
                        Some(bytes_from_c_string((*from_child).string)),
                        ptr::null(),
                    );
                    from_child = (*from_child).next;
                } else {
                    if (*to_child).string.is_null() {
                        return;
                    }

                    compose_patch(
                        patches,
                        ADD_OP,
                        path,
                        Some(bytes_from_c_string((*to_child).string)),
                        to_child,
                    );
                    to_child = (*to_child).next;
                }
            }
        }
        _ => {}
    }
}

pub(crate) unsafe fn generate_patches(
    from: *mut cJSON,
    to: *mut cJSON,
    case_sensitive: bool,
) -> *mut cJSON {
    let patches;

    if from.is_null() || to.is_null() {
        return ptr::null_mut();
    }

    patches = cJSON_CreateArray();
    if patches.is_null() {
        return ptr::null_mut();
    }

    create_patches(patches, b"", from, to, case_sensitive);

    patches
}

pub(crate) unsafe fn apply_patches(
    object: *mut cJSON,
    patches: *const cJSON,
    case_sensitive: bool,
) -> c_int {
    let mut current_patch;

    if !is_array(patches) {
        return 1;
    }

    current_patch = (*patches).child;
    while !current_patch.is_null() {
        let status = apply_patch(object, current_patch, case_sensitive);
        if status != 0 {
            return status;
        }

        current_patch = (*current_patch).next;
    }

    0
}
