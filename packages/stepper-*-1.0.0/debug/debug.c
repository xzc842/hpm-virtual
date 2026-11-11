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

/* 步进电机：STEP 上升沿累计角度，DIR 决定方向。 */
#include <hpm/debug/plugin.h>

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const HpmDebugHostApi* api;
    char name[64];
    char step_pin[64];
    char dir_pin[64];
    uint32_t step_level;
    double step_angle;
    double angle;
    int direction;
} StepperCtx;

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

static int pin_eq(const char* a, const char* b) {
    while (*a || *b) {
        while (*a == '.' || *a == '_' || *a == ' ') ++a;
        while (*b == '.' || *b == '_' || *b == ' ') ++b;
        if (*a != *b) return 0;
        if (*a) { ++a; ++b; }
    }
    return 1;
}

static void emit_ui(StepperCtx* ctx) {
    char json[768];
    snprintf(json, sizeof(json),
             "{\"$ui\":{\"schema\":\"hpm-ui/1\",\"role\":\"output\","
             "\"title\":\"步进电机\",\"description\":\"STEP/DIR wheel\","
             "\"channels\":["
             "{\"id\":\"angle\",\"name\":\"角度\",\"direction\":\"out\","
             "\"type\":\"number\",\"widget\":\"value\",\"unit\":\"deg\","
             "\"readonly\":true},"
             "{\"id\":\"direction\",\"name\":\"方向\",\"direction\":\"out\","
             "\"type\":\"number\",\"widget\":\"value\",\"readonly\":true}],"
             "\"state\":{\"angle\":%.2f,\"direction\":%d},"
             "\"pins\":[\"%s\",\"%s\"],\"order\":40}}",
             ctx->angle, ctx->direction, ctx->step_pin, ctx->dir_pin);
    ctx->api->emit_json(ctx->api->host, json);
}

static void emit_state(StepperCtx* ctx) {
    char json[128];
    snprintf(json, sizeof(json),
             "{\"$state\":{\"angle\":%.2f,\"direction\":%d}}",
             ctx->angle, ctx->direction);
    ctx->api->emit_json(ctx->api->host, json);
}

static void emit_error(StepperCtx* ctx, const char* code, const char* message,
                       const char* channel) {
    char json[256];
    snprintf(json, sizeof(json),
             "{\"$error\":{\"code\":\"%s\",\"message\":\"%s\","
             "\"channel\":\"%s\",\"fatal\":false}}",
             code, message, channel);
    ctx->api->emit_json(ctx->api->host, json);
}

static void handle_json(StepperCtx* ctx, const char* text) {
    char cmd[32] = {0};
    if (get_string(text, "cmd", cmd, sizeof(cmd)) != 0) return;
    if (strcmp(cmd, "describe") == 0) {
        emit_ui(ctx);
    } else if (strcmp(cmd, "get") == 0) {
        emit_state(ctx);
    } else if (strcmp(cmd, "set") == 0 || strcmp(cmd, "invoke") == 0) {
        char channel[64] = {0};
        get_string(text, "channel", channel, sizeof(channel));
        emit_error(ctx, "readonly", "stepper is output-only", channel);
    }
}

uint32_t hpm_debug_abi_version(void) {
    return HPM_DEBUG_ABI_VERSION;
}

void* hpm_debug_create(const HpmDebugHostApi* api,
                       const HpmDebugDeviceInfo* info) {
    if (!api || !info) return NULL;
    StepperCtx* ctx = (StepperCtx*)calloc(1, sizeof(StepperCtx));
    if (!ctx) return NULL;
    ctx->api = api;
    snprintf(ctx->name, sizeof(ctx->name), "%s",
             info->device ? info->device : "stepper");
    ctx->step_angle = 1.8;
    ctx->direction = 1;

    for (size_t i = 0; i < info->config_count; ++i) {
        if (info->config[i].key && info->config[i].value &&
            strcmp(info->config[i].key, "step_angle") == 0) {
            ctx->step_angle = atof(info->config[i].value);
        }
    }
    for (size_t i = 0; i < info->binding_count; ++i) {
        const char* key = info->bindings[i].key;
        const char* value = info->bindings[i].value;
        if (!key || !value) continue;
        if (strcmp(key, "step") == 0) {
            snprintf(ctx->step_pin, sizeof(ctx->step_pin), "%s", value);
        } else if (strcmp(key, "dir") == 0) {
            snprintf(ctx->dir_pin, sizeof(ctx->dir_pin), "%s", value);
        }
    }
    emit_ui(ctx);
    emit_state(ctx);
    return ctx;
}

void hpm_debug_destroy(void* handle) {
    free(handle);
}

int hpm_debug_event(void* handle, const HpmDebugEvent* ev) {
    StepperCtx* ctx = (StepperCtx*)handle;
    if (!ctx || !ev) return -1;
    if (ev->type == HPM_DEBUG_EVENT_JSON && ev->u.json) {
        handle_json(ctx, ev->u.json);
        return 0;
    }
    if (ev->type != HPM_DEBUG_EVENT_PIN) return 0;
    const HpmDebugPinEvent* pin = &ev->u.pin;
    if (!pin->pin) return 0;
    if (ctx->dir_pin[0] && pin_eq(pin->pin, ctx->dir_pin)) {
        ctx->direction = pin->value ? 1 : -1;
        return 0;
    }
    if (ctx->step_pin[0] && pin_eq(pin->pin, ctx->step_pin)) {
        const uint32_t value = pin->value ? 1u : 0u;
        if (value == 1u && ctx->step_level == 0u) {
            ctx->angle += ctx->step_angle * (double)ctx->direction;
            emit_state(ctx);
        }
        ctx->step_level = value;
    }
    return 0;
}
