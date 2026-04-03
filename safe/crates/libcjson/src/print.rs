use std::cmp::min;
use std::ffi::CStr;
use std::os::raw::{c_char, c_int};
use std::ptr;

use crate::abi::{
    cJSON, cJSON_Array, cJSON_False, cJSON_NULL, cJSON_Number, cJSON_Object, cJSON_Raw,
    cJSON_String, cJSON_True, cJSON_bool,
};
use crate::hooks::{current_hooks, deallocate_with_hooks, InternalHooks};
use crate::number::print_number_bytes;
use crate::string::{print_string, print_string_ptr};

pub(crate) struct PrintBuffer {
    pub(crate) buffer: *mut u8,
    pub(crate) length: usize,
    pub(crate) offset: usize,
    pub(crate) depth: usize,
    pub(crate) noalloc: bool,
    pub(crate) format: bool,
    pub(crate) hooks: InternalHooks,
}

pub(crate) unsafe fn ensure(buffer: &mut PrintBuffer, needed: usize) -> *mut u8 {
    if buffer.buffer.is_null() {
        return ptr::null_mut();
    }

    if buffer.length > 0 && buffer.offset >= buffer.length {
        return ptr::null_mut();
    }

    if needed > c_int::MAX as usize {
        return ptr::null_mut();
    }

    let needed = needed + buffer.offset + 1;
    if needed <= buffer.length {
        return buffer.buffer.add(buffer.offset);
    }

    if buffer.noalloc {
        return ptr::null_mut();
    }

    let newsize = if needed > (c_int::MAX as usize / 2) {
        if needed <= c_int::MAX as usize {
            c_int::MAX as usize
        } else {
            return ptr::null_mut();
        }
    } else {
        needed * 2
    };

    let newbuffer = if let Some(reallocate) = buffer.hooks.reallocate {
        let reallocated = reallocate(buffer.buffer.cast(), newsize) as *mut u8;
        if reallocated.is_null() {
            deallocate_with_hooks(&buffer.hooks, buffer.buffer.cast());
            buffer.length = 0;
            buffer.buffer = ptr::null_mut();
            return ptr::null_mut();
        }
        reallocated
    } else {
        let allocated = (buffer.hooks.allocate)(newsize) as *mut u8;
        if allocated.is_null() {
            deallocate_with_hooks(&buffer.hooks, buffer.buffer.cast());
            buffer.length = 0;
            buffer.buffer = ptr::null_mut();
            return ptr::null_mut();
        }

        ptr::copy_nonoverlapping(buffer.buffer, allocated, buffer.offset + 1);
        deallocate_with_hooks(&buffer.hooks, buffer.buffer.cast());
        allocated
    };

    buffer.length = newsize;
    buffer.buffer = newbuffer;

    newbuffer.add(buffer.offset)
}

pub(crate) unsafe fn update_offset(buffer: &mut PrintBuffer) {
    if buffer.buffer.is_null() {
        return;
    }

    let buffer_pointer = buffer.buffer.add(buffer.offset) as *const c_char;
    buffer.offset += CStr::from_ptr(buffer_pointer).to_bytes().len();
}

unsafe fn append_literal(output_buffer: &mut PrintBuffer, literal: &[u8]) -> bool {
    let output = ensure(output_buffer, literal.len());
    if output.is_null() {
        return false;
    }

    ptr::copy_nonoverlapping(literal.as_ptr(), output, literal.len());
    *output.add(literal.len()) = 0;
    true
}

