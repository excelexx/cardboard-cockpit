"""Resolve explicit macOS camera names without opening any camera.

OpenCV 4.11 AVFoundation orders video + muxed devices by uniqueID, rather
than discovery order: modules/videoio/src/cap_avfoundation_mac.mm.
"""
import argparse
import json
import subprocess
import sys


def camera_argument(value):
    try:
        return int(value)
    except ValueError:
        if not value.strip():
            raise argparse.ArgumentTypeError("Use a camera index or device name.")
        return value.strip()


def list_cameras():
    if sys.platform != "darwin":
        raise RuntimeError("Camera names/listing currently require macOS; use explicit camera indices on other systems.")
    script = """
ObjC.import('Foundation');
$.NSBundle.bundleWithPath('/System/Library/Frameworks/AVFoundation.framework').load;
var cls = $.NSClassFromString('AVCaptureDevice');
var devices = cls.devicesWithMediaType('vide').arrayByAddingObjectsFromArray(cls.devicesWithMediaType('muxx'));
var result = [];
for (var i = 0; i < devices.count; i++) {
    var d = devices.objectAtIndex(i);
    result.push({name: ObjC.unwrap(d.localizedName), id: ObjC.unwrap(d.uniqueID)});
}
result.sort(function(a, b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0; });
JSON.stringify(result);
"""
    try:
        result = subprocess.run(["osascript", "-l", "JavaScript"], input=script,
                                capture_output=True, text=True, check=True, timeout=10)
        devices = json.loads(result.stdout)
        return [{"index": index, "name": device["name"], "id": device["id"]}
                for index, device in enumerate(devices)]
    except (subprocess.SubprocessError, ValueError, KeyError, TypeError) as error:
        raise RuntimeError("Could not list camera devices. Reconnect the phone and try --list-cameras.") from error


def resolve_camera(selection, devices=None):
    if isinstance(selection, int):
        if selection < 0:
            raise ValueError("Camera index cannot be negative.")
        return selection, "Camera %d" % selection
    devices = list_cameras() if devices is None else devices
    exact = [d for d in devices if d["name"].casefold() == selection.casefold() or d["id"] == selection]
    matches = exact or [d for d in devices if selection.casefold() in d["name"].casefold()]
    if len(matches) != 1:
        raise ValueError("Camera '%s' is %s. Use --list-cameras and select its exact name; no fallback camera was opened." %
                         (selection, "not connected" if not matches else "ambiguous"))
    return matches[0]["index"], matches[0]["name"]
