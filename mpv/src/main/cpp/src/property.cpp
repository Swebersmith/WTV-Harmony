/**
 * Copyright (C) 2025 Bao Han <erbws@qq.com>
 */

#include "globals.h"
#include "log.h"

void NativePlayer::set_option_string(const std::string& option, const std::string& value) const
{
    if (!handle) {
        log_e("[napi:set_option_string] mpv is not initialized");
        return;
    }

    mpv_set_option_string(handle, option.c_str(), value.c_str());
}

double NativePlayer::get_property(const std::string& property) const
{
    if (!handle) {
        log_e("[napi:get_property] mpv is not initialized");
        return 0;
    }

    double value = 0;

    // mpv_get_property() can convert int64_t to double losslessly.
    // They all result 'number', so only query double value to make code clean.
    mpv_get_property(handle, property.c_str(), MPV_FORMAT_DOUBLE, &value);

    return value;
}

bool NativePlayer::get_property_bool(const std::string& property) const
{
    if (!handle) {
        log_e("[napi:get_property_bool] mpv is not initialized");
        return false;
    }

    int value = 0;

    mpv_get_property(handle, property.c_str(), MPV_FORMAT_FLAG, &value);

    return value != 0;
}

std::string NativePlayer::get_property_string(const std::string& property) const
{
    if (!handle) {
        log_e("[napi:get_property_string] mpv is not initialized");
        return {};
    }

    char* value = mpv_get_property_string(handle, property.c_str());
    if (!value) {
        return "";
    }

    std::string result = value;
    mpv_free(value);

    return result;
}

void NativePlayer::set_property_int(const std::string& property, int64_t value) const
{
    if (!handle) {
        log_e("[napi:set_property_int] mpv is not initialized");
        return;
    }

    mpv_set_property(handle, property.c_str(), MPV_FORMAT_INT64, &value);
}

void NativePlayer::set_property_double(const std::string& property, double value) const
{
    if (!handle) {
        log_e("[napi:set_property_double] mpv is not initialized");
        return;
    }

    mpv_set_property(handle, property.c_str(), MPV_FORMAT_DOUBLE, &value);
}

void NativePlayer::set_property_bool(const std::string& property, const bool value) const
{
    if (!handle) {
        log_e("[napi:set_property_bool] mpv is not initialized");
        return;
    }

    int flag = value ? 1 : 0;
    mpv_set_property(handle, property.c_str(), MPV_FORMAT_FLAG, &flag);
}

void NativePlayer::set_property_string(const std::string& property, const std::string& value) const
{
    if (!handle) {
        log_e("[napi:set_property_string] mpv is not initialized");
        return;
    }

    mpv_set_property_string(handle, property.c_str(), value.c_str());
}



void NativePlayer::observe_property(const std::string& property, uint8_t format) const
{
    if (!handle) {
        log_e("[napi:observe_property] mpv is not initialized");
        return;
    }

    mpv_observe_property(handle, 0, property.c_str(), static_cast<mpv_format>(format));
}
