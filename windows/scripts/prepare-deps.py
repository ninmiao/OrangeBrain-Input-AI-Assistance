"""Pinned Windows native dependencies. Requires VS 2022 C++/ATL and 7-Zip.

Downloads and compiled libraries are ignored by Git. Python 3.12+ recommended.
Use --skip-boost only when both architectures' Boost libraries already exist.
"""
from pathlib import Path
import urllib.request,hashlib,subprocess,shutil,argparse,os,tarfile
ROOT=Path(__file__).resolve().parents[2]
PACKAGES={
 'x64':('rime-33e7814-Windows-msvc-x64.7z','7478c7caa4ff6b37de86daba1f7ce4a994a4f5ba24872a820fb2b3a9b01fed15'),
 'x86':('rime-33e7814-Windows-msvc-x86.7z','af235c26c06152ce09ceb8fe9d9ab9fba7ab43ce30aa952b40174d806f5cc3d9'),
}
def download(url,path,sha):
    if not path.exists():
        temp=path.with_suffix('.partial');urllib.request.urlretrieve(url,temp)
        if hashlib.sha256(temp.read_bytes()).hexdigest()!=sha:raise RuntimeError('Download checksum mismatch: '+path.name)
        temp.replace(path)
    if hashlib.sha256(path.read_bytes()).hexdigest()!=sha:raise RuntimeError('Cached checksum mismatch: '+path.name)
def run(skip_boost=False):
    archives=ROOT/'.tools/windows-downloads';archives.mkdir(exist_ok=True,parents=True)
    seven=shutil.which('7z') or r'C:\Program Files\7-Zip\7z.exe'
    native=ROOT/'windows/native'
    for arch,(name,sha) in PACKAGES.items():
        archive=archives/name;download('https://github.com/rime/librime/releases/download/1.17.0/'+name,archive,sha)
        subprocess.run([seven,'x','-y',str(archive),'-o'+str(archives/arch)],check=True,stdout=subprocess.DEVNULL)
        lib=native/('lib64' if arch=='x64' else 'lib');lib.mkdir(exist_ok=True)
        shutil.copy2(archives/arch/'dist/lib/rime.lib',lib/'rime.lib')
        if arch=='x64':
            (native/'output').mkdir(exist_ok=True)
            shutil.copy2(archives/arch/'dist/lib/rime.dll',native/'output/rime.dll')
            for p in (archives/arch/'dist/include').glob('*.h'):shutil.copy2(p,native/'include'/p.name)
    if skip_boost:return
    boost=ROOT/'android/app/src/main/jni/boost'
    if not (boost/'boost/version.hpp').exists() and not (boost/'libs/config/include/boost/version.hpp').exists():
        archive=archives/'boost-1.89.0-cmake.tar.xz'
        download('https://github.com/boostorg/boost/releases/download/boost-1.89.0/boost-1.89.0-cmake.tar.xz',archive,'67acec02d0d118b5de9eb441f5fb707b3a1cdd884be00ca24b9a73c995511f74')
        temp=archives/'boost-source';temp.mkdir(exist_ok=True)
        with tarfile.open(archive) as tf:
            # Reject path traversal and links; archive contains source only.
            for member in tf.getmembers():
                path=(temp/member.name).resolve()
                if not path.is_relative_to(temp.resolve()) or member.issym() or member.islnk():raise RuntimeError('Unsafe archive member')
            tf.extractall(temp,filter='data')
        roots=[p for p in temp.iterdir() if p.is_dir() and (p/'bootstrap.bat').exists()]
        if len(roots)!=1:raise RuntimeError('Unexpected Boost archive layout')
        shutil.copytree(roots[0],boost,dirs_exist_ok=True)
    vswhere=Path(os.environ['ProgramFiles(x86)'])/'Microsoft Visual Studio/Installer/vswhere.exe'
    vs=subprocess.check_output([str(vswhere),'-latest','-products','*','-requires','Microsoft.VisualStudio.Component.VC.Tools.x86.x64','-property','installationPath'],text=True).strip()
    if not vs:raise RuntimeError('Install Visual Studio 2022 C++ Build Tools and ATL')
    for bits in ('64','32'):
        cmd=archives/f'build-boost-{bits}.cmd';stage=ROOT/f'.tools/boost-win{bits}'
        text=f'@echo off\ncall "{vs}/VC/Auxiliary/Build/vcvars{bits}.bat"\nif errorlevel 1 exit /b 1\ncd /d "{boost}"\nif not exist b2.exe call bootstrap.bat\nif errorlevel 1 exit /b 1\nb2 headers\nif errorlevel 1 exit /b 1\nb2 -j4 toolset=msvc-14.3 address-model={bits} variant=release link=static runtime-link=static threading=multi --with-thread --with-serialization --with-filesystem --with-locale --with-date_time --with-chrono --with-regex --stagedir="{stage}" stage\n'
        cmd.write_text(text,encoding='utf-8');subprocess.run([str(cmd)],check=True)
    print('Pinned librime and Boost x64/x86 dependencies ready.')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--skip-boost',action='store_true');run(parser.parse_args().skip_boost)
