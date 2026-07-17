#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &str| {
    _ = parse::parse(data, "fuzz.pen");
    _ = parse::parse_comments(data, "fuzz.pen");
});
