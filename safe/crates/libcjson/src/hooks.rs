use std::ffi::CStr;
use std::mem;
use std::os::raw::{c_char, c_void};
use std::ptr;

use crate::abi::{cJSON, cJSON_Hooks, free_fn, malloc_fn, realloc_fn};

extern "C" {
    fn malloc(size: usize) -> *mut c_void;
    fn free(pointer: *mut c_void);
    fn realloc(pointer: *mut c_void, size: usize) -> *mut c_void;
}

#[derive(Clone, Copy)]
pub struct InternalHooks {
    pub allocate: malloc_fn,
    pub deallocate: free_fn,
    #[allow(dead_code)]
    pub reallocate: Option<realloc_fn>,
}

unsafe extern "C" fn internal_malloc(size: usize) -> *mut c_void {
    malloc(size)
}

unsafe extern "C" fn internal_free(pointer: *mut c_void) {
    free(pointer);
}

unsafe extern "C" fn internal_realloc(pointer: *mut c_void, size: usize) -> *mut c_void {
    realloc(pointer, size)
}

impl InternalHooks {
    pub const fn system() -> Self {
        Self {
            allocate: internal_malloc,
            deallocate: internal_free,
            reallocate: Some(internal_realloc),
        }
    }
}

static mut GLOBAL_HOOKS: InternalHooks = InternalHooks::system();

pub unsafe fn current_hooks() -> InternalHooks {
    GLOBAL_HOOKS
}

pub unsafe fn allocate(size: usize) -> *mut c_void {
    let hooks = current_hooks();
    (hooks.allocate)(size)
}

pub unsafe fn deallocate(pointer: *mut c_void) {
    let hooks: InternalHooks;

    if pointer.is_null() {
        return;
    }

    hooks = current_hooks();
    (hooks.deallocate)(pointer);
}

pub unsafe fn duplicate_c_string(string: *const c_char) -> *mut c_char {
    if string.is_null() {
        return ptr::null_mut();
    }

    duplicate_bytes_with_hooks(CStr::from_ptr(string).to_bytes(), &current_hooks())
}

pub unsafe fn new_item() -> *mut cJSON {
    new_item_with_hooks(&current_hooks())
}

pub unsafe fn allocate_with_hooks(hooks: &InternalHooks, size: usize) -> *mut c_void {
    (hooks.allocate)(size)
}

pub unsafe fn deallocate_with_hooks(hooks: &InternalHooks, pointer: *mut c_void) {
    if pointer.is_null() {
        return;
    }

    (hooks.deallocate)(pointer);
}

pub unsafe fn duplicate_bytes_with_hooks(bytes: &[u8], hooks: &InternalHooks) -> *mut c_char {
    let copy = allocate_with_hooks(hooks, bytes.len() + 1) as *mut c_char;
    if copy.is_null() {
        return ptr::null_mut();
    }

    ptr::copy_nonoverlapping(bytes.as_ptr() as *const c_char, copy, bytes.len());
    *copy.add(bytes.len()) = 0;

    copy
}

pub unsafe fn new_item_with_hooks(hooks: &InternalHooks) -> *mut cJSON {
    let node = allocate_with_hooks(hooks, mem::size_of::<cJSON>()) as *mut cJSON;
    if !node.is_null() {
        ptr::write_bytes(node, 0, 1);
    }

    node
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_InitHooks(hooks: *mut cJSON_Hooks) {
    if hooks.is_null() {
        GLOBAL_HOOKS = InternalHooks::system();
        return;
    }

    GLOBAL_HOOKS = InternalHooks {
        allocate: (*hooks).malloc_fn.unwrap_or(internal_malloc),
        deallocate: (*hooks).free_fn.unwrap_or(internal_free),
        reallocate: if (*hooks).malloc_fn.is_none() && (*hooks).free_fn.is_none() {
            Some(internal_realloc)
        } else {
            None
        },
    };
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_malloc(size: usize) -> *mut c_void {
    allocate(size)
}

#[no_mangle]
pub unsafe extern "C" fn cJSON_free(object: *mut c_void) {
    deallocate(object);
}
