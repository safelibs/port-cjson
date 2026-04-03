use std::os::raw::{c_char, c_double, c_int, c_void};
use std::ptr;

use crate::abi::{cJSON, cJSON_IsReference, cJSON_String};
use crate::hooks::{deallocate, duplicate_c_string};

const MAX_NUMERIC_LITERAL_LENGTH: usize = 63;
const PRINT_NUMBER_BUFFER_LEN: usize = 26;

const FORMAT_INTEGER: &[u8] = b"%d\0";
const FORMAT_DOUBLE_15: &[u8] = b"%1.15g\0";
const FORMAT_DOUBLE_17: &[u8] = b"%1.17g\0";

unsafe extern "C" {
    fn snprintf(buffer: *mut c_char, bufsz: usize, format: *const c_char, ...) -> c_int;
    fn strtod(string: *const c_char, end: *mut *mut c_char) -> c_double;
}

#[cfg(cjson_enable_locales)]
#[repr(C)]
struct lconv_prefix {
    decimal_point: *mut c_char,
}

#[cfg(cjson_enable_locales)]
unsafe extern "C" {
    fn localeconv() -> *mut lconv_prefix;
}

pub fn saturating_valueint(number: c_double) -> c_int {
    if number >= c_int::MAX as c_double {
        c_int::MAX
    } else if number <= c_int::MIN as c_double {
        c_int::MIN
    } else {
        number as c_int
    }
}

pub fn compare_double(a: c_double, b: c_double) -> bool {
    let max_value = a.abs().max(b.abs());
    (a - b).abs() <= max_value * c_double::EPSILON
}

#[cfg(cjson_enable_locales)]
pub unsafe fn get_decimal_point() -> u8 {
    let conv = localeconv();
    if conv.is_null() || (*conv).decimal_point.is_null() {
        b'.'
    } else {
        *(*conv).decimal_point as u8
    }
}

#[cfg(not(cjson_enable_locales))]
pub unsafe fn get_decimal_point() -> u8 {
    b'.'
}

fn consume_integer_part(input: &[u8], index: &mut usize) -> Option<()> {
    match input.get(*index) {
        Some(b'0') => {
            *index += 1;
            if matches!(input.get(*index), Some(b'0'..=b'9')) {
                return None;
            }
        }
        Some(b'1'..=b'9') => {
            *index += 1;
            while matches!(input.get(*index), Some(b'0'..=b'9')) {
                *index += 1;
            }
        }
        _ => return None,
    }

    Some(())
}

fn consume_fractional_part(input: &[u8], index: &mut usize) -> Option<()> {
    if input.get(*index) != Some(&b'.') {
        return Some(());
    }

    *index += 1;
    let start = *index;
    while matches!(input.get(*index), Some(b'0'..=b'9')) {
        *index += 1;
    }

    if *index == start {
        return None;
    }

    Some(())
}

fn consume_exponent_part(input: &[u8], index: &mut usize) -> Option<()> {
    if !matches!(input.get(*index), Some(b'e' | b'E')) {
        return Some(());
    }

    *index += 1;
    if matches!(input.get(*index), Some(b'+' | b'-')) {
        *index += 1;
    }

    let start = *index;
    while matches!(input.get(*index), Some(b'0'..=b'9')) {
        *index += 1;
    }

    if *index == start {
        return None;
    }

    Some(())
}

pub fn consume_number_token(input: &[u8]) -> Option<usize> {
    let mut index = 0usize;

    if input.get(index) == Some(&b'-') {
        index += 1;
    }

    consume_integer_part(input, &mut index)?;
    consume_fractional_part(input, &mut index)?;
    consume_exponent_part(input, &mut index)?;

    Some(index)
}

fn consume_numeric_candidate(input: &[u8]) -> usize {
    let mut index = 0usize;

    while matches!(
        input.get(index),
        Some(b'0'..=b'9' | b'+' | b'-' | b'e' | b'E' | b'.')
    ) {
        index += 1;
    }

    index
}

pub(crate) enum NumberParseResult {
    Success { length: usize, number: c_double },
    Failure { error_offset: usize },
}

