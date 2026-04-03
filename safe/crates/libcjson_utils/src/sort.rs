use std::cmp::Ordering;
use std::ptr;

use crate::{cJSON, compare_strings};

pub(crate) unsafe fn sort_object(object: *mut cJSON, case_sensitive: bool) {
    let mut current = if object.is_null() {
        ptr::null_mut()
    } else {
        (*object).child
    };
    let mut entries: Vec<*mut cJSON> = Vec::new();
    let mut index = 0usize;

    if object.is_null() {
        return;
    }

    while !current.is_null() {
        entries.push(current);
        current = (*current).next;
    }

    if entries.len() < 2 {
        return;
    }

    let already_sorted = entries.windows(2).all(|window| {
        compare_strings((*window[0]).string, (*window[1]).string, case_sensitive) < 0
    });
    if already_sorted {
        return;
    }

    entries.sort_by(|left, right| {
        let diff = unsafe { compare_strings((**left).string, (**right).string, case_sensitive) };
        if diff < 0 {
            Ordering::Less
        } else if diff > 0 {
            Ordering::Greater
        } else {
            Ordering::Equal
        }
    });

    let last_index = entries.len() - 1;
    while index < entries.len() {
        (*entries[index]).next = if index + 1 < entries.len() {
            entries[index + 1]
        } else {
            ptr::null_mut()
        };
        (*entries[index]).prev = if index == 0 {
            entries[last_index]
        } else {
            entries[index - 1]
        };
        index += 1;
    }

    (*object).child = entries[0];
}
