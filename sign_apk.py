#!/usr/bin/env python3
import os
import sys
import zipfile
import hashlib
import base64
import struct
import subprocess
import tempfile
import shutil

def run_cmd(cmd, input_data=None):
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE if input_data else None,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = p.communicate(input=input_data)
    if p.returncode != 0:
        raise RuntimeError(f"Command {' '.join(cmd)} failed (code {p.returncode}): {err.decode('utf-8', errors='ignore')}")
    return out

def get_or_create_test_key(key_path, cert_path):
    # Generates a standard Android Debug Test Key
    if not os.path.exists(key_path) or not os.path.exists(cert_path):
        run_cmd([
            'openssl', 'req', '-x509', '-newkey', 'rsa:2048',
            '-keyout', key_path, '-out', cert_path,
            '-days', '10000', '-nodes',
            '-subj', '/C=US/O=Android/OU=Android/CN=Android Debug Test'
        ])

def repack_zip(input_apk, work_zip, key_path, cert_path):
    temp_dir = tempfile.mkdtemp()
    try:
        with zipfile.ZipFile(input_apk, 'r') as zin:
            zin.extractall(temp_dir)
        
        # Inject latest assets from source tree
        src_assets = os.path.join(os.path.dirname(__file__), 'touchbar-hackintosh', 'src', 'main', 'assets', 'ipados')
        target_assets = os.path.join(temp_dir, 'assets', 'ipados')
        if os.path.exists(src_assets):
            os.makedirs(target_assets, exist_ok=True)
            for item in os.listdir(src_assets):
                s = os.path.join(src_assets, item)
                d = os.path.join(target_assets, item)
                if os.path.isdir(s):
                    shutil.copytree(s, d, dirs_exist_ok=True)
                else:
                    shutil.copy2(s, d)
            print(f"📦 Assets atualizados injetados em {target_assets}")
        
        meta_dir = os.path.join(temp_dir, 'META-INF')
        if os.path.exists(meta_dir):
            for f in os.listdir(meta_dir):
                if f.upper().endswith(('.RSA', '.DSA', '.EC', '.SF', '.MF')):
                    os.remove(os.path.join(meta_dir, f))
        else:
            os.makedirs(meta_dir, exist_ok=True)
        
        # 1. Generate MANIFEST.MF
        manifest_lines = [
            b"Manifest-Version: 1.0\r\n",
            b"Created-By: 1.0 (Android)\r\n",
            b"\r\n"
        ]
        
        file_entries = []
        for root, dirs, files in os.walk(temp_dir):
            dirs.sort()
            files.sort()
            for file in files:
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, temp_dir).replace('\\', '/')
                if rel_path.startswith('META-INF/'):
                    continue
                with open(full_path, 'rb') as f:
                    content = f.read()
                digest = base64.b64encode(hashlib.sha256(content).digest()).decode('ascii')
                file_entries.append((rel_path, digest))
        
        manifest_entries_map = {}
        for rel_path, digest in file_entries:
            entry_bytes = f"Name: {rel_path}\r\nSHA-256-Digest: {digest}\r\n\r\n".encode('utf-8')
            manifest_lines.append(entry_bytes)
            manifest_entries_map[rel_path] = entry_bytes
        
        manifest_content = b"".join(manifest_lines)
        manifest_path = os.path.join(meta_dir, 'MANIFEST.MF')
        with open(manifest_path, 'wb') as f:
            f.write(manifest_content)
        
        # 2. Generate CERT.SF
        manifest_digest = base64.b64encode(hashlib.sha256(manifest_content).digest()).decode('ascii')
        sf_lines = [
            b"Signature-Version: 1.0\r\n",
            b"Created-By: 1.0 (Android)\r\n",
            f"SHA-256-Digest-Manifest: {manifest_digest}\r\n".encode('ascii'),
            b"X-Android-APK-Signed: 2\r\n",
            b"\r\n"
        ]
        for rel_path, digest in file_entries:
            entry_raw = manifest_entries_map[rel_path]
            entry_digest = base64.b64encode(hashlib.sha256(entry_raw).digest()).decode('ascii')
            sf_lines.append(f"Name: {rel_path}\r\nSHA-256-Digest: {entry_digest}\r\n\r\n".encode('utf-8'))
        
        sf_content = b"".join(sf_lines)
        sf_path = os.path.join(meta_dir, 'CERT.SF')
        with open(sf_path, 'wb') as f:
            f.write(sf_content)
        
        # 3. Generate CERT.RSA
        rsa_path = os.path.join(meta_dir, 'CERT.RSA')
        cert_rsa_bytes = run_cmd([
            'openssl', 'smime', '-sign', '-in', sf_path,
            '-outform', 'DER', '-inkey', key_path,
            '-signer', cert_path, '-noattr', '-binary'
        ])
        with open(rsa_path, 'wb') as f:
            f.write(cert_rsa_bytes)
        
        if os.path.exists(work_zip):
            os.remove(work_zip)
        
        with zipfile.ZipFile(work_zip, 'w') as zout:
            for meta_f in ['MANIFEST.MF', 'CERT.SF', 'CERT.RSA']:
                p = os.path.join(meta_dir, meta_f)
                if os.path.exists(p):
                    zout.write(p, f'META-INF/{meta_f}', compress_type=zipfile.ZIP_DEFLATED)
            
            for root, dirs, files in os.walk(temp_dir):
                dirs.sort()
                files.sort()
                for file in files:
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, temp_dir).replace('\\', '/')
                    if rel_path.startswith('META-INF/'):
                        continue
                    if rel_path == 'resources.arsc' or rel_path.endswith('.arsc') or rel_path.startswith('lib/'):
                        zout.write(full_path, rel_path, compress_type=zipfile.ZIP_STORED)
                    else:
                        zout.write(full_path, rel_path, compress_type=zipfile.ZIP_DEFLATED)
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

