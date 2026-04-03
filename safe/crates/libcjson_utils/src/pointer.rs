use std::ffi::CStr;
use std::os::raw::c_char;
use std::ptr;

use crate::{
    bytes_from_c_string, cJSON, cJSON_DetachItemFromObject,
    cJSON_DetachItemFromObjectCaseSensitive, compare_bytes, duplicate_bytes, is_array, is_object,
};

pub(crate) fn encode_string_as_pointer(destination: &mut Vec<u8>, source: &[u8]) {
    let mut index = 0usize;

    while index < source.len() {
        match source[index] {
            b'/' => destination.extend_from_slice(b"~1"),
            b'~' => destination.extend_from_slice(b"~0"),
            byte => destination.push(byte),
        }
        index += 1;
    }
}

pub(crate) fn decode_pointer_token(token: &[u8]) -> Option<Vec<u8>> {
    let mut output = Vec::with_capacity(token.len());
    let mut index = 0usize;

    while index < token.len() {
        if token[index] == b'~' {
            if index + 1 >= token.len() {
                return None;
            }

            match token[index + 1] {
                b'0' => output.push(b'~'),
                b'1' => output.push(b'/'),
                _ => return None,
            }

            index += 2;
            continue;
        }

        output.push(token[index]);
        index += 1;
    }

    Some(output)
}

pub(crate) fn decode_array_index_from_pointer(token: &[u8]) -> Option<usize> {
    let mut parsed_index = 0usize;
    let mut position = 0usize;

    if token.is_empty() {
        return None;
    }

    if token[0] == b'0' {
        return if token.len() == 1 { Some(0) } else { None };
    }

    while position < token.len() {
        let byte = token[position];
        if !byte.is_ascii_digit() {
            return None;
        }

        parsed_index = parsed_index.checked_mul(10)?;
        parsed_index = parsed_index.checked_add((byte - b'0') as usize)?;
        position += 1;
    }

    Some(parsed_index)
}

pub(crate) unsafe fn get_array_item(array: *const cJSON, mut item: usize) -> *mut cJSON {
    let mut child = if array.is_null() {
        ptr::null_mut()
    } else {
        (*array).child
    };

    while !child.is_null() && item > 0 {
        item -= 1;
        child = (*child).next;
    }

    child
}

unsafe fn find_object_child_by_name(
    object: *mut cJSON,
    name: &[u8],
    case_sensitive: bool,
) -> *mut cJSON {
    let mut current_element = if object.is_null() {
        ptr::null_mut()
    } else {
        (*object).child
    };

    while !current_element.is_null() {
        if !(*current_element).string.is_null()
            && compare_bytes(
                bytes_from_c_string((*current_element).string),
                name,
                case_sensitive,
            ) == 0
        {
            return current_element;
        }

        current_element = (*current_element).next;
    }

    ptr::null_mut()
}

pub(crate) unsafe fn get_item_from_pointer_bytes(
    object: *mut cJSON,
    pointer: &[u8],
    case_sensitive: bool,
) -> *mut cJSON {
    let mut current_element = object;

    if object.is_null() {
        return ptr::null_mut();
    }

    if pointer.is_empty() {
        return current_element;
    }

    if pointer[0] != b'/' {
        return ptr::null_mut();
    }

    for token in pointer[1..].split(|byte| *byte == b'/') {
        if current_element.is_null() {
            return ptr::null_mut();
        }

        if is_array(current_element) {
            let index = match decode_array_index_from_pointer(token) {
                Some(index) => index,
                None => return ptr::null_mut(),
            };

            current_element = get_array_item(current_element, index);
        } else if is_object(current_element) {
            let decoded = match decode_pointer_token(token) {
                Some(decoded) => decoded,
                None => return ptr::null_mut(),
            };

            current_element = find_object_child_by_name(current_element, &decoded, case_sensitive);
        } else {
            return ptr::null_mut();
        }
    }

    current_element
}

pub(crate) unsafe fn get_item_from_pointer(
    object: *mut cJSON,
    pointer: *const c_char,
    case_sensitive: bool,
) -> *mut cJSON {
    if pointer.is_null() {
        return ptr::null_mut();
    }

    get_item_from_pointer_bytes(object, CStr::from_ptr(pointer).to_bytes(), case_sensitive)
}

