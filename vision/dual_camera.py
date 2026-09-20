"""Launch laptop-yoke and phone-throttle capture with one combined local control stream."""
import argparse
from pathlib import Path
import signal
import subprocess
import sys
import time


def camera_names():
    """Use the same AVFoundation ordering as the tracker."""
    if sys.platform != "darwin":
        return []
    try:
        from .camera_devices import list_cameras
    except ImportError:
        from camera_devices import list_cameras
    return [device["name"] for device in list_cameras()]


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
    command = [sys.executable, tracker, '--camera', str(cameras[0]),
               '--throttle-camera', str(cameras[1]), '--paper-test', '--throttle-idle', '15']
    if args.yoke_intrinsics:
        command.extend(['--intrinsics', str(args.yoke_intrinsics)])
    if args.throttle_intrinsics:
        command.extend(['--throttle-intrinsics', str(args.throttle_intrinsics)])
    return [command]


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
    print('Use SET UP CARDBOARD to calibrate, then TUTORIAL for takeoff, targets and landing. Q stops both cameras.', flush=True)
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
