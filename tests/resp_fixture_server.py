#!/usr/bin/env python3
import pathlib
import socket
import sys
import time

server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", 0))
server.listen()
server.settimeout(1)
pathlib.Path(sys.argv[1]).write_text(str(server.getsockname()[1]))

while True:
    try:
        client, _ = server.accept()
    except socket.timeout:
        continue
    with client:
        client.settimeout(2)
        try:
            request = client.recv(4096)
        except (socket.timeout, ConnectionError):
            continue
        if b"FRAGMENT" in request:
            frame = b"$8\r\n\x00\xffA\r\nB\x80Z\r\n"
            for byte in frame:
                try:
                    client.sendall(bytes([byte]))
                except ConnectionError:
                    break
                time.sleep(0.01)
        elif b"MALFORMED" in request:
            client.sendall(b"$x\r\n")
        elif b"AUTHERR" in request:
            client.sendall(b"-NOAUTH Authentication required.\r\n")
        elif b"DISCONNECT" in request:
            client.sendall(b"$20\r\npartial")
        elif b"SLOW" in request:
            for byte in b"+PONG\r\n":
                try:
                    client.sendall(bytes([byte]))
                except ConnectionError:
                    break
                time.sleep(1)
        elif b"STALL" in request:
            time.sleep(8)
        elif b"BLACKHOLE" in request:
            time.sleep(8)