pub unsafe fn parse_number_token(input: &[u8]) -> NumberParseResult {
    let candidate_length = consume_numeric_candidate(input);
    if candidate_length == 0 {
        return NumberParseResult::Failure { error_offset: 0 };
    }

    if candidate_length > MAX_NUMERIC_LITERAL_LENGTH {
        return NumberParseResult::Failure { error_offset: 0 };
    }

    let token = &input[..candidate_length];
    let decimal_point = get_decimal_point();
    let mut adjusted = Vec::with_capacity(token.len() + 1);
    for byte in token {
        adjusted.push(if *byte == b'.' { decimal_point } else { *byte });
    }
    adjusted.push(0);

    let start = adjusted.as_ptr() as *const c_char;
    let mut end = ptr::null_mut();
    let number = strtod(start, &mut end);
    let consumed = end.offset_from(start) as usize;
    if end == start as *mut c_char {
        return NumberParseResult::Failure { error_offset: 0 };
    }

    let Some(token_length) = consume_number_token(input) else {
        return NumberParseResult::Failure {
            error_offset: consumed.min(candidate_length),
        };
    };

    if token_length != candidate_length || consumed != candidate_length {
        return NumberParseResult::Failure {
            error_offset: consumed.min(candidate_length),
        };
    }

    NumberParseResult::Success {
        length: token_length,
        number,
    }
}

pub unsafe fn print_number_bytes(item: *const cJSON) -> Option<Vec<u8>> {
    let number = (*item).valuedouble;

    if number.is_nan() || number.is_infinite() {
        return Some(b"null".to_vec());
    }

    let mut buffer = [0 as c_char; PRINT_NUMBER_BUFFER_LEN];
    let length = if number == (*item).valueint as c_double {
        snprintf(
            buffer.as_mut_ptr(),
            buffer.len(),
            FORMAT_INTEGER.as_ptr() as *const c_char,
            (*item).valueint,
        )
    } else {
        let mut length = snprintf(
            buffer.as_mut_ptr(),
            buffer.len(),
            FORMAT_DOUBLE_15.as_ptr() as *const c_char,
            number,
        );
        if length < 0 || length > (buffer.len() as c_int - 1) {
            return None;
        }

        let mut end = ptr::null_mut();
        let test = strtod(buffer.as_ptr(), &mut end);
        if end != buffer.as_ptr().add(length as usize) as *mut c_char
            || !compare_double(test, number)
        {
            length = snprintf(
                buffer.as_mut_ptr(),
                buffer.len(),
                FORMAT_DOUBLE_17.as_ptr() as *const c_char,
                number,
            );
        }

        length
    };

    if length < 0 || length > (buffer.len() as c_int - 1) {
        return None;
    }

    let decimal_point = get_decimal_point();
    let mut printed = Vec::with_capacity(length as usize);
    for byte in buffer[..length as usize].iter() {
        let value = *byte as u8;
        printed.push(if value == decimal_point { b'.' } else { value });
    }

    Some(printed)
}

pub unsafe fn set_number_fields(item: *mut cJSON, number: c_double) {
    (*item).valueint = saturating_valueint(number);
    (*item).valuedouble = number;
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_SetNumberHelper(object: *mut cJSON, number: c_double) -> c_double {
    if object.is_null() {
        return number;
    }

    set_number_fields(object, number);
    (*object).valuedouble
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_SetValuestring(
    object: *mut cJSON,
    valuestring: *const c_char,
) -> *mut c_char {
    let old_length: usize;
    let new_length: usize;
    let copy: *mut c_char;

    if object.is_null()
        || ((*object).type_ & cJSON_String) == 0
        || ((*object).type_ & cJSON_IsReference) != 0
    {
        return ptr::null_mut();
    }

    if (*object).valuestring.is_null() || valuestring.is_null() {
        return ptr::null_mut();
    }

    old_length = std::ffi::CStr::from_ptr((*object).valuestring)
        .to_bytes()
        .len();
    new_length = std::ffi::CStr::from_ptr(valuestring).to_bytes().len();
    if new_length <= old_length {
        ptr::copy_nonoverlapping(valuestring, (*object).valuestring, new_length + 1);
        return (*object).valuestring;
    }

    copy = duplicate_c_string(valuestring);
    if copy.is_null() {
        return ptr::null_mut();
    }

    deallocate((*object).valuestring as *mut c_void);
    (*object).valuestring = copy;

    copy
}
