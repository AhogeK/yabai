TEST_FUNC(fast_focus_input_gate_accepts,
{
    uint64_t last_input_ns = 0;

    TEST_CHECK(fast_focus_input_gate_accepts(1000000000ULL, &last_input_ns), true);
    TEST_CHECK(fast_focus_input_gate_accepts(1010000000ULL, &last_input_ns), false);
    TEST_CHECK(fast_focus_input_gate_accepts(1051000000ULL, &last_input_ns), true);
});

TEST_FUNC(fast_focus_choose_window,
{
    struct window focused = { .id = 1 };
    struct window fallback = { .id = 2 };

    TEST_CHECK(fast_focus_choose_window(&focused, &fallback) == &focused, true);
    TEST_CHECK(fast_focus_choose_window(NULL, &fallback) == &fallback, true);
    TEST_CHECK(fast_focus_choose_window(NULL, NULL) == NULL, true);
});
