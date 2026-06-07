#!/bin/bash
# Selkies (gstreamer branch) - WebRTC streaming launcher
# Termux native (non-proot) on DISPLAY=:1 (Xvnc XFCE4 desktop)

export DISPLAY=:1

# Audio via PulseAudio over TCP (AAudio sink for Android)
export PULSE_SERVER=tcp:127.0.0.1:4713
export SELKIES_AUDIO_ENABLED=true
export SELKIES_MICROPHONE_ENABLED=false

# Use GStreamer media pipeline (pixelflux C extension has issues in Termux)
export SELKIES_MEDIA_PIPELINE=gstreamer

# Use openh264enc (x264enc not available in Termux)
export SELKIES_ENCODER_RTC=h264_mediacodec

# Reasonable framerate for CPU encoding
export SELKIES_FRAMERATE=30

# No basic auth for local network
export SELKIES_ENABLE_BASIC_AUTH=false

# Set port
export SELKIES_PORT=8081

# Set web root
export SELKIES_WEB_ROOT=~/proton11/selkies/addons/gst-web/src

# Mode
export SELKIES_MODE=webrtc

echo "Starting new selkies (gstreamer branch) on port 8081..."
echo "DISPLAY=$DISPLAY"
echo "Encoder: openh264enc"
echo "Pipeline: gstreamer"

exec selkies
