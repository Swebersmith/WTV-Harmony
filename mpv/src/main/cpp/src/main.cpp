/**
 * Copyright (c) 2026 Bao Han <erbws@qq.com>
 */

#include <thread>

#include "globals.h"
#include "node.h"
#include "log.h"

void NativePlayer::create()
{
    if (handle) {
        log_e("[napi:create] mpv is already created");
        return;
    }

    handle = mpv_create();
    if (!handle) {
        log_e("[napi:create] fail to create mpv");
        return;
    }
}

void NativePlayer::request_log_messages(const std::string& level) const
{
    if (!handle) {
        log_e("[napi:request_log_messages] mpv is not initialized");
        return;
    }

    mpv_request_log_messages(handle, level.c_str());
}

void NativePlayer::initialize()
{
    if (!handle) {
        log_e("[napi:initialize] mpv is not created");
        return;
    }

    if (mpv_initialize(handle) < 0) {
        log_e("[napi:initialize] mpv init failed");
        return;
    }

    request_thread_exit = false;
    thread = std::thread(&NativePlayer::thread_event, this);
}

void NativePlayer::destroy()
{
    if (!handle) {
        log_e("[napi:destroy] mpv is already destroyed");
        return;
    }

    request_thread_exit = true;
    mpv_wakeup(handle);
    if (thread.joinable()) {
        thread.join();
    }

    mpv_terminate_destroy(handle);
    handle = nullptr;
}

void NativePlayer::attach_surface(const std::string& surface) const
{
    if (!handle) {
        log_e("[napi:attach_surface] mpv is not initialized");
        return;
    }

    const uint64_t surface_id = std::stoull(surface);

    int64_t wid = 0;
    memcpy(&wid, &surface_id, sizeof(surface_id));
    if (wid == 0) {
        log_e("[napi:attach_surface] invalid surface");
        return;
    }

    mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid);
}

void NativePlayer::detach_surface() const
{
    if (!handle) {
        log_e("[napi:detach_surface] mpv is not initialized");
        return;
    }

    int64_t wid = 0;
    mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid);
}

int NativePlayer::command(const std::vector<std::string>& commands) const
{
    if (!handle) {
        log_e("[napi:command] mpv is not initialized");
        return MPV_ERROR_UNINITIALIZED;
    }

    std::vector<const char*> args;
    args.reserve(commands.size() + 1);
    for (const auto& cmd : commands) {
        args.push_back(cmd.c_str());
    }

    args.push_back(nullptr);

    return mpv_command(handle, args.data());
}

aki::Value NativePlayer::command_with_return(const std::vector<std::string>& commands) const
{
    if (!handle) {
        log_e("[napi:command] mpv is not initialized");
        return aki::Value::NewObject();
    }

    std::vector<const char*> args;
    args.reserve(commands.size() + 1);
    for (const auto& cmd : commands) {
        args.push_back(cmd.c_str());
    }

    args.push_back(nullptr);

    mpv_node res{};
    const int status = mpv_command_ret(handle, args.data(), &res);
    if (status < 0) {
        const std::string message = std::string("[napi:command] ") + mpv_error_string(status);
        log_e(message.c_str());
        return aki::Value::NewObject();
    }

    aki::Value ret = mpv_node_to_aki_value(res);
    mpv_free_node_contents(&res);

    return ret;
}

void NativePlayer::load_file(
    const std::string& url,
    const std::map<std::string, std::string>& options) const
{
    if (!handle) {
        log_e("[napi:load_file] mpv is not initialized");
        return;
    }

    std::string command = "loadfile";
    std::string flags = "append";

    std::vector<mpv_node> option_values;
    std::vector<char*> option_keys;
    option_values.reserve(options.size());
    option_keys.reserve(options.size());

    for (const auto& [name, value] : options) {
        mpv_node node{};
        node.format = MPV_FORMAT_STRING;
        node.u.string = const_cast<char*>(value.c_str());
        option_values.push_back(node);
        option_keys.push_back(const_cast<char*>(name.c_str()));
    }

    mpv_node_list option_list{
        .num = static_cast<int>(option_values.size()),
        .values = option_values.data(),
        .keys = option_keys.data(),
    };

    std::vector<mpv_node> arguments(5);
    arguments[0].format = MPV_FORMAT_STRING;
    arguments[0].u.string = command.data();
    arguments[1].format = MPV_FORMAT_STRING;
    arguments[1].u.string = const_cast<char*>(url.c_str());
    arguments[2].format = MPV_FORMAT_STRING;
    arguments[2].u.string = flags.data();
    arguments[3].format = MPV_FORMAT_INT64;
    arguments[3].u.int64 = -1;
    arguments[4].format = MPV_FORMAT_NODE_MAP;
    arguments[4].u.list = &option_list;

    mpv_node_list argument_list{
        .num = static_cast<int>(arguments.size()),
        .values = arguments.data(),
        .keys = nullptr,
    };
    mpv_node args{};
    args.format = MPV_FORMAT_NODE_ARRAY;
    args.u.list = &argument_list;

    mpv_node result{};
    const int status = mpv_command_node(handle, &args, &result);
    if (status < 0) {
        const std::string message = std::string("[napi:load_file] ") + mpv_error_string(status);
        log_e(message.c_str());
        return;
    }

    mpv_free_node_contents(&result);
}
