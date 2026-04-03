use std::ffi::CStr;
use std::os::raw::c_char;
use std::ptr;
use std::slice;

use crate::abi::{
    cJSON, cJSON_Array, cJSON_False, cJSON_NULL, cJSON_Number, cJSON_Object, cJSON_True, cJSON_bool,
};
use crate::delete::delete_item;
use crate::error::{clear_parse_error, set_parse_error};
use crate::hooks::{current_hooks, new_item_with_hooks, InternalHooks};
use crate::number::{parse_number_token, set_number_fields, NumberParseResult};
use crate::string::parse_string;

const CJSON_NESTING_LIMIT: usize = 1000;
const MAX_NUMERIC_LITERAL_LENGTH: usize = 63;

pub(crate) struct ParseBuffer {
    pub(crate) content: *const u8,
    pub(crate) length: usize,
    pub(crate) offset: usize,
    pub(crate) depth: usize,
    pub(crate) hooks: InternalHooks,
}

impl ParseBuffer {
    pub(crate) fn can_read(&self, size: usize) -> bool {
        !self.content.is_null()
            && self
                .offset
                .checked_add(size)
                .is_some_and(|end| end <= self.length)
    }

    pub(crate) fn can_access_at_index(&self, index: usize) -> bool {
        !self.content.is_null()
            && self
                .offset
                .checked_add(index)
                .is_some_and(|position| position < self.length)
    }

    pub(crate) unsafe fn buffer_at_offset(&self) -> *const u8 {
        self.content.add(self.offset)
    }

    unsafe fn remaining_input(&self) -> &[u8] {
        slice::from_raw_parts(
            self.buffer_at_offset(),
            self.length.saturating_sub(self.offset),
        )
    }

    pub(crate) unsafe fn skip_whitespace(&mut self) {
        if self.content.is_null() || !self.can_access_at_index(0) {
            return;
        }

        while self.can_access_at_index(0) && *self.buffer_at_offset() <= 32 {
            self.offset += 1;
        }

        if self.offset == self.length {
            self.offset -= 1;
        }
    }

    pub(crate) unsafe fn skip_utf8_bom(&mut self) {
        if self.content.is_null() || self.offset != 0 || !self.can_access_at_index(4) {
            return;
        }

        if self.remaining_input().starts_with(b"\xEF\xBB\xBF") {
            self.offset += 3;
        }
    }
}

unsafe fn parse_number(item: *mut cJSON, input_buffer: &mut ParseBuffer) -> bool {
    if input_buffer.content.is_null() {
        return false;
    }

    let remaining = input_buffer.remaining_input();
    let mut candidate_length = 0usize;
    while matches!(
        remaining.get(candidate_length),
        Some(b'0'..=b'9' | b'+' | b'-' | b'e' | b'E' | b'.')
    ) {
        candidate_length += 1;
    }
    if candidate_length > MAX_NUMERIC_LITERAL_LENGTH {
        return false;
    }

    let (token_length, number) = match parse_number_token(remaining) {
        NumberParseResult::Success { length, number } => (length, number),
        NumberParseResult::Failure { error_offset } => {
            input_buffer.offset += error_offset;
            return false;
        }
    };

    set_number_fields(item, number);
    (*item).type_ = cJSON_Number;
    input_buffer.offset += token_length;

    true
}