unsafe fn print_value(item: *const cJSON, output_buffer: &mut PrintBuffer) -> bool {
    if item.is_null() || output_buffer.buffer.is_null() {
        return false;
    }

    match (*item).type_ & 0xFF {
        cJSON_NULL => append_literal(output_buffer, b"null"),
        cJSON_False => append_literal(output_buffer, b"false"),
        cJSON_True => append_literal(output_buffer, b"true"),
        cJSON_Number => {
            let Some(number) = print_number_bytes(item) else {
                return false;
            };

            let output = ensure(output_buffer, number.len());
            if output.is_null() {
                return false;
            }

            ptr::copy_nonoverlapping(number.as_ptr(), output, number.len());
            *output.add(number.len()) = 0;
            output_buffer.offset += number.len();
            true
        }
        cJSON_Raw => {
            if (*item).valuestring.is_null() {
                return false;
            }

            let raw = CStr::from_ptr((*item).valuestring).to_bytes_with_nul();
            let output = ensure(output_buffer, raw.len());
            if output.is_null() {
                return false;
            }

            ptr::copy_nonoverlapping(raw.as_ptr(), output, raw.len());
            true
        }
        cJSON_String => print_string(item, output_buffer),
        cJSON_Array => print_array(item, output_buffer),
        cJSON_Object => print_object(item, output_buffer),
        _ => false,
    }
}

unsafe fn print_array(item: *const cJSON, output_buffer: &mut PrintBuffer) -> bool {
    let mut current_element = (*item).child;

    let output = ensure(output_buffer, 1);
    if output.is_null() {
        return false;
    }

    *output = b'[';
    output_buffer.offset += 1;
    output_buffer.depth += 1;

    while !current_element.is_null() {
        if !print_value(current_element, output_buffer) {
            return false;
        }
        update_offset(output_buffer);

        if !(*current_element).next.is_null() {
            let length = if output_buffer.format { 2 } else { 1 };
            let output = ensure(output_buffer, length + 1);
            if output.is_null() {
                return false;
            }

            *output = b',';
            if output_buffer.format {
                *output.add(1) = b' ';
            }
            *output.add(length) = 0;
            output_buffer.offset += length;
        }

        current_element = (*current_element).next;
    }

    let output = ensure(output_buffer, 2);
    if output.is_null() {
        return false;
    }

    *output = b']';
    *output.add(1) = 0;
    output_buffer.depth -= 1;

    true
}

unsafe fn print_object(item: *const cJSON, output_buffer: &mut PrintBuffer) -> bool {
    let mut current_item = (*item).child;
    let opening_length = if output_buffer.format { 2 } else { 1 };
    let output = ensure(output_buffer, opening_length + 1);
    if output.is_null() {
        return false;
    }

    *output = b'{';
    output_buffer.depth += 1;
    if output_buffer.format {
        *output.add(1) = b'\n';
    }
    output_buffer.offset += opening_length;

    while !current_item.is_null() {
        if output_buffer.format {
            let output = ensure(output_buffer, output_buffer.depth);
            if output.is_null() {
                return false;
            }

            for index in 0..output_buffer.depth {
                *output.add(index) = b'\t';
            }
            output_buffer.offset += output_buffer.depth;
        }

        if !print_string_ptr((*current_item).string as *const u8, output_buffer) {
            return false;
        }
        update_offset(output_buffer);

        let separator_length = if output_buffer.format { 2 } else { 1 };
        let output = ensure(output_buffer, separator_length);
        if output.is_null() {
            return false;
        }

        *output = b':';
        if output_buffer.format {
            *output.add(1) = b'\t';
        }
        output_buffer.offset += separator_length;

        if !print_value(current_item, output_buffer) {
            return false;
        }
        update_offset(output_buffer);

        let trailing_length = (if output_buffer.format { 1 } else { 0 })
            + (if !(*current_item).next.is_null() {
                1
            } else {
                0
            });
        let output = ensure(output_buffer, trailing_length + 1);
        if output.is_null() {
            return false;
        }

        if !(*current_item).next.is_null() {
            *output = b',';
        }
        if output_buffer.format {
            *output.add(trailing_length - 1) = b'\n';
        }
        *output.add(trailing_length) = 0;
        output_buffer.offset += trailing_length;

        current_item = (*current_item).next;
    }

    let closing_length = if output_buffer.format {
        output_buffer.depth + 1
    } else {
        2
    };
    let output = ensure(output_buffer, closing_length);
    if output.is_null() {
        return false;
    }

    if output_buffer.format {
        for index in 0..(output_buffer.depth - 1) {
            *output.add(index) = b'\t';
        }
        *output.add(output_buffer.depth - 1) = b'}';
        *output.add(output_buffer.depth) = 0;
    } else {
        *output = b'}';
        *output.add(1) = 0;
    }
    output_buffer.depth -= 1;

    true
}

