#![allow(non_camel_case_types)]
#![allow(non_upper_case_globals)]

use std::ffi::CStr;
use std::os::raw::{c_char, c_double, c_int, c_void};
use std::ptr;
use std::slice;
use std::sync::Mutex;

const cJSON_Invalid: c_int = 0;
const cJSON_False: c_int = 1 << 0;
const cJSON_True: c_int = 1 << 1;
const cJSON_NULL: c_int = 1 << 2;
const cJSON_Number: c_int = 1 << 3;
const cJSON_String: c_int = 1 << 4;
const cJSON_Array: c_int = 1 << 5;
const cJSON_Object: c_int = 1 << 6;
const cJSON_Raw: c_int = 1 << 7;
const cJSON_IsReference: c_int = 256;
const cJSON_StringIsConst: c_int = 512;

const VERSION: &[u8] = b"1.7.17\0";
const PRINT_STUB: &[u8] = b"null\0";

type cJSON_bool = c_int;
type malloc_fn = unsafe extern "C" fn(usize) -> *mut c_void;
type free_fn = unsafe extern "C" fn(*mut c_void);

unsafe extern "C" {
    fn malloc(size: usize) -> *mut c_void;
    fn free(ptr: *mut c_void);
}

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

#[repr(C)]
#[derive(Clone, Copy)]
pub struct cJSON_Hooks
{
    pub malloc_fn: Option<malloc_fn>,
    pub free_fn: Option<free_fn>,
}

struct GlobalState
{
    hooks: cJSON_Hooks,
    parse_error: usize,
}

impl GlobalState
{
    const fn new() -> Self
    {
        Self {
            hooks: cJSON_Hooks {
                malloc_fn: None,
                free_fn: None,
            },
            parse_error: 0,
        }
    }
}

static STATE: Mutex<GlobalState> = Mutex::new(GlobalState::new());

#[cfg(cjson_enable_locales)]
const LOCALES_ENABLED: bool = true;
#[cfg(not(cjson_enable_locales))]
const LOCALES_ENABLED: bool = false;

fn state() -> std::sync::MutexGuard<'static, GlobalState>
{
    STATE.lock().expect("global cJSON state poisoned")
}

fn bool_to_cjson(value: bool) -> cJSON_bool
{
    if value { 1 } else { 0 }
}

unsafe fn allocate_raw(size: usize) -> *mut c_void
{
    let hooks = state().hooks;
    if let Some(allocator) = hooks.malloc_fn {
        allocator(size)
    } else {
        malloc(size)
    }
}

unsafe fn free_raw(pointer: *mut c_void)
{
    if pointer.is_null() {
        return;
    }

    let hooks = state().hooks;
    if let Some(deallocator) = hooks.free_fn {
        deallocator(pointer);
    } else {
        free(pointer);
    }
}

unsafe fn duplicate_c_string(value: *const c_char) -> *mut c_char
{
    if value.is_null() {
        return ptr::null_mut();
    }

    let bytes = CStr::from_ptr(value).to_bytes_with_nul();
    let output = allocate_raw(bytes.len()) as *mut c_char;
    if output.is_null() {
        return ptr::null_mut();
    }

    ptr::copy_nonoverlapping(bytes.as_ptr() as *const c_char, output, bytes.len());
    output
}

unsafe fn allocate_item(item_type: c_int) -> *mut cJSON
{
    let item = allocate_raw(std::mem::size_of::<cJSON>()) as *mut cJSON;
    if item.is_null() {
        return ptr::null_mut();
    }

    ptr::write(
        item,
        cJSON {
            next: ptr::null_mut(),
            prev: ptr::null_mut(),
            child: ptr::null_mut(),
            type_: item_type,
            valuestring: ptr::null_mut(),
            valueint: 0,
            valuedouble: 0.0,
            string: ptr::null_mut(),
        },
    );
    item
}

unsafe fn set_parse_error(parse_error: *const c_char)
{
    state().parse_error = parse_error as usize;
}

unsafe fn append_child(parent: *mut cJSON, item: *mut cJSON) -> cJSON_bool
{
    if parent.is_null() || item.is_null() {
        return 0;
    }

    (*item).next = ptr::null_mut();
    (*item).prev = ptr::null_mut();

    if (*parent).child.is_null() {
        (*parent).child = item;
        return 1;
    }

    let mut tail = (*parent).child;
    while !(*tail).next.is_null() {
        tail = (*tail).next;
    }

    (*tail).next = item;
    (*item).prev = tail;
    1
}

