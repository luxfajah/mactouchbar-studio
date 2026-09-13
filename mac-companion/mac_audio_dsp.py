#!/usr/bin/env python3
"""
DeepFilterNet3 Real-Time Audio DSP Server
- Receives 48kHz 16-bit PCM UDP stream from Android on port 9878
- Enhances audio using DeepFilterNet3 neural network (<20ms latency per 50ms chunk)
- Forwards enhanced audio to CoreAudio HAL virtual mic on 127.0.0.1:9879
- Supports instantaneous real-time toggle (DSP On/Off bypass) via control port 9877
"""

import os
import sys
import time
import socket
import select
import numpy as np

INPUT_PORT = 9878       # Receives from Android
OUTPUT_PORT = 9879      # Sends to CoreAudio MacMicEngine
CONTROL_PORT = 9877     # Receives IPC control commands (DSP toggle)
SAMPLE_RATE = 48000
CHUNK_SAMPLES = 2400    # 50ms @ 48kHz (ideal balance between throughput & latency)
CHUNK_BYTES = CHUNK_SAMPLES * 2  # 16-bit = 2 bytes per sample

class DeepFilterDSP:
    def __init__(self):
        self.enabled = True
        self.model = None
        self.df_state = None
        self.running = False
        
        self.in_sock = None
        self.out_sock = None
        self.ctrl_sock = None
        
        self.total_processed_chunks = 0
        self.avg_inference_ms = 0.0
        
        self.load_model()

    def load_model(self):
        print("🧠 [DeepFilterDSP] Loading DeepFilterNet3 model...", flush=True)
        t0 = time.time()
        try:
            import torch
            from df.enhance import init_df, enhance
            self.torch = torch
            self.enhance_fn = enhance
            
            self.model, self.df_state, _ = init_df()
            self.model.eval()
            
            # Warmup model with dummy chunk to eliminate initial JIT delay
            warmup_tensor = self.torch.zeros((1, CHUNK_SAMPLES), dtype=self.torch.float32)
            for _ in range(3):
                with self.torch.inference_mode():
                    _ = self.enhance_fn(self.model, self.df_state, warmup_tensor, pad=False)
                    
            print(f"✅ [DeepFilterDSP] DeepFilterNet3 loaded and warmed up in {time.time() - t0:.2f}s (48.0 kHz ready)", flush=True)
        except Exception as e:
            print(f"❌ [DeepFilterDSP] Error loading DeepFilterNet: {e}", flush=True)
            self.model = None

    def start(self):
        self.running = True
        
        # Sockets
        self.in_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.in_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.in_sock.bind(("0.0.0.0", INPUT_PORT))
        self.in_sock.setblocking(False)

        self.out_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        
        self.ctrl_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.ctrl_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.ctrl_sock.bind(("127.0.0.1", CONTROL_PORT))
        self.ctrl_sock.setblocking(False)
        
        print(f"🎙️ [DeepFilterDSP] Listening for Android audio on UDP {INPUT_PORT}", flush=True)
        print(f"🔊 [DeepFilterDSP] Forwarding to CoreAudio on 127.0.0.1:{OUTPUT_PORT}", flush=True)
        print(f"⚙️ [DeepFilterDSP] Control socket ready on 127.0.0.1:{CONTROL_PORT}", flush=True)

        self.loop()

    def set_dsp_enabled(self, enabled: bool):
        self.enabled = enabled
        status = "✨ ATIVADO (DeepFilterNet3)" if enabled else "Bypass (Áudio Bruto)"
        print(f"🎛️ [DeepFilterDSP] Filtro DSP alterado para: {status}", flush=True)

    def loop(self):
        raw_buffer = bytearray()
        dest_addr = ("127.0.0.1", OUTPUT_PORT)
        
        while self.running:
            # Monitor both audio input and control command sockets
            r_socks, _, _ = select.select([self.in_sock, self.ctrl_sock], [], [], 0.02)
            
            # Handle control commands
            if self.ctrl_sock in r_socks:
                try:
                    data, _ = self.ctrl_sock.recvfrom(256)
                    cmd = data.decode("utf-8", errors="ignore").strip().lower()
                    if cmd in ("on", "true", "1", "dsp_on"):
                        self.set_dsp_enabled(True)
                    elif cmd in ("off", "false", "0", "dsp_off"):
                        self.set_dsp_enabled(False)
                    elif cmd == "status":
                        resp = f"DSP:{'1' if self.enabled else '0'},Chunks:{self.total_processed_chunks},Lat:{self.avg_inference_ms:.1f}ms"
                        self.ctrl_sock.sendto(resp.encode(), ("127.0.0.1", CONTROL_PORT))
                except Exception:
                    pass

            # Handle incoming audio packets
            if self.in_sock in r_socks:
                try:
                    packet, _ = self.in_sock.recvfrom(4096)
                    if not packet:
                        continue
                        
                    if not self.enabled or self.model is None:
                        # Bypass mode: forward directly with zero delay
                        self.out_sock.sendto(packet, dest_addr)
                        raw_buffer.clear()
                        continue
                        
                    raw_buffer.extend(packet)
                    
                    # When we have accumulated 50ms of audio (CHUNK_BYTES = 4800 bytes)
                    while len(raw_buffer) >= CHUNK_BYTES:
                        chunk_raw = raw_buffer[:CHUNK_BYTES]
                        del raw_buffer[:CHUNK_BYTES]
                        
                        # Convert 16-bit PCM bytes to Float32 Tensor [-1.0, 1.0]
                        np_samples = np.frombuffer(chunk_raw, dtype=np.int16).astype(np.float32) / 32768.0
                        tensor = self.torch.from_numpy(np_samples).unsqueeze(0)
                        
                        t0 = time.perf_counter()
                        with self.torch.inference_mode():
                            enhanced = self.enhance_fn(self.model, self.df_state, tensor, pad=False)
                        dt_ms = (time.perf_counter() - t0) * 1000.0
                        
                        self.total_processed_chunks += 1
                        self.avg_inference_ms = 0.9 * self.avg_inference_ms + 0.1 * dt_ms
                        
                        # Convert back to Int16 PCM
                        out_np = (enhanced.squeeze(0).numpy() * 32767.0).clip(-32768, 32767).astype(np.int16)
                        out_bytes = out_np.tobytes()
                        
                        # Forward clean audio in sub-chunks to CoreAudio ring buffer
                        sub_size = 960 # 480 samples / 10ms packets
                        for offset in range(0, len(out_bytes), sub_size):
                            sub = out_bytes[offset:offset + sub_size]
                            self.out_sock.sendto(sub, dest_addr)
                            
                except Exception:
                    pass

    def stop(self):
        self.running = False
        if self.in_sock: self.in_sock.close()
        if self.out_sock: self.out_sock.close()
        if self.ctrl_sock: self.ctrl_sock.close()

if __name__ == "__main__":
    dsp = DeepFilterDSP()
    try:
        dsp.start()
    except KeyboardInterrupt:
        print("\nStopping DeepFilterDSP...", flush=True)
        dsp.stop()