unsafe fn print(item: *const cJSON, format: bool, hooks: &InternalHooks) -> *mut c_char {
    const DEFAULT_BUFFER_SIZE: usize = 256;

    let mut buffer = PrintBuffer {
        buffer: (hooks.allocate)(DEFAULT_BUFFER_SIZE) as *mut u8,
        length: DEFAULT_BUFFER_SIZE,
        offset: 0,
        depth: 0,
        noalloc: false,
        format,
        hooks: *hooks,
    };

    if buffer.buffer.is_null() {
        return ptr::null_mut();
    }

    if !print_value(item, &mut buffer) {
        deallocate_with_hooks(hooks, buffer.buffer.cast());
        return ptr::null_mut();
    }
    update_offset(&mut buffer);

    if let Some(reallocate) = hooks.reallocate {
        let printed = reallocate(buffer.buffer.cast(), buffer.offset + 1) as *mut c_char;
        if printed.is_null() {
            deallocate_with_hooks(hooks, buffer.buffer.cast());
            return ptr::null_mut();
        }
        return printed;
    }

    let printed = (hooks.allocate)(buffer.offset + 1) as *mut c_char;
    if printed.is_null() {
        deallocate_with_hooks(hooks, buffer.buffer.cast());
        return ptr::null_mut();
    }

    ptr::copy_nonoverlapping(
        buffer.buffer,
        printed as *mut u8,
        min(buffer.length, buffer.offset + 1),
    );
    *printed.add(buffer.offset) = 0;
    deallocate_with_hooks(hooks, buffer.buffer.cast());

    printed
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Print(item: *const cJSON) -> *mut c_char {
    print(item, true, &current_hooks())
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_PrintUnformatted(item: *const cJSON) -> *mut c_char {
    print(item, false, &current_hooks())
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_PrintBuffered(
    item: *const cJSON,
    prebuffer: c_int,
    fmt: cJSON_bool,
) -> *mut c_char {
    let hooks = current_hooks();
    let mut buffer = PrintBuffer {
        buffer: ptr::null_mut(),
        length: 0,
        offset: 0,
        depth: 0,
        noalloc: false,
        format: fmt != 0,
        hooks,
    };

    if prebuffer < 0 {
        return ptr::null_mut();
    }

    buffer.buffer = (buffer.hooks.allocate)(prebuffer as usize) as *mut u8;
    if buffer.buffer.is_null() {
        return ptr::null_mut();
    }
    buffer.length = prebuffer as usize;

    if !print_value(item, &mut buffer) {
        deallocate_with_hooks(&buffer.hooks, buffer.buffer.cast());
        return ptr::null_mut();
    }

    buffer.buffer as *mut c_char
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_PrintPreallocated(
    item: *mut cJSON,
    buffer: *mut c_char,
    length: c_int,
    format: cJSON_bool,
) -> cJSON_bool {
    let mut print_buffer = PrintBuffer {
        buffer: buffer as *mut u8,
        length: if length < 0 { 0 } else { length as usize },
        offset: 0,
        depth: 0,
        noalloc: true,
        format: format != 0,
        hooks: current_hooks(),
    };

    if length < 0 || buffer.is_null() {
        return 0;
    }

    if print_value(item, &mut print_buffer) {
        1
    } else {
        0
    }
}
