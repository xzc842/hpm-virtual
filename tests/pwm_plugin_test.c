#include <hpm/debug/plugin.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static double g_angle = -1.0;
static double g_duty = -1.0;
static int g_errors = 0;

static void fake_log(void* host, int level, const char* message) {
    (void)host;
    if (level >= HPM_DEBUG_LOG_ERROR) {
        fprintf(stderr, "plugin error: %s\n", message);
        ++g_errors;
    }
}

static void fake_emit(void* host, const char* json) {
    (void)host;
    const char* a = strstr(json, "\"angle\":");
    if (a) g_angle = atof(a + 8);
    const char* d = strstr(json, "\"duty_pct\":");
    if (d) g_duty = atof(d + 11);
}

static int fake_get_pin(void* host, const char* pin, uint32_t* value,
                        uint32_t* function, uint32_t* direction) {
    (void)host;
    if (strcmp(pin, "P1.0") != 0) return -1;
    if (value) *value = 0;
    if (function) *function = 0;
    if (direction) *direction = 0;
    return 0;
}

static HpmDebugKv g_bindings[] = {
    {"pin", "P1.0"},
};
static HpmDebugKv g_config[] = {
    {"freq_hz", "50"},
    {"min_duty", "5"},
    {"max_duty", "10"},
};

static void feed(HpmDebugEventFn event, void* ctx, uint64_t time, uint32_t value) {
    HpmDebugEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = HPM_DEBUG_EVENT_PIN;
    ev.u.pin.time = time;
    ev.u.pin.pin = "P1.0";
    ev.u.pin.value = value;
    ev.u.pin.changed = 1;
    event(ctx, &ev);
}

static void check(int condition, const char* message) {
    if (condition) {
        printf("  ok   %s\n", message);
    } else {
        printf("  FAIL %s\n", message);
        ++g_errors;
    }
}

int main(void) {
    HpmDebugHostApi api;
    memset(&api, 0, sizeof(api));
    api.abi_version = HPM_DEBUG_ABI_VERSION;
    api.log = fake_log;
    api.emit_json = fake_emit;
    api.get_pin = fake_get_pin;

    HpmDebugDeviceInfo info;
    memset(&info, 0, sizeof(info));
    info.device = "servo";
    info.driver = "pwm";
    info.bindings = g_bindings;
    info.binding_count = 1;
    info.config = g_config;
    info.config_count = 3;

    check(hpm_debug_abi_version() == HPM_DEBUG_ABI_VERSION, "ABI version");
    void* ctx = hpm_debug_create(&api, &info);
    check(ctx != NULL, "create servo context");
    if (!ctx) return 1;
    check(fabs(g_angle - 90.0) < 0.01, "initial angle 90");

    /* 50Hz, 1ms pulse => 0deg */
    feed(hpm_debug_event, ctx, 1000, 1);
    feed(hpm_debug_event, ctx, 2000, 0);
    feed(hpm_debug_event, ctx, 21000, 1);
    feed(hpm_debug_event, ctx, 22000, 0);
    feed(hpm_debug_event, ctx, 41000, 1);
    feed(hpm_debug_event, ctx, 42000, 0);
    check(fabs(g_angle - 0.0) < 0.6, "1ms pulse -> 0deg");
    check(fabs(g_duty - 5.0) < 0.2, "duty 5%");

    /* 1.5ms pulse => 90deg */
    feed(hpm_debug_event, ctx, 61000, 1);
    feed(hpm_debug_event, ctx, 62500, 0);
    feed(hpm_debug_event, ctx, 81000, 1);
    feed(hpm_debug_event, ctx, 82500, 0);
    check(fabs(g_angle - 90.0) < 0.6, "1.5ms pulse -> 90deg");

    /* 2ms pulse => 180deg */
    feed(hpm_debug_event, ctx, 101000, 1);
    feed(hpm_debug_event, ctx, 103000, 0);
    feed(hpm_debug_event, ctx, 121000, 1);
    feed(hpm_debug_event, ctx, 123000, 0);
    check(fabs(g_angle - 180.0) < 0.6, "2ms pulse -> 180deg");
    check(fabs(g_duty - 10.0) < 0.2, "duty 10%");

    hpm_debug_destroy(ctx);
    printf("PWM PLUGIN: %s\n", g_errors == 0 ? "ok" : "failed");
    return g_errors == 0 ? 0 : 1;
}