unsafe fn set_item_key(item: *mut cJSON, key: *const c_char, constant: bool) -> bool
{
    if item.is_null() {
        return false;
    }

    if !(*item).string.is_null() && ((*item).type_ & cJSON_StringIsConst) == 0 {
        free_raw((*item).string as *mut c_void);
        (*item).string = ptr::null_mut();
    }

    if key.is_null() {
        (*item).type_ &= !cJSON_StringIsConst;
        return true;
    }

    if constant {
        (*item).string = key as *mut c_char;
        (*item).type_ |= cJSON_StringIsConst;
        return true;
    }

    let copied_key = duplicate_c_string(key);
    if copied_key.is_null() {
        return false;
    }

    (*item).string = copied_key;
    (*item).type_ &= !cJSON_StringIsConst;
    true
}

unsafe fn cstr_bytes(value: *const c_char) -> &'static [u8]
{
    CStr::from_ptr(value).to_bytes()
}

unsafe fn object_item_matches_key(item: *const cJSON, key: *const c_char, case_sensitive: bool) -> bool
{
    if item.is_null() || key.is_null() || (*item).string.is_null() {
        return false;
    }

    let lhs = cstr_bytes((*item).string);
    let rhs = cstr_bytes(key);

    if case_sensitive {
        lhs == rhs
    } else {
        lhs.eq_ignore_ascii_case(rhs)
    }
}

unsafe fn find_object_item(
    object: *const cJSON,
    key: *const c_char,
    case_sensitive: bool,
) -> *mut cJSON
{
    if object.is_null() {
        return ptr::null_mut();
    }

    let mut current = (*object).child;
    while !current.is_null() {
        if object_item_matches_key(current, key, case_sensitive) {
            return current;
        }
        current = (*current).next;
    }

    ptr::null_mut()
}

unsafe fn create_reference_copy(item: *const cJSON) -> *mut cJSON
{
    if item.is_null() {
        return ptr::null_mut();
    }

    let reference = allocate_item((*item).type_ | cJSON_IsReference);
    if reference.is_null() {
        return ptr::null_mut();
    }

    (*reference).child = (*item).child;
    (*reference).valuestring = (*item).valuestring;
    (*reference).valueint = (*item).valueint;
    (*reference).valuedouble = (*item).valuedouble;
    reference
}

unsafe fn duplicate_item(item: *const cJSON, recurse: bool) -> *mut cJSON
{
    if item.is_null() {
        return ptr::null_mut();
    }

    let duplicate = allocate_item((*item).type_ & !cJSON_IsReference);
    if duplicate.is_null() {
        return ptr::null_mut();
    }

    (*duplicate).valueint = (*item).valueint;
    (*duplicate).valuedouble = (*item).valuedouble;

    if !(*item).valuestring.is_null() {
        if ((*item).type_ & cJSON_IsReference) != 0 {
            (*duplicate).valuestring = (*item).valuestring;
            (*duplicate).type_ |= cJSON_IsReference;
        } else {
            (*duplicate).valuestring = duplicate_c_string((*item).valuestring);
        }
    }

    if !(*item).string.is_null() {
        if ((*item).type_ & cJSON_StringIsConst) != 0 {
            (*duplicate).string = (*item).string;
            (*duplicate).type_ |= cJSON_StringIsConst;
        } else {
            (*duplicate).string = duplicate_c_string((*item).string);
        }
    }

    if recurse && !(*item).child.is_null() {
        let mut source_child = (*item).child;
        let mut previous_child: *mut cJSON = ptr::null_mut();
        while !source_child.is_null() {
            let copied_child = duplicate_item(source_child, true);
            if copied_child.is_null() {
                cJSON_Delete(duplicate);
                return ptr::null_mut();
            }

            if previous_child.is_null() {
                (*duplicate).child = copied_child;
            } else {
                (*previous_child).next = copied_child;
                (*copied_child).prev = previous_child;
            }

            previous_child = copied_child;
            source_child = (*source_child).next;
        }
    }

    duplicate
}

