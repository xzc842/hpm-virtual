/*
 * MIT License
 *
 * Copyright (c) 2026 XueZicheng <xuezicheng842@outlook.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/*
 * 通用超声波虚拟设备。
 *
 * role = bidirectional：
 *   target_distance（inout）由 hpm-gui 输入，表示 3D 目标距离；
 *   distance（inout）由 3D 仿真的 virtual.gd 测量后写回；
 *   in_range / effective_distance（out）用于显示。
 *
 * 数据流：
 *   hpm-gui -> target_distance -> virtual.gd 移动目标并射线测量
 *            -> send("distance", 实测值) -> 本插件 -> $state
 */
#include <hpm/debug/plugin.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const HpmDebugHostApi* api;
    char name[64];
    char trig[64];
    char echo[64];
    int has_trig;
    int has_echo;
    uint32_t trig_level;
    double effective;
    double max_distance;
    double target_distance;
    double distance;
    int in_range;
    int has_state;
} UltrasonicCtx;

static void on_pin(UltrasonicCtx* ctx, const HpmDebugPinEvent* pin) {
    if (!ctx->has_trig || !pin->pin || strcmp(pin->pin, ctx->trig) != 0) return;
    const uint32_t value = pin->value ? 1u : 0u;
    if (ctx->has_echo && value == 1u && ctx->trig_level == 0u) {
        /* 先清掉上电默认高电平，只有近距才发一个 ECHO 脉冲。 */
        ctx->api->set_pin(ctx->api->host, ctx->echo, 0);
        if (ctx->distance < ctx->effective) {
            ctx->api->pulse_pin(ctx->api->host, ctx->echo, 1, 0, 1000000);
        }
    }
    ctx->trig_level = value;
}

static const char* find_key(const char* json, const char* key) {
    char pattern[96];
    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    const char* p = strstr(json, pattern);
    if (!p) return NULL;
    p += strlen(pattern);
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') ++p;
    if (*p != ':') return NULL;
    ++p;
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') ++p;
    return p;
}

static int get_string(const char* json, const char* key, char* out, size_t cap) {
    const char* p = find_key(json, key);
    if (!p || *p != '"') return -1;
    ++p;
    size_t i = 0;
    while (*p && *p != '"') {
        if (*p == '\\' && p[1]) ++p;
        if (i + 1 < cap) out[i++] = *p;
        ++p;
    }
    out[i] = '\0';
    return 0;
}

static double get_number(const char* json, const char* key, double fallback) {
    const char* p = find_key(json, key);
    if (!p) return fallback;
    if (*p == '"') ++p;
    return atof(p);
}

static double clamp(double value, double lo, double hi) {
    if (value < lo) return lo;
    if (value > hi) return hi;
    return value;
}

static void emit_ui(UltrasonicCtx* ctx) {
    char json[1280];
    snprintf(json, sizeof(json),
             "{\"$ui\":{\"schema\":\"hpm-ui/1\","
             "\"role\":\"bidirectional\",\"title\":\"超声波\","
             "\"description\":\"3D 仿真输入目标距离，virtual.gd 实测后回写\","
             "\"channels\":["
             "{\"id\":\"target_distance\",\"name\":\"目标距离\",\"direction\":\"inout\","
             "\"type\":\"number\",\"widget\":\"slider\",\"min\":2,\"max\":%.1f,"
             "\"unit\":\"cm\",\"default\":%.1f},"
             "{\"id\":\"distance\",\"name\":\"实测距离\",\"direction\":\"inout\","
             "\"type\":\"number\",\"widget\":\"value\",\"min\":0,\"max\":%.1f,"
             "\"unit\":\"cm\",\"readonly\":true},"
             "{\"id\":\"in_range\",\"name\":\"有效范围内\",\"direction\":\"out\","
             "\"type\":\"bool\",\"widget\":\"status\",\"readonly\":true},"
             "{\"id\":\"effective_distance\",\"name\":\"有效距离\",\"direction\":\"out\","
             "\"type\":\"number\",\"widget\":\"text\",\"min\":0,\"max\":%.1f,"
             "\"unit\":\"cm\",\"readonly\":true}],"
             "\"state\":{\"target_distance\":%.1f,\"distance\":%.1f,"
             "\"in_range\":%s,\"effective_distance\":%.1f},"
             "\"pins\":[],\"order\":30}}",
             ctx->max_distance, ctx->target_distance,
             ctx->max_distance, ctx->max_distance,
             ctx->target_distance, ctx->distance,
             ctx->in_range ? "true" : "false", ctx->effective);
    ctx->api->emit_json(ctx->api->host, json);
}

static void emit_state(UltrasonicCtx* ctx) {
    char json[384];
    snprintf(json, sizeof(json),
             "{\"$state\":{\"target_distance\":%.1f,\"distance\":%.1f,"
             "\"in_range\":%s,\"effective_distance\":%.1f}}",
             ctx->target_distance, ctx->distance,
             ctx->in_range ? "true" : "false", ctx->effective);
    ctx->api->emit_json(ctx->api->host, json);
}

