#!/usr/bin/env python3
"""Linux native SSH dispatch, argument safety, diagnostics and failure cleanup."""
from pathlib import Path
import json, os, subprocess, sys, tempfile, time

FAKE = r"""#!/usr/bin/python3
import json,os,struct,sys,time
from pathlib import Path
args=sys.argv[1:]
Path(os.environ['HOWL_TEST_ARGS']).write_text(json.dumps({'pid':os.getpid(),'args':args}))
assert '-T' in args and '-a' in args and '-x' in args
assert 'BatchMode=yes' in args and 'StrictHostKeyChecking=yes' in args
assert args[args.index('-S')+1]=='none'
mode=args[-2]
if mode=='denied':
 os.write(2,b'Permission denied (publickey).\n');sys.exit(255)
h=b''
while len(h)<12:
 part=os.read(0,12-len(h))
 if not part:sys.exit(1)
 h+=part
assert h==struct.pack('>4sBBHI',b'HWLS',9,1,0,0)
if mode=='truncated':os.write(1,b'HWLS');sys.exit(0)
if mode=='wrongversion':os.write(1,struct.pack('>4sBBHI',b'HWLS',8,2,0,8));sys.exit(0)
if mode=='oversizedwelcome':os.write(1,struct.pack('>4sBBHI',b'HWLS',9,2,0,1024*1024));sys.exit(0)
if mode=='fragmented':
 for byte in struct.pack('>4sBBHIQ',b'HWLS',9,2,0,8,73):
  os.write(1,bytes([byte]));time.sleep(.002)
 h=os.read(0,12)
 assert h==struct.pack('>4sBBHI',b'HWLS',9,12,0,0),h
 # Deliberate EOF after the valid handshake and subsequent semantic request.
 sys.exit(0)
sys.exit(2)
"""

def main():
    if not sys.platform.startswith('linux'):
        print('Howl SSH carrier: Linux runtime proof skipped on non-Linux')
        return
    cli=Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix='howl-ssh-') as directory:
        root=Path(directory);fake=root/'ssh';fake.write_text(FAKE);fake.chmod(0o700)
        env={**os.environ,'PATH':str(root)+os.pathsep+os.environ.get('PATH',''),'HOWL_TEST_ARGS':str(root/'args.json')}
        cases={'denied':'Permission denied (publickey).','truncated':'ConnectionClosed',
               'wrongversion':'UnsupportedFramingVersion','oversizedwelcome':'InvalidPayload',
               'fragmented':'ConnectionClosed'}
        for name,message in cases.items():
            result=subprocess.run([str(cli),'state',f'ssh://{name}/a%00b'],env=env,capture_output=True,text=True,timeout=5)
            assert result.returncode!=0 and 'InvalidEndpoint' in result.stderr
            # Malformed input must never execute the carrier.
            assert not (root/'args.json').exists()
            endpoint=f"ssh://{name}/a'$(touch${{IFS}}bad);x?bridge=/opt/b'ridge"
            result=subprocess.run([str(cli),'state',endpoint],env=env,capture_output=True,text=True,timeout=5)
            assert result.returncode!=0 and message in result.stderr,(name,result)
            assert not result.stdout,(name,result.stdout)
            args=json.loads((root/'args.json').read_text())
            assert args['args'][-1]=="exec '/opt/b'\\''ridge' '/a'\\''$(touch${IFS}bad);x'"
            assert not Path('/proc',str(args['pid'])).exists(),('SSH child leaked',args['pid'])
            (root/'args.json').unlink()
    print('Howl SSH carrier: PASS (no network; safe argv, five failed/fragmented handshakes, bounded diagnostics and child cleanup)')

if __name__=='__main__': main()
