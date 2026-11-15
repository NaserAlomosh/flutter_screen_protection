#!/usr/bin/env python3
"""Sequential real-emulator evidence runner. Requires Pillow, Android SDK and test APK."""
import argparse, hashlib, json, os, pathlib, re, select, shutil, subprocess, time, urllib.request
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('api', type=int)
parser.add_argument('--image', required=True)
parser.add_argument('--apk', default='/private/tmp/fsp-validation.apk')
parser.add_argument('--evidence-dir', default='docs/evidence/ANDROID_API_29_37')
a = parser.parse_args()
sdk = pathlib.Path(os.environ.get('ANDROID_HOME', str(pathlib.Path.home() / 'Library/Android/sdk')))
out = pathlib.Path(__file__).resolve().parents[1] / a.evidence_dir / f'api-{a.api}'
out.mkdir(parents=True, exist_ok=True)
(out/'run.json').write_text(json.dumps(dict(api=a.api, image=a.image, apkSha256=hashlib.sha256(pathlib.Path(a.apk).read_bytes()).hexdigest()), indent=2)+'\n')
env = dict(os.environ, ANDROID_AVD_HOME='/private/tmp/fsp-rebuild-avds')
pathlib.Path(env['ANDROID_AVD_HOME']).mkdir(exist_ok=True)
name = f'FSP_REBUILD_{a.api}'
subprocess.run([str(sdk/'cmdline-tools/latest/bin/avdmanager'), 'create', 'avd', '-n', name, '-k', a.image, '--device', 'pixel_2', '--force'], input='no\n', text=True, env=env, check=True, stdout=open(out/'avd.log','w'), stderr=subprocess.STDOUT)
log = open(out/'emulator.log', 'w')
emulator = subprocess.Popen([str(sdk/'emulator/emulator'), '-avd', name, '-port', '5580', '-no-window', '-no-audio', '-no-snapshot', '-gpu', 'swiftshader', '-memory', '2048'], env=env, stdout=log, stderr=subprocess.STDOUT)
serial = 'emulator-5580'

def adb(*args, **kw):
    return subprocess.run([str(sdk/'platform-tools/adb'), '-s', serial, *args], capture_output=True, timeout=kw.pop('timeout', 30), **kw)

def capture(name, blocked, method='adb-screencap'):
    p = out/f'{name}.png'
    window_state=adb('shell','dumpsys','window').stdout.decode(errors='replace')
    (out/f'{name}-full-window.txt').write_text(window_state)
    foreground=bool(re.search(r'mCurrentFocus=.*ValidationActivity', window_state))
    result = adb('exec-out', 'screencap', '-p')
    p.write_bytes(result.stdout)
    surface_log = adb('logcat','-d','-s','SurfaceFlinger').stdout.decode(errors='replace')
    (out/f'{name}-surface.txt').write_text(surface_log)
    (out/f'{name}-capture.txt').write_text(f'exit={result.returncode}\nstderr={result.stderr.decode(errors="replace")}')
    if not result.stdout and blocked:
        flags = adb('shell','dumpsys','window','windows').stdout.decode(errors='replace')
        secure = bool(re.search(r'ValidationActivity[^\n]*.*?fl=[^\n]*\bSECURE\b', flags, re.S))
        refusal = result.returncode != 0 or b'error' in result.stderr.lower() or b'failed' in result.stderr.lower() or 'FB is protected: PERMISSION_DENIED' in surface_log
        return dict(test=name, expectedBlocked=True, method=method, status='PASS' if secure and foreground else 'FAIL', foreground=foreground, captureOutcome='No pixel data returned; secure window verified; compare allowed control', captureRefused=refusal, secureWindow=secure, stderr=result.stderr.decode(errors='replace'), exitCode=result.returncode)
    try:
        im = Image.open(p).convert('RGB')
        pixels = list(im.getdata())
        green = sum(abs(r-32)<8 and abs(g-192)<8 and abs(b-96)<8 for r,g,b in pixels)/len(pixels)
        red = sum(abs(r-224)<8 and abs(g-32)<8 and abs(b-64)<8 for r,g,b in pixels)/len(pixels)
        marker = green + red if blocked else green
        status = 'PASS' if foreground and (marker < .001 if blocked else marker > .25) else 'FAIL'
        return dict(test=name, expectedBlocked=blocked, method=method, status=status, foreground=foreground, markerFraction=marker, screenshot=p.name)
    except Exception as e:
        return dict(test=name, method=method, status='FAIL', error=str(e))