unsafe fn detach_child(parent: *mut cJSON, item: *mut cJSON) -> *mut cJSON
{
    if parent.is_null() || item.is_null() {
        return ptr::null_mut();
    }

    let mut current = (*parent).child;
    while !current.is_null() {
        if current == item {
            if !(*current).prev.is_null() {
                (*(*current).prev).next = (*current).next;
            } else {
                (*parent).child = (*current).next;
            }

            if !(*current).next.is_null() {
                (*(*current).next).prev = (*current).prev;
            }

            (*current).next = ptr::null_mut();
            (*current).prev = ptr::null_mut();
            return current;
        }
        current = (*current).next;
    }

    ptr::null_mut()
}

unsafe fn array_item_at(array: *const cJSON, index: c_int) -> *mut cJSON
{
    if array.is_null() || index < 0 {
        return ptr::null_mut();
    }

    let mut current = (*array).child;
    let mut remaining = index;
    while !current.is_null() && remaining > 0 {
        current = (*current).next;
        remaining -= 1;
    }

    current
}

unsafe fn delete_chain(mut item: *mut cJSON)
{
    while !item.is_null() {
        let next = (*item).next;

        if ((*item).type_ & cJSON_IsReference) == 0 {
            delete_chain((*item).child);
            if !(*item).valuestring.is_null() {
                free_raw((*item).valuestring as *mut c_void);
            }
        }

        if !(*item).string.is_null() && ((*item).type_ & cJSON_StringIsConst) == 0 {
            free_raw((*item).string as *mut c_void);
        }

        free_raw(item as *mut c_void);
        item = next;
    }
}

unsafe fn replace_child(parent: *mut cJSON, item: *mut cJSON, replacement: *mut cJSON) -> cJSON_bool
{
    if parent.is_null() || item.is_null() || replacement.is_null() {
        return 0;
    }

    let mut current = (*parent).child;
    while !current.is_null() {
        if current == item {
            (*replacement).prev = (*item).prev;
            (*replacement).next = (*item).next;

            if !(*item).prev.is_null() {
                (*(*item).prev).next = replacement;
            } else {
                (*parent).child = replacement;
            }

            if !(*item).next.is_null() {
                (*(*item).next).prev = replacement;
            }

            (*item).next = ptr::null_mut();
            (*item).prev = ptr::null_mut();
            cJSON_Delete(item);
            return 1;
        }
        current = (*current).next;
    }

    0
}

unsafe fn compare_items(lhs: *const cJSON, rhs: *const cJSON, case_sensitive: bool) -> bool
{
    if lhs.is_null() || rhs.is_null() {
        return false;
    }

    if ((*lhs).type_ & 0xff) != ((*rhs).type_ & 0xff) {
        return false;
    }

    match (*lhs).type_ & 0xff {
        cJSON_Invalid | cJSON_NULL => true,
        cJSON_False | cJSON_True => true,
        cJSON_Number => (*lhs).valuedouble == (*rhs).valuedouble,
        cJSON_String | cJSON_Raw => {
            if (*lhs).valuestring.is_null() || (*rhs).valuestring.is_null() {
                (*lhs).valuestring.is_null() && (*rhs).valuestring.is_null()
            } else {
                cstr_bytes((*lhs).valuestring) == cstr_bytes((*rhs).valuestring)
            }
        }
        cJSON_Array => {
            let mut left = (*lhs).child;
            let mut right = (*rhs).child;
            while !left.is_null() && !right.is_null() {
                if !compare_items(left, right, case_sensitive) {
                    return false;
                }
                left = (*left).next;
                right = (*right).next;
            }
            left.is_null() && right.is_null()
        }
        cJSON_Object => {
            let mut left = (*lhs).child;
            let mut right = (*rhs).child;
            while !left.is_null() && !right.is_null() {
                if !object_item_matches_key(left, (*right).string, case_sensitive) {
                    return false;
                }
                if !compare_items(left, right, case_sensitive) {
                    return false;
                }
                left = (*left).next;
                right = (*right).next;
            }
            left.is_null() && right.is_null()
        }
        _ => false,
    }
}

unsafe fn create_number_item(number: c_double) -> *mut cJSON
{
    let item = allocate_item(cJSON_Number);
    if item.is_null() {
        return ptr::null_mut();
    }

    (*item).valuedouble = number;
    (*item).valueint = number as c_int;
    item
}

unsafe fn create_string_item(string: *const c_char, item_type: c_int) -> *mut cJSON
{
    let item = allocate_item(item_type);
    if item.is_null() {
        return ptr::null_mut();
    }

    (*item).valuestring = duplicate_c_string(string);
    if string.is_null() || !(*item).valuestring.is_null() {
        item
    } else {
        cJSON_Delete(item);
        ptr::null_mut()
    }
}

