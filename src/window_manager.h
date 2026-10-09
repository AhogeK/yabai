#ifndef WINDOW_MANAGER_H
#define WINDOW_MANAGER_H

#define kCPSAllWindows    0x100
#define kCPSUserGenerated 0x200
#define kCPSNoWindows     0x400

enum window_op_error
{
    WINDOW_OP_ERROR_SUCCESS,
    WINDOW_OP_ERROR_INVALID_SRC_VIEW,
    WINDOW_OP_ERROR_INVALID_SRC_NODE,
    WINDOW_OP_ERROR_INVALID_DST_VIEW,
    WINDOW_OP_ERROR_INVALID_DST_NODE,
    WINDOW_OP_ERROR_INVALID_OPERATION,
    WINDOW_OP_ERROR_SAME_WINDOW,
    WINDOW_OP_ERROR_CANT_MINIMIZE,
    WINDOW_OP_ERROR_ALREADY_MINIMIZED,
    WINDOW_OP_ERROR_MINIMIZE_FAILED,
    WINDOW_OP_ERROR_NOT_MINIMIZED,
    WINDOW_OP_ERROR_DEMINIMIZE_FAILED,
    WINDOW_OP_ERROR_MAX_STACK,
    WINDOW_OP_ERROR_SAME_STACK,
};

enum purify_mode
{
    PURIFY_DISABLED,
    PURIFY_MANAGED,
    PURIFY_ALWAYS
};

static const char *purify_mode_str[] =
{
    "on",
    "float",
    "off"
};

enum ffm_mode
{
    FFM_DISABLED,
    FFM_AUTOFOCUS,
    FFM_AUTORAISE
};

static const char *ffm_mode_str[] =
{
    "disabled",
    "autofocus",
    "autoraise"
};

enum window_origin_mode
{
    WINDOW_ORIGIN_DEFAULT,
    WINDOW_ORIGIN_FOCUSED,
    WINDOW_ORIGIN_CURSOR
};

static const char *window_origin_mode_str[] =
{
    "default",
    "focused",
    "cursor"
};

struct scratchpad
{
    char *label;
    struct window *window;
};

// Fullscreen-restore memory.
//
// Entering a native fullscreen space makes macOS move the window into a space of its own;
// when that space goes away the system drops the window back onto the display's *first*
// user space instead of the one it came from (macOS 27.0.1, see docs/plans). We remember
// where the window came from (and which side of its split it occupied) so it can be put
// back. Entries are short-lived: they are dropped on restore, on window destruction, when
// the source space disappears, or by the oldest-first cap below.
struct fullscreen_restore_entry {
    uint32_t window_id;
    uint32_t neighbour_id;   // the other window in the source view (0 when not exactly one)
    uint64_t src_sid;        // user space the window came from
    uint8_t  was_after;      // 1 when the window sat right/below of neighbour_id
};

#define FULLSCREEN_RESTORE_MAX 8

// Rolling geometry memory.
//
// The side a window occupies cannot be recovered once it has left its view, and
// window->windowed_frame is only maintained by yabai's *own* fullscreen toggle (not by the
// system's native fullscreen, which is what the video-call case uses). So the geometry is
// recorded while the window is still sitting in a user space: source space, sibling window
// and side. Entering fullscreen copies the record into the restore entry above.
struct window_geometry_memory {
    uint32_t window_id;
    uint32_t neighbour_id;
    uint64_t sid;
    uint8_t  was_after;
};

#define GEOMETRY_MEMORY_MAX 16

struct window_manager
{
    AXUIElementRef system_element;
    struct table application;
    struct table window;
    struct table managed_window;
    struct table window_lost_focused_event;
    struct table application_lost_front_switched_event;
    struct table window_animations_table;
    struct table insert_feedback;
    pthread_mutex_t window_animations_lock;
    struct rule *rules;
    struct application **applications_to_refresh;
    uint32_t focused_window_id;
    ProcessSerialNumber focused_window_psn;
    uint32_t last_window_id;
    bool enable_mff;
    enum ffm_mode ffm_mode;
    enum purify_mode purify_mode;
    enum window_origin_mode window_origin_mode;
    bool enable_window_opacity;
    float menubar_opacity;
    float active_window_opacity;
    float normal_window_opacity;
    float window_opacity_duration;
    float window_animation_duration;
    int window_animation_easing;
    struct rgba_color insert_feedback_color;
    struct scratchpad *scratchpad_window;

