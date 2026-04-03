use std::os::raw::c_char;

unsafe fn skip_oneline_comment(input: &mut *mut c_char) {
    *input = (*input).add(2);

    while (**input) != 0 {
        if (**input) == b'\n' as c_char {
            *input = (*input).add(1);
            return;
        }

        *input = (*input).add(1);
    }
}

unsafe fn skip_multiline_comment(input: &mut *mut c_char) {
    *input = (*input).add(2);

    while (**input) != 0 {
        if (**input) == b'*' as c_char && *(*input).add(1) == b'/' as c_char {
            *input = (*input).add(2);
            return;
        }

        *input = (*input).add(1);
    }
}

unsafe fn minify_string(input: &mut *mut c_char, output: &mut *mut c_char) {
    **output = **input;
    *input = (*input).add(1);
    *output = (*output).add(1);

    while (**input) != 0 {
        **output = **input;

        if (**input) == b'"' as c_char {
            *input = (*input).add(1);
            *output = (*output).add(1);
            return;
        }

        if (**input) == b'\\' as c_char && *(*input).add(1) == b'"' as c_char {
            *(*output).add(1) = *(*input).add(1);
            *input = (*input).add(1);
            *output = (*output).add(1);
        }

        *input = (*input).add(1);
        *output = (*output).add(1);
    }
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Minify(json: *mut c_char) {
    let mut json = json;
    let mut into = json;

    if json.is_null() {
        return;
    }

    while *json != 0 {
        match *json as u8 {
            b' ' | b'\t' | b'\r' | b'\n' => {
                json = json.add(1);
            }
            b'/' => {
                if *json.add(1) == b'/' as c_char {
                    skip_oneline_comment(&mut json);
                } else if *json.add(1) == b'*' as c_char {
                    skip_multiline_comment(&mut json);
                } else {
                    json = json.add(1);
                }
            }
            b'"' => {
                minify_string(&mut json, &mut into);
            }
            _ => {
                *into = *json;
                json = json.add(1);
                into = into.add(1);
            }
        }
    }

    *into = 0;
}