unsafe fn print_stub() -> *mut c_char
{
    duplicate_c_string(PRINT_STUB.as_ptr() as *const c_char)
}

unsafe fn print_into_buffer(buffer: *mut c_char, length: c_int) -> cJSON_bool
{
    if buffer.is_null() || length < PRINT_STUB.len() as c_int {
        return 0;
    }

    ptr::copy_nonoverlapping(
        PRINT_STUB.as_ptr() as *const c_char,
        buffer,
        PRINT_STUB.len(),
    );
    1
}

macro_rules! type_predicate {
    ($name:ident, $mask:expr) => {
        #[no_mangle]
        pub unsafe extern "C" fn $name(item: *const cJSON) -> cJSON_bool
        {
            if item.is_null() {
                return 0;
            }

            bool_to_cjson(((*item).type_ & $mask) != 0)
        }
    };
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Version() -> *const c_char
{
    VERSION.as_ptr() as *const c_char
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_InitHooks(hooks: *mut cJSON_Hooks)
{
    let mut global_state = state();
    if hooks.is_null() {
        global_state.hooks = cJSON_Hooks {
            malloc_fn: None,
            free_fn: None,
        };
    } else {
        global_state.hooks = cJSON_Hooks {
            malloc_fn: (*hooks).malloc_fn,
            free_fn: (*hooks).free_fn,
        };
    }
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Parse(value: *const c_char) -> *mut cJSON
{
    set_parse_error(value);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ParseWithLength(
    value: *const c_char,
    _buffer_length: usize,
) -> *mut cJSON
{
    set_parse_error(value);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ParseWithOpts(
    value: *const c_char,
    return_parse_end: *mut *const c_char,
    _require_null_terminated: cJSON_bool,
) -> *mut cJSON
{
    if !return_parse_end.is_null() {
        *return_parse_end = value;
    }
    set_parse_error(value);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ParseWithLengthOpts(
    value: *const c_char,
    _buffer_length: usize,
    return_parse_end: *mut *const c_char,
    _require_null_terminated: cJSON_bool,
) -> *mut cJSON
{
    if !return_parse_end.is_null() {
        *return_parse_end = value;
    }
    set_parse_error(value);
    ptr::null_mut()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Print(item: *const cJSON) -> *mut c_char
{
    if item.is_null() {
        return ptr::null_mut();
    }
    print_stub()
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_PrintUnformatted(item: *const cJSON) -> *mut c_char
{
    cJSON_Print(item)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_PrintBuffered(
    item: *const cJSON,
    _prebuffer: c_int,
    _fmt: cJSON_bool,
) -> *mut c_char
{
    cJSON_Print(item)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_PrintPreallocated(
    item: *mut cJSON,
    buffer: *mut c_char,
    length: c_int,
    _format: cJSON_bool,
) -> cJSON_bool
{
    if item.is_null() {
        return 0;
    }
    print_into_buffer(buffer, length)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Delete(item: *mut cJSON)
{
    delete_chain(item);
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_GetArraySize(array: *const cJSON) -> c_int
{
    if array.is_null() {
        return 0;
    }

    let mut count = 0;
    let mut current = (*array).child;
    while !current.is_null() {
        count += 1;
        current = (*current).next;
    }
    count
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_GetArrayItem(array: *const cJSON, index: c_int) -> *mut cJSON
{
    array_item_at(array, index)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_GetObjectItem(
    object: *const cJSON,
    string: *const c_char,
) -> *mut cJSON
{
    find_object_item(object, string, false)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_GetObjectItemCaseSensitive(
    object: *const cJSON,
    string: *const c_char,
) -> *mut cJSON
{
    find_object_item(object, string, true)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_HasObjectItem(
    object: *const cJSON,
    string: *const c_char,
) -> cJSON_bool
{
    bool_to_cjson(!find_object_item(object, string, false).is_null())
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_GetErrorPtr() -> *const c_char
{
    state().parse_error as *const c_char
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_GetStringValue(item: *const cJSON) -> *mut c_char
{
    if item.is_null() || ((*item).type_ & cJSON_String) == 0 {
        return ptr::null_mut();
    }
    (*item).valuestring
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_GetNumberValue(item: *const cJSON) -> c_double
{
    if item.is_null() || ((*item).type_ & cJSON_Number) == 0 {
        return f64::NAN;
    }
    (*item).valuedouble
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_IsInvalid(item: *const cJSON) -> cJSON_bool
{
    if item.is_null() {
        return 0;
    }

    bool_to_cjson(((*item).type_ & 0xff) == cJSON_Invalid)
}

type_predicate!(cJSON_IsFalse, cJSON_False);
type_predicate!(cJSON_IsTrue, cJSON_True);
type_predicate!(cJSON_IsBool, cJSON_False | cJSON_True);
type_predicate!(cJSON_IsNull, cJSON_NULL);
type_predicate!(cJSON_IsNumber, cJSON_Number);
type_predicate!(cJSON_IsString, cJSON_String);
type_predicate!(cJSON_IsArray, cJSON_Array);
type_predicate!(cJSON_IsObject, cJSON_Object);
type_predicate!(cJSON_IsRaw, cJSON_Raw);

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateNull() -> *mut cJSON
{
    allocate_item(cJSON_NULL)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateTrue() -> *mut cJSON
{
    allocate_item(cJSON_True)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateFalse() -> *mut cJSON
{
    allocate_item(cJSON_False)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateBool(boolean: cJSON_bool) -> *mut cJSON
{
    if boolean == 0 {
        cJSON_CreateFalse()
    } else {
        cJSON_CreateTrue()
    }
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateNumber(num: c_double) -> *mut cJSON
{
    create_number_item(num)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateString(string: *const c_char) -> *mut cJSON
{
    create_string_item(string, cJSON_String)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateRaw(raw: *const c_char) -> *mut cJSON
{
    create_string_item(raw, cJSON_Raw)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateArray() -> *mut cJSON
{
    allocate_item(cJSON_Array)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateObject() -> *mut cJSON
{
    allocate_item(cJSON_Object)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateStringReference(string: *const c_char) -> *mut cJSON
{
    let item = allocate_item(cJSON_String | cJSON_IsReference);
    if item.is_null() {
        return ptr::null_mut();
    }

    (*item).valuestring = string as *mut c_char;
    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateObjectReference(child: *const cJSON) -> *mut cJSON
{
    let item = allocate_item(cJSON_Object | cJSON_IsReference);
    if item.is_null() {
        return ptr::null_mut();
    }

    (*item).child = child as *mut cJSON;
    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateArrayReference(child: *const cJSON) -> *mut cJSON
{
    let item = allocate_item(cJSON_Array | cJSON_IsReference);
    if item.is_null() {
        return ptr::null_mut();
    }

    (*item).child = child as *mut cJSON;
    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateIntArray(numbers: *const c_int, count: c_int) -> *mut cJSON
{
    if numbers.is_null() || count < 0 {
        return ptr::null_mut();
    }

    let array = cJSON_CreateArray();
    if array.is_null() {
        return ptr::null_mut();
    }

    for number in slice::from_raw_parts(numbers, count as usize) {
        let item = cJSON_CreateNumber(*number as c_double);
        if cJSON_AddItemToArray(array, item) == 0 {
            cJSON_Delete(array);
            return ptr::null_mut();
        }
    }

    array
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateFloatArray(numbers: *const f32, count: c_int) -> *mut cJSON
{
    if numbers.is_null() || count < 0 {
        return ptr::null_mut();
    }

    let array = cJSON_CreateArray();
    if array.is_null() {
        return ptr::null_mut();
    }

    for number in slice::from_raw_parts(numbers, count as usize) {
        let item = cJSON_CreateNumber(*number as c_double);
        if cJSON_AddItemToArray(array, item) == 0 {
            cJSON_Delete(array);
            return ptr::null_mut();
        }
    }

    array
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateDoubleArray(
    numbers: *const c_double,
    count: c_int,
) -> *mut cJSON
{
    if numbers.is_null() || count < 0 {
        return ptr::null_mut();
    }

    let array = cJSON_CreateArray();
    if array.is_null() {
        return ptr::null_mut();
    }

    for number in slice::from_raw_parts(numbers, count as usize) {
        let item = cJSON_CreateNumber(*number);
        if cJSON_AddItemToArray(array, item) == 0 {
            cJSON_Delete(array);
            return ptr::null_mut();
        }
    }

    array
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_CreateStringArray(
    strings: *const *const c_char,
    count: c_int,
) -> *mut cJSON
{
    if strings.is_null() || count < 0 {
        return ptr::null_mut();
    }

    let array = cJSON_CreateArray();
    if array.is_null() {
        return ptr::null_mut();
    }

    for string in slice::from_raw_parts(strings, count as usize) {
        let item = cJSON_CreateString(*string);
        if cJSON_AddItemToArray(array, item) == 0 {
            cJSON_Delete(array);
            return ptr::null_mut();
        }
    }

    array
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddItemToArray(array: *mut cJSON, item: *mut cJSON) -> cJSON_bool
{
    append_child(array, item)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddItemToObject(
    object: *mut cJSON,
    string: *const c_char,
    item: *mut cJSON,
) -> cJSON_bool
{
    if !set_item_key(item, string, false) {
        return 0;
    }
    append_child(object, item)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddItemToObjectCS(
    object: *mut cJSON,
    string: *const c_char,
    item: *mut cJSON,
) -> cJSON_bool
{
    if !set_item_key(item, string, true) {
        return 0;
    }
    append_child(object, item)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddItemReferenceToArray(
    array: *mut cJSON,
    item: *mut cJSON,
) -> cJSON_bool
{
    let reference = create_reference_copy(item);
    append_child(array, reference)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddItemReferenceToObject(
    object: *mut cJSON,
    string: *const c_char,
    item: *mut cJSON,
) -> cJSON_bool
{
    let reference = create_reference_copy(item);
    if reference.is_null() {
        return 0;
    }

    if !set_item_key(reference, string, false) {
        cJSON_Delete(reference);
        return 0;
    }

    append_child(object, reference)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_DetachItemViaPointer(
    parent: *mut cJSON,
    item: *mut cJSON,
) -> *mut cJSON
{
    detach_child(parent, item)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_DetachItemFromArray(
    array: *mut cJSON,
    which: c_int,
) -> *mut cJSON
{
    detach_child(array, array_item_at(array, which))
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_DeleteItemFromArray(array: *mut cJSON, which: c_int)
{
    let item = cJSON_DetachItemFromArray(array, which);
    cJSON_Delete(item);
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_DetachItemFromObject(
    object: *mut cJSON,
    string: *const c_char,
) -> *mut cJSON
{
    detach_child(object, find_object_item(object, string, false))
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_DetachItemFromObjectCaseSensitive(
    object: *mut cJSON,
    string: *const c_char,
) -> *mut cJSON
{
    detach_child(object, find_object_item(object, string, true))
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_DeleteItemFromObject(
    object: *mut cJSON,
    string: *const c_char,
)
{
    let item = cJSON_DetachItemFromObject(object, string);
    cJSON_Delete(item);
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_DeleteItemFromObjectCaseSensitive(
    object: *mut cJSON,
    string: *const c_char,
)
{
    let item = cJSON_DetachItemFromObjectCaseSensitive(object, string);
    cJSON_Delete(item);
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_InsertItemInArray(
    array: *mut cJSON,
    which: c_int,
    newitem: *mut cJSON,
) -> cJSON_bool
{
    if array.is_null() || newitem.is_null() {
        return 0;
    }

    if which <= 0 || (*array).child.is_null() {
        let first = (*array).child;
        (*newitem).next = first;
        (*newitem).prev = ptr::null_mut();
        if !first.is_null() {
            (*first).prev = newitem;
        }
        (*array).child = newitem;
        return 1;
    }

    let current = array_item_at(array, which);
    if current.is_null() {
        return append_child(array, newitem);
    }

    (*newitem).prev = (*current).prev;
    (*newitem).next = current;
    if !(*current).prev.is_null() {
        (*(*current).prev).next = newitem;
    }
    (*current).prev = newitem;
    1
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ReplaceItemViaPointer(
    parent: *mut cJSON,
    item: *mut cJSON,
    replacement: *mut cJSON,
) -> cJSON_bool
{
    replace_child(parent, item, replacement)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ReplaceItemInArray(
    array: *mut cJSON,
    which: c_int,
    newitem: *mut cJSON,
) -> cJSON_bool
{
    replace_child(array, array_item_at(array, which), newitem)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ReplaceItemInObject(
    object: *mut cJSON,
    string: *const c_char,
    newitem: *mut cJSON,
) -> cJSON_bool
{
    if !set_item_key(newitem, string, false) {
        return 0;
    }
    replace_child(object, find_object_item(object, string, false), newitem)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_ReplaceItemInObjectCaseSensitive(
    object: *mut cJSON,
    string: *const c_char,
    newitem: *mut cJSON,
) -> cJSON_bool
{
    if !set_item_key(newitem, string, false) {
        return 0;
    }
    replace_child(object, find_object_item(object, string, true), newitem)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Duplicate(
    item: *const cJSON,
    recurse: cJSON_bool,
) -> *mut cJSON
{
    duplicate_item(item, recurse != 0)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Compare(
    a: *const cJSON,
    b: *const cJSON,
    case_sensitive: cJSON_bool,
) -> cJSON_bool
{
    bool_to_cjson(compare_items(a, b, case_sensitive != 0))
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_Minify(_json: *mut c_char)
{
    let _ = LOCALES_ENABLED;
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddNullToObject(
    object: *mut cJSON,
    name: *const c_char,
) -> *mut cJSON
{
    let item = cJSON_CreateNull();
    if cJSON_AddItemToObject(object, name, item) == 0 {
        cJSON_Delete(item);
        return ptr::null_mut();
    }
    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddTrueToObject(
    object: *mut cJSON,
    name: *const c_char,
) -> *mut cJSON
{
    let item = cJSON_CreateTrue();
    if cJSON_AddItemToObject(object, name, item) == 0 {
        cJSON_Delete(item);
        return ptr::null_mut();
    }
    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddFalseToObject(
    object: *mut cJSON,
    name: *const c_char,
) -> *mut cJSON
{
    let item = cJSON_CreateFalse();
    if cJSON_AddItemToObject(object, name, item) == 0 {
        cJSON_Delete(item);
        return ptr::null_mut();
    }
    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddBoolToObject(
    object: *mut cJSON,
    name: *const c_char,
    boolean: cJSON_bool,
) -> *mut cJSON
{
    let item = cJSON_CreateBool(boolean);
    if cJSON_AddItemToObject(object, name, item) == 0 {
        cJSON_Delete(item);
        return ptr::null_mut();
    }
    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddNumberToObject(
    object: *mut cJSON,
    name: *const c_char,
    number: c_double,
) -> *mut cJSON
{
    let item = cJSON_CreateNumber(number);
    if cJSON_AddItemToObject(object, name, item) == 0 {
        cJSON_Delete(item);
        return ptr::null_mut();
    }
    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddStringToObject(
    object: *mut cJSON,
    name: *const c_char,
    string: *const c_char,
) -> *mut cJSON
{
    let item = cJSON_CreateString(string);
    if cJSON_AddItemToObject(object, name, item) == 0 {
        cJSON_Delete(item);
        return ptr::null_mut();
    }
    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddRawToObject(
    object: *mut cJSON,
    name: *const c_char,
    raw: *const c_char,
) -> *mut cJSON
{
    let item = cJSON_CreateRaw(raw);
    if cJSON_AddItemToObject(object, name, item) == 0 {
        cJSON_Delete(item);
        return ptr::null_mut();
    }
    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddObjectToObject(
    object: *mut cJSON,
    name: *const c_char,
) -> *mut cJSON
{
    let item = cJSON_CreateObject();
    if cJSON_AddItemToObject(object, name, item) == 0 {
        cJSON_Delete(item);
        return ptr::null_mut();
    }
    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_AddArrayToObject(
    object: *mut cJSON,
    name: *const c_char,
) -> *mut cJSON
{
    let item = cJSON_CreateArray();
    if cJSON_AddItemToObject(object, name, item) == 0 {
        cJSON_Delete(item);
        return ptr::null_mut();
    }
    item
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_SetNumberHelper(object: *mut cJSON, number: c_double) -> c_double
{
    if object.is_null() {
        return number;
    }

    (*object).valuedouble = number;
    (*object).valueint = number as c_int;
    number
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_SetValuestring(
    object: *mut cJSON,
    valuestring: *const c_char,
) -> *mut c_char
{
    if object.is_null() || ((*object).type_ & cJSON_String) == 0 {
        return ptr::null_mut();
    }

    if !(*object).valuestring.is_null() && ((*object).type_ & cJSON_IsReference) == 0 {
        free_raw((*object).valuestring as *mut c_void);
    }

    (*object).valuestring = duplicate_c_string(valuestring);
    (*object).type_ &= !cJSON_IsReference;
    (*object).valuestring
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_malloc(size: usize) -> *mut c_void
{
    allocate_raw(size)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_free(object: *mut c_void)
{
    free_raw(object);
}