    struct fullscreen_restore_entry fullscreen_restore[FULLSCREEN_RESTORE_MAX];
    int fullscreen_restore_count;
    // A native fullscreen transition reports the space change before the window shows up in
    // that space's window list, so remember the pair and retry on later window events.
    uint64_t pending_fullscreen_sid;
    uint64_t pending_fullscreen_src_sid;
    // The view follows the restored window with a single switch, made only once the space churn
    // of the exit has settled. Switching during that churn - or re-asserting after it - produces a
    // visible back-and-forth with whatever else is switching spaces, so the switch is deferred
    // while space changes keep arriving, dropped if anything else switches spaces, and never
    // repeated.
    uint64_t view_follow_sid;
    uint32_t view_follow_window_id;
    int view_follow_generation;
    bool view_follow_abort;
    struct window_geometry_memory geometry_memory[GEOMETRY_MEMORY_MAX];
    int geometry_memory_count;
};

void window_manager_query_window_rules(FILE *rsp);
void window_manager_query_windows_for_spaces(FILE *rsp, uint64_t *space_list, int space_count, uint64_t flags);
void window_manager_query_windows_for_display(FILE *rsp, uint32_t did, uint64_t flags);
void window_manager_query_windows_for_displays(FILE *rsp, uint64_t flags);
bool window_manager_rule_matches_window(struct rule *rule, struct window *window, char *window_title, char *window_role, char *window_subrole);
void window_manager_apply_manage_rule_effects_to_window(struct space_manager *sm, struct window_manager *wm, struct window *window, struct rule_effects *effects);
void window_manager_apply_rule_effects_to_window(struct space_manager *sm, struct window_manager *wm, struct window *window, struct rule_effects *effects);
void window_manager_apply_manage_rules_to_window(struct space_manager *sm, struct window_manager *wm, struct window *window, char *window_title, char *window_role, char *window_subrole, bool one_shot_rules);
void window_manager_apply_rules_to_window(struct space_manager *sm, struct window_manager *wm, struct window *window, char *window_title, char *window_role, char *window_subrole, bool one_shot_rules);
void window_manager_center_mouse(struct window_manager *wm, struct window *window);
bool window_manager_is_window_eligible(struct window *window);
bool window_manager_should_manage_window(struct window *window);
void window_manager_tile_window(struct window_manager *wm, struct window *window);
void window_manager_move_window(struct window *window, float x, float y);
void window_manager_resize_window(struct window *window, float width, float height);
enum window_op_error window_manager_adjust_window_ratio(struct window_manager *wm, struct window *window, int action, float ratio);
void window_manager_animate_window(struct window_capture capture);
void window_manager_animate_window_list(struct window_capture *window_list, int window_count);
void window_manager_set_window_frame(struct window *window, float x, float y, float width, float height);
int window_manager_find_rank_of_window_in_list(uint32_t wid, uint32_t *window_list, int window_count);
struct window *window_manager_find_window_on_space_by_rank_filtering_window(struct window_manager *wm, uint64_t sid, int rank, uint32_t filter_wid);
struct window *window_manager_find_window_at_point_filtering_window(struct window_manager *wm, CGPoint point, uint32_t filter_wid);
struct window *window_manager_find_window_at_point(struct window_manager *wm, CGPoint point);
struct window *window_manager_find_window_below_cursor(struct window_manager *wm);
struct window *window_manager_find_closest_managed_window_in_direction(struct window_manager *wm, struct window *window, int direction);
struct window *window_manager_find_prev_managed_window(struct space_manager *sm, struct window_manager *wm, struct window *window);
struct window *window_manager_find_next_managed_window(struct space_manager *sm, struct window_manager *wm, struct window *window);
struct window *window_manager_find_first_managed_window(struct space_manager *sm, struct window_manager *wm);
struct window *window_manager_find_last_managed_window(struct space_manager *sm, struct window_manager *wm);
struct window *window_manager_find_recent_managed_window(struct window_manager *wm);
struct window *window_manager_find_prev_window_in_stack(struct space_manager *sm, struct window_manager *wm, struct window *window);
struct window *window_manager_find_next_window_in_stack(struct space_manager *sm, struct window_manager *wm, struct window *window);
struct window *window_manager_find_first_window_in_stack(struct space_manager *sm, struct window_manager *wm, struct window *window);
struct window *window_manager_find_last_window_in_stack(struct space_manager *sm, struct window_manager *wm, struct window *window);
struct window *window_manager_find_recent_window_in_stack(struct space_manager *sm, struct window_manager *wm, struct window *window);
struct window *window_manager_find_window_in_stack(struct space_manager *sm, struct window_manager *wm, struct window *window, int index);
struct window *window_manager_find_largest_managed_window(struct space_manager *sm, struct window_manager *wm);
struct window *window_manager_find_smallest_managed_window(struct space_manager *sm, struct window_manager *wm);
struct window *window_manager_find_sibling_for_managed_window(struct window_manager *wm, struct window *window);
struct window *window_manager_find_first_nephew_for_managed_window(struct window_manager *wm, struct window *window);
struct window *window_manager_find_second_nephew_for_managed_window(struct window_manager *wm, struct window *window);
struct window *window_manager_find_uncle_for_managed_window(struct window_manager *wm, struct window *window);
struct window *window_manager_find_first_cousin_for_managed_window(struct window_manager *wm, struct window *window);
struct window *window_manager_find_second_cousin_for_managed_window(struct window_manager *wm, struct window *window);
void window_manager_focus_window_without_raise(ProcessSerialNumber *window_psn, uint32_t window_id);
void window_manager_focus_window_with_raise(ProcessSerialNumber *window_psn, uint32_t window_id, AXUIElementRef window_ref);
struct window *window_manager_focused_window(struct window_manager *wm);
struct application *window_manager_focused_application(struct window_manager *wm);
struct view *window_manager_find_managed_window(struct window_manager *wm, struct window *window);
void window_manager_remove_managed_window(struct window_manager *wm, uint32_t wid);
void window_manager_add_managed_window(struct window_manager *wm, struct window *window, struct view *view);
bool window_manager_find_lost_front_switched_event(struct window_manager *wm, pid_t pid);
void window_manager_remove_lost_front_switched_event(struct window_manager *wm, pid_t pid);
void window_manager_add_lost_front_switched_event(struct window_manager *wm, pid_t pid);
bool window_manager_find_lost_focused_event(struct window_manager *wm, uint32_t window_id);
void window_manager_remove_lost_focused_event(struct window_manager *wm, uint32_t window_id);
void window_manager_add_lost_focused_event(struct window_manager *wm, uint32_t window_id);
struct window *window_manager_find_window(struct window_manager *wm, uint32_t window_id);
void window_manager_remove_window(struct window_manager *wm, uint32_t window_id);
void window_manager_add_window(struct window_manager *wm, struct window *window);
struct application *window_manager_find_application(struct window_manager *wm, pid_t pid);
void window_manager_remove_application(struct window_manager *wm, pid_t pid);
void window_manager_add_application(struct window_manager *wm, struct application *application);
struct window **window_manager_find_application_windows(struct window_manager *wm, struct application *application, int *window_count);
enum window_op_error window_manager_move_window_relative(struct window_manager *wm, struct window *window, int type, float dx, float dy);
void window_manager_resize_window_relative_internal(struct window *window, CGRect frame, int direction, float dx, float dy, bool animate);
enum window_op_error window_manager_resize_window_relative(struct window_manager *wm, struct window *window, int direction, float dx, float dy, bool animate);
void window_manager_set_purify_mode(struct window_manager *wm, enum purify_mode mode);
void window_manager_set_menubar_opacity(struct window_manager *wm, float opacity);
void window_manager_set_active_window_opacity(struct window_manager *wm, float opacity);
void window_manager_set_normal_window_opacity(struct window_manager *wm, float opacity);
void window_manager_set_window_opacity_enabled(struct window_manager *wm, bool enabled);
bool window_manager_set_opacity(struct window_manager *wm, struct window *window, float opacity);
void window_manager_set_window_opacity(struct window_manager *wm, struct window *window, float opacity);
void window_manager_set_focus_follows_mouse(struct window_manager *wm, enum ffm_mode mode);
enum window_op_error window_manager_set_window_insertion(struct space_manager *sm, struct window *window, int direction);
enum window_op_error window_manager_stack_window(struct space_manager *sm, struct window_manager *wm, struct window *a, struct window *b);
enum window_op_error window_manager_warp_window(struct space_manager *sm, struct window_manager *wm, struct window *a, struct window *b);
enum window_op_error window_manager_swap_window(struct space_manager *sm, struct window_manager *wm, struct window *a, struct window *b);
enum window_op_error window_manager_minimize_window(struct window *window);
enum window_op_error window_manager_deminimize_window(struct window *window);
bool window_manager_close_window(struct window *window);
void window_manager_send_window_to_space(struct space_manager *sm, struct window_manager *wm, struct window *window, uint64_t sid, bool moved_by_rule);
struct window *window_manager_create_and_add_window(struct space_manager *sm, struct window_manager *wm, struct application *application, AXUIElementRef window_ref, uint32_t window_id, bool one_shot_rules);
struct window **window_manager_add_application_windows(struct space_manager *sm, struct window_manager *wm, struct application *application, int *count);
bool window_manager_add_existing_application_windows(struct space_manager *sm, struct window_manager *wm, struct application *application, int refresh_index);
enum window_op_error window_manager_apply_grid(struct space_manager *sm, struct window_manager *wm, struct window *window, unsigned r, unsigned c, unsigned x, unsigned y, unsigned w, unsigned h);
void window_manager_purify_window(struct window_manager *wm, struct window *window);
void window_manager_make_window_floating(struct space_manager *sm, struct window_manager *wm, struct window *window, bool should_float, bool force);
void window_manager_make_window_sticky(struct space_manager *sm, struct window_manager *wm, struct window *window, bool should_sticky);
void window_manager_adjust_layer(struct window *window, int layer);
bool window_manager_set_window_layer(struct window *window, int layer);
void window_manager_toggle_window_shadow(struct window *window);
void window_manager_toggle_window_zoom_parent(struct window_manager *wm, struct window *window);
void window_manager_toggle_window_zoom_fullscreen(struct window_manager *wm, struct window *window);
void window_manager_toggle_window_windowed_fullscreen(struct window *window);
void window_manager_toggle_window_native_fullscreen(struct window *window);
void window_manager_toggle_window_expose(struct window *window);
void window_manager_toggle_window_pip(struct space_manager *sm, struct window *window);
bool window_manager_toggle_scratchpad_window_by_label(struct window_manager *wm, char *label);
bool window_manager_toggle_scratchpad_window(struct window_manager *wm, struct window *window, int forced_mode);
bool window_manager_set_scratchpad_for_window(struct window_manager *wm, struct window *window, char *label);
bool window_manager_remove_scratchpad_for_window(struct window_manager *wm, struct window *window, bool unfloat);
void window_manager_scratchpad_recover_windows(void);
void window_manager_wait_for_native_fullscreen_transition(struct window *window);
void window_manager_validate_and_check_for_windows_on_space(struct space_manager *sm, struct window_manager *wm, uint64_t sid);
void window_manager_correct_for_mission_control_changes(struct space_manager *sm, struct window_manager *wm);
void window_manager_handle_display_add_and_remove(struct space_manager *sm, struct window_manager *wm, uint32_t did);
void window_manager_begin(struct space_manager *sm, struct window_manager *wm);
void window_manager_init(struct window_manager *wm);
void window_manager_note_fullscreen_entry(struct window_manager *wm, uint64_t fullscreen_sid, uint64_t src_sid);
void window_manager_remember_geometry(struct space_manager *sm, struct window_manager *wm, uint64_t sid);
void window_manager_restore_fullscreen_entries(struct space_manager *sm, struct window_manager *wm);
void window_manager_retry_fullscreen_entry(struct window_manager *wm);
void window_manager_arm_view_follow(struct window_manager *wm, uint64_t sid, uint32_t window_id);
void window_manager_view_follow_on_space_change(struct window_manager *wm, uint64_t new_sid);
void window_manager_abort_view_follow(struct window_manager *wm);
void window_manager_view_follow_fire(struct window_manager *wm, int generation);
void window_manager_view_follow_focus_window(struct window_manager *wm, uint32_t window_id);
void window_manager_view_follow_window(struct window_manager *wm, uint32_t window_id);

// Fallback, used only when nothing switches the view at all after a restore: the single switch is
// normally made the moment the exit's own space change lands.
#define VIEW_FOLLOW_FALLBACK_SECONDS 0.4f
// The system takes a moment to finish the space switch; focusing the window right away would be
// dropped while the display is animating (the same reason the signal scripts sleep before it).
#define VIEW_FOLLOW_FOCUS_DELAY_SECONDS 0.15f
void window_manager_forget_fullscreen_entry(struct window_manager *wm, uint32_t window_id);
void window_manager_forget_fullscreen_entries_on_space(struct window_manager *wm, uint64_t sid);

#endif
