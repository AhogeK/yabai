TEST_FUNC(window_is_visible,
{
    TEST_CHECK(window_is_visible(true,  false, false, false, true),  true);
    TEST_CHECK(window_is_visible(false, false, false, false, true),  false);
    TEST_CHECK(window_is_visible(true,  true,  false, false, true),  false);
    TEST_CHECK(window_is_visible(true,  false, true,  false, true),  false);
    TEST_CHECK(window_is_visible(true,  false, false, true,  false), true);
    TEST_CHECK(window_is_visible(true,  false, false, false, false), false);
    TEST_CHECK(window_is_visible(true,  true,  false, true,  false), false);
    TEST_CHECK(window_is_visible(true,  false, true,  true,  false), false);
});

TEST_FUNC(window_is_sticky_effective,
{
    struct window window = {0};
    window.id = 1;
    window.flags = WINDOW_STICKY;

    TEST_CHECK(window_is_sticky_effective(&window), true);
});