def sign_apk_v2(aligned_apk, output_apk, key_path, cert_path):
    with open(aligned_apk, 'rb') as f:
        apk_bytes = f.read()

    eocd_offset = -1
    for i in range(len(apk_bytes)-22, max(0, len(apk_bytes)-65557), -1):
        if apk_bytes[i:i+4] == b'\x50\x4b\x05\x06':
            eocd_offset = i
            break

    eocd_bytes = apk_bytes[eocd_offset:]
    orig_cd_size = struct.unpack('<I', eocd_bytes[12:16])[0]
    orig_cd_offset = struct.unpack('<I', eocd_bytes[16:20])[0]

    section1 = apk_bytes[:orig_cd_offset]
    section2 = apk_bytes[orig_cd_offset:orig_cd_offset + orig_cd_size]
    # In APK v2 hashing, section 3 uses orig_cd_offset (block_start) in EOCD
    section3_for_hash = eocd_bytes[:16] + struct.pack('<I', orig_cd_offset) + eocd_bytes[20:]

    # Chunk hashing
    CHUNK_SIZE = 1048576
    chunks = []
    for sec in [section1, section2, section3_for_hash]:
        for i in range(0, len(sec), CHUNK_SIZE):
            chunk = sec[i:i+CHUNK_SIZE]
            ch = hashlib.sha256(b'\xa5' + struct.pack('<I', len(chunk)) + chunk).digest()
            chunks.append(ch)

    root_digest = hashlib.sha256(b'\x5a' + struct.pack('<I', len(chunks)) + b''.join(chunks)).digest()

    cert_der = run_cmd(['openssl', 'x509', '-in', cert_path, '-outform', 'DER'])
    pubkey_der = run_cmd(['openssl', 'rsa', '-in', key_path, '-pubout', '-outform', 'DER'])

    # Build signed_data
    digest_entry = struct.pack('<I', 0x0103) + struct.pack('<I', len(root_digest)) + root_digest
    digests_field = struct.pack('<I', len(struct.pack('<I', len(digest_entry)) + digest_entry)) + struct.pack('<I', len(digest_entry)) + digest_entry
    certs_field = struct.pack('<I', len(struct.pack('<I', len(cert_der)) + cert_der)) + struct.pack('<I', len(cert_der)) + cert_der
    add_attr_field = struct.pack('<I', 0)

    signed_data_bytes = digests_field + certs_field + add_attr_field
    signed_data = struct.pack('<I', len(signed_data_bytes)) + signed_data_bytes

    # Sign signed_data_bytes
    signature = run_cmd(['openssl', 'dgst', '-sha256', '-sign', key_path], input_data=signed_data_bytes)
    sig_entry = struct.pack('<I', 0x0103) + struct.pack('<I', len(signature)) + signature
    signatures_field = struct.pack('<I', len(struct.pack('<I', len(sig_entry)) + sig_entry)) + struct.pack('<I', len(sig_entry)) + sig_entry

    public_key_field = struct.pack('<I', len(pubkey_der)) + pubkey_der

    signer = struct.pack('<I', len(signed_data + signatures_field + public_key_field)) + signed_data + signatures_field + public_key_field
    signers = struct.pack('<I', len(signer)) + signer

    v2_pair = struct.pack('<Q', 4 + len(signers)) + struct.pack('<I', 0x7109871a) + signers

    # 4096-byte page alignment for Central Directory
    current_unpadded_cd = orig_cd_offset + len(v2_pair) + 32
    pad_needed = (4096 - (current_unpadded_cd % 4096)) % 4096
    if pad_needed < 12 and pad_needed > 0:
        pad_needed += 4096
    
    if pad_needed >= 12:
        pad_val_len = pad_needed - 12
        pad_pair = struct.pack('<Q', 4 + pad_val_len) + struct.pack('<I', 0x42726577) + (b'\x00' * pad_val_len)
    else:
        pad_pair = b''

    all_pairs = v2_pair + pad_pair
    total_block_size = len(all_pairs) + 8 + 16
    new_cd_offset = orig_cd_offset + 8 + total_block_size

    apk_signing_block = (
        struct.pack('<Q', total_block_size) +
        all_pairs +
        struct.pack('<Q', total_block_size) +
        b'APK Sig Block 42'
    )

    final_eocd = eocd_bytes[:16] + struct.pack('<I', new_cd_offset) + eocd_bytes[20:]
    final_apk = section1 + apk_signing_block + section2 + final_eocd

    with open(output_apk, 'wb') as f:
        f.write(final_apk)
    print(f"✅ APK assinado com sucesso (v1+v2 + 4096 alignment): {output_apk}")

