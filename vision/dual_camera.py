"""Run independent laptop-yoke and phone-throttle workers on localhost."""
import argparse
import ctypes
from pathlib import Path
import signal
import subprocess
import sys
import time


def camera_names():
    """Match OpenCV's AVFoundation video + muxed enumeration, without capture."""
    if sys.platform != "darwin":
        return []
    av = ctypes.CDLL('/System/Library/Frameworks/AVFoundation.framework/AVFoundation')
    objc = ctypes.CDLL('/usr/lib/libobjc.A.dylib')
    objc.objc_getClass.argtypes = [ctypes.c_char_p]
    objc.objc_getClass.restype = ctypes.c_void_p
    objc.sel_registerName.argtypes = [ctypes.c_char_p]
    objc.sel_registerName.restype = ctypes.c_void_p
    address = ctypes.cast(objc.objc_msgSend, ctypes.c_void_p).value

    def send(obj, name, *args, result=ctypes.c_void_p):
        function = ctypes.CFUNCTYPE(result, ctypes.c_void_p, ctypes.c_void_p,
                                    *([ctypes.c_void_p] * len(args)))(address)
        return function(obj, objc.sel_registerName(name.encode()), *args)

    pool = send(send(objc.objc_getClass(b'NSAutoreleasePool'), 'alloc'), 'init')
    try:
        device_class = objc.objc_getClass(b'AVCaptureDevice')
        video = send(device_class, 'devicesWithMediaType:', ctypes.c_void_p.in_dll(av, 'AVMediaTypeVideo').value)
        muxed = send(device_class, 'devicesWithMediaType:', ctypes.c_void_p.in_dll(av, 'AVMediaTypeMuxed').value)
        devices = send(video, 'arrayByAddingObjectsFromArray:', muxed)
        return [send(send(send(devices, 'objectAtIndex:', index), 'localizedName'),
                     'UTF8String', result=ctypes.c_char_p).decode()
                for index in range(send(devices, 'count', result=ctypes.c_ulong))]
    finally:
        send(pool, 'drain', result=None)


def select_cameras(names, yoke=None, throttle=None):
    def unique(words, role):
        matches = [index for index, name in enumerate(names)
                   if any(word in name.lower() for word in words)]
        if len(matches) != 1:
            raise ValueError('Cannot identify one %s camera. Connect it, run --list-cameras, then set --%s-camera INDEX.' % (role, role))
        return matches[0]
    if yoke is None:
        yoke = unique(('macbook', 'facetime', 'built-in'), 'yoke')
    if throttle is None:
        throttle = unique(('iphone', 'continuity'), 'throttle')
    if yoke < 0 or throttle < 0 or yoke == throttle:
        raise ValueError('Select two different, nonnegative camera indices.')
    if names and (yoke >= len(names) or throttle >= len(names)):
        raise ValueError('Selected camera is unavailable. Run --list-cameras again.')
    return yoke, throttle


def worker_commands(args, cameras):
    tracker = str(Path(__file__).with_name('tracker.py'))
    commands = [[sys.executable, tracker, '--camera', str(cameras[0]), '--paper-test', '--yoke-only', '--port', '8765'],
                [sys.executable, tracker, '--camera', str(cameras[1]), '--throttle-only', '--no-preview', '--port', '8766']]
    for command, profile in zip(commands, (args.yoke_intrinsics, args.throttle_intrinsics)):
        if profile:
            command.extend(['--intrinsics', str(profile)])
    return commands


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list-cameras', action='store_true')
    parser.add_argument('--yoke-camera', type=int)
    parser.add_argument('--throttle-camera', type=int)
    parser.add_argument('--yoke-intrinsics', type=Path)
    parser.add_argument('--throttle-intrinsics', type=Path)
    args = parser.parse_args()
    names = camera_names()
    if args.list_cameras:
        for index, name in enumerate(names):
            print('%d: %s' % (index, name))
        if not names:
            print('Automatic listing is available on macOS. Supply explicit camera indices on other systems.')
        return 0
    try:
        cameras = select_cameras(names, args.yoke_camera, args.throttle_camera)
    except ValueError as error:
        parser.error(str(error))
    for role, index in zip(('LAPTOP YOKE', 'PHONE THROTTLE'), cameras):
        print('%s: camera %d%s' % (role, index, ' / ' + names[index] if names else ''), flush=True)
    print('Hold yoke 7 steady to center; SPACE in the tracker window recenters. Q stops both cameras.', flush=True)
    def stop(_signal, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    children = []
    try:
        for command in worker_commands(args, cameras):
            children.append(subprocess.Popen(command))
        # Workers have independent capture loops. A disconnected phone cannot
        # block yoke frames. Avoid reopening a camera the user explicitly closed.
        reported = set()
        while any(child.poll() is None for child in children):
            for index, child in enumerate(children):
                code = child.poll()
                if code == 0:
                    return 0
                if code is not None and index not in reported:
                    reported.add(index)
                    print('%s worker stopped; the other camera keeps running. Restart the launcher to reconnect this camera.' % ('Yoke' if index == 0 else 'Throttle'), file=sys.stderr, flush=True)
            time.sleep(.2)
        return 1
    except KeyboardInterrupt:
        return 0
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()
        for child in children:
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()


if __name__ == '__main__':
    sys.exit(main())
