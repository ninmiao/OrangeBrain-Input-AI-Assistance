"""Pinned Windows native dependencies. Requires VS 2022 C++/ATL and 7-Zip.

Downloads and compiled libraries are ignored by Git. Python 3.12+ recommended.
Use --skip-boost only when both architectures' Boost libraries already exist.
"""
from pathlib import Path
import urllib.request,hashlib,subprocess,shutil,argparse,os,tarfile
ROOT=Path(__file__).resolve().parents[2]
PACKAGES={
 'x64':('1.17.0','rime-33e7814-Windows-msvc-x64.7z','7478c7caa4ff6b37de86daba1f7ce4a994a4f5ba24872a820fb2b3a9b01fed15','lib64'),
 'x86':('1.17.0','rime-33e7814-Windows-msvc-x86.7z','af235c26c06152ce09ceb8fe9d9ab9fba7ab43ce30aa952b40174d806f5cc3d9','lib'),
}
BOOST_LIBS=('thread','serialization','filesystem','locale','date_time','chrono','regex')
# Boost builds per architecture: stage suffix, b2 target, vcvars script. ARM64 only
# feeds the native ARM64 TSF module; Rime and the services stay x64.
BOOST_TARGETS={
 'x64':('64','architecture=x86 address-model=64','vcvars64'),
 'x86':('32','architecture=x86 address-model=32','vcvars32'),
 'arm64':('arm64','architecture=arm address-model=64','vcvarsamd64_arm64'),
}
def download(url,path,sha):
    if not path.exists():
        temp=path.with_suffix('.partial');urllib.request.urlretrieve(url,temp)
        if hashlib.sha256(temp.read_bytes()).hexdigest()!=sha:raise RuntimeError('Download checksum mismatch: '+path.name)
        temp.replace(path)
    if hashlib.sha256(path.read_bytes()).hexdigest()!=sha:raise RuntimeError('Cached checksum mismatch: '+path.name)
def run(skip_boost=False, architecture='both', reuse_boost=False):
    archives=ROOT/'.tools/windows-downloads';archives.mkdir(exist_ok=True,parents=True)
    seven=shutil.which('7z') or r'C:\Program Files\7-Zip\7z.exe'
    native=ROOT/'windows/native'
    boost_architectures=tuple(BOOST_TARGETS) if architecture=='both' else (architecture,)
    architectures=tuple(a for a in boost_architectures if a in PACKAGES)
    for arch in architectures:
        tag,name,sha,library_dir=PACKAGES[arch]
        archive=archives/name;download(f'https://github.com/rime/librime/releases/download/{tag}/{name}',archive,sha)
        subprocess.run([seven,'x','-y',str(archive),'-o'+str(archives/arch)],check=True,stdout=subprocess.DEVNULL)
        lib=native/library_dir;lib.mkdir(exist_ok=True)
        shutil.copy2(archives/arch/'dist/lib/rime.lib',lib/'rime.lib')
        if arch=='x64':
            output=native/'output'
            output.mkdir(exist_ok=True,parents=True)
            shutil.copy2(archives/arch/'dist/lib/rime.dll',output/'rime.dll')
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
    for arch in boost_architectures:
        bits,target,vcvars=BOOST_TARGETS[arch]
        cmd=archives/f'build-boost-{bits}.cmd';stage=ROOT/f'.tools/boost-win{bits}'
        text=f'@echo off\ncall "{vs}/VC/Auxiliary/Build/{vcvars}.bat"\nif errorlevel 1 exit /b 1\ncd /d "{boost}"\nif not exist b2.exe call .\\bootstrap.bat vc143\nif errorlevel 1 exit /b 1\n.\\b2.exe headers\nif errorlevel 1 exit /b 1\n'
        if not reuse_boost or not all(any((stage/'lib').glob(f'libboost_{name}-*.lib')) for name in BOOST_LIBS):
            libraries=' '.join(f'--with-{name}' for name in BOOST_LIBS)
            text+=f'.\\b2.exe -j4 toolset=msvc-14.3 {target} variant=release link=static runtime-link=static threading=multi {libraries} --stagedir="{stage}" stage\n'
        cmd.write_text(text,encoding='utf-8');subprocess.run([str(cmd)],check=True)
    print(f'Pinned librime ({", ".join(architectures) or "none"}) and Boost ({", ".join(boost_architectures)}) ready')
if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--skip-boost',action='store_true')
    parser.add_argument('--architecture',choices=['both',*BOOST_TARGETS],default='both')
    parser.add_argument('--reuse-boost',action='store_true')
    args=parser.parse_args()
    run(args.skip_boost,args.architecture,args.reuse_boost)