fn split_parent_child(path: &[u8]) -> Option<(&[u8], &[u8])> {
    let slash_index = path.iter().rposition(|byte| *byte == b'/')?;
    Some((&path[..slash_index], &path[(slash_index + 1)..]))
}

pub(crate) unsafe fn detach_item_from_array(array: *mut cJSON, mut which: usize) -> *mut cJSON {
    let mut current = if array.is_null() {
        ptr::null_mut()
    } else {
        (*array).child
    };

    while !current.is_null() && which > 0 {
        current = (*current).next;
        which -= 1;
    }

    if current.is_null() {
        return ptr::null_mut();
    }

    if current != (*array).child {
        (*(*current).prev).next = (*current).next;
    }
    if !(*current).next.is_null() {
        (*(*current).next).prev = (*current).prev;
    }
    if current == (*array).child {
        (*array).child = (*current).next;
    } else if (*current).next.is_null() {
        (*(*array).child).prev = (*current).prev;
    }

    (*current).prev = ptr::null_mut();
    (*current).next = ptr::null_mut();

    current
}

pub(crate) unsafe fn detach_path_bytes(
    object: *mut cJSON,
    path: &[u8],
    case_sensitive: bool,
) -> *mut cJSON {
    let (parent_pointer, child_pointer) = match split_parent_child(path) {
        Some(parts) => parts,
        None => return ptr::null_mut(),
    };
    let parent = get_item_from_pointer_bytes(object, parent_pointer, case_sensitive);
    let decoded_child = match decode_pointer_token(child_pointer) {
        Some(decoded_child) => decoded_child,
        None => return ptr::null_mut(),
    };

    if is_array(parent) {
        let index = match decode_array_index_from_pointer(&decoded_child) {
            Some(index) => index,
            None => return ptr::null_mut(),
        };

        return detach_item_from_array(parent, index);
    }

    if is_object(parent) {
        let child_name = crate::nul_terminated(&decoded_child);
        if case_sensitive {
            return cJSON_DetachItemFromObjectCaseSensitive(
                parent,
                child_name.as_ptr() as *const c_char,
            );
        }

        return cJSON_DetachItemFromObject(parent, child_name.as_ptr() as *const c_char);
    }

    ptr::null_mut()
}

unsafe fn find_pointer_from_object_to_bytes(
    object: *const cJSON,
    target: *const cJSON,
) -> Option<Vec<u8>> {
    let mut child_index = 0usize;
    let mut current_child = if object.is_null() {
        ptr::null_mut()
    } else {
        (*object).child
    };

    if object.is_null() || target.is_null() {
        return None;
    }

    if object == target {
        return Some(Vec::new());
    }

    while !current_child.is_null() {
        if let Some(target_pointer) = find_pointer_from_object_to_bytes(current_child, target) {
            if is_array(object) {
                let index_string = child_index.to_string();
                let mut full_pointer =
                    Vec::with_capacity(1 + index_string.len() + target_pointer.len());

                full_pointer.push(b'/');
                full_pointer.extend_from_slice(index_string.as_bytes());
                full_pointer.extend_from_slice(&target_pointer);

                return Some(full_pointer);
            }

            if is_object(object) {
                if (*current_child).string.is_null() {
                    return None;
                }

                let mut full_pointer = Vec::with_capacity(1 + target_pointer.len());
                full_pointer.push(b'/');
                encode_string_as_pointer(
                    &mut full_pointer,
                    bytes_from_c_string((*current_child).string),
                );
                full_pointer.extend_from_slice(&target_pointer);

                return Some(full_pointer);
            }

            return None;
        }

        current_child = (*current_child).next;
        child_index += 1;
    }

    None
}

pub(crate) unsafe fn find_pointer_from_object_to(
    object: *const cJSON,
    target: *const cJSON,
) -> *mut c_char {
    match find_pointer_from_object_to_bytes(object, target) {
        Some(pointer) => duplicate_bytes(&pointer),
        None => ptr::null_mut(),
    }
}