unsafe fn parse_value(item: *mut cJSON, input_buffer: &mut ParseBuffer) -> bool {
    if input_buffer.content.is_null() {
        return false;
    }

    if input_buffer.can_read(4)
        && slice::from_raw_parts(input_buffer.buffer_at_offset(), 4) == b"null"
    {
        (*item).type_ = cJSON_NULL;
        input_buffer.offset += 4;
        return true;
    }

    if input_buffer.can_read(5)
        && slice::from_raw_parts(input_buffer.buffer_at_offset(), 5) == b"false"
    {
        (*item).type_ = cJSON_False;
        input_buffer.offset += 5;
        return true;
    }

    if input_buffer.can_read(4)
        && slice::from_raw_parts(input_buffer.buffer_at_offset(), 4) == b"true"
    {
        (*item).type_ = cJSON_True;
        (*item).valueint = 1;
        input_buffer.offset += 4;
        return true;
    }

    if input_buffer.can_access_at_index(0) && *input_buffer.buffer_at_offset() == b'"' {
        return parse_string(item, input_buffer);
    }

    if input_buffer.can_access_at_index(0)
        && matches!(*input_buffer.buffer_at_offset(), b'-' | b'0'..=b'9')
    {
        return parse_number(item, input_buffer);
    }

    if input_buffer.can_access_at_index(0) && *input_buffer.buffer_at_offset() == b'[' {
        return parse_array(item, input_buffer);
    }

    if input_buffer.can_access_at_index(0) && *input_buffer.buffer_at_offset() == b'{' {
        return parse_object(item, input_buffer);
    }

    false
}

unsafe fn parse_array(item: *mut cJSON, input_buffer: &mut ParseBuffer) -> bool {
    let mut head: *mut cJSON = ptr::null_mut();
    let mut current_item: *mut cJSON = ptr::null_mut();

    if input_buffer.depth >= CJSON_NESTING_LIMIT {
        return false;
    }
    input_buffer.depth += 1;

    if *input_buffer.buffer_at_offset() != b'[' {
        return false;
    }

    input_buffer.offset += 1;
    input_buffer.skip_whitespace();
    if input_buffer.can_access_at_index(0) && *input_buffer.buffer_at_offset() == b']' {
        input_buffer.depth -= 1;
        (*item).type_ = cJSON_Array;
        (*item).child = ptr::null_mut();
        input_buffer.offset += 1;
        return true;
    }

    if !input_buffer.can_access_at_index(0) {
        input_buffer.offset -= 1;
        return false;
    }

    input_buffer.offset -= 1;
    loop {
        let new_item = new_item_with_hooks(&input_buffer.hooks);
        if new_item.is_null() {
            if !head.is_null() {
                delete_item(head);
            }
            return false;
        }

        if head.is_null() {
            head = new_item;
            current_item = new_item;
        } else {
            (*current_item).next = new_item;
            (*new_item).prev = current_item;
            current_item = new_item;
        }

        input_buffer.offset += 1;
        input_buffer.skip_whitespace();
        if !parse_value(current_item, input_buffer) {
            delete_item(head);
            return false;
        }
        input_buffer.skip_whitespace();

        if !(input_buffer.can_access_at_index(0) && *input_buffer.buffer_at_offset() == b',') {
            break;
        }
    }

    if !input_buffer.can_access_at_index(0) || *input_buffer.buffer_at_offset() != b']' {
        if !head.is_null() {
            delete_item(head);
        }
        return false;
    }

    input_buffer.depth -= 1;
    if !head.is_null() {
        (*head).prev = current_item;
    }

    (*item).type_ = cJSON_Array;
    (*item).child = head;
    input_buffer.offset += 1;

    true
}

