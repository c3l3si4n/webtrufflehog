#!/usr/bin/env python3
import sys
import json
import struct
import subprocess
import tempfile
import queue
import threading
import requests
import os
import hashlib
from urllib.parse import urlparse

# Global queues and caches
url_queue = queue.Queue()
result_queue = queue.Queue()
url_cache = set() # Store URL hashes
result_cache = {} # Store content hash -> findings mapping


# save all stderr to a file
sys.stderr = open('/opt/webtrufflehog/webtrufflehog.log', 'w')

# Helper function to send messages to the extension
def send_message(message):
    try:
        encoded_content = json.dumps(message).encode('utf-8')
        sys.stdout.buffer.write(struct.pack('I', len(encoded_content)))
        sys.stdout.buffer.write(encoded_content)
        sys.stdout.buffer.flush()
    except Exception as e:
        print(f"Error sending message: {str(e)}", file=sys.stderr)

# Helper function to read messages from the extension
def read_message():
    try:
        raw_length = sys.stdin.buffer.read(4)
        if not raw_length:
            return None
        message_length = struct.unpack('I', raw_length)[0]
        message = sys.stdin.buffer.read(message_length).decode('utf-8')
        return json.loads(message)
    except Exception:
        return None

def get_url_hash(url):
    return hashlib.md5(url.encode()).hexdigest()

def get_content_hash(content):
    return hashlib.md5(content.encode()).hexdigest()

def download_url(url):
    try:
        response = requests.get(url, timeout=30)
        response.raise_for_status()
        return response.text
    except Exception as e:
        print(f"Error downloading {url}: {str(e)}", file=sys.stderr)
        return None

def scan_with_trufflehog(content, temp_dir):
    if not content:
        return []
        
    temp_file = os.path.join(temp_dir, 'scan_target.txt')
    try:
        with open(temp_file, 'w') as f:
            f.write(content)
        
        result = subprocess.run(
            ['trufflehog', 'filesystem', temp_file, '--json'],
            capture_output=True,
            text=True
        )
        findings = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        return findings
    except Exception as e:
        print(f"Error scanning with trufflehog: {str(e)}", file=sys.stderr)
        return []
    finally:
        try:
            if os.path.exists(temp_file):
                os.remove(temp_file)
        except Exception as e:
            print(f"Error removing temp file: {str(e)}", file=sys.stderr)

def worker():
    while True:
        temp_dir = None
        try:
            temp_dir = tempfile.mkdtemp()
            job = url_queue.get()
            if job is None:  # Poison pill
                break
            
            url = job['url']
            job_id = job['id']
            
            # Check URL cache
            url_hash = get_url_hash(url)
            if url_hash in url_cache:
                url_queue.task_done()
                continue
                
            content = download_url(url)
            if content:
                content_hash = get_content_hash(content)
                
                # Check result cache
                if content_hash in result_cache:
                    findings = result_cache[content_hash]
                else:
                    findings = scan_with_trufflehog(content, temp_dir)
                    result_cache[content_hash] = findings
                
                if findings:
                    result_queue.put({
                        'id': job_id,
                        'url': url,
                        'findings': findings
                    })
                
                url_cache.add(url_hash)
            
            url_queue.task_done()
        except Exception as e:
            print(f"Worker error: {str(e)}", file=sys.stderr)
        finally:
            try:
                if temp_dir and os.path.exists(temp_dir):
                    os.rmdir(temp_dir)
            except Exception as e:
                print(f"Error removing temp dir: {str(e)}", file=sys.stderr)

def append_result(result,filename):
    with open(filename, 'a') as f:
        f.write(json.dumps(result) + '\n')

def result_sender():
    while True:
        try:
            result = result_queue.get()
            if result is None:  # Poison pill
                break
            
            append_result(result, '/opt/webtrufflehog/results.json')
            send_message(result)
            result_queue.task_done()
        except Exception as e:
            print(f"Result sender error: {str(e)}", file=sys.stderr)

def main():
    # Start worker threads
    num_workers = 10
    workers = []
    for _ in range(num_workers):
        t = threading.Thread(target=worker)
        t.daemon = True
        t.start()
        workers.append(t)

    # Start result sender thread
    sender = threading.Thread(target=result_sender)
    sender.daemon = True
    sender.start()

    try:
        while True:
            message = read_message()
            if not message:
                break

            if 'url' in message:
                url_queue.put({
                    'id': message.get('id'),
                    'url': message['url']
                })
            if 'status' in message:
                # return number of queue items
                send_message({'status': url_queue.qsize()})
    finally:
        # Clean shutdown
        for _ in workers:
            url_queue.put(None)
        result_queue.put(None)
        
        for w in workers:
            w.join()
        sender.join()

if __name__ == "__main__":
    main()
