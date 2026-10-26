import argparse
import os
import re
import subprocess
import sys
import zipfile


def read_pubspec_version(path='./pubspec.yaml'):
    """读取 pubspec.yaml 里的 version —— 版本号唯一的真实来源。"""
    with open(path, 'r', encoding='utf-8') as file:
        for line in file:
            if line.startswith('version:'):
                return line.split(':', 1)[1].strip().strip('"\'')
    raise ValueError(f'{path} 里找不到 version 字段')


def read_exe_version(exe_path):
    """读取 PE 的 VERSIONINFO。

    这个值由 pubspec 的 version 经 CMake 的 FLUTTER_VERSION 写进 Runner.rc，
    应用内的 package_info_plus 读的也是它，所以它是"这个包实际是什么版本"的权威答案。
    """
    if not os.path.exists(exe_path):
        return None
    command = [
        'powershell', '-NoProfile', '-NonInteractive', '-Command',
        f"(Get-Item -LiteralPath '{exe_path}').VersionInfo.FileVersion",
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f'读取 {exe_path} 版本失败: {result.stderr.strip()}')
    return result.stdout.strip() or None


def version_core(version):
    """'0.3.22+13' / 'v0.3.22' -> '0.3.22'"""
    return version.strip().lstrip('vV').split('+')[0].strip()


def verify_versions(release_path, release_version):
    """校验 pubspec / exe / zip 文件名三处版本一致，返回错误列表（空列表表示通过）。"""
    pubspec_version = read_pubspec_version()
    exe_version = read_exe_version(os.path.join(release_path, 'oasx.exe'))

    print('版本号校验：')
    print(f'  pubspec.yaml : {pubspec_version}')
    print(f'  oasx.exe     : {exe_version or "(读取失败)"}')
    print(f'  zip 文件名   : {release_version}')

    errors = []
    if exe_version is None:
        errors.append('读不到 oasx.exe 的版本资源，构建产物可能不完整')
    elif exe_version != pubspec_version:
        errors.append(
            f'oasx.exe 版本 {exe_version} 与 pubspec {pubspec_version} 不一致，'
            '构建产物不是当前源码编出来的，请重新执行 flutter build windows --release'
        )
    if version_core(pubspec_version) != version_core(release_version):
        errors.append(
            f'zip 名版本 {version_core(release_version)} 与 pubspec '
            f'{version_core(pubspec_version)} 不一致，请检查 CHANGELOG.md 或 --version 参数'
        )
    return errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--path",
        type=str,
        help="xxx",
    )
    parser.add_argument(
        "--version",
        type=str,
        help="xxx",
    )
    args, _ = parser.parse_known_args()
    if args.path:
        release_path = args.path
    else:
        if os.path.exists("./build/windows/x64/runner/Release/oasx.exe"):
            release_path = "./build/windows/x64/runner/Release"
        elif os.path.exists("./build/windows/runner/Release/oasx.exe"):
            release_path = "./build/windows/runner/Release"
        else:
            raise FileNotFoundError("No release path found.")
    match = re.search(r'build.*Release', release_path)
    if match:
        release_path = match.group(0)
        release_path = release_path.replace('\\', '/')
        print(f"Matched string: {release_path}")
    else:
        print("No match found.")

    if args.version:
        release_version = args.version
    else:
        with open('./CHANGELOG.md', 'r', encoding='utf-8') as file:
            log = file.read()
            release_version = re.search(r'v\d+\.\d+\.\d+', log).group(0)
            release_version = release_version.replace('\n', '').replace('\r', '').replace(' ', '')

    errors = verify_versions(release_path, release_version)
    if errors:
        print('\n版本号校验失败：')
        for error in errors:
            print(f'  - {error}')
        sys.exit(1)
    print('版本号校验通过。\n')

    # 压缩
    zip_filename = f'oasx_{release_version}_windows.zip'
    with zipfile.ZipFile(zip_filename, 'w', zipfile.ZIP_DEFLATED) as zip_file:
        # 遍历文件夹中的文件
        for foldername, subfolders, filenames in os.walk(release_path):
            for filename in filenames:
                # 构建文件的完整路径
                file_path = os.path.join(foldername, filename)

                # 将文件添加到 Zip 文件中
                zip_file.write(file_path, os.path.relpath(file_path, release_path))

    print(f'已生成 {zip_filename}')