unsafe fn parse_object(item: *mut cJSON, input_buffer: &mut ParseBuffer) -> bool {
    let mut head: *mut cJSON = ptr::null_mut();
    let mut current_item: *mut cJSON = ptr::null_mut();

    if input_buffer.depth >= CJSON_NESTING_LIMIT {
        return false;
    }
    input_buffer.depth += 1;

    if !input_buffer.can_access_at_index(0) || *input_buffer.buffer_at_offset() != b'{' {
        return false;
    }

    input_buffer.offset += 1;
    input_buffer.skip_whitespace();
    if input_buffer.can_access_at_index(0) && *input_buffer.buffer_at_offset() == b'}' {
        input_buffer.depth -= 1;
        (*item).type_ = cJSON_Object;
        (*item).child = ptr::null_mut();
        input_buffer.offset += 1;
        return true;
    }

    if !input_buffer.can_access_at_index(0) {
        input_buffer.offset -= 1;
        return false;
    }

    input_buffer.offset -= 1;
    loop {
        let new_item = new_item_with_hooks(&input_buffer.hooks);
        if new_item.is_null() {
            if !head.is_null() {
                delete_item(head);
            }
            return false;
        }

        if head.is_null() {
            head = new_item;
            current_item = new_item;
        } else {
            (*current_item).next = new_item;
            (*new_item).prev = current_item;
            current_item = new_item;
        }

        input_buffer.offset += 1;
        input_buffer.skip_whitespace();
        if !parse_string(current_item, input_buffer) {
            delete_item(head);
            return false;
        }
        input_buffer.skip_whitespace();

        (*current_item).string = (*current_item).valuestring;
        (*current_item).valuestring = ptr::null_mut();

        if !input_buffer.can_access_at_index(0) || *input_buffer.buffer_at_offset() != b':' {
            delete_item(head);
            return false;
        }

        input_buffer.offset += 1;
        input_buffer.skip_whitespace();
        if !parse_value(current_item, input_buffer) {
            delete_item(head);
            return false;
        }
        input_buffer.skip_whitespace();

        if !(input_buffer.can_access_at_index(0) && *input_buffer.buffer_at_offset() == b',') {
            break;
        }
    }

    if !input_buffer.can_access_at_index(0) || *input_buffer.buffer_at_offset() != b'}' {
        delete_item(head);
        return false;
    }

    input_buffer.depth -= 1;
    if !head.is_null() {
        (*head).prev = current_item;
    }

    (*item).type_ = cJSON_Object;
    (*item).child = head;
    input_buffer.offset += 1;

    true
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Parse(value: *const c_char) -> *mut cJSON {
    cJSON_ParseWithOpts(value, ptr::null_mut(), 0)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ParseWithLength(
    value: *const c_char,
    buffer_length: usize,
) -> *mut cJSON {
    cJSON_ParseWithLengthOpts(value, buffer_length, ptr::null_mut(), 0)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ParseWithOpts(
    value: *const c_char,
    return_parse_end: *mut *const c_char,
    require_null_terminated: cJSON_bool,
) -> *mut cJSON {
    if value.is_null() {
        return ptr::null_mut();
    }

    let buffer_length = CStr::from_ptr(value).to_bytes().len() + 1;
    cJSON_ParseWithLengthOpts(
        value,
        buffer_length,
        return_parse_end,
        require_null_terminated,
    )
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ParseWithLengthOpts(
    value: *const c_char,
    buffer_length: usize,
    return_parse_end: *mut *const c_char,
    require_null_terminated: cJSON_bool,
) -> *mut cJSON {
    let hooks = current_hooks();
    let mut buffer = ParseBuffer {
        content: value as *const u8,
        length: buffer_length,
        offset: 0,
        depth: 0,
        hooks,
    };
    let mut item: *mut cJSON;

    clear_parse_error();

    if value.is_null() || buffer_length == 0 {
        return ptr::null_mut();
    }

    item = new_item_with_hooks(&buffer.hooks);
    if item.is_null() {
        let error_pointer = value;
        if !return_parse_end.is_null() {
            *return_parse_end = error_pointer;
        }
        set_parse_error(error_pointer);
        return ptr::null_mut();
    }

    buffer.skip_utf8_bom();
    buffer.skip_whitespace();
    if !parse_value(item, &mut buffer) {
        delete_item(item);
        item = ptr::null_mut();
    } else if require_null_terminated != 0 {
        buffer.skip_whitespace();
        if buffer.offset >= buffer.length || *buffer.buffer_at_offset() != 0 {
            delete_item(item);
            item = ptr::null_mut();
        }
    }

    if !item.is_null() {
        if !return_parse_end.is_null() {
            *return_parse_end = buffer.buffer_at_offset() as *const c_char;
        }
        return item;
    }

    let position = if buffer.offset < buffer.length {
        buffer.offset
    } else if buffer.length > 0 {
        buffer.length - 1
    } else {
        0
    };
    let error_pointer = value.add(position);
    if !return_parse_end.is_null() {
        *return_parse_end = error_pointer;
    }
    set_parse_error(error_pointer);

    ptr::null_mut()
}