if __name__ == '__main__':
    in_apk = sys.argv[1] if len(sys.argv) > 1 else 'touchbar-hackintosh/build/outputs/apk/debug/touchbar-hackintosh-debug.apk'
    out_apk = sys.argv[2] if len(sys.argv) > 2 else 'TouchbarHackintosh.apk'
    
    key_file = '/tmp/test_project.key'
    cert_file = '/tmp/test_project.crt'
    zipalign_bin = '/Users/luxfajah/Library/Android/sdk/build-tools/34.0.0/zipalign'
    
    print(f"🔑 Gerando/Utilizando Keystore de Teste do Projeto...")
    get_or_create_test_key(key_file, cert_file)
    
    temp_v1_zip = '/tmp/temp_repacked.apk'
    temp_aligned = '/tmp/temp_aligned.apk'
    
    print("Passo 1: Empacotando APK com recursos não comprimidos e assinatura v1...")
    repack_zip(in_apk, temp_v1_zip, key_file, cert_file)
    
    print("Passo 2: Alinhando binário em 4 bytes com zipalign...")
    if os.path.exists(temp_aligned):
        os.remove(temp_aligned)
    run_cmd([zipalign_bin, '-f', '-p', '4', temp_v1_zip, temp_aligned])
    
    print("Passo 3: Injetando APK Signature Scheme v2 com alinhamento de 4096 bytes...")
    sign_apk_v2(temp_aligned, out_apk, key_file, cert_file)
    print("Pronto para instalação!")