static void emit_error(UltrasonicCtx* ctx, const char* code, const char* message,
                       const char* channel, int fatal) {
    char json[256];
    snprintf(json, sizeof(json),
             "{\"$error\":{\"code\":\"%s\",\"message\":\"%s\","
             "\"channel\":\"%s\",\"fatal\":%s}}",
             code, message, channel, fatal ? "true" : "false");
    ctx->api->emit_json(ctx->api->host, json);
}

static void handle_json(UltrasonicCtx* ctx, const char* text) {
    char cmd[32] = {0};
    if (get_string(text, "cmd", cmd, sizeof(cmd)) != 0) return;
    if (strcmp(cmd, "describe") == 0) {
        emit_ui(ctx);
        return;
    }
    if (strcmp(cmd, "get") == 0) {
        emit_state(ctx);
        return;
    }
    if (strcmp(cmd, "set") != 0) {
        if (strcmp(cmd, "invoke") == 0) {
            char channel[64] = {0};
            get_string(text, "channel", channel, sizeof(channel));
            emit_error(ctx, "unsupported", "no actions", channel, 0);
        }
        return;
    }

    char channel[64] = {0};
    get_string(text, "channel", channel, sizeof(channel));
    if (strcmp(channel, "target_distance") == 0) {
        double value = get_number(text, "value", ctx->target_distance);
        ctx->target_distance = clamp(value, 2.0, ctx->max_distance);
        ctx->in_range = ctx->distance < ctx->effective;
        if (ctx->has_echo) {
            ctx->api->set_pin(ctx->api->host, ctx->echo, 0);
        }
        emit_state(ctx);
        return;
    }
    if (strcmp(channel, "distance") == 0) {
        double value = get_number(text, "value", ctx->distance);
        ctx->distance = clamp(value, 0.0, ctx->max_distance);
        ctx->in_range = ctx->distance < ctx->effective;
        if (ctx->has_echo) {
            ctx->api->set_pin(ctx->api->host, ctx->echo, 0);
        }
        emit_state(ctx);
        return;
    }
    emit_error(ctx, "unknown_channel", "unknown channel", channel, 0);
}

uint32_t hpm_debug_abi_version(void) {
    return HPM_DEBUG_ABI_VERSION;
}

void* hpm_debug_create(const HpmDebugHostApi* api,
                       const HpmDebugDeviceInfo* info) {
    if (!api || !info) return NULL;
    UltrasonicCtx* ctx = (UltrasonicCtx*)calloc(1, sizeof(UltrasonicCtx));
    if (!ctx) return NULL;

    ctx->api = api;
    snprintf(ctx->name, sizeof(ctx->name), "%s",
             info->device ? info->device : "ultrasonic");
    ctx->effective = 30.0;
    ctx->max_distance = 400.0;
    ctx->target_distance = 100.0;
    ctx->distance = ctx->max_distance;
    ctx->in_range = 0;

    for (size_t i = 0; i < info->config_count; ++i) {
        const char* key = info->config[i].key;
        const char* value = info->config[i].value;
        if (!key || !value) continue;
        if (strcmp(key, "effective_distance") == 0) ctx->effective = atof(value);
        if (strcmp(key, "max_distance") == 0) ctx->max_distance = atof(value);
    }
    if (ctx->max_distance <= 0.0) ctx->max_distance = 400.0;
    if (ctx->effective <= 0.0 || ctx->effective > ctx->max_distance) {
        ctx->effective = 30.0;
    }
    ctx->target_distance = ctx->max_distance * 0.25;
    if (ctx->target_distance < 2.0) ctx->target_distance = 2.0;

    for (size_t i = 0; i < info->binding_count; ++i) {
        const char* key = info->bindings[i].key;
        const char* value = info->bindings[i].value;
        if (!key || !value) continue;
        if (strcmp(key, "trig") == 0) {
            snprintf(ctx->trig, sizeof(ctx->trig), "%s", value);
            ctx->has_trig = 1;
        } else if (strcmp(key, "echo") == 0) {
            snprintf(ctx->echo, sizeof(ctx->echo), "%s", value);
            ctx->has_echo = 1;
        }
    }
    if (ctx->has_trig) {
        uint32_t value = 0, function = 0, direction = 0;
        if (api->get_pin(api->host, ctx->trig, &value, &function,
                         &direction) == 0) {
            ctx->trig_level = value ? 1u : 0u;
        }
    }
    if (ctx->has_echo) {
        api->set_pin(api->host, ctx->echo, 0);
    } else {
        api->log(api->host, HPM_DEBUG_LOG_WARN,
                 "ultrasonic has no echo binding; firmware cannot measure");
    }

    emit_ui(ctx);
    emit_state(ctx);
    return ctx;
}

void hpm_debug_destroy(void* handle) {
    free(handle);
}

int hpm_debug_event(void* handle, const HpmDebugEvent* ev) {
    UltrasonicCtx* ctx = (UltrasonicCtx*)handle;
    if (!ctx || !ev) return -1;
    if (ev->type == HPM_DEBUG_EVENT_JSON && ev->u.json) {
        handle_json(ctx, ev->u.json);
    } else if (ev->type == HPM_DEBUG_EVENT_PIN) {
        on_pin(ctx, &ev->u.pin);
    }
    return 0;
}
