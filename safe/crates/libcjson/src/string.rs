use std::ptr;
use std::slice;

use crate::abi::{cJSON, cJSON_String};
use crate::hooks::duplicate_bytes_with_hooks;
use crate::parse::ParseBuffer;
use crate::print::{ensure, PrintBuffer};

fn parse_hex4(input: &[u8]) -> Option<u16> {
    if input.len() < 4 {
        return None;
    }

    let mut value = 0u16;
    for byte in &input[..4] {
        value <<= 4;
        value |= match byte {
            b'0'..=b'9' => (byte - b'0') as u16,
            b'a'..=b'f' => (byte - b'a' + 10) as u16,
            b'A'..=b'F' => (byte - b'A' + 10) as u16,
            _ => return None,
        };
    }

    Some(value)
}

fn push_codepoint_utf8(output: &mut Vec<u8>, codepoint: u32) -> Option<()> {
    let mut buffer = [0u8; 4];
    let encoded = char::from_u32(codepoint)?.encode_utf8(&mut buffer);
    output.extend_from_slice(encoded.as_bytes());
    Some(())
}

fn utf16_literal_to_utf8(input: &[u8], output: &mut Vec<u8>) -> Option<usize> {
    if input.len() < 6 || input[0] != b'\\' || input[1] != b'u' {
        return None;
    }

    let first_code = parse_hex4(&input[2..6])?;
    if (0xDC00..=0xDFFF).contains(&first_code) {
        return None;
    }

    let (codepoint, consumed) = if (0xD800..=0xDBFF).contains(&first_code) {
        if input.len() < 12 || input[6] != b'\\' || input[7] != b'u' {
            return None;
        }

        let second_code = parse_hex4(&input[8..12])?;
        if !(0xDC00..=0xDFFF).contains(&second_code) {
            return None;
        }

        let codepoint =
            0x10000 + ((((first_code & 0x03FF) as u32) << 10) | ((second_code & 0x03FF) as u32));
        (codepoint, 12usize)
    } else {
        (first_code as u32, 6usize)
    };

    push_codepoint_utf8(output, codepoint)?;
    Some(consumed)
}

pub(crate) unsafe fn parse_string(item: *mut cJSON, input_buffer: &mut ParseBuffer) -> bool {
    if !input_buffer.can_access_at_index(0) || *input_buffer.buffer_at_offset() != b'"' {
        return false;
    }

    let base = input_buffer.content;
    let mut input_pointer = input_buffer.offset + 1;
    let mut input_end = input_pointer;
    let mut skipped_bytes = 0usize;

    while input_end < input_buffer.length && *base.add(input_end) != b'"' {
        if *base.add(input_end) == b'\\' {
            if input_end + 1 >= input_buffer.length {
                input_buffer.offset = input_end;
                return false;
            }
            skipped_bytes += 1;
            input_end += 1;
        }
        input_end += 1;
    }

    if input_end >= input_buffer.length || *base.add(input_end) != b'"' {
        input_buffer.offset = input_end.min(input_buffer.length.saturating_sub(1));
        return false;
    }

    let allocation_length = (input_end - input_buffer.offset).saturating_sub(skipped_bytes);
    let input = slice::from_raw_parts(base, input_buffer.length);
    let mut output = Vec::with_capacity(allocation_length);

    while input_pointer < input_end {
        if input[input_pointer] != b'\\' {
            output.push(input[input_pointer]);
            input_pointer += 1;
            continue;
        }

        if input_pointer + 1 >= input_end + 1 {
            input_buffer.offset = input_pointer;
            return false;
        }

        match input[input_pointer + 1] {
            b'b' => output.push(b'\x08'),
            b'f' => output.push(b'\x0c'),
            b'n' => output.push(b'\n'),
            b'r' => output.push(b'\r'),
            b't' => output.push(b'\t'),
            b'"' | b'\\' | b'/' => output.push(input[input_pointer + 1]),
            b'u' => {
                let Some(consumed) =
                    utf16_literal_to_utf8(&input[input_pointer..input_end], &mut output)
                else {
                    input_buffer.offset = input_pointer;
                    return false;
                };
                input_pointer += consumed;
                continue;
            }
            _ => {
                input_buffer.offset = input_pointer;
                return false;
            }
        }

        input_pointer += 2;
    }

    let allocated = duplicate_bytes_with_hooks(&output, &input_buffer.hooks);
    if allocated.is_null() {
        return false;
    }

    (*item).type_ = cJSON_String;
    (*item).valuestring = allocated;
    input_buffer.offset = input_end + 1;

    true
}

pub(crate) unsafe fn print_string_ptr(input: *const u8, output_buffer: &mut PrintBuffer) -> bool {
    if input.is_null() {
        let output = ensure(output_buffer, 3);
        if output.is_null() {
            return false;
        }

        ptr::copy_nonoverlapping(b"\"\"\0".as_ptr(), output, 3);
        return true;
    }

    let mut input_pointer = input;
    let mut escape_characters = 0usize;
    while *input_pointer != 0 {
        match *input_pointer {
            b'"' | b'\\' | b'\x08' | b'\x0c' | b'\n' | b'\r' | b'\t' => {
                escape_characters += 1;
            }
            0..=31 => {
                escape_characters += 5;
            }
            _ => {}
        }

        input_pointer = input_pointer.add(1);
    }

    let output_length = input_pointer.offset_from(input) as usize + escape_characters;
    let output = ensure(output_buffer, output_length + 3);
    if output.is_null() {
        return false;
    }

    if escape_characters == 0 {
        *output = b'"';
        ptr::copy_nonoverlapping(input, output.add(1), output_length);
        *output.add(output_length + 1) = b'"';
        *output.add(output_length + 2) = 0;
        return true;
    }

    *output = b'"';
    let mut source = input;
    let mut target = output.add(1);
    while *source != 0 {
        if *source > 31 && *source != b'"' && *source != b'\\' {
            *target = *source;
            target = target.add(1);
            source = source.add(1);
            continue;
        }

        *target = b'\\';
        target = target.add(1);
        match *source {
            b'\\' => *target = b'\\',
            b'"' => *target = b'"',
            b'\x08' => *target = b'b',
            b'\x0c' => *target = b'f',
            b'\n' => *target = b'n',
            b'\r' => *target = b'r',
            b'\t' => *target = b't',
            value => {
                *target = b'u';
                *target.add(1) = b'0';
                *target.add(2) = b'0';
                *target.add(3) = b"0123456789abcdef"[(value >> 4) as usize];
                *target.add(4) = b"0123456789abcdef"[(value & 0x0F) as usize];
                target = target.add(5);
                source = source.add(1);
                continue;
            }
        }

        target = target.add(1);
        source = source.add(1);
    }

    *target = b'"';
    *target.add(1) = 0;

    true
}

pub(crate) unsafe fn print_string(item: *const cJSON, output_buffer: &mut PrintBuffer) -> bool {
    print_string_ptr((*item).valuestring as *const u8, output_buffer)
}
