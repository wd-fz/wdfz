"""Deterministic UDP impairment for real ENet tests, one socket per client."""
import heapq
import random
import select
import socket
import threading
import time

class LanProxy:
    def __init__(self, server_port, seed=714):
        self.target = ('127.0.0.1', server_port)
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.bind(('127.0.0.1', 0))
        self.port = self.socket.getsockname()[1]
        self.random = random.Random(seed)
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.forwarded = self.dropped = self.duplicated = 0
        self.thread.start()

    def run(self):
        client, queue, sequence = None, [], 0
        while not self.stop.is_set():
            if select.select([self.socket], [], [], .002)[0]:
                packet, address = self.socket.recvfrom(65535)
                if address != self.target:
                    client = address
                    recipient = self.target
                else:
                    recipient = client
                if recipient is not None:
                    if self.random.random() < .03:
                        self.dropped += 1
                    else:
                        copies = 2 if self.random.random() < .01 else 1
                        self.duplicated += copies - 1
                        for _ in range(copies):
                            sequence += 1
                            heapq.heappush(queue, (time.monotonic() + .040 + self.random.uniform(-.010, .010), sequence, recipient, packet))
            now = time.monotonic()
            while queue and queue[0][0] <= now:
                _, _, recipient, packet = heapq.heappop(queue)
                self.socket.sendto(packet, recipient)
                self.forwarded += 1

    def close(self):
        self.stop.set()
        self.thread.join(timeout=2)
        self.socket.close()