results=[]
owned=False
try:
    deadline=time.time()+600
    while time.time()<deadline:
        if emulator.poll() is not None: raise RuntimeError(f'Emulator exited {emulator.returncode}; see emulator.log')
        if adb('shell','getprop','sys.boot_completed').stdout.strip()==b'1': break
        time.sleep(2)
    else: raise RuntimeError('Boot timed out')
    avd_name=adb('emu','avd','name').stdout.decode(errors='replace').splitlines()
    if not avd_name or avd_name[0] != name: raise RuntimeError('ADB port belongs to a different AVD')
    owned=True
    (out/'device.txt').write_bytes(adb('shell','getprop').stdout)
    actual=adb('shell','getprop','ro.build.version.sdk').stdout.decode().strip()
    if actual != str(a.api): raise RuntimeError(f'Expected API {a.api}, got {actual}')
    if a.api >= 34:
        # Configure navigation before launching: changing this overlay can recreate
        # the Activity and discard the framework's back callback registration.
        adb('shell','cmd','overlay','enable','--user','0','com.android.internal.systemui.navbar.gestural')
        adb('shell','settings','put','global','enable_back_animation','1')
        time.sleep(2)
    adb('shell','input','keyevent','82')
    adb('install','-r',a.apk,timeout=120).check_returncode()
    adb('forward','tcp:8876','tcp:8765')
    adb('logcat','-c')
    stream=subprocess.Popen([str(sdk/'platform-tools/adb'),'-s',serial,'logcat','-v','brief'], stdout=subprocess.PIPE, bufsize=0)
    package='com.naseralomosh.flutter_screen_protection_example'
    component=package+'/.ValidationActivity'
    adb('shell','am','start','-n',component).check_returncode()
    deadline=time.time()+600
    done=False
    with open(out/'logcat.txt','wb') as transcript:
        while time.time()<deadline:
            ready,_,_=select.select([stream.stdout],[],[],1)
            if not ready: continue
            line=stream.stdout.readline()
            transcript.write(line); transcript.flush()
            text=line.decode(errors='replace')
            transition=re.search(r'FSP_TRANSITION (\S+) (GATED|SECURE|GESTURE)',text)
            if transition:
                test,mode=transition.groups()
                gesture_process=None
                if mode=='GESTURE':
                    config=adb('shell','cmd','overlay','enable','--user','0','com.android.internal.systemui.navbar.gestural')
                    (out/'gesture-config.txt').write_bytes(config.stdout+config.stderr)
                    time.sleep(1)
                    gesture_process=subprocess.Popen([str(sdk/'platform-tools/adb'),'-s',serial,'shell','input','swipe','2','900','600','900','2000'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                for sample in range(3):
                    time.sleep(.1)
                    name=f'{test}-{sample}'
                    item=capture(name,True,method='transition-adb-screencap')
                    if mode=='GATED':
                        flags=(out/f'{name}-full-window.txt').read_text()
                        native_secure=bool(re.search(r'ValidationActivity[^\n]*.*?fl=[^\n]*\bSECURE\b', flags, re.S))
                        item['nativeSecure']=native_secure
                        if native_secure or not (out/f'{name}.png').stat().st_size:
                            item['status']='FAIL'
                            item['reason']='Gate test requires an unprotected native window and a real neutral PNG'
                        elif item['status']=='PASS':
                            px=list(Image.open(out/f'{name}.png').convert('RGB').getdata())
                            black=sum(max(pixel)<8 for pixel in px)/len(px)
                            item['neutralBlackFraction']=black
                            if black<.8:
                                item['status']='FAIL'
                                item['reason']='Expected a neutral black Flutter gate'
                    if mode=='GESTURE' and (out/f'{name}.png').stat().st_size:
                        im=Image.open(out/f'{name}.png').convert('RGB')
                        px=list(im.getdata())
                        red=sum(abs(r-224)<8 and abs(g-32)<8 and abs(b-64)<8 for r,g,b in px)/len(px)
                        item['sensitiveRedFraction']=red
                        item['status']='PASS' if item.get('foreground') and red<.001 else 'FAIL'
                        item['method']='edge-gesture-adb-screencap'
                    results.append(item)
                    print(a.api,name,item['status'],flush=True)
                if gesture_process is not None:
                    gesture_process.wait(timeout=10)
                    time.sleep(7)
                    gesture_log=adb('logcat','-d','-s','flutter').stdout.decode(errors='replace')
                    observed='FSP_OS_GESTURE_STARTED' in gesture_log
                    (out/'os-gesture-flutter.txt').write_text(gesture_log)
                    results.append(dict(test='os_predictive_progress_observed',method='Android edge gesture',status='PASS' if observed else 'BLOCKED',note='ADB edge swipe reached Flutter userGestureInProgress' if observed else 'Injected edge swipe did not produce a Flutter predictive-progress callback'))
                    if observed:results.append(capture('os_predictive_committed',True))
                urllib.request.urlopen('http://127.0.0.1:8876/next',timeout=15).read()
            match=re.search(r'FSP_EVIDENCE (\S+) (BLOCKED|ALLOWED)',text)
            if match:
                test,state=match.groups(); blocked=state=='BLOCKED'
                if test=='system_back':
                    adb('shell','input','keyevent','4')
                    time.sleep(1)
                # FrameTiming reports are batched by the engine (up to ~1 second).
                # Settled evidence waits for that safe-release barrier; transition samples do not.
                time.sleep(1.5)
                release_wait=time.monotonic()
                if not blocked:
                    # Wait for the asynchronous safe-release barrier, bounded and recorded.
                    while time.monotonic()-release_wait < 5:
                        flags=adb('shell','dumpsys','window','windows').stdout.decode(errors='replace')
                        if not re.search(r'ValidationActivity[^\n]*.*?fl=[^\n]*\bSECURE\b',flags,re.S): break
                        time.sleep(.2)
                result=capture(test,blocked)
                result['settledCheckSeconds']=round(time.monotonic()-release_wait,3)
                results.append(result)
                (out/f'{test}-window.txt').write_bytes(adb('shell','dumpsys','window','windows').stdout)
                print(a.api,test,result['status'],flush=True)
                if test in ['global_enabled_home','protected_transfer']:
                    before=adb('shell','find','/sdcard/Pictures/Screenshots','-type','f').stdout
                    before_system_log=adb('logcat','-d','-s','SurfaceFlinger','Screenshot','ScreenshotController','GlobalScreenshot').stdout.decode(errors='replace')
                    adb('shell','input','keyevent','120')
                    time.sleep(2)
                    after=adb('shell','find','/sdcard/Pictures/Screenshots','-type','f').stdout
                    new=set(after.decode().splitlines())-set(before.decode().splitlines())
                    for f in new: adb('pull',f,str(out/('system-ui-'+pathlib.Path(f).name)))
                    system_log=adb('logcat','-d','-s','SurfaceFlinger','Screenshot','ScreenshotController','GlobalScreenshot').stdout.decode(errors='replace')
                    (out/f'{test}-system-ui.txt').write_text(system_log)
                    new_system_log='\n'.join(line for line in system_log.splitlines() if line not in before_system_log.splitlines())
                    status='BLOCKED'
                    if new:
                        fractions=[]
                        for f in new:
                            im=Image.open(out/('system-ui-'+pathlib.Path(f).name)).convert('RGB')
                            px=list(im.getdata())
                            fractions.append(sum((abs(r-32)<8 and abs(g-192)<8 and abs(b-96)<8) or (blocked and abs(r-224)<8 and abs(g-32)<8 and abs(b-64)<8) for r,g,b in px)/len(px))
                        status='PASS' if (max(fractions)<.001 if blocked else max(fractions)>.25) else 'FAIL'
                    elif blocked and ('PERMISSION_DENIED' in new_system_log or 'secure' in new_system_log.lower()):
                        status='PASS'
                    results.append(dict(test=test,method='System UI KEYCODE_SYSRQ',status=status,newFiles=sorted(new),note='Saved-image pixels or explicit secure capture refusal log; otherwise BLOCKED/inconclusive.'))
                    time.sleep(8) # Let the System UI thumbnail of the allowed control disappear.
                if test in ['lifecycle_secure','lifecycle_allowed']:
                    adb('shell','am','start','-n',component,'-a','fsp.RECREATE')
                    time.sleep(2)
                    results.append(capture(test+'_activity_recreation',blocked))
                    adb('shell','input','keyevent','3')
                    adb('shell','am','start','-n',component)
                    time.sleep(1)
                    results.append(capture(test+'_background_foreground',blocked))
                    adb('shell','settings','put','system','accelerometer_rotation','0')
                    adb('shell','settings','put','system','user_rotation','0' if blocked else '1')
                    time.sleep(1)
                    results.append(capture(test+'_orientation',blocked))
                urllib.request.urlopen('http://127.0.0.1:8876/next', timeout=15).read()
            if 'FSP_MATRIX_DONE' in text:
                done=True; break
        stream.terminate()
    if not done: results.append(dict(test='integration_completion',status='FAIL',reason='Timed out; inspect logcat'))
except Exception as e:
    results.append(dict(test='execution',status='BLOCKED',reason=str(e)))
finally:
    (out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    if owned: adb('emu','kill')
    try: emulator.wait(timeout=15)
    except subprocess.TimeoutExpired: emulator.terminate()
    shutil.rmtree(pathlib.Path(env['ANDROID_AVD_HOME'])/(name+'.avd'), ignore_errors=True)
    (pathlib.Path(env['ANDROID_AVD_HOME'])/(name+'.ini')).unlink(missing_ok=True)
    print(json.dumps(results),flush=True)
