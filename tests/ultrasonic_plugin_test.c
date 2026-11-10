/*
 * Copyright (C) 2026 XueZicheng <xuezicheng842@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <hpm/debug/plugin.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static double g_target = -1.0;
static double g_distance = -1.0;
static int g_in_range = -1;
static char g_ui[2048];
static int g_errors = 0;

static void fake_log(void* host, int level, const char* message) {
    (void)host;
    if (level >= HPM_DEBUG_LOG_ERROR) {
        fprintf(stderr, "plugin error: %s\n", message);
        ++g_errors;
    }
}

static double number_after(const char* json, const char* key) {
    char pattern[64];
    snprintf(pattern, sizeof(pattern), "\"%s\":", key);
    const char* p = strstr(json, pattern);
    return p ? atof(p + strlen(pattern)) : -1.0;
}

static void fake_emit(void* host, const char* json) {
    (void)host;
    if (strstr(json, "$ui")) {
        snprintf(g_ui, sizeof(g_ui), "%s", json);
        return;
    }
    double target = number_after(json, "target_distance");
    double distance = number_after(json, "distance");
    if (target >= 0.0) g_target = target;
    if (distance >= 0.0) g_distance = distance;
    const char* range = strstr(json, "\"in_range\":");
    if (range) g_in_range = strncmp(range + 11, "true", 4) == 0;
}

static void send_json(HpmDebugEventFn event, void* ctx, const char* json) {
    HpmDebugEvent ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = HPM_DEBUG_EVENT_JSON;
    ev.u.json = json;
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

    HpmDebugKv config[] = {
        {"effective_distance", "30"},
        {"max_distance", "400"},
    };
    HpmDebugDeviceInfo info;
    memset(&info, 0, sizeof(info));
    info.device = "sonar";
    info.driver = "ultrasonic";
    info.config = config;
    info.config_count = 2;

    check(hpm_debug_abi_version() == HPM_DEBUG_ABI_VERSION, "ABI version");
    void* ctx = hpm_debug_create(&api, &info);
    check(ctx != NULL, "create ultrasonic context");
    if (!ctx) return 1;
    check(strstr(g_ui, "\"role\":\"bidirectional\"") != NULL, "注册双向设备");
    check(strstr(g_ui, "\"target_distance\"") != NULL, "声明目标距离输入");
    check(strstr(g_ui, "\"distance\"") != NULL, "声明实测距离回写");

    send_json(hpm_debug_event, ctx, "{\"cmd\":\"set\",\"channel\":\"target_distance\",\"value\":25}");
    check(fabs(g_target - 25.0) < 0.01, "输入更新目标距离");
    check(g_in_range == 0, "初始不在有效范围");

    send_json(hpm_debug_event, ctx, "{\"cmd\":\"set\",\"channel\":\"distance\",\"value\":10}");
    check(fabs(g_distance - 10.0) < 0.01, "3D 实测值回写距离");
    check(g_in_range == 1, "实测值进入有效范围");

    send_json(hpm_debug_event, ctx, "{\"cmd\":\"set\",\"channel\":\"distance\",\"value\":80}");
    check(g_in_range == 0, "实测值离开有效范围");

    hpm_debug_destroy(ctx);
    printf("ULTRASONIC PLUGIN: %s\n", g_errors == 0 ? "ok" : "failed");
    return g_errors == 0 ? 0 : 1;
}
