"""Two independent loopback devices, with a phone outage and restart."""
import asyncio
import json
import sys
import time
import cv2
import numpy as np
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed


phone_ready = None
phone_connections = set()

def handler_for(phone):
    frame = np.full((180, 320, 3), (220, 20, 20) if phone else (20, 20, 220), np.uint8)
    jpeg = cv2.imencode('.jpg', frame)[1].tobytes()
    async def handler(connection):
        sequence = 0
        if phone:
            phone_connections.add(connection.request.path)
            if len(phone_connections) >= 2:
                phone_ready.set()
        try:
            while True:
                packet = dict(version=1, sequence=sequence, timestamp=int(time.time()*1000), tracking=True,
                              yoke=dict(roll=-.8 if phone else .25, pitch=.9 if phone else -.4, confidence=1),
                              throttle=dict(value=.75 if phone else .1, confidence=1),
                              weapons=dict(primary=phone, salvo=phone, primary_confidence=1, salvo_confidence=1))
                await connection.send(jpeg if connection.request.path == '/preview' else json.dumps(packet))
                sequence += 1
                await asyncio.sleep(.033)
        except ConnectionClosed:
            pass
    return handler


async def main():
    global phone_ready
    phone_ready = asyncio.Event()
    async with serve(handler_for(False), '127.0.0.1', int(sys.argv[1])):
        async with serve(handler_for(True), '127.0.0.1', int(sys.argv[2])):
            await asyncio.wait_for(phone_ready.wait(), 12)
            await asyncio.sleep(2)
        await asyncio.sleep(3)
        async with serve(handler_for(True), '127.0.0.1', int(sys.argv[2])):
            await asyncio.sleep(8)

asyncio.run(main())
